import AuthenticationServices
import Foundation
import Observation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum LinearConnectionState: Equatable {
    case disconnected
    case connected(LinearConnectionSummary)
    case working(String)
    case failed(String)
}

struct LinearConnectionSummary: Codable, Equatable {
    var id: UUID?
    var workspaceID: String
    var workspaceName: String?
    var status: String
    var lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case workspaceName = "workspace_name"
        case status
        case lastSyncedAt = "last_synced_at"
    }
}

struct LinearSyncResult: Codable, Equatable {
    var ok: Bool
    var projectsPushed: Int?
    var projectsPulled: Int?
    var tasksPushed: Int?
    var tasksPulled: Int?
    var lastSyncedAt: Date?
    var conflicts: [LinearSyncConflictDTO]?

    enum CodingKeys: String, CodingKey {
        case ok
        case projectsPushed = "projects_pushed"
        case projectsPulled = "projects_pulled"
        case tasksPushed = "tasks_pushed"
        case tasksPulled = "tasks_pulled"
        case lastSyncedAt = "last_synced_at"
        case conflicts
    }
}

struct LinearSyncConflictDTO: Codable, Equatable {
    var kind: String
    var cueInID: UUID
    var source: String
    var remoteUpdatedAt: Date
    var localUpdatedAt: Date
    var linkRemoteUpdatedAt: Date?
    /// Free-form remote snapshot — the server returns Linear's title/notes/
    /// status/priority/dueDate. Decoded as `[String: String]` for the simple
    /// banner UI; richer rendering can decode it again from the original JSON
    /// when the merge sheet is built.
    var remoteSnapshot: [String: String]?

    enum CodingKeys: String, CodingKey {
        case kind
        case cueInID = "cuein_id"
        case source
        case remoteUpdatedAt = "remote_updated_at"
        case localUpdatedAt = "local_updated_at"
        case linkRemoteUpdatedAt = "link_remote_updated_at"
        case remoteSnapshot = "remote_snapshot"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try c.decode(String.self, forKey: .kind)
        self.cueInID = try c.decode(UUID.self, forKey: .cueInID)
        self.source = try c.decode(String.self, forKey: .source)
        self.remoteUpdatedAt = try c.decode(Date.self, forKey: .remoteUpdatedAt)
        self.localUpdatedAt = try c.decode(Date.self, forKey: .localUpdatedAt)
        self.linkRemoteUpdatedAt = try? c.decode(Date.self, forKey: .linkRemoteUpdatedAt)
        // Remote snapshot is JSON-typed on the server; flatten to strings for now.
        if let raw = try? c.decode([String: AnyCodableValue].self, forKey: .remoteSnapshot) {
            var flat: [String: String] = [:]
            for (key, value) in raw {
                flat[key] = value.stringRepresentation
            }
            self.remoteSnapshot = flat
        } else {
            self.remoteSnapshot = nil
        }
    }
}

@Observable
@MainActor
final class LinearIntegrationStore {
    static let shared = LinearIntegrationStore()

    private let client = SupabaseClient.shared
    private let authStore = SupabaseAuthStore.shared
    private let callbackURL = "cuein://linear/callback"

    var state: LinearConnectionState = .disconnected
    var lastSyncResult: LinearSyncResult?
    private var currentConnection: LinearConnectionSummary?
    private var isSyncing = false
    private var lastAutomaticSyncAt: Date?

    private init() {}

    func refreshStatus() async {
        guard let session = authStore.session else {
            currentConnection = nil
            state = .disconnected
            return
        }
        do {
            let response: LinearStatusResponse = try await client.invokeFunction(
                "linear-status",
                body: EmptyLinearRequest(),
                session: session
            )
            if let connection = response.connection {
                currentConnection = connection
                state = .connected(connection)
            } else if case .working = state {
                return
            } else {
                currentConnection = nil
                state = .disconnected
            }
        } catch {
            if case .connected = state {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func connect() async {
        guard let session = authStore.session else {
            state = .failed("Sign in to CueIn Cloud before connecting Linear.")
            return
        }
        state = .working("Opening Linear...")
        do {
            let start: LinearOAuthStartResponse = try await client.invokeFunction(
                "linear-oauth-start",
                body: LinearOAuthStartRequest(redirectURI: callbackURL),
                session: session
            )
            guard let url = URL(string: start.authorizationURL) else {
                throw SupabaseClientError.invalidResponse
            }
            let callback = try await LinearWebOAuthSession.start(url: url, callbackScheme: "cuein")
            try await completeOAuth(callbackURL: callback)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func handleIncomingURL(_ url: URL) async -> Bool {
        guard url.scheme == "cuein", url.host == "linear" else { return false }
        do {
            try await completeOAuth(callbackURL: url)
        } catch {
            state = .failed(error.localizedDescription)
        }
        return true
    }

    /// Triggers a Linear sync. When `targets` is provided, the edge function
    /// pushes only those task / project rows instead of scanning the whole user
    /// table — used by the per-record push path. Pass `nil` for manual "Sync
    /// all" / scheduled pulls.
    func syncNow(action: LinearSyncAction = .full, targets: LinearSyncTargets? = nil) async {
        guard let session = authStore.session else {
            state = .failed("Sign in to CueIn Cloud before syncing Linear.")
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        state = .working("Syncing Linear...")
        do {
            if CueInSyncEngine.shared.hasPendingMutations() {
                await CueInSyncEngine.shared.syncNow()
            }
            let result: LinearSyncResult = try await client.invokeFunction(
                "linear-sync",
                body: LinearSyncRequest(action: action.rawValue, targets: targets),
                session: session
            )
            lastSyncResult = result
            // Translate server conflicts into the local TasksStore map. Always
            // invoked (even on empty array) so a clean re-sync clears stale
            // conflicts for tasks the user resolved.
            let mapped = (result.conflicts ?? []).compactMap { dto -> TaskConflict? in
                guard dto.kind == "task" else { return nil }
                return TaskConflict(
                    cueInID: dto.cueInID,
                    source: .linear,
                    remoteUpdatedAt: dto.remoteUpdatedAt,
                    localUpdatedAt: dto.localUpdatedAt,
                    remoteSnapshot: dto.remoteSnapshot ?? [:],
                    observedAt: Date()
                )
            }
            TasksStore.shared.applyServerConflicts(mapped, source: .linear)
            // Skip the trailing cloud pull when the run touched nothing — the
            // common debounced-push case where Linear was already in sync.
            // See NotionIntegrationStore for the matching rationale.
            let pulled = (result.tasksPulled ?? 0) + (result.projectsPulled ?? 0)
            let pushed = (result.tasksPushed ?? 0) + (result.projectsPushed ?? 0)
            let hasConflicts = !(result.conflicts?.isEmpty ?? true)
            if pulled > 0 || pushed > 0 || hasConflicts {
                await CueInSyncEngine.shared.syncNow()
            }
            state = currentConnectedState(lastSyncedAt: result.lastSyncedAt)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func syncIfDue(minimumInterval: TimeInterval = 300) async {
        await refreshStatus()
        guard case .connected = state else { return }
        if let lastAutomaticSyncAt, Date().timeIntervalSince(lastAutomaticSyncAt) < minimumInterval {
            return
        }
        lastAutomaticSyncAt = Date()
        await syncNow(action: .pull)
    }

    /// Resolves a Linear conflict by either (a) keeping the local edit and
    /// force-overwriting Linear, or (b) discarding the local edit and pulling
    /// the remote version into CueIn.
    func resolveConflict(taskID: UUID, keepLocal: Bool) async {
        if keepLocal {
            // Bump local updatedAt so the next push wins the timestamp check
            // anyway, and pass the explicit force_overwrite flag so the server
            // skips its conflict check for this id specifically.
            TasksStore.shared.markKeptLocalForConflict(taskID: taskID)
            await syncNow(
                action: .push,
                targets: LinearSyncTargets(
                    taskIDs: [taskID],
                    projectIDs: nil,
                    forceOverwriteTaskIDs: [taskID]
                )
            )
        } else {
            // "Use theirs": pull the latest from Linear (the pull pass will
            // overwrite the local row), then drop the conflict marker so the
            // banner disappears. We optimistically clear *before* the pull so
            // the UI updates immediately even if the network call is slow.
            TasksStore.shared.clearConflict(for: taskID)
            await syncNow(action: .pull)
        }
    }

    func disconnect() async {
        guard let session = authStore.session else { return }
        state = .working("Disconnecting Linear...")
        do {
            let _: LinearDisconnectResponse = try await client.invokeFunction(
                "linear-disconnect",
                body: EmptyLinearRequest(),
                session: session
            )
            state = .disconnected
            lastSyncResult = nil
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func completeOAuth(callbackURL url: URL) async throws {
        guard let session = authStore.session else {
            throw SupabaseClientError.server(status: 401, message: "Sign in to CueIn Cloud before connecting Linear.")
        }
        let items = Self.callbackItems(from: url)
        if let error = items["error"] {
            throw SupabaseClientError.server(status: 400, message: error)
        }
        guard let code = items["code"], let oauthState = items["state"] else {
            throw SupabaseClientError.invalidResponse
        }
        self.state = .working("Finishing Linear setup...")
        let response: LinearOAuthCompleteResponse = try await client.invokeFunction(
            "linear-oauth-complete",
            body: LinearOAuthCompleteRequest(code: code, state: oauthState),
            session: session
        )
        currentConnection = response.connection
        self.state = .connected(response.connection)
        await syncNow(action: .pull)
    }

    private func currentConnectedState(lastSyncedAt: Date?) -> LinearConnectionState {
        if var summary = currentConnection {
            summary.lastSyncedAt = lastSyncedAt ?? summary.lastSyncedAt
            currentConnection = summary
            return .connected(summary)
        }
        return .connected(LinearConnectionSummary(
            id: nil,
            workspaceID: "linear",
            workspaceName: "Linear",
            status: "active",
            lastSyncedAt: lastSyncedAt
        ))
    }

    private static func callbackItems(from url: URL) -> [String: String] {
        var items: [String: String] = [:]
        let queries = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for item in queries {
            items[item.name] = item.value
        }
        return items
    }
}

enum LinearSyncAction: String {
    case full
    case push
    case pull
}

private struct LinearOAuthStartRequest: Encodable {
    var redirectURI: String

    enum CodingKeys: String, CodingKey {
        case redirectURI = "redirect_uri"
    }
}

private struct LinearOAuthStartResponse: Decodable {
    var authorizationURL: String
    var state: String

    enum CodingKeys: String, CodingKey {
        case authorizationURL = "authorization_url"
        case state
    }
}

private struct LinearOAuthCompleteRequest: Encodable {
    var code: String
    var state: String
}

private struct LinearOAuthCompleteResponse: Decodable {
    var connection: LinearConnectionSummary
}

struct LinearSyncTargets: Encodable, Equatable {
    var taskIDs: [UUID]?
    var projectIDs: [UUID]?
    /// Task ids the user explicitly chose "Keep mine" for. The server will
    /// skip the 3-way conflict check for these ids so the local version wins.
    var forceOverwriteTaskIDs: [UUID]?

    enum CodingKeys: String, CodingKey {
        case taskIDs = "task_ids"
        case projectIDs = "project_ids"
        case forceOverwriteTaskIDs = "force_overwrite_task_ids"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let ids = taskIDs, !ids.isEmpty {
            try c.encode(ids.map { $0.uuidString.lowercased() }, forKey: .taskIDs)
        }
        if let ids = projectIDs, !ids.isEmpty {
            try c.encode(ids.map { $0.uuidString.lowercased() }, forKey: .projectIDs)
        }
        if let ids = forceOverwriteTaskIDs, !ids.isEmpty {
            try c.encode(ids.map { $0.uuidString.lowercased() }, forKey: .forceOverwriteTaskIDs)
        }
    }

    var isEmpty: Bool {
        (taskIDs?.isEmpty ?? true) && (projectIDs?.isEmpty ?? true) && (forceOverwriteTaskIDs?.isEmpty ?? true)
    }
}

private struct LinearSyncRequest: Encodable {
    var action: String
    var targets: LinearSyncTargets?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(action, forKey: .action)
        if let t = targets, !t.isEmpty {
            try c.encode(t, forKey: .targets)
        }
    }

    enum CodingKeys: String, CodingKey {
        case action
        case targets
    }
}

private struct LinearStatusResponse: Decodable {
    var connection: LinearConnectionSummary?
}

private struct LinearDisconnectResponse: Decodable {
    var ok: Bool
}

private struct EmptyLinearRequest: Encodable {}

/// Tiny "any JSON value" decoder used to flatten the server's `remote_snapshot`
/// (which can hold strings, numbers, bools, nulls, nested objects) into a
/// `[String: String]` for the simple conflict banner UI. Non-string scalars are
/// stringified; nested objects/arrays are JSON-encoded.
struct AnyCodableValue: Decodable {
    let stringRepresentation: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { stringRepresentation = v; return }
        if let v = try? c.decode(Bool.self) { stringRepresentation = v ? "true" : "false"; return }
        if let v = try? c.decode(Int.self) { stringRepresentation = String(v); return }
        if let v = try? c.decode(Double.self) { stringRepresentation = String(v); return }
        if c.decodeNil() { stringRepresentation = ""; return }
        // Object / array fallback: re-encode to JSON text via JSONSerialization.
        let raw = try c.decode(JSONValue.self)
        stringRepresentation = raw.jsonText
    }
}

private indirect enum JSONValue: Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if c.decodeNil() { self = .null; return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    var jsonText: String {
        switch self {
        case .object(let dict):
            let pairs = dict.map { "\"\($0.key)\":\($0.value.jsonText)" }
            return "{\(pairs.joined(separator: ","))}"
        case .array(let arr):
            return "[\(arr.map(\.jsonText).joined(separator: ","))]"
        case .string(let s):
            return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
        case .number(let n): return String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }
}

private enum LinearWebOAuthSession {
    #if os(iOS) || os(macOS)
    @MainActor private static var activePresenter: LinearWebAuthenticationPresenter?
    #endif
    @MainActor private static var activeSession: ASWebAuthenticationSession?

    @MainActor
    static func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                activeSession = nil
                #if os(iOS) || os(macOS)
                activePresenter = nil
                #endif
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let authError = error as? ASWebAuthenticationSessionError,
                          authError.code == .canceledLogin {
                    continuation.resume(throwing: SupabaseClientError.server(status: 400, message: "Linear authorization was cancelled before CueIn received a callback."))
                } else {
                    continuation.resume(throwing: error ?? SupabaseClientError.invalidResponse)
                }
            }
            #if os(iOS) || os(macOS)
            let presenter = LinearWebAuthenticationPresenter()
            session.presentationContextProvider = presenter
            activePresenter = presenter
            #endif
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            session.start()
        }
    }
}

#if os(iOS)
private final class LinearWebAuthenticationPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#elseif os(macOS)
private final class LinearWebAuthenticationPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
#endif

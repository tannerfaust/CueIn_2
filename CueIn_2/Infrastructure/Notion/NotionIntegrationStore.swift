import AuthenticationServices
import Foundation
import Observation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum NotionConnectionState: Equatable {
    case disconnected
    case connected(NotionConnectionSummary)
    case working(String)
    case failed(String)
}

struct NotionConnectionSummary: Codable, Equatable {
    var id: UUID?
    var workspaceID: String
    var workspaceName: String?
    var projectsDatabaseID: String?
    var tasksDatabaseID: String?
    var externalTasksDatabaseID: String?
    var externalTasksDatabaseTitle: String?
    var status: String
    var lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case workspaceName = "workspace_name"
        case projectsDatabaseID = "projects_database_id"
        case tasksDatabaseID = "tasks_database_id"
        case externalTasksDatabaseID = "external_tasks_database_id"
        case externalTasksDatabaseTitle = "external_tasks_database_title"
        case status
        case lastSyncedAt = "last_synced_at"
    }
}

struct NotionSyncResult: Codable, Equatable {
    var ok: Bool
    var projectsPushed: Int?
    var projectsPulled: Int?
    var tasksPushed: Int?
    var tasksPulled: Int?
    var lastSyncedAt: Date?
    var conflicts: [NotionSyncConflictDTO]?

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

struct NotionSyncConflictDTO: Codable, Equatable {
    var kind: String
    var cueInID: UUID
    var source: String
    var remoteUpdatedAt: Date
    var localUpdatedAt: Date
    var linkRemoteUpdatedAt: Date?
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
final class NotionIntegrationStore {
    static let shared = NotionIntegrationStore()

    private let client = SupabaseClient.shared
    private let authStore = SupabaseAuthStore.shared
    private let callbackURL = "cuein://notion/callback"

    var state: NotionConnectionState = .disconnected
    var lastSyncResult: NotionSyncResult?
    private var currentConnection: NotionConnectionSummary?
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
            let response: NotionStatusResponse = try await client.invokeFunction(
                "notion-status",
                body: EmptyNotionRequest(),
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
            state = .failed("Sign in to CueIn Cloud before connecting Notion.")
            return
        }
        state = .working("Opening Notion...")
        do {
            let start: NotionOAuthStartResponse = try await client.invokeFunction(
                "notion-oauth-start",
                body: NotionOAuthStartRequest(redirectURI: callbackURL),
                session: session
            )
            guard let url = URL(string: start.authorizationURL) else {
                throw SupabaseClientError.invalidResponse
            }
            let callback = try await NotionWebOAuthSession.start(url: url, callbackScheme: "cuein")
            try await completeOAuth(callbackURL: callback)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func handleIncomingURL(_ url: URL) async -> Bool {
        guard url.scheme == "cuein", url.host == "notion" else { return false }
        do {
            try await completeOAuth(callbackURL: url)
        } catch {
            state = .failed(error.localizedDescription)
        }
        return true
    }

    /// Triggers a Notion sync. When `targets` is provided, the edge function
    /// pushes only those task / project rows instead of scanning the whole user
    /// table. Pass `nil` for manual "Sync all" / scheduled pulls.
    func syncNow(action: NotionSyncAction = .full, targets: NotionSyncTargets? = nil) async {
        guard let session = authStore.session else {
            state = .failed("Sign in to CueIn Cloud before syncing Notion.")
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        state = .working("Syncing Notion...")
        do {
            if CueInSyncEngine.shared.hasPendingMutations() {
                await CueInSyncEngine.shared.syncNow()
            }
            let result: NotionSyncResult = try await client.invokeFunction(
                "notion-sync",
                body: NotionSyncRequest(action: action.rawValue, targets: targets),
                session: session
            )
            lastSyncResult = result
            let mapped = (result.conflicts ?? []).compactMap { dto -> TaskConflict? in
                guard dto.kind == "task" else { return nil }
                return TaskConflict(
                    cueInID: dto.cueInID,
                    source: .notion,
                    remoteUpdatedAt: dto.remoteUpdatedAt,
                    localUpdatedAt: dto.localUpdatedAt,
                    remoteSnapshot: dto.remoteSnapshot ?? [:],
                    observedAt: Date()
                )
            }
            TasksStore.shared.applyServerConflicts(mapped, source: .notion)
            // The edge function already wrote the touched rows to Supabase as
            // part of push. We only need a follow-up cloud pull when the run
            // actually changed remote rows the client hasn't seen yet — i.e.
            // a pull happened, conflicts were emitted, or push completion
            // bumped link metadata. In the common debounced-push case where
            // nothing changed, skip the extra round-trip entirely.
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

    /// Resolves a Notion conflict by either keeping the local edit
    /// (force-overwrites Notion) or pulling the remote version into CueIn.
    func resolveConflict(taskID: UUID, keepLocal: Bool) async {
        if keepLocal {
            TasksStore.shared.markKeptLocalForConflict(taskID: taskID)
            await syncNow(
                action: .push,
                targets: NotionSyncTargets(
                    taskIDs: [taskID],
                    projectIDs: nil,
                    forceOverwriteTaskIDs: [taskID]
                )
            )
        } else {
            TasksStore.shared.clearConflict(for: taskID)
            await syncNow(action: .pull)
        }
    }

    func disconnect() async {
        guard let session = authStore.session else { return }
        state = .working("Disconnecting Notion...")
        do {
            let _: NotionDisconnectResponse = try await client.invokeFunction(
                "notion-disconnect",
                body: EmptyNotionRequest(),
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
            throw SupabaseClientError.server(status: 401, message: "Sign in to CueIn Cloud before connecting Notion.")
        }
        let items = Self.callbackItems(from: url)
        if let error = items["error"] {
            throw SupabaseClientError.server(status: 400, message: error)
        }
        guard let code = items["code"], let oauthState = items["state"] else {
            throw SupabaseClientError.invalidResponse
        }
        self.state = .working("Finishing Notion setup...")
        let response: NotionOAuthCompleteResponse = try await client.invokeFunction(
            "notion-oauth-complete",
            body: NotionOAuthCompleteRequest(code: code, state: oauthState),
            session: session
        )
        currentConnection = response.connection
        self.state = .connected(response.connection)
        await syncNow(action: .pull)
    }

    private func currentConnectedState(lastSyncedAt: Date?) -> NotionConnectionState {
        if var summary = currentConnection {
            summary.lastSyncedAt = lastSyncedAt ?? summary.lastSyncedAt
            currentConnection = summary
            return .connected(summary)
        }
        return .connected(NotionConnectionSummary(
            id: nil,
            workspaceID: "notion",
            workspaceName: "Notion",
            projectsDatabaseID: nil,
            tasksDatabaseID: nil,
            externalTasksDatabaseID: nil,
            externalTasksDatabaseTitle: nil,
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

enum NotionSyncAction: String {
    case full
    case push
    case pull
}

private struct NotionOAuthStartRequest: Encodable {
    var redirectURI: String

    enum CodingKeys: String, CodingKey {
        case redirectURI = "redirect_uri"
    }
}

private struct NotionOAuthStartResponse: Decodable {
    var authorizationURL: String
    var state: String

    enum CodingKeys: String, CodingKey {
        case authorizationURL = "authorization_url"
        case state
    }
}

private struct NotionOAuthCompleteRequest: Encodable {
    var code: String
    var state: String
}

private struct NotionOAuthCompleteResponse: Decodable {
    var connection: NotionConnectionSummary
}

struct NotionSyncTargets: Encodable, Equatable {
    var taskIDs: [UUID]?
    var projectIDs: [UUID]?
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

private struct NotionSyncRequest: Encodable {
    var action: String
    var targets: NotionSyncTargets?

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

private struct NotionStatusResponse: Decodable {
    var connection: NotionConnectionSummary?
}

private struct NotionDisconnectResponse: Decodable {
    var ok: Bool
}

private struct EmptyNotionRequest: Encodable {}

private enum NotionWebOAuthSession {
    #if os(iOS) || os(macOS)
    @MainActor private static var activePresenter: NotionWebAuthenticationPresenter?
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
                    continuation.resume(throwing: SupabaseClientError.server(status: 400, message: "Notion authorization was cancelled before CueIn received a callback. Select a page and tap Allow access to finish."))
                } else {
                    continuation.resume(throwing: error ?? SupabaseClientError.invalidResponse)
                }
            }
            #if os(iOS) || os(macOS)
            let presenter = NotionWebAuthenticationPresenter()
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
private final class NotionWebAuthenticationPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#elseif os(macOS)
private final class NotionWebAuthenticationPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
#endif

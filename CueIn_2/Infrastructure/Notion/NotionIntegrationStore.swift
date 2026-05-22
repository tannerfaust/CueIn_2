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
    var status: String
    var lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case workspaceName = "workspace_name"
        case projectsDatabaseID = "projects_database_id"
        case tasksDatabaseID = "tasks_database_id"
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

    enum CodingKeys: String, CodingKey {
        case ok
        case projectsPushed = "projects_pushed"
        case projectsPulled = "projects_pulled"
        case tasksPushed = "tasks_pushed"
        case tasksPulled = "tasks_pulled"
        case lastSyncedAt = "last_synced_at"
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

    func syncNow(action: NotionSyncAction = .full) async {
        guard let session = authStore.session else {
            state = .failed("Sign in to CueIn Cloud before syncing Notion.")
            return
        }
        state = .working("Syncing Notion...")
        do {
            await CueInSyncEngine.shared.syncNow()
            let result: NotionSyncResult = try await client.invokeFunction(
                "notion-sync",
                body: NotionSyncRequest(action: action.rawValue),
                session: session
            )
            lastSyncResult = result
            await CueInSyncEngine.shared.syncNow()
            state = currentConnectedState(lastSyncedAt: result.lastSyncedAt)
        } catch {
            state = .failed(error.localizedDescription)
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
            body: NotionOAuthCompleteRequest(code: code, state: oauthState, redirectURI: callbackURL),
            session: session
        )
        currentConnection = response.connection
        self.state = .connected(response.connection)
        await syncNow(action: .full)
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
    var redirectURI: String

    enum CodingKeys: String, CodingKey {
        case code
        case state
        case redirectURI = "redirect_uri"
    }
}

private struct NotionOAuthCompleteResponse: Decodable {
    var connection: NotionConnectionSummary
}

private struct NotionSyncRequest: Encodable {
    var action: String
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
                } else {
                    continuation.resume(throwing: error ?? SupabaseClientError.invalidResponse)
                }
            }
            #if os(iOS) || os(macOS)
            let presenter = NotionWebAuthenticationPresenter()
            session.presentationContextProvider = presenter
            activePresenter = presenter
            #endif
            session.prefersEphemeralWebBrowserSession = true
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

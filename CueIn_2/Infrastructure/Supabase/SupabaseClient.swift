import Foundation

enum SupabaseClientError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case server(status: Int, message: String)
    case decoding(path: String, message: String, body: String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Supabase is not configured."
        case .invalidResponse:
            return "The backend returned an invalid response."
        case let .server(status, message):
            if message.localizedCaseInsensitiveContains("<!doctype html")
                || message.localizedCaseInsensitiveContains("<html") {
                return "Backend error \(status): Supabase returned an HTML security page. Check that the project URL is the project root, like https://your-project.supabase.co."
            }
            return "Backend error \(status): \(message)"
        case let .decoding(path, message, body):
            return "Backend decode error at \(path): \(message). Body: \(body)"
        }
    }
}

@MainActor
final class SupabaseClient {
    static let shared = SupabaseClient()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        self.encoder = JSONEncoder.cueInSyncEncoder
        self.decoder = JSONDecoder.cueInSyncDecoder
    }

    func sendMagicLink(email: String) async throws {
        let config = try configuration()
        let body = MagicLinkRequest(email: email, redirectTo: config.redirectURL.absoluteString)
        let _: EmptyResponse = try await request(
            baseURL: config.authBaseURL,
            path: "otp",
            method: "POST",
            body: body,
            config: config,
            session: nil
        )
    }

    func signInWithPassword(email: String, password: String) async throws -> SupabaseAuthSession {
        let config = try configuration()
        let body = PasswordSignInRequest(email: email, password: password)
        let response: SupabaseAuthResponse = try await request(
            baseURL: config.authBaseURL,
            path: "token",
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            method: "POST",
            body: body,
            config: config,
            session: nil
        )
        return response.session
    }

    func signUpWithPassword(email: String, password: String) async throws -> SupabaseSignUpResponse {
        let config = try configuration()
        let body = PasswordSignInRequest(email: email, password: password)
        return try await request(
            baseURL: config.authBaseURL,
            path: "signup",
            method: "POST",
            body: body,
            config: config,
            session: nil
        )
    }

    func signInWithIDToken(provider: String, idToken: String, nonce: String? = nil) async throws -> SupabaseAuthSession {
        let config = try configuration()
        let body = IDTokenSignInRequest(provider: provider, idToken: idToken, nonce: nonce)
        let response: SupabaseAuthResponse = try await request(
            baseURL: config.authBaseURL,
            path: "token",
            queryItems: [URLQueryItem(name: "grant_type", value: "id_token")],
            method: "POST",
            body: body,
            config: config,
            session: nil
        )
        return response.session
    }

    func user(accessToken: String) async throws -> SupabaseUser {
        let config = try configuration()
        let tempSession = SupabaseAuthSession(
            accessToken: accessToken,
            refreshToken: "",
            tokenType: "bearer",
            expiresAt: Date().addingTimeInterval(60),
            user: SupabaseUser(id: UUID(), email: nil)
        )
        let response: SupabaseUser = try await request(
            baseURL: config.authBaseURL,
            path: "user",
            method: "GET",
            body: Optional<EmptyBody>.none,
            config: config,
            session: tempSession
        )
        return response
    }

    func refreshSession(_ session: SupabaseAuthSession) async throws -> SupabaseAuthSession {
        let config = try configuration()
        let body = RefreshTokenRequest(refreshToken: session.refreshToken)
        let response: SupabaseAuthResponse = try await request(
            baseURL: config.authBaseURL,
            path: "token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            body: body,
            config: config,
            session: nil
        )
        return response.session
    }

    func signOut(_ session: SupabaseAuthSession) async throws {
        let config = try configuration()
        let _: EmptyResponse = try await request(
            baseURL: config.authBaseURL,
            path: "logout",
            method: "POST",
            body: EmptyBody(),
            config: config,
            session: session
        )
    }

    func upsert<Record: Encodable>(_ records: [Record], table: SupabaseTable, session: SupabaseAuthSession) async throws {
        guard !records.isEmpty else { return }
        let config = try configuration()
        let _: EmptyResponse = try await request(
            baseURL: config.restBaseURL,
            path: table.rawValue,
            queryItems: [URLQueryItem(name: "on_conflict", value: table.upsertConflictTarget)],
            method: "POST",
            body: records,
            extraHeaders: [
                "Prefer": "resolution=merge-duplicates,return=minimal"
            ],
            config: config,
            session: session
        )
    }

    func fetch<Record: Decodable>(_ type: Record.Type, table: SupabaseTable, updatedAfter: Date?, session: SupabaseAuthSession) async throws -> [Record] {
        let config = try configuration()
        var query = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "updated_at.asc")
        ]
        if let updatedAfter {
            query.append(URLQueryItem(name: "updated_at", value: "gte.\(ISO8601DateFormatter.cueInSync.string(from: updatedAfter))"))
        }

        return try await request(
            baseURL: config.restBaseURL,
            path: table.rawValue,
            queryItems: query,
            method: "GET",
            body: Optional<EmptyBody>.none,
            config: config,
            session: session
        )
    }

    func deleteAccount(session: SupabaseAuthSession) async throws {
        let config = try configuration()
        let profile = ProfileDTO(
            id: session.user.id,
            displayName: nil,
            avatarURL: nil,
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: Date(),
            syncVersion: 1
        )
        try await upsert([profile], table: .profiles, session: session)
        let _: EmptyResponse = try await request(
            baseURL: config.authBaseURL,
            path: "logout",
            method: "POST",
            body: EmptyBody(),
            config: config,
            session: session
        )
    }

    private func configuration() throws -> SupabaseConfiguration {
        guard let config = SupabaseConfiguration.current else {
            throw SupabaseClientError.missingConfiguration
        }
        return config
    }

    private func request<Response: Decodable, Body: Encodable>(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Body?,
        extraHeaders: [String: String] = [:],
        config: SupabaseConfiguration,
        session: SupabaseAuthSession?
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw SupabaseClientError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(session?.accessToken ?? config.anonKey)", forHTTPHeaderField: "Authorization")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseClientError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "No response body"
            throw SupabaseClientError.server(status: http.statusCode, message: message)
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "Unreadable response body"
            throw SupabaseClientError.decoding(path: path, message: error.localizedDescription, body: body)
        }
    }
}

enum SupabaseTable: String, CaseIterable {
    case profiles
    case fields
    case projects
    case tasks
    case goals
    case scheduleRecords = "schedule_records"
    case appLayoutSettings = "app_layout_settings"

    var upsertConflictTarget: String {
        switch self {
        case .appLayoutSettings:
            return "user_id,key"
        default:
            return "id"
        }
    }
}

private struct MagicLinkRequest: Encodable {
    var email: String
    var createUser = true
    var redirectTo: String

    enum CodingKeys: String, CodingKey {
        case email
        case createUser = "create_user"
        case redirectTo = "redirect_to"
    }
}

private struct PasswordSignInRequest: Encodable {
    var email: String
    var password: String
}

private struct IDTokenSignInRequest: Encodable {
    var provider: String
    var idToken: String
    var nonce: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case idToken = "id_token"
        case nonce
    }
}

private struct RefreshTokenRequest: Encodable {
    var refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct EmptyBody: Encodable {}
private struct EmptyResponse: Decodable {}

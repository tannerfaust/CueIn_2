import Foundation

struct SupabaseAuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String
    var expiresAt: Date
    var user: SupabaseUser

    var isExpired: Bool {
        expiresAt <= Date().addingTimeInterval(30)
    }
}

struct SupabaseUser: Codable, Equatable, Identifiable {
    var id: UUID
    var email: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
    }
}

struct SupabaseAuthResponse: Codable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String
    var expiresIn: TimeInterval
    var user: SupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case user
    }

    var session: SupabaseAuthSession {
        SupabaseAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresAt: Date().addingTimeInterval(expiresIn),
            user: user
        )
    }
}

struct SupabaseAuthUserResponse: Codable {
    var user: SupabaseUser
}


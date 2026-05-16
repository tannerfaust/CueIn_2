import Foundation

struct SupabaseConfiguration: Equatable {
    static let urlDefaultsKey = "cuein.supabase.projectURL"
    static let anonKeyDefaultsKey = "cuein.supabase.anonKey"
    static let redirectURLDefaultsKey = "cuein.supabase.redirectURL"

    var projectURL: URL
    var anonKey: String
    var redirectURL: URL

    static var current: SupabaseConfiguration? {
        let defaults = UserDefaults.standard
        let rawURL = defaults.string(forKey: urlDefaultsKey)
            ?? Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let rawAnonKey = defaults.string(forKey: anonKeyDefaultsKey)
            ?? Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        let rawRedirectURL = defaults.string(forKey: redirectURLDefaultsKey) ?? "cuein://auth/callback"

        guard
            let rawURL,
            let rawAnonKey,
            let projectURL = normalizedProjectURL(from: rawURL),
            let redirectURL = URL(string: rawRedirectURL),
            !rawAnonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return SupabaseConfiguration(
            projectURL: projectURL,
            anonKey: rawAnonKey,
            redirectURL: redirectURL
        )
    }

    static func save(projectURL: String, anonKey: String, redirectURL: String) {
        let defaults = UserDefaults.standard
        let normalizedURL = normalizedProjectURL(from: projectURL)?.absoluteString
            ?? projectURL.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(normalizedURL, forKey: urlDefaultsKey)
        defaults.set(anonKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: anonKeyDefaultsKey)
        defaults.set(redirectURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: redirectURLDefaultsKey)
    }

    static func normalizedProjectURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"

        guard var components = URLComponents(string: withScheme),
              let host = components.host,
              host.hasSuffix(".supabase.co")
        else {
            return nil
        }

        components.scheme = "https"
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    var authBaseURL: URL {
        projectURL.appending(path: "auth/v1")
    }

    var restBaseURL: URL {
        projectURL.appending(path: "rest/v1")
    }
}

enum SupabaseConfigurationState: Equatable {
    case missing
    case ready(SupabaseConfiguration)
}

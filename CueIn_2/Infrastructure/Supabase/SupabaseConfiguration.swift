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
        let bundledURL = usableBundledString(for: "SUPABASE_URL")
        let bundledAnonKey = usableBundledString(for: "SUPABASE_ANON_KEY")

        #if DEBUG
        let rawURL = bundledURL ?? usableDefaultsString(for: urlDefaultsKey, defaults: defaults)
        let rawAnonKey = bundledAnonKey ?? usableDefaultsString(for: anonKeyDefaultsKey, defaults: defaults)
        #else
        let rawURL = bundledURL
        let rawAnonKey = bundledAnonKey
        #endif

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

    private static func usableBundledString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        return usableConfigurationString(value)
    }

    private static func usableDefaultsString(for key: String, defaults: UserDefaults) -> String? {
        guard let value = defaults.string(forKey: key) else { return nil }
        return usableConfigurationString(value)
    }

    private static func usableConfigurationString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("$("),
              !trimmed.localizedCaseInsensitiveContains("replace_with")
        else {
            return nil
        }
        return trimmed
    }

    var authBaseURL: URL {
        projectURL.appending(path: "auth/v1")
    }

    var restBaseURL: URL {
        projectURL.appending(path: "rest/v1")
    }

    var functionsBaseURL: URL {
        projectURL.appending(path: "functions/v1")
    }
}

enum SupabaseConfigurationState: Equatable {
    case missing
    case ready(SupabaseConfiguration)
}

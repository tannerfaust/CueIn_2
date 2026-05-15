import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
#if os(iOS)
import UIKit
#endif

@Observable
@MainActor
final class SupabaseAuthStore {
    static let shared = SupabaseAuthStore()

    private let client: SupabaseClient
    private let tokenStore: KeychainTokenStore

    var session: SupabaseAuthSession?
    var isWorking = false
    var lastError: String?
    var lastMagicLinkEmail: String?
    var pendingAppleNonce: String?

    var configurationState: SupabaseConfigurationState {
        if let config = SupabaseConfiguration.current {
            return .ready(config)
        }
        return .missing
    }

    var isSignedIn: Bool {
        session != nil
    }

    private init() {
        self.client = SupabaseClient.shared
        self.tokenStore = KeychainTokenStore.shared
        self.session = tokenStore.load()
    }

    func configure(projectURL: String, anonKey: String, redirectURL: String) {
        SupabaseConfiguration.save(projectURL: projectURL, anonKey: anonKey, redirectURL: redirectURL)
    }

    func sendMagicLink(email: String) async {
        await perform {
            try await self.client.sendMagicLink(email: email)
            self.lastMagicLinkEmail = email
        }
    }

    func signInWithPassword(email: String, password: String) async {
        await perform {
            let newSession = try await self.client.signInWithPassword(email: email, password: password)
            self.save(newSession)
        }
    }

    func signInWithGoogle() async {
        await signInWithOAuth(provider: "google")
    }

    func signInWithOAuth(provider: String) async {
        guard let config = SupabaseConfiguration.current else {
            lastError = SupabaseClientError.missingConfiguration.localizedDescription
            return
        }

        var components = URLComponents(url: config.authBaseURL.appending(path: "authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: config.redirectURL.absoluteString)
        ]
        guard let url = components?.url else {
            lastError = "Unable to build OAuth URL."
            return
        }

        isWorking = true
        lastError = nil
        do {
            let callback = try await WebOAuthSession.start(url: url, callbackScheme: config.redirectURL.scheme ?? "cuein")
            let fragmentItems = Self.callbackItems(from: callback)
            guard
                let accessToken = fragmentItems["access_token"],
                let refreshToken = fragmentItems["refresh_token"]
            else {
                throw SupabaseClientError.invalidResponse
            }
            let expiresIn = TimeInterval(fragmentItems["expires_in"].flatMap(Double.init) ?? 3600)
            let user = try await client.user(accessToken: accessToken)
            save(
                SupabaseAuthSession(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    tokenType: fragmentItems["token_type"] ?? "bearer",
                    expiresAt: Date().addingTimeInterval(expiresIn),
                    user: user
                )
            )
        } catch {
            lastError = error.localizedDescription
        }
        isWorking = false
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        guard
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8)
        else {
            lastError = "Apple did not return an identity token."
            return
        }

        await perform {
            let newSession = try await self.client.signInWithIDToken(
                provider: "apple",
                idToken: token,
                nonce: self.pendingAppleNonce
            )
            self.save(newSession)
            self.pendingAppleNonce = nil
        }
    }

    func refreshIfNeeded() async {
        guard let current = session, current.isExpired else { return }
        await perform {
            let newSession = try await self.client.refreshSession(current)
            self.save(newSession)
        }
    }

    func signOut() async {
        guard let current = session else {
            tokenStore.clear()
            return
        }
        await perform {
            try await self.client.signOut(current)
            self.clearSession()
        }
    }

    func deleteAccount() async {
        guard let current = session else { return }
        await perform {
            try await self.client.deleteAccount(session: current)
            self.clearSession()
        }
    }

    func makeAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        pendingAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        isWorking = true
        lastError = nil
        do {
            try await operation()
        } catch {
            lastError = error.localizedDescription
        }
        isWorking = false
    }

    private func save(_ newSession: SupabaseAuthSession) {
        session = newSession
        tokenStore.save(newSession)
    }

    private func clearSession() {
        session = nil
        tokenStore.clear()
    }

    private static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            guard status == errSecSuccess else { fatalError("Unable to generate nonce.") }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    private static func callbackItems(from url: URL) -> [String: String] {
        var items: [String: String] = [:]
        let fragments = url.fragment?.split(separator: "&").map(String.init) ?? []
        let queries = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for item in queries {
            items[item.name] = item.value
        }
        for fragment in fragments {
            let parts = fragment.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            items[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
        }
        return items
    }
}

private enum WebOAuthSession {
    #if os(iOS)
    @MainActor private static var activePresenter: WebAuthenticationPresenter?
    #endif
    @MainActor private static var activeSession: ASWebAuthenticationSession?

    @MainActor
    static func start(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                activeSession = nil
                #if os(iOS)
                activePresenter = nil
                #endif
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? SupabaseClientError.invalidResponse)
                }
            }
            #if os(iOS)
            let presenter = WebAuthenticationPresenter()
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
private final class WebAuthenticationPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#endif

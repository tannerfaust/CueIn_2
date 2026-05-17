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
    var lastAuthNotice: String?
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
            self.lastAuthNotice = nil
            await CueInSyncRuntimeBridge.shared.migrateAndSyncCurrentWorkspace()
        }
    }

    func signUpWithPassword(email: String, password: String) async {
        await perform {
            let response = try await self.client.signUpWithPassword(email: email, password: password)
            if let session = response.session {
                self.save(session)
                self.lastAuthNotice = nil
                await CueInSyncRuntimeBridge.shared.migrateAndSyncCurrentWorkspace()
            } else {
                self.lastAuthNotice = "Account created. Confirm your email, then sign in."
            }
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
            try await handleCallback(callback)
            await CueInSyncRuntimeBridge.shared.migrateAndSyncCurrentWorkspace()
        } catch {
            lastError = error.localizedDescription
        }
        isWorking = false
    }

    func handleIncomingURL(_ url: URL) async {
        await perform {
            try await self.handleCallback(url)
            await CueInSyncRuntimeBridge.shared.migrateAndSyncCurrentWorkspace()
        }
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
            await CueInSyncRuntimeBridge.shared.migrateAndSyncCurrentWorkspace()
        }
    }

    func refreshIfNeeded() async {
        guard let current = session, current.isExpired else { return }
        await perform {
            let newSession = try await self.client.refreshSession(current)
            self.save(newSession)
            await CueInSyncEngine.shared.syncNow()
        }
    }

    func validateStoredSession() async {
        guard let current = session else { return }
        if current.isExpired {
            await refreshIfNeeded()
            return
        }
        do {
            let user = try await client.user(accessToken: current.accessToken)
            if user != current.user {
                var next = current
                next.user = user
                save(next)
            }
        } catch {
            if Self.shouldClearSession(for: error) {
                clearStaleSessionAfterBackendRejection()
            }
        }
    }

    func signOut() async {
        guard let current = session else {
            tokenStore.clear()
            return
        }
        isWorking = true
        lastError = nil
        lastAuthNotice = nil
        do {
            try await client.signOut(current)
            clearSession()
        } catch {
            if Self.shouldClearSession(for: error) {
                clearSession()
                lastAuthNotice = "Session cleared."
            } else {
                lastError = error.localizedDescription
            }
        }
        isWorking = false
    }

    func deleteAccount() async {
        guard let current = session else { return }
        isWorking = true
        lastError = nil
        lastAuthNotice = nil
        do {
            try await client.deleteAccount(session: current)
            clearSession()
            lastAuthNotice = "Account deleted."
        } catch {
            if Self.shouldClearSession(for: error) {
                clearSession()
                lastAuthNotice = "This account was already deleted. Local session cleared."
            } else {
                lastError = error.localizedDescription
            }
        }
        isWorking = false
    }

    func clearStaleSessionAfterBackendRejection() {
        clearSession()
        lastError = nil
        lastAuthNotice = "Your account session is no longer valid. Sign in again to sync."
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
        lastAuthNotice = nil
        do {
            try await operation()
        } catch {
            if Self.shouldClearSession(for: error) {
                clearStaleSessionAfterBackendRejection()
            } else {
                lastError = error.localizedDescription
            }
        }
        isWorking = false
    }

    private func save(_ newSession: SupabaseAuthSession) {
        session = newSession
        tokenStore.save(newSession)
    }

    private func handleCallback(_ url: URL) async throws {
        let callbackValues = Self.callbackItems(from: url)
        guard
            let accessToken = callbackValues["access_token"],
            let refreshToken = callbackValues["refresh_token"]
        else {
            throw SupabaseClientError.invalidResponse
        }

        let expiresIn = TimeInterval(callbackValues["expires_in"].flatMap(Double.init) ?? 3600)
        let user = try await client.user(accessToken: accessToken)
        save(
            SupabaseAuthSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                tokenType: callbackValues["token_type"] ?? "bearer",
                expiresAt: Date().addingTimeInterval(expiresIn),
                user: user
            )
        )
    }

    private func clearSession() {
        session = nil
        tokenStore.clear()
    }

    private static func shouldClearSession(for error: Error) -> Bool {
        guard let clientError = error as? SupabaseClientError else { return false }
        return clientError.invalidatesAuthSession
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

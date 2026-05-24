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
    private var activeRefreshTask: Task<Void, Never>?
    private var lastRefreshFailedAt: Date?

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
        AppLogger.shared.log("Configuring Supabase with project URL: \(projectURL)", category: .system)
        SupabaseConfiguration.save(projectURL: projectURL, anonKey: anonKey, redirectURL: redirectURL)
    }

    func sendMagicLink(email: String) async {
        AppLogger.shared.log("Requesting Magic Link for \(email)", category: .system)
        await perform {
            try await self.client.sendMagicLink(email: email)
            self.lastMagicLinkEmail = email
            AppLogger.shared.log("Magic Link request succeeded for \(email)", category: .system)
        }
    }

    func signInWithPassword(email: String, password: String) async {
        AppLogger.shared.log("Attempting sign-in with password for \(email)", category: .system)
        await perform {
            let newSession = try await self.client.signInWithPassword(email: email, password: password)
            self.save(newSession)
            self.lastAuthNotice = nil
            AppLogger.shared.log("Sign-in succeeded for \(email)", category: .system)
            await CueInSyncRuntimeBridge.shared.migrateAndSyncCurrentWorkspace()
        }
    }

    func signUpWithPassword(email: String, password: String) async {
        AppLogger.shared.log("Attempting sign-up with password for \(email)", category: .system)
        await perform {
            let response = try await self.client.signUpWithPassword(email: email, password: password)
            if let session = response.session {
                self.save(session)
                self.lastAuthNotice = nil
                AppLogger.shared.log("Sign-up succeeded and logged in automatically for \(email)", category: .system)
                await CueInSyncRuntimeBridge.shared.migrateAndSyncCurrentWorkspace()
            } else {
                self.lastAuthNotice = "Account created. Confirm your email, then sign in."
                AppLogger.shared.log("Sign-up succeeded for \(email) (requires email confirmation)", category: .system)
            }
        }
    }

    func signInWithGoogle() async {
        AppLogger.shared.log("Triggered Google OAuth sign-in", category: .system)
        await signInWithOAuth(provider: "google")
    }

    func signInWithOAuth(provider: String) async {
        AppLogger.shared.log("Attempting OAuth sign-in with provider: \(provider)", category: .system)
        guard let config = SupabaseConfiguration.current else {
            let err = SupabaseClientError.missingConfiguration
            AppLogger.shared.error(err, message: "Missing Supabase configuration for OAuth")
            lastError = err.localizedDescription
            return
        }

        var components = URLComponents(url: config.authBaseURL.appending(path: "authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: config.redirectURL.absoluteString)
        ]
        guard let url = components?.url else {
            let msg = "Unable to build OAuth URL."
            AppLogger.shared.error(SupabaseClientError.invalidResponse, message: msg)
            lastError = msg
            return
        }

        isWorking = true
        lastError = nil
        do {
            let callback = try await WebOAuthSession.start(url: url, callbackScheme: config.redirectURL.scheme ?? "cuein")
            try await handleCallback(callback)
            AppLogger.shared.log("OAuth sign-in succeeded for provider \(provider)", category: .system)
            await CueInSyncRuntimeBridge.shared.migrateAndSyncCurrentWorkspace()
        } catch {
            AppLogger.shared.error(error, message: "OAuth sign-in failed for provider \(provider)")
            lastError = error.localizedDescription
        }
        isWorking = false
    }

    func handleIncomingURL(_ url: URL) async {
        AppLogger.shared.log("Handling incoming auth callback URL: \(url.host ?? "")", category: .system)
        await perform {
            try await self.handleCallback(url)
            AppLogger.shared.log("Auth callback URL processed successfully", category: .system)
            await CueInSyncRuntimeBridge.shared.migrateAndSyncCurrentWorkspace()
        }
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        guard
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8)
        else {
            let msg = "Apple did not return an identity token."
            AppLogger.shared.error(SupabaseClientError.invalidResponse, message: msg)
            lastError = msg
            return
        }

        AppLogger.shared.log("Attempting sign-in with Apple", category: .system)
        await perform {
            let newSession = try await self.client.signInWithIDToken(
                provider: "apple",
                idToken: token,
                nonce: self.pendingAppleNonce
            )
            self.save(newSession)
            self.pendingAppleNonce = nil
            AppLogger.shared.log("Apple sign-in succeeded", category: .system)
            await CueInSyncRuntimeBridge.shared.migrateAndSyncCurrentWorkspace()
        }
    }

    func refreshIfNeeded() async {
        guard let current = session, current.isExpired else { return }
        if let lastFailed = lastRefreshFailedAt, Date().timeIntervalSince(lastFailed) < 15 {
            return
        }
        if let existingTask = activeRefreshTask {
            await existingTask.value
            return
        }
        let task = Task {
            AppLogger.shared.log("Token expired; attempting refresh", category: .system)
            await perform {
                do {
                    let newSession = try await self.client.refreshSession(current)
                    self.save(newSession)
                    AppLogger.shared.log("Token refresh succeeded", category: .system)
                } catch {
                    self.lastRefreshFailedAt = Date()
                    throw error
                }
            }
        }
        activeRefreshTask = task
        await task.value
        activeRefreshTask = nil
    }

    func validateStoredSession() async {
        guard let current = session else { return }
        if current.isExpired {
            AppLogger.shared.log("Stored session expired during validation. Refreshing...", category: .system)
            await refreshIfNeeded()
            return
        }
        do {
            let user = try await client.user(accessToken: current.accessToken)
            if user != current.user {
                AppLogger.shared.log("User details changed in database; updating local profile", category: .system)
                var next = current
                next.user = user
                save(next)
            }
        } catch {
            AppLogger.shared.error(error, message: "Stored session validation failed")
            if Self.shouldClearSession(for: error) {
                clearStaleSessionAfterBackendRejection()
            }
        }
    }

    func signOut() async {
        guard let current = session else {
            AppLogger.shared.log("Sign-out requested but no local session found. Clearing token store.", category: .system)
            tokenStore.clear()
            return
        }
        AppLogger.shared.log("Signing out user: \(current.user.email ?? "")", category: .system)
        isWorking = true
        lastError = nil
        lastAuthNotice = nil
        do {
            try await client.signOut(current)
            clearSession()
            AppLogger.shared.log("Sign-out succeeded on remote server and local session cleared", category: .system)
        } catch {
            AppLogger.shared.error(error, message: "Remote sign-out failed")
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
        AppLogger.shared.log("Requesting account deletion for user: \(current.user.email ?? "")", category: .system)
        isWorking = true
        lastError = nil
        lastAuthNotice = nil
        do {
            try await client.deleteAccount(session: current)
            clearSession()
            lastAuthNotice = "Account deleted."
            AppLogger.shared.log("Account deletion succeeded", category: .system)
        } catch {
            AppLogger.shared.error(error, message: "Account deletion failed")
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
        AppLogger.shared.log("Stale authentication session rejected by backend. Clearing local session.", category: .system)
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
            AppLogger.shared.error(error, message: "Authentication operation failed during perform")
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

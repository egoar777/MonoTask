import AuthenticationServices
import Foundation
import Observation
import SwiftData
import Supabase

@Observable
@MainActor
final class AuthManager {
    static let shared = AuthManager()
    static let callbackScheme = "com.monotask.ios"
    private static let emailCallbackURL = URL(string: "\(callbackScheme)://auth-callback")!
    private static let socialCallbackURL = URL(string: "\(callbackScheme)://oauth-callback")!

    enum SocialProvider: String {
        case google, apple

        var name: String { self == .google ? "Google" : "Apple" }
        var supabaseProvider: Provider { self == .google ? .google : .apple }
    }

    private struct AuthSettings: Decodable {
        let external: [String: Bool]
    }

    private(set) var userID: UUID?
    private(set) var email: String?
    var activeContainer: ModelContainer?
    var isRestoring = true
    var isBusy = false
    private(set) var activeSocialProvider: SocialProvider?
    var errorMessage: String?
    var infoMessage: String?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var authEventsTask: Task<Void, Never>?

    private init() {}

    func start() async {
        guard !started else { return }
        started = true
        guard let client = SupabaseService.shared.client else {
            errorMessage = "Supabase не настроен."
            isRestoring = false
            return
        }
        // Keep a cached session available for local work when the network is down.
        if let session = client.auth.currentSession { setSession(session) }
        authEventsTask = Task { @MainActor in
            for await (event, session) in client.auth.authStateChanges {
                if event == .signedOut || event == .userDeleted {
                    clearSession()
                } else if let session {
                    setSession(session)
                }
            }
        }
        if NetworkMonitor.shared.isConnected {
            if let session = try? await client.auth.session {
                setSession(session)
            } else if client.auth.currentSession == nil {
                clearSession()
            }
        }
        isRestoring = false
    }

    func signIn(email: String, password: String) async {
        guard !isBusy, let client = SupabaseService.shared.client else { return }
        isBusy = true
        errorMessage = nil
        infoMessage = nil
        defer { isBusy = false }
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            setSession(session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        guard !isBusy, let client = SupabaseService.shared.client else { return }
        isBusy = true
        errorMessage = nil
        infoMessage = nil
        defer { isBusy = false }
        do {
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                redirectTo: Self.emailCallbackURL
            )
            if let session = response.session {
                setSession(session)
            } else {
                infoMessage = "Проверьте почту и подтвердите адрес, затем войдите."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(
        with provider: SocialProvider,
        launchFlow: @escaping @MainActor @Sendable (URL) async throws -> URL
    ) async {
        guard !isBusy else { return }
        guard let client = SupabaseService.shared.client,
            let projectURL = SupabaseConfig.shared.cleanUrl
        else {
            errorMessage = "Вход через \(provider.name) пока недоступен."
            return
        }
        isBusy = true
        activeSocialProvider = provider
        errorMessage = nil
        infoMessage = nil
        defer {
            isBusy = false
            activeSocialProvider = nil
        }
        do {
            var request = URLRequest(url: projectURL.appending(path: "auth/v1/settings"), timeoutInterval: 10)
            request.allHTTPHeaderFields = client.headers
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let settings = try JSONDecoder().decode(AuthSettings.self, from: data)
            guard settings.external[provider.rawValue] == true else {
                errorMessage = "Вход через \(provider.name) ещё не подключён."
                return
            }
            let session = try await client.auth.signInWithOAuth(
                provider: provider.supabaseProvider,
                redirectTo: Self.socialCallbackURL,
                queryParams: provider == .google ? [("prompt", "select_account")] : [],
                launchFlow: { url in
                    let callback = try await launchFlow(url)
                    guard Self.matchesCallback(callback, expected: Self.socialCallbackURL) else {
                        throw URLError(.badURL)
                    }
                    return callback
                }
            )
            setSession(session)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch is CancellationError {
            return
        } catch let error as URLError
            where error.code == .notConnectedToInternet || error.code == .networkConnectionLost
        {
            errorMessage = "Нет подключения к интернету. Подключитесь и попробуйте снова."
        } catch {
            errorMessage = "Не удалось войти через \(provider.name). Попробуйте ещё раз."
        }
    }

    func signOut() async {
        guard !isBusy, let client = SupabaseService.shared.client else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await client.auth.signOut(scope: .local)
            clearSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleAuthURL(_ url: URL) async {
        guard !isBusy, userID == nil, Self.matchesCallback(url, expected: Self.emailCallbackURL),
            let client = SupabaseService.shared.client
        else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let session = try await client.auth.session(from: url)
            setSession(session)
        } catch {
            errorMessage = "Не удалось подтвердить адрес. Откройте ссылку из последнего письма на этом устройстве или войдите с паролем."
        }
    }

    private static func matchesCallback(_ url: URL, expected: URL) -> Bool {
        url.scheme == expected.scheme && url.host == expected.host && url.path == expected.path
            && url.user == nil && url.password == nil && url.port == nil
    }

    private func setSession(_ session: Session) {
        if userID != session.user.id { TaskDeletionManager.shared.commitPending() }
        userID = session.user.id
        email = session.user.email
        errorMessage = nil
    }

    private func clearSession() {
        TaskDeletionManager.shared.commitPending()
        userID = nil
        email = nil
        activeContainer = nil
        SupabaseService.shared.syncStatus = .idle
        SupabaseService.shared.hasPendingChanges = false
        SupabaseService.shared.localChangeRevision = 0
        NotificationService.shared.clearForSignOut()
    }
}

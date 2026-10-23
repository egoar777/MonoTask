import Foundation
import Observation
import SwiftData
import Supabase

@Observable
@MainActor
final class AuthManager {
    static let shared = AuthManager()

    private(set) var userID: UUID?
    private(set) var email: String?
    var activeContainer: ModelContainer?
    var isRestoring = true
    var isBusy = false
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
        guard let client = SupabaseService.shared.client else { return }
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
        guard let client = SupabaseService.shared.client else { return }
        isBusy = true
        errorMessage = nil
        infoMessage = nil
        defer { isBusy = false }
        do {
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                redirectTo: URL(string: "com.monotask.ios://auth-callback")
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

    func signOut() async {
        guard let client = SupabaseService.shared.client else { return }
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
        guard url.scheme == "com.monotask.ios", url.host == "auth-callback",
            let client = SupabaseService.shared.client
        else { return }
        do {
            let session = try await client.auth.session(from: url)
            setSession(session)
        } catch {
            errorMessage = error.localizedDescription
        }
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
        NotificationService.shared.clearForSignOut()
    }
}

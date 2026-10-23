import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    enum ConnectionStatus: Equatable {
        case notConfigured
        case offline
        case checking
        case connected
        case error(String)

        var displayText: String {
            switch self {
            case .notConfigured: return "Не настроено"
            case .offline: return "Оффлайн (изменения локально)"
            case .checking: return "Проверка..."
            case .connected: return "Подключено"
            case .error(let msg): return "Ошибка: \(msg)"
            }
        }
    }

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success(Date)
        case error(String)

        var isSyncing: Bool {
            if case .syncing = self { return true }
            return false
        }

        var displayText: String {
            switch self {
            case .idle: return "Готово"
            case .syncing: return "Синхронизация..."
            case .success(let date):
                let formatter = DateFormatter()
                formatter.dateStyle = .none
                formatter.timeStyle = .short
                return "Синхронизировано в \(formatter.string(from: date))"
            case .error(let msg): return "Ошибка: \(msg)"
            }
        }
    }

    private(set) var client: SupabaseClient?
    var connectionStatus: ConnectionStatus = .notConfigured
    var syncStatus: SyncStatus = .idle

    private init() {
        configureClient()
    }

    func configureClient() {
        guard SupabaseConfig.shared.isConfigured,
            let url = SupabaseConfig.shared.cleanUrl
        else {
            client = nil
            connectionStatus = .notConfigured
            return
        }

        let key = SupabaseConfig.shared.anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
        client = SupabaseClient(supabaseURL: url, supabaseKey: key, options: options)
        connectionStatus = .connected
    }

    func testConnection() async -> Bool {
        if client == nil {
            configureClient()
        }
        guard SupabaseConfig.shared.isConfigured,
            let client = client,
            AuthManager.shared.userID != nil,
            (try? await client.auth.session) != nil
        else {
            connectionStatus = .notConfigured
            return false
        }

        connectionStatus = .checking
        do {
            // Verify connection by attempting to select from monotask_tags
            _ =
                try await client
                .from("monotask_tags")
                .select()
                .limit(1)
                .execute()

            connectionStatus = .connected
            return true
        } catch {
            let errorMsg = error.localizedDescription
            connectionStatus = .error(errorMsg)
            return false
        }
    }
}

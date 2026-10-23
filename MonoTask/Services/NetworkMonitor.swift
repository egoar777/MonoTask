import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.monotask.networkmonitor", qos: .utility)

    private(set) var isConnected: Bool = true
    private(set) var wasOffline: Bool = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let currentlyConnected = (path.status == .satisfied)
                let transitionedFromOffline = !self.isConnected && currentlyConnected

                self.isConnected = currentlyConnected

                if !currentlyConnected {
                    self.wasOffline = true
                    print("[NetworkMonitor] Device is offline")
                    SupabaseService.shared.connectionStatus = .offline
                } else {
                    if transitionedFromOffline || self.wasOffline {
                        print("[NetworkMonitor] Internet restored after offline. Posting .networkRestored")
                        self.wasOffline = false
                        NotificationCenter.default.post(name: .networkRestored, object: nil)
                    }
                    if SupabaseService.shared.connectionStatus == .offline {
                        SupabaseService.shared.connectionStatus =
                            SupabaseConfig.shared.isConfigured ? .connected : .notConfigured
                    }
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
}

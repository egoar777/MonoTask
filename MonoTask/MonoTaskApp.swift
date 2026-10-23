import SwiftUI
import SwiftData

@main
struct MonoTaskApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth = AuthManager.shared

    init() {
        Theme.registerFonts()
        NotificationService.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(auth)
                .preferredColorScheme(Theme.colorScheme)
                .onOpenURL { url in Task { await auth.handleAuthURL(url) } }
                .onReceive(NotificationCenter.default.publisher(for: .networkRestored)) { _ in syncActiveStore() }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in syncActiveStore() }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    syncActiveStore()
                }
                .onReceive(NotificationCenter.default.publisher(for: .macTriggerSync)) { _ in syncActiveStore() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { syncActiveStore() }
                    if phase == .background { TaskDeletionManager.shared.commitPending() }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1060, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новая задача") {
                    NotificationCenter.default.post(name: .macFocusNewTask, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Синхронизировать") {
                    NotificationCenter.default.post(name: .macTriggerSync, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
    }

    private func syncActiveStore() {
        guard auth.userID != nil, let container = auth.activeContainer,
            NetworkMonitor.shared.isConnected
        else { return }
        NotificationService.shared.refresh(context: container.mainContext)
        Task { @MainActor in
            try? await SupabaseSyncService.shared.sync(context: container.mainContext)
        }
    }

    @ViewBuilder private var rootView: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--screenshots") {
            ScreenshotPreviewRoot()
        } else if ProcessInfo.processInfo.arguments.contains("--scroll-gesture-test") {
            ScrollGestureTestRoot()
        } else {
            AuthenticatedRootView()
        }
        #else
        AuthenticatedRootView()
        #endif
    }
}

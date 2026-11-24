import SwiftUI
import SwiftData

struct AuthenticatedRootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var didFinishOnboarding = false
    @State private var container: ModelContainer?
    @State private var containerUserID: UUID?
    @State private var storeError: String?
    @State private var isShowingSignIn = false
    @State private var pendingHomeRevealUserID: UUID?
    #if os(iOS)
    @State private var isMovingLaunchBrand = false
    @State private var hasFinishedLaunch = false

    private var isLaunchBrandVisible: Bool {
        !reduceMotion && !hasFinishedLaunch
    }

    private var canCompleteLaunch: Bool {
        showsOnboarding || !auth.isRestoring
    }

    private var isOpeningWelcome: Bool {
        !showsOnboarding && !auth.isRestoring && auth.userID == nil
    }
    #endif

    private var showsOnboarding: Bool {
        !hasCompletedOnboarding && !didFinishOnboarding
    }

    var body: some View {
        ZStack {
            if !showsOnboarding {
                destination
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(destinationEntrance)
            }
            if showsOnboarding {
                onboarding
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(onboardingExit)
                    .zIndex(1)
            }
        }
        .clipped()
        #if os(iOS)
        .opacity(isLaunchBrandVisible && !isOpeningWelcome ? 0 : 1)
        .animation(
            reduceMotion || isOpeningWelcome ? nil : .easeInOut(duration: 0.36).delay(0.22),
            value: isLaunchBrandVisible
        )
        .allowsHitTesting(!isLaunchBrandVisible)
        .accessibilityHidden(isLaunchBrandVisible)
        .overlayPreferenceValue(AuthBrandBoundsKey.self) { anchor in
            GeometryReader { geometry in
                let target = anchor.map { geometry[$0] }
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let destination = target.map { CGPoint(x: $0.midX, y: $0.midY) } ?? center
                AuthBrandHeader(title: "MonoTask")
                .frame(width: target?.width)
                .position(isMovingLaunchBrand ? destination : center)
            }
            .opacity(isLaunchBrandVisible ? 1 : 0)
            .animation(
                reduceMotion || isOpeningWelcome ? nil : .easeInOut(duration: 0.22),
                value: isLaunchBrandVisible
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .task(id: canCompleteLaunch) { await finishLaunch() }
        #endif
        .background(Theme.Colors.background.ignoresSafeArea())
        .onChange(of: didFinishOnboarding) { _, finished in
            if finished { hasCompletedOnboarding = true }
        }
        .task { await auth.start() }
        .task(id: auth.userID) { await openStoreForCurrentUser() }
    }

    private var onboarding: some View {
        #if os(iOS)
        OnboardingView(isReady: !isLaunchBrandVisible, onSkip: skipOnboarding, onFinish: finishOnboarding)
        #else
        OnboardingView(onSkip: skipOnboarding, onFinish: finishOnboarding)
        #endif
    }

    private var onboardingExit: AnyTransition {
        .asymmetric(insertion: .identity, removal: reduceMotion ? .opacity : .move(edge: .leading))
    }

    private var destinationEntrance: AnyTransition {
        .asymmetric(insertion: reduceMotion ? .opacity : .move(edge: .trailing), removal: .identity)
    }

    @ViewBuilder
    private var destination: some View {
        if auth.isRestoring {
            ProgressView("Восстанавливаем вход…")
        } else if auth.userID == nil || isShowingSignIn {
            #if os(iOS)
            signInView(isLaunching: isLaunchBrandVisible)
            #else
            signInView(isLaunching: false)
            #endif
        } else if let userID = auth.userID {
            if containerUserID == userID, let container {
                NotificationHostView()
                    .modelContainer(container)
                    .opacity(!reduceMotion && pendingHomeRevealUserID == userID ? 0 : 1)
                    .task { revealHome(for: userID) }
                    .id(userID)
            } else if let storeError {
                ContentUnavailableView(
                    "Не удалось открыть данные",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(storeError))
            } else {
                ProgressView("Открываем задачи…")
            }
        }
    }

    private func skipOnboarding() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { hasCompletedOnboarding = true }
    }

    private func finishOnboarding() {
        guard showsOnboarding else { return }
        withAnimation(reduceMotion ? MonoBrandMotion.fade : MonoBrandMotion.page) {
            didFinishOnboarding = true
        }
    }

    private func signInView(isLaunching: Bool) -> some View {
        AuthView(isLaunching: isLaunching, departureUserID: auth.userID) {
            pendingHomeRevealUserID = auth.userID
            isShowingSignIn = false
        }
        .onAppear {
            if auth.userID == nil { isShowingSignIn = true }
        }
    }

    private func revealHome(for userID: UUID) {
        guard pendingHomeRevealUserID == userID, auth.userID == userID else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.36)) {
            pendingHomeRevealUserID = nil
        }
    }

    #if os(iOS)
    private func finishLaunch() async {
        guard canCompleteLaunch, !hasFinishedLaunch else { return }
        if !reduceMotion { try? await Task.sleep(for: .milliseconds(400)) }
        guard !Task.isCancelled else { return }
        if isOpeningWelcome && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.45)) {
                isMovingLaunchBrand = true
            } completion: {
                hasFinishedLaunch = true
            }
        } else {
            hasFinishedLaunch = true
        }
    }
    #endif

    private func openStoreForCurrentUser() async {
        container = nil
        containerUserID = nil
        auth.activeContainer = nil
        storeError = nil
        guard let userID = auth.userID else { return }

        let schema = Schema([
            TaskItem.self, SubtaskItem.self, Tag.self, DailyNote.self,
            WeeklyReview.self, FocusSchedule.self, ActivityEntry.self,
            CompletedHistoryEntry.self, SyncTombstone.self,
        ])
        do {
            let directory = URL.applicationSupportDirectory
                .appending(path: "users/\(userID.uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(
                schema: schema,
                url: directory.appending(path: "MonoTask.store"),
                cloudKitDatabase: .none
            )
            let opened = try ModelContainer(for: schema, configurations: [configuration])
            guard auth.userID == userID else { return }
            container = opened
            containerUserID = userID
            auth.activeContainer = opened
            NotificationService.shared.refresh(context: opened.mainContext)
            try? await SupabaseSyncService.shared.sync(context: opened.mainContext)
        } catch {
            storeError = error.localizedDescription
        }
    }
}

private struct NotificationHostView: View {
    @Environment(\.modelContext) private var context
    @State private var notifications = NotificationService.shared
    @State private var openedTask: TaskItem?
    @State private var missingTask = false

    var body: some View {
        ContentView()
            .sheet(item: $openedTask) { task in TaskEditSheet(task: task) }
            .alert("Задача недоступна", isPresented: $missingTask) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text("Возможно, задача удалена или уведомление относится к другому аккаунту.")
            }
            .task(id: notifications.route) {
                guard let route = notifications.route else { return }
                guard route.userID == AuthManager.shared.userID else {
                    missingTask = true
                    notifications.route = nil
                    return
                }
                NotificationCenter.default.post(name: .dismissTaskEditor, object: nil)
                openedTask = nil
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                if let id = route.taskID {
                    var tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
                    if !tasks.contains(where: { $0.id == id }) {
                        try? await SupabaseSyncService.shared.sync(context: context)
                        tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
                    }
                    guard !Task.isCancelled else { return }
                    openedTask = tasks.first { $0.id == id }
                    missingTask = openedTask == nil
                } else {
                    notifications.morningNavigationToken = UUID()
                }
                notifications.route = nil
            }
    }
}

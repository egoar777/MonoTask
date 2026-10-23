import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @Query private var allTasks: [TaskItem]
    @State private var selectedTab: AppTab = .today
    @State private var isCaptureActive: Bool = false

    init(initialTab: AppTab = .today) {
        _selectedTab = State(initialValue: initialTab)
    }

    private var openTaskCount: Int {
        allTasks.filter { !$0.isDone && !TaskDeletionManager.shared.isPending($0) }.count
    }

    var body: some View {
        #if os(macOS)
        MacRootView(initialTab: selectedTab)
            .overlay(alignment: .bottom) {
                UndoDeletionToast().padding(.bottom, 20)
            }
        #else
        VStack(spacing: 0) {
            ZStack {
                switch selectedTab {
                case .today:
                    TodayView(isCaptureActive: $isCaptureActive, bottomNavigation: AnyView(tabBar))
                case .activity:
                    HeatmapView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if selectedTab != .today {
                tabBar.background(Theme.Colors.tabBarBackground.ignoresSafeArea(edges: .bottom))
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if selectedTab != .today {
                UndoDeletionToast().padding(.bottom, 88)
            }
        }
        .onChange(of: selectedTab) { _, _ in
            isCaptureActive = false
            hideKeyboard()
        }
        .onChange(of: NotificationService.shared.morningNavigationToken) { _, _ in
            selectedTab = .today
        }
        .tint(Theme.Colors.accent)
        .preferredColorScheme(Theme.colorScheme)
        #endif
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        VStack(spacing: 0) {
            Hairline()

            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            guard selectedTab != tab else { return }
            hideKeyboard()
            Haptics.selection()
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: isSelected ? tab.activeSystemImage : tab.systemImage)
                        .font(.system(size: 19, weight: isSelected ? .medium : .light))
                        .frame(width: 28, height: 24)

                    if tab == .today && openTaskCount > 0 && !isSelected {
                        Circle()
                            .fill(Theme.Colors.priority)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -1)
                    }
                }

                Text(tab.title.uppercased())
                    .font(Theme.Typography.numeric(9.5, weight: isSelected ? .bold : .regular))
                    .tracking(0.6)
            }
            .foregroundColor(isSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}

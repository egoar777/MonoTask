import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allTasks: [TaskItem]
    @State private var sharedLists = SharedListStore.shared
    @State private var selectedTab: AppTab = .today
    @State private var isCaptureActive: Bool = false
    @State private var captureDraft = ""
    @State private var capturePriority = false
    @Namespace private var glassMorph
    @Namespace private var navigationSelection
    @State private var isCapturePresented = false
    @State private var captureTag: Tag?

    init(initialTab: AppTab = .today) {
        _selectedTab = State(initialValue: initialTab)
    }

    private var openTaskCount: Int {
        allTasks.filter { !$0.isDone && !TaskDeletionManager.shared.isPending($0) }.count
    }

    var body: some View {
        #if os(macOS)
        MacRootView(initialTab: selectedTab)
            .sheet(isPresented: $sharedLists.isPresented) { SharedListsView() }
            .overlay(alignment: .bottom) {
                UndoDeletionToast().padding(.bottom, 20)
            }
        #else
        ZStack(alignment: .bottom) {
            TodayView(
                isCaptureActive: $isCaptureActive,
                captureTag: $captureTag
            )
            .ignoresSafeArea(.container, edges: .bottom)
            .opacity(selectedTab == .today ? 1 : 0)
            .allowsHitTesting(selectedTab == .today)
            .accessibilityHidden(selectedTab != .today)

            if selectedTab == .activity {
                HeatmapView()
                    .ignoresSafeArea(.container, edges: .bottom)
                    .contentMargins(.bottom, 88, for: .scrollContent)
                    .transition(.opacity)
            } else if selectedTab == .settings {
                SettingsView()
                    .ignoresSafeArea(.container, edges: .bottom)
                    .contentMargins(.bottom, 88, for: .scrollContent)
                    .transition(.opacity)
            }

            UndoDeletionToast().padding(.bottom, 84)

            tabBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())

        .sheet(isPresented: $sharedLists.isPresented) { SharedListsView() }
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
        GeometryReader { geometry in
            GlassCluster {
                ZStack(alignment: .trailing) {
                    if !isCapturePresented {
                        HStack(spacing: 12) {
                            HStack(spacing: 0) {
                                ForEach(AppTab.allCases) { tab in tabButton(tab) }
                            }
                            .padding(4)
                            .frame(width: max(0, geometry.size.width - 72))
                            .modifier(FloatingGlass(shape: Capsule(), id: "tabs", namespace: glassMorph))

                            Button(action: beginCapture) {
                                Image(systemName: "plus")
                                    .font(.system(size: 25, weight: .medium))
                                    .frame(width: 60, height: 60)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .modifier(FloatingGlass(shape: Capsule(), id: "capture", namespace: glassMorph))
                            .accessibilityLabel("Новая задача")
                            .accessibilityHint("Раскрывает строку ввода")
                            .accessibilityIdentifier("navigation-add-task")
                        }
                        .transition(.opacity)
                    } else {
                        FloatingTaskCapture(
                            isPresented: $isCapturePresented,
                            isFocused: $isCaptureActive,
                            title: $captureDraft,
                            highPriority: $capturePriority,
                            activeTag: captureTag
                        )
                        .frame(width: geometry.size.width, height: 60)
                        .modifier(FloatingGlass(shape: Capsule(), id: "capture", namespace: glassMorph))
                        .transition(.opacity)
                    }
                }
            }
        }
        .frame(height: 60)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func beginCapture() {
        Haptics.selection()
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.42)) {
            selectedTab = .today
            isCapturePresented = true
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            guard selectedTab != tab else { return }
            hideKeyboard()
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.38)) {
                selectedTab = tab
            }
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

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.Colors.accent.opacity(0.16))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                        .matchedGeometryEffect(id: "selection", in: navigationSelection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("navigation-\(tab.rawValue)")

    }
}

#Preview {
    ContentView()
}

private struct FloatingTaskCapture: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool
    @Binding var isFocused: Bool
    @Binding var title: String
    @Binding var highPriority: Bool
    let activeTag: Tag?
    @FocusState private var fieldFocused: Bool

    private var canSubmit: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                PriorityToggleButton(isOn: $highPriority, size: 36)
                TextField("Новая задача", text: $title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                SubmitCircleButton(isEnabled: canSubmit, size: 36, action: submit)
                Button {
                    if fieldFocused {
                        fieldFocused = false
                    } else {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.42)) {
                            isPresented = false
                        }
                    }
                } label: {
                    Image(systemName: fieldFocused ? "keyboard.chevron.compact.down" : "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(fieldFocused ? "Скрыть клавиатуру" : "Закрыть ввод")
            }
            .padding(.horizontal, 8)

        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .onChange(of: fieldFocused) { _, focused in isFocused = focused }
        .onChange(of: isFocused) { _, focused in
            if !focused { fieldFocused = false }
        }
        .onChange(of: isPresented) { _, presented in
            if !presented { fieldFocused = false }
        }
    }

    private func submit() {
        guard canSubmit else { fieldFocused = false; return }
        context.createTask(title: title, tag: activeTag, highPriority: highPriority)
        Haptics.light()
        title = ""
        highPriority = false
    }
}

private struct GlassCluster<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 12, content: content)
        } else {
            content()
        }
    }
}

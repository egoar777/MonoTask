import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var keyboard = KeyboardObserver.shared
    @State private var sharedLists = SharedListStore.shared
    @State private var selectedTab: AppTab = .today
    @State private var isCaptureActive: Bool = false
    @State private var captureDraft = ""
    @State private var capturePriority = false
    @Namespace private var glassMorph
    @Namespace private var navigationSelection
    @State private var isCapturePresented = false
    @State private var captureControlsVisible = false
    @State private var captureTag: Tag?

    init(initialTab: AppTab = .today) {
        _selectedTab = State(initialValue: initialTab)
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
                captureTag: $captureTag,
                captureBottomInset: isCapturePresented ? 128 : 88
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

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
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
                ZStack(alignment: .bottomTrailing) {
                    if !isCapturePresented {
                        HStack(spacing: 12) {
                            HStack(spacing: 0) {
                                ForEach(AppTab.allCases) { tab in tabButton(tab) }
                            }
                            .padding(4)
                            .frame(width: max(0, geometry.size.width - 72))
                            .modifier(FloatingGlass(shape: Capsule(), id: "tabs", namespace: glassMorph))
                            Spacer().frame(width: 60)
                        }
                        .transition(.opacity)
                    }

                    // Animate the glass independently so its changing width never moves or clips the text.
                    Color.clear
                        .frame(
                            width: isCapturePresented ? geometry.size.width : 60,
                            height: isCapturePresented ? 100 : 60
                        )
                        .modifier(
                            FloatingGlass(
                                shape: RoundedRectangle(cornerRadius: 28, style: .continuous),
                                id: "capture", namespace: glassMorph
                            )
                        )
                        .allowsHitTesting(false)

                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomTrailing)
            }
            .overlay(alignment: .bottomTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    FloatingTaskCapture(
                        isPresented: $isCapturePresented,
                        isFocused: $isCaptureActive,
                        title: $captureDraft,
                        highPriority: $capturePriority,
                        activeTag: $captureTag
                    )
                    .frame(width: geometry.size.width, height: 100)
                    .animation(nil, value: isCapturePresented)
                    .opacity(captureControlsVisible ? 1 : 0)
                    .animation(nil, value: captureControlsVisible)
                    .allowsHitTesting(captureControlsVisible)
                    .accessibilityHidden(!captureControlsVisible)

                    Button(action: beginCapture) {
                        Image(systemName: "plus")
                            .font(.system(size: 25, weight: .medium))
                            .frame(width: 60, height: 60)
                            .contentShape(Circle())
                    }
                    .buttonStyle(FullSurfaceButtonStyle())
                    .foregroundStyle(Theme.Colors.accent)
                    .opacity(isCapturePresented ? 0 : 1)
                    .allowsHitTesting(!isCapturePresented)
                    .accessibilityHidden(isCapturePresented)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isCapturePresented)
                    .accessibilityLabel("Новая задача")
                    .accessibilityHint("Раскрывает строку ввода")
                    .accessibilityIdentifier("navigation-add-task")
                }
                .frame(width: geometry.size.width, height: 100, alignment: .bottomTrailing)

            }
        }
        .frame(height: isCapturePresented ? 100 : 60)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: isCapturePresented ? 0.22 : 0.18),
            value: isCapturePresented
        )
        .overlay(alignment: .top) {
            UndoDeletionToast()
                .padding(.bottom, 10)
                .alignmentGuide(.top) { $0[.bottom] }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, keyboard.isKeyboardVisible ? 5 : -10)
        .onChange(of: isCapturePresented) { _, presented in
            if !presented {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { captureControlsVisible = false }
            }
        }
    }

    private func beginCapture() {
        Haptics.selection()
        withAnimation(
            reduceMotion ? nil : .easeInOut(duration: 0.22), completionCriteria: .logicallyComplete
        ) {
            selectedTab = .today
            isCapturePresented = true
        } completion: {
            // Reveal the field and every control together, after the glass reaches its final size.
            guard isCapturePresented else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { captureControlsVisible = true }
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
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 28, height: 24)

                }

                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.Colors.fill)
                        .matchedGeometryEffect(id: "selection", in: navigationSelection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(FullSurfaceButtonStyle())
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
    @Binding var activeTag: Tag?
    @FocusState private var fieldFocused: Bool

    private var canSubmit: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                TextField("Новая задача", text: $title)
                    .font(Theme.Typography.body)
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                    .frame(minHeight: 44)
                Button {
                    if fieldFocused {
                        fieldFocused = false
                        isFocused = false
                        hideKeyboard()
                    } else {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { isPresented = false }
                    }
                } label: {
                    Image(systemName: fieldFocused ? "keyboard.chevron.compact.down" : "xmark")
                        .font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FullSurfaceButtonStyle())
                .accessibilityLabel(fieldFocused ? "Скрыть клавиатуру" : "Закрыть ввод")
            }
            HStack(spacing: 8) {
                CaptureCategoryPicker(selection: $activeTag)
                Spacer(minLength: 4)
                PriorityToggleButton(isOn: $highPriority, size: 36)
                SubmitCircleButton(isEnabled: canSubmit, size: 36, action: submit)
                    .accessibilityLabel("Добавить задачу")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
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

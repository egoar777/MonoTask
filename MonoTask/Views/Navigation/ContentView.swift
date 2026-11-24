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
    @State private var capturePriority: Priority = .none
    @State private var captureReminderDate: Date?
    @State private var captureRepeatsReminderDaily = false
    @State private var availableDockWidth: CGFloat?
    @State private var isCapturePresented = false
    @State private var captureHeight: CGFloat = 60
    @State private var captureTag: Tag?
    @State private var sharedCaptureListID: UUID?
    @State private var isFolderOpen = false
    @State private var isFolderClosing = false
    @State private var foldersHomeRequest = 0

    init(initialTab: AppTab = .today) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ClassicFoldersView(
                isCaptureActive: $isCaptureActive,
                captureTag: $captureTag,
                sharedCaptureListID: $sharedCaptureListID, isFolderOpen: $isFolderOpen,
                isFolderClosing: $isFolderClosing,
                captureBottomInset: isCaptureVisible ? captureHeight + 28 : 88,
                homeRequest: foldersHomeRequest
            )
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(.container, edges: .bottom)
            .opacity(selectedTab == .today ? 1 : 0)
            .allowsHitTesting(selectedTab == .today)
            .accessibilityHidden(selectedTab != .today)

            if selectedTab == .activity {
                HeatmapView()
                    .ignoresSafeArea(.container, edges: .bottom)
                    .contentMargins(.bottom, 88, for: .scrollContent)
            } else if selectedTab == .settings {
                SettingsView(bottomContentMargin: 88)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .background(Theme.Colors.background.ignoresSafeArea())

        .sheet(isPresented: $sharedLists.isPresented) { SharedListsView() }
        .onChange(of: isFolderOpen) { _, open in
            isCaptureActive = false
            isCapturePresented = open
            if !open { isFolderClosing = false }
        }
        .onChange(of: isFolderClosing) { _, closing in
            if closing { isCaptureActive = false }
        }
        .onChange(of: selectedTab) { _, tab in
            #if os(macOS)
            if tab == .today {
                if isFolderOpen { isCapturePresented = true }
                return
            }
            #endif
            isCaptureActive = false
            isCapturePresented = false
            hideKeyboard()
        }
        .onChange(of: NotificationService.shared.morningNavigationToken) { _, _ in
            selectedTab = .today
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        .toolbarVisibility(selectedTab == .today ? .visible : .hidden, for: .windowToolbar)
        .onReceive(NotificationCenter.default.publisher(for: .macFocusNewTask)) { _ in
            beginCapture()
            isCaptureActive = true
        }
        #endif
        .tint(Theme.Colors.accent)
        .preferredColorScheme(Theme.colorScheme)
    }

    // MARK: - Tab Bar

    private var isCaptureVisible: Bool { selectedTab == .today && isCapturePresented && !isFolderClosing }
    private var isCaptureExpanded: Bool { isCaptureVisible && isCaptureActive }
    private var dockSideInset: CGFloat { isCaptureExpanded ? 8 : 21 }

    private var tabBar: some View {
        GlassCluster {
            #if os(macOS)
            VStack(alignment: .trailing, spacing: 8) {
                if isCaptureVisible { captureControl }
                HStack(spacing: 12) {
                    macTabBar
                    if !isCaptureVisible { captureControl }
                }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 720)
            #else
            ZStack(alignment: .bottomTrailing) {
                if !isCaptureVisible {
                    GeometryReader { geometry in
                        if #available(iOS 26.0, *) {
                            NativeDockTabBar(selection: $selectedTab, onFoldersDoubleTap: showFoldersHome)
                                .frame(width: geometry.size.width + 42, height: 83)
                                .frame(width: geometry.size.width, height: 62, alignment: .top)
                        } else {
                            NativeDockTabBar(selection: $selectedTab, onFoldersDoubleTap: showFoldersHome)
                                .frame(width: geometry.size.width, height: 49)
                                .frame(height: 62)
                        }
                    }
                    .frame(height: 62)
                    .padding(.trailing, 74)
                    .transition(dockTransition)
                }

                captureControl
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            #endif
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: { height in
            if abs(captureHeight - height) > 0.5 { captureHeight = height }
        }
        .overlay(alignment: .top) {
            UndoDeletionToast()
                .padding(.bottom, 10)
                .alignmentGuide(.top) { $0[.bottom] }
        }
        .padding(.horizontal, dockSideInset)
        .padding(.top, 8)
        #if os(macOS)
        .padding(.bottom, 12)
        #else
        .padding(.bottom, isCaptureExpanded ? 8 : 0)
        #endif
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            availableDockWidth = $0
        }
        .animation(reduceMotion ? nil : keyboard.transitionAnimation, value: isCaptureActive)
        .animation(
            reduceMotion ? nil : .smooth(duration: isCaptureVisible ? 0.36 : 0.20),
            value: isCaptureVisible)
    }

    #if os(macOS)
    private var macTabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    if isSelected && tab == .today {
                        showFoldersHome()
                    } else {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isSelected ? tab.activeSystemImage : tab.systemImage)
                            .font(.system(size: 18, weight: .medium))
                        Text(tab.title)
                            .font(Theme.Typography.caption.weight(.medium))
                    }
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(isSelected ? Theme.Colors.fillStrong : .clear, in: Capsule())
                }
                .buttonStyle(FullSurfaceButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("navigation-\(tab.rawValue)")
            }
        }
        .padding(6)
        .modifier(FloatingGlass(shape: Capsule(), interactive: false))
    }
    #endif

    private var captureControl: some View {
        #if os(macOS)
        let captureWidth = availableDockWidth.map { min(720, max(0, $0 - 2 * dockSideInset)) }
        #else
        let captureWidth = availableDockWidth.map { max(0, $0 - 2 * dockSideInset) }
        #endif
        let shape = RoundedRectangle(cornerRadius: isCaptureVisible ? 28 : 31)
        return ZStack(alignment: .trailing) {
            if isCaptureVisible {
                FloatingTaskCapture(
                    isPresented: $isCapturePresented,
                    isFocused: $isCaptureActive,
                    title: $captureDraft,
                    priority: $capturePriority,
                    reminderDate: $captureReminderDate,
                    repeatsReminderDaily: $captureRepeatsReminderDaily,
                    activeTag: $captureTag,
                    locksFolder: isFolderOpen, sharedListID: sharedCaptureListID
                )
                .frame(width: captureWidth)
                .fixedSize(horizontal: false, vertical: true)
                .transition(dockTransition)
            } else {
                Button(action: beginCapture) {
                    Image(systemName: "plus")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(width: 62, height: 62)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(dockTransition)
                .accessibilityLabel("Новая задача")
                .accessibilityHint("Раскрывает строку ввода")
                .accessibilityIdentifier("navigation-add-task")
            }
        }
        .frame(width: isCaptureVisible ? captureWidth : 62, alignment: .trailing)
        .frame(minHeight: 62)
        .background {
            if isCaptureVisible {
                // The translucent gray settles near #2C2C2E over a dark backdrop.
                shape.inset(by: 1).fill(Color(hex: "#3D3D40").opacity(0.68))
            }
        }
        .clipShape(shape)
        .modifier(
            FloatingGlass(
                shape: shape,
                interactive: !isCaptureVisible,
                tint: isCaptureVisible ? Color(white: 0.10).opacity(0.82) : nil
            ))
    }

    private var dockTransition: AnyTransition {
        reduceMotion ? .identity : .opacity
    }

    private func showFoldersHome() {
        selectedTab = .today
        isCaptureActive = false
        isCapturePresented = false
        hideKeyboard()
        foldersHomeRequest += 1
    }

    private func beginCapture() {
        Haptics.selection()
        selectedTab = .today
        isCapturePresented = true
    }

}

#Preview {
    ContentView()
}

#if os(iOS)
/// Keep selection and touch feedback inside UIKit's system tab bar.
private struct NativeDockTabBar: UIViewRepresentable {
    @Binding var selection: AppTab
    var onFoldersDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITabBar {
        let bar = UITabBar()
        bar.delegate = context.coordinator
        bar.itemPositioning = .fill
        bar.layoutMargins = .zero
        bar.insetsLayoutMarginsFromSafeArea = false
        bar.preservesSuperviewLayoutMargins = false
        bar.items = AppTab.allCases.enumerated().map { index, tab in
            let item = UITabBarItem(
                title: tab.title, image: UIImage(systemName: tab.systemImage),
                selectedImage: UIImage(systemName: tab.activeSystemImage))
            item.tag = index
            item.accessibilityIdentifier = "navigation-\(tab.rawValue)"
            return item
        }
        return bar
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITabBar, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 62)
    }

    func updateUIView(_ bar: UITabBar, context: Context) {
        context.coordinator.parent = self
        bar.tintColor = UIColor(Theme.Colors.accent)
        let index = AppTab.allCases.firstIndex(of: selection) ?? 0
        if let item = bar.items?[index], bar.selectedItem !== item { bar.selectedItem = item }

    }

    @MainActor
    final class Coordinator: NSObject, UITabBarDelegate {
        var parent: NativeDockTabBar
        private var lastFoldersTap: TimeInterval?
        init(_ parent: NativeDockTabBar) { self.parent = parent }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard AppTab.allCases.indices.contains(item.tag) else { return }
            let tab = AppTab.allCases[item.tag]
            parent.selection = tab
            guard tab == .today else {
                lastFoldersTap = nil
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            if let previous = lastFoldersTap, now - previous <= 0.4 {
                lastFoldersTap = nil
                parent.onFoldersDoubleTap()
            } else {
                lastFoldersTap = now
            }
        }
    }
}
#endif

private struct FloatingTaskCapture: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool
    @Binding var isFocused: Bool
    @Binding var title: String
    @Binding var priority: Priority
    @Binding var reminderDate: Date?
    @Binding var repeatsReminderDaily: Bool
    @Binding var activeTag: Tag?
    var locksFolder = false
    var sharedListID: UUID?
    @State private var sharedStore = SharedListStore.shared
    @State private var isReminderPickerPresented = false
    @State private var isCreatingFolder = false
    @State private var proposedReminderDate = Date.now
    @State private var proposedRepeatsDaily = false
    @State private var reminderPickerHeight: CGFloat = 164
    @State private var reminderDateSize: CGSize?
    @ScaledMetric(relativeTo: .body) private var dailyButtonHeight: CGFloat = 34
    @FocusState private var fieldFocused: Bool
    @ObservedObject private var keyboard = KeyboardObserver.shared

    private var canSubmit: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        #if os(macOS)
        let titleAxis = Axis.horizontal
        let collapseIcon = "chevron.down"
        let collapseLabel = "Свернуть ввод"
        #else
        let titleAxis = Axis.vertical
        let collapseIcon = "keyboard.chevron.compact.down"
        let collapseLabel = "Скрыть клавиатуру"
        #endif

        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                TextField(
                    "Новая задача", text: $title,
                    prompt: Text("Новая задача").foregroundStyle(Theme.Colors.textSecondary),
                    axis: titleAxis
                )
                #if os(macOS)
                .textFieldStyle(.plain)
                #endif
                .font(Theme.Typography.body)
                .lineLimit(1...(isFocused ? 6 : 1))
                .focused($fieldFocused)
                .submitLabel(.done)
                .onSubmit(submit)
                .accessibilityIdentifier("task-capture-title")
                .frame(minHeight: 44)
                if !isFocused {
                    priorityMenu
                        .frame(width: 44, height: 44)
                        .transition(.opacity)
                }
                Button {
                    if fieldFocused {
                        fieldFocused = false
                        isFocused = false
                        hideKeyboard()
                    } else {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: isFocused ? collapseIcon : "xmark")
                        .font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .contentTransition(.opacity)
                }
                .buttonStyle(FullSurfaceButtonStyle())
                .modifier(FloatingGlass(shape: Circle().inset(by: 4), interactive: true))
                .accessibilityLabel(isFocused ? collapseLabel : "Закрыть ввод")
            }
            if isFocused {
                HStack(spacing: 8) {
                    if let sharedListID {
                        Label(
                            sharedStore.lists.first { $0.id == sharedListID }?.title ?? "Общая папка",
                            systemImage: "person.2"
                        )
                        .font(Theme.Typography.caption).lineLimit(1)
                    } else if locksFolder {
                        Label(activeTag?.name ?? "Все задачи", systemImage: "folder")
                            .font(Theme.Typography.caption).lineLimit(1)
                    } else {
                        CaptureCategoryPicker(selection: $activeTag, usesFolderTerminology: true) {
                            fieldFocused = false
                            isFocused = false
                            isCreatingFolder = true
                        }
                    }
                    if priority != .none && sharedListID == nil {
                        reminderButton
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: 4)
                    priorityMenu
                        .frame(width: 44, height: 44)
                    SubmitCircleButton(isEnabled: canSubmit, size: 36, action: submit)
                        .accessibilityLabel("Добавить задачу")
                }
                .animation(reduceMotion ? nil : Theme.Motion.standard, value: priority)
                .transition(.opacity)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .foregroundStyle(Theme.Colors.textPrimary)
        .sheet(
            isPresented: $isReminderPickerPresented,
            onDismiss: {
                if isPresented { fieldFocused = true }
            }
        ) {
            reminderPicker
        }
        .sheet(
            isPresented: $isCreatingFolder,
            onDismiss: {
                if isPresented { fieldFocused = true }
            }
        ) {
            TagEditSheet(onCreate: { activeTag = $0 })
        }
        .onChange(of: priority) { _, value in
            if value == .none { clearReminder() }
        }
        .onChange(of: fieldFocused) { _, focused in
            withAnimation(reduceMotion ? nil : keyboard.transitionAnimation) { isFocused = focused }
        }
        .onChange(of: isFocused) { _, focused in fieldFocused = focused }
        #if os(macOS)
        .task {
            await Task.yield()
            if isPresented && isFocused && !Task.isCancelled { fieldFocused = true }
        }
        #endif
        .onChange(of: isPresented) { _, presented in
            if !presented { fieldFocused = false }
        }
    }

    private var reminderButton: some View {
        Button(action: openReminderPicker) {
            Image(systemName: reminderDate == nil ? "bell" : "bell.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(reminderDate == nil ? Theme.Colors.textPrimary : Theme.Colors.priority)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(FullSurfaceButtonStyle())
        .modifier(FloatingGlass(shape: Circle().inset(by: 4), interactive: true))
        .accessibilityLabel("Напоминание")
        .accessibilityValue(reminderSummary)
        .accessibilityIdentifier("capture-reminder")
    }

    private var reminderSummary: String {
        guard let reminderDate else { return "Не задано" }
        return repeatsReminderDaily
            ? reminderDate.taskReminderLabel(repeatsDaily: true)
            : reminderDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var canSaveReminder: Bool { proposedRepeatsDaily || proposedReminderDate > .now }

    private var reminderPicker: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        reminderDateField(trailingPadding: 6)
                        HStack(spacing: 6) {
                            reminderTimeField
                            dailyReminderButton
                        }
                    }
                    VStack(spacing: proposedRepeatsDaily ? 2 : 4) {
                        reminderDateField()
                        reminderTimeField
                        dailyReminderButton
                    }
                }
                .frame(maxWidth: .infinity)

                if !canSaveReminder {
                    Text("Выберите будущее время.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.priority)
                }
                if reminderDate != nil {
                    Button("Удалить напоминание", role: .destructive) {
                        clearReminder()
                        isReminderPickerPresented = false
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: { height in
                reminderPickerHeight = ceil(height) + 60
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Напоминание")
            #if os(macOS)
            .macNavigationHeader {
                Button("Отмена") { isReminderPickerPresented = false }
                .keyboardShortcut(.cancelAction)
                Spacer()
                saveReminderButton
            }
            #else
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { isReminderPickerPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) { saveReminderButton }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: reminderPickerHeight)
        #else
        .presentationDetents([.height(reminderPickerHeight)])
        .presentationDragIndicator(.hidden)
        #endif
    }

    private var saveReminderButton: some View {
        Button("Готово") {
            guard canSaveReminder else { return }
            reminderDate = proposedReminderDate
            repeatsReminderDaily = proposedRepeatsDaily
            isReminderPickerPresented = false
        }
        .disabled(!canSaveReminder)
    }

    private func reminderDateField(trailingPadding: CGFloat = 0) -> some View {
        reminderPickerField("Дата", components: .date, identifier: "capture-reminder-date")
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                reminderDateSize = $0
            }
            .padding(.trailing, trailingPadding)
            .opacity(proposedRepeatsDaily ? 0 : 1)
            .frame(
                width: proposedRepeatsDaily ? 0 : reminderDateSize.map { $0.width + trailingPadding },
                height: proposedRepeatsDaily ? 0 : reminderDateSize?.height,
                alignment: .trailing
            )
            .clipped()
            .allowsHitTesting(!proposedRepeatsDaily)
            .accessibilityHidden(proposedRepeatsDaily)
    }

    private var reminderTimeField: some View {
        reminderPickerField("Время", components: .hourAndMinute, identifier: "capture-reminder-time")
    }

    private func reminderPickerField(
        _ label: LocalizedStringKey, components: DatePickerComponents, identifier: String
    ) -> some View {
        DatePicker(label, selection: $proposedReminderDate, displayedComponents: components)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)
            .environment(\.locale, Locale(identifier: "ru_RU"))
            .accessibilityIdentifier(identifier)
    }

    private var dailyReminderButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                proposedRepeatsDaily.toggle()
            }
        } label: {
            Text("Ежедневно")
                .font(.body)
                .foregroundStyle(proposedRepeatsDaily ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 11)
                .frame(minHeight: dailyButtonHeight)
                .background(proposedRepeatsDaily ? Theme.Colors.accent : Theme.Colors.fillStrong, in: Capsule())
                .drawingGroup()
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(proposedRepeatsDaily ? "Включено" : "Выключено")
        .accessibilityIdentifier("capture-reminder-daily")
    }

    private func openReminderPicker() {
        proposedReminderDate = reminderDate ?? Date.now.addingTimeInterval(3600)
        proposedRepeatsDaily = repeatsReminderDaily
        fieldFocused = false
        isReminderPickerPresented = true
    }

    private func clearReminder() {
        reminderDate = nil
        repeatsReminderDaily = false
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(sharedListID == nil ? Priority.selectable : [Priority.none, .high]) { value in
                Button {
                    priority = value
                    Haptics.selection()
                } label: {
                    Label {
                        Text(value.title)
                    } icon: {
                        value.menuIcon
                    }
                }
            }
        } label: {
            Image(systemName: priority == .none ? "star" : priority.systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(priority == .none ? Theme.Colors.textMuted : priority.color)
                .frame(width: 36, height: 36)
        }
        .menuStyle(.borderlessButton)
        #if os(macOS)
        .menuIndicator(.hidden)
        .frame(width: 36, height: 36)
        #endif
        .modifier(FloatingGlass(shape: Circle(), interactive: true))
        .accessibilityLabel("Приоритет")
        .accessibilityValue(priority.title)
        .accessibilityIdentifier("capture-priority")
    }

    private func submit() {
        guard canSubmit else { fieldFocused = false; return }
        if let sharedListID {
            guard sharedStore.accountID != nil else { return }
            var task = SharedTask(listID: sharedListID, title: title)
            task.isHighPriority = priority == .high
            sharedStore.save(task)
            Task { await sharedStore.sync() }
        } else {
            let date = priority == .none ? nil : reminderDate
            if let date, !repeatsReminderDaily, date <= .now {
                openReminderPicker()
                return
            }
            guard
                let created = context.createTask(
                    title: title, tag: activeTag, highPriority: priority == .high,
                    reminderDate: date, repeatsReminderDaily: repeatsReminderDaily
                )
            else { return }
            created.priority = priority
            context.saveAndSync(delaySeconds: 0.3)
            if date != nil {
                Task { await NotificationService.shared.enableTaskReminders() }
            }
        }
        Haptics.light()
        title = ""
        priority = .none
        clearReminder()
        fieldFocused = true
        Task { @MainActor in
            await Task.yield()
            guard isPresented else { return }
            fieldFocused = true
        }
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

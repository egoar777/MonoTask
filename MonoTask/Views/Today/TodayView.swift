import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\TaskItem.sortOrder), SortDescriptor(\TaskItem.createdAt, order: .reverse)]) private
        var allTasks: [TaskItem]
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var keyboard = KeyboardObserver.shared
    @Binding var captureTag: Tag?
    @Binding var isCaptureActive: Bool
    var captureBottomInset: CGFloat = 88
    var showsHeader: Bool = true
    private let canEditTask: () -> Bool

    @State private var isHeaderCollapsedByScroll = false
    @State private var scope: TaskScope = .all
    @State private var taskToEdit: TaskItem?
    @State private var showCompleted: Bool = false
    @State private var showingClearCompleted: Bool = false
    @State private var targetedTaskId: UUID? = nil
    /// Re-renders the screen when the day rolls over, so "Фокус дня" follows the weekday
    @State private var today: Date = Date.now.startOfDay

    init(
        initialScope: TaskScope = .all,
        isCaptureActive: Binding<Bool> = .constant(false), captureTag: Binding<Tag?> = .constant(nil),
        captureBottomInset: CGFloat = 88, showsHeader: Bool = true,
        canEditTask: @escaping () -> Bool = { true }
    ) {
        self._isCaptureActive = isCaptureActive
        self._captureTag = captureTag
        self.captureBottomInset = captureBottomInset
        self.showsHeader = showsHeader
        self.canEditTask = canEditTask
        self._scope = State(initialValue: initialScope)
    }

    private func editTask(_ task: TaskItem) {
        guard canEditTask() else { return }
        taskToEdit = task
    }

    private var scheduledTags: [Tag] {
        _ = today
        return FocusService.shared.currentFocusTags(allTags: tags, override: nil)
    }

    private var activeScope: TaskScope {
        scope.validated(tags: tags)
    }

    private var activeTag: Tag? {
        activeScope.defaultTag(tags: tags, scheduledTags: scheduledTags)
    }

    private var showsTaskFolder: Bool {
        #if os(macOS)
        if case .tag = activeScope { return false }
        return true
        #else
        return showsHeader
        #endif
    }

    private var filteredTasks: [TaskItem] {
        activeScope.filter(allTasks, scheduledTags: scheduledTags)
            .filter { !TaskDeletionManager.shared.isPending($0) }
    }

    private var openTasks: [TaskItem] {
        filteredTasks.filter { !$0.isDone }
            .sorted { $0.priority.rank > $1.priority.rank }
    }

    private var completedTasks: [TaskItem] {
        filteredTasks.filter(\.isDone)
    }

    var body: some View {
        KeyboardAnchoredLayout {
            VStack(spacing: 0) {
                if showsHeader {
                    FocusHeroCard(
                        compact: keyboard.isKeyboardVisible || isHeaderCollapsedByScroll,
                        collapseAnimation: keyboard.isKeyboardVisible
                            ? keyboard.transitionAnimation : Theme.Motion.standard,
                        tags: tags,
                        scheduledTags: scheduledTags,
                        scope: $scope,
                        today: today,
                        doneCount: completedTasks.count,
                        totalCount: filteredTasks.count,
                        openCount: { chipScope in
                            chipScope.filter(allTasks, scheduledTags: scheduledTags)
                                .filter { !$0.isDone && !TaskDeletionManager.shared.isPending($0) }.count
                        }
                    )
                    .modifier(MediumPriorityDropTarget(tasks: allTasks))
                    .zIndex(10)
                }

                ScrollViewReader { scrollProxy in
                    // Animate membership changes, but let native swipe cells settle without an animated sort.
                    taskList
                        .animation(reduceMotion ? nil : Theme.Motion.standard, value: Set(filteredTasks.map(\.id)))
                        .animation(reduceMotion ? nil : Theme.Motion.standard, value: Set(openTasks.map(\.id)))
                        .animation(reduceMotion ? nil : Theme.Motion.standard, value: Set(completedTasks.map(\.id)))
                        .onScrollGeometryChange(for: CGFloat.self) { geometry in
                            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                        } action: { _, offset in
                            // Keep separate thresholds so the header's height change cannot toggle it back.
                            if offset > 64 {
                                isHeaderCollapsedByScroll = true
                            } else if offset < 8 {
                                isHeaderCollapsedByScroll = false
                            }
                        }
                        .scrollBounceBehavior(showsHeader ? .always : .basedOnSize, axes: .vertical)
                        .scrollDismissesKeyboard(.interactively)
                        .contentMargins(.bottom, captureBottomInset, for: .scrollContent)
                        .monoScrollEdge()
                        .onChange(of: scope) { _, _ in
                            withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                                scrollProxy.scrollTo("top_anchor", anchor: .top)
                            }
                        }
                }
            }
            .modelContainer(modelContext.container)
        } dock: {
            VStack(spacing: 0) {
                #if os(iOS)
                EmptyView()
                #else
                if showsHeader {
                    UndoDeletionToast()
                    FastCaptureBar(
                        activeTag: activeTag,
                        isCaptureActive: $isCaptureActive
                    )
                }
                #endif
            }
            .modelContainer(modelContext.container)
        }
        .ignoresSafeArea(.keyboard)
        .background(Theme.Colors.background.ignoresSafeArea())
        .sheet(item: $taskToEdit) { task in
            TaskEditSheet(task: task)
        }
        .clearCompletedAlert(isPresented: $showingClearCompleted, tasks: completedTasks)
        .onAppear {
            hideKeyboard()
            captureTag = activeTag
            if showsHeader && NotificationService.shared.morningNavigationToken != nil { applyMorningScope() }
        }
        .onChange(of: NotificationService.shared.morningNavigationToken) { _, _ in
            if showsHeader { applyMorningScope() }
        }
        .onDisappear {
            isCaptureActive = false
            hideKeyboard()
        }
        .onChange(of: activeTag?.id) { _, _ in captureTag = activeTag }
        .onChange(of: taskToEdit) { _, _ in
            isCaptureActive = false
            hideKeyboard()
        }
        .onChange(of: tags.map(\.id)) { _, _ in
            // The selected context was deleted (here or on another device)
            if scope != activeScope {
                scope = activeScope
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            today = Date.now.startOfDay
        }
    }

    private func applyMorningScope() {
        switch NotificationService.shared.preferences.morningScope {
        case "all": scope = .all
        case "priority": scope = .highPriority
        default: scope = .all
        }
    }

    @ViewBuilder private var taskList: some View {
        #if os(iOS)
        List {
            taskListContent
                .listRowInsets(
                    EdgeInsets(
                        top: 0, leading: Theme.Spacing.screenPadding, bottom: 0, trailing: Theme.Spacing.screenPadding)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { taskListContent }
                .padding(.horizontal, Theme.Spacing.screenPadding)
                .padding(.bottom, 4)
        }
        #endif
    }

    @ViewBuilder private var taskListContent: some View {
        Color.clear.frame(height: 1)
            .background {
                if !showsHeader { ScrollBounceDisabler() }
            }
            .id("top_anchor")
        if !openTasks.isEmpty {
            taskRows
        } else if showsHeader || !completedTasks.isEmpty {
            emptyState
        }
        if !completedTasks.isEmpty { completedSection }
    }

    // MARK: - Sections

    private var taskRows: some View {
        TaskSectionContainer {
            ForEach(openTasks.map { TaskListEntry(task: $0, completed: false) }) { entry in
                let task = entry.task
                TaskRowView(
                    task: task,
                    allTags: tags,
                    showsTag: showsTaskFolder,
                    isTargeted: targetedTaskId == task.id,
                    onEdit: editTask
                )
                .overlay(alignment: .bottom) {
                    TaskRowSeparator()
                }
                .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.screenPadding, bottom: 0, trailing: 0))
                .dropDestination(for: String.self) { items, _ in
                    targetedTaskId = nil
                    guard let rawId = items.first,
                        let sourceId = UUID(uuidString: rawId),
                        sourceId != task.id
                    else { return false }
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                        modelContext.reorderTask(
                            sourceId, onto: task.id,
                            in: allTasks.filter { !TaskDeletionManager.shared.isPending($0) },
                            highPriority: nil)
                    }
                    return true
                } isTargeted: { targeted in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        targetedTaskId = targeted ? task.id : (targetedTaskId == task.id ? nil : targetedTaskId)
                    }
                }

            }
        }
    }

    private var completedSection: some View {
        TaskSectionContainer {
            HStack {
                Button {
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                        showCompleted.toggle()
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        SectionTitle(text: "Выполнено", count: completedTasks.count)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(showCompleted ? 0 : -90))
                            .foregroundColor(Theme.Colors.textMuted)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FullSurfaceButtonStyle())

                Spacer()

                Button {
                    Haptics.selection()
                    showingClearCompleted = true
                } label: {
                    Image(systemName: "trash")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: Theme.Spacing.touchTargetMin, height: Theme.Spacing.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FullSurfaceButtonStyle())
                .accessibilityLabel("Очистить выполненные")
            }
            .padding(.bottom, 6)
            .padding(.top, 20)

            if showCompleted {
                ForEach(completedTasks.map { TaskListEntry(task: $0, completed: true) }) { entry in
                    let task = entry.task
                    TaskRowView(
                        task: task,
                        allTags: tags,
                        showsTag: showsTaskFolder,
                        onEdit: editTask
                    )
                    .overlay(alignment: .bottom) {
                        TaskRowSeparator()
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.screenPadding, bottom: 0, trailing: 0))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Нет открытых задач")
                .font(Theme.Typography.heading(26))
                .foregroundColor(Theme.Colors.textPrimary)

            Text(
                completedTasks.isEmpty
                    ? "В этом списке нет задач. Добавьте первую через строку ввода."
                    : "Открытых задач в этом списке не осталось."
            )
            .font(Theme.Typography.callout)
            .foregroundColor(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 28)
    }
}

/// Native List flattens both ForEach groups. A task that changes section or priority
/// needs a fresh cell so the system swipe state cannot follow the old position.
private struct TaskListEntry: Identifiable {
    let task: TaskItem
    let id: String

    init(task: TaskItem, completed: Bool) {
        self.task = task
        id = completed ? "completed-\(task.id)" : "open-\(task.id)-\(task.priority.rawValue)"
    }
}

/// iOS must expose every task as a real List row for system swipe actions.
private struct TaskSectionContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(iOS)
        content
        #else
        VStack(alignment: .leading, spacing: 0) { content }
        #endif
    }
}

#Preview {
    TodayView()
}

/// Lives inside scroll content so only the containing folder stops rubber-banding.
struct ScrollBounceDisabler: View {
    var body: some View {
        #if os(iOS)
        ScrollBounceDisablerBridge()
        #else
        EmptyView()
        #endif
    }
}

#if os(iOS)
import UIKit

private struct ScrollBounceDisablerBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MarkerView, context: Context) {
        uiView.disableBounce()
    }

    final class MarkerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            disableBounce()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            disableBounce()
        }

        func disableBounce() {
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    scrollView.bounces = false
                    scrollView.alwaysBounceVertical = false
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
#endif

/// The existing header is the upward drop destination, without adding an idle drop zone.
struct MediumPriorityDropTarget: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tasks: [TaskItem]
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(isTargeted ? Priority.medium.color.opacity(0.12) : Color.clear)
            .accessibilityIdentifier("priority-drop-target")
            .dropDestination(for: String.self) { items, _ in
                guard let value = items.first, let id = UUID(uuidString: value) else { return false }
                var accepted = false
                withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                    accepted = modelContext.prioritizeTask(id, in: tasks)
                }
                if accepted { Haptics.selection() }
                return accepted
            } isTargeted: {
                isTargeted = $0
            }
    }
}

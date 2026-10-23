import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\TaskItem.sortOrder), SortDescriptor(\TaskItem.createdAt, order: .reverse)]) private
        var allTasks: [TaskItem]
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]

    @Binding var isCaptureActive: Bool
    let bottomNavigation: AnyView

    @State private var scope: TaskScope = .focus
    @State private var taskToEdit: TaskItem?
    @State private var showCompleted: Bool = false
    @State private var showingClearCompleted: Bool = false
    @State private var targetedTaskId: UUID? = nil
    /// Re-renders the screen when the day rolls over, so "Фокус дня" follows the weekday
    @State private var today: Date = Date.now.startOfDay

    init(isCaptureActive: Binding<Bool> = .constant(false), bottomNavigation: AnyView = AnyView(EmptyView())) {
        self._isCaptureActive = isCaptureActive
        self.bottomNavigation = bottomNavigation
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

    private var filteredTasks: [TaskItem] {
        activeScope.filter(allTasks, scheduledTags: scheduledTags)
            .filter { !TaskDeletionManager.shared.isPending($0) }
    }

    private var highPriorityTasks: [TaskItem] {
        filteredTasks.filter { $0.isHighPriorityToday && !$0.isDone }
    }

    private var regularTasks: [TaskItem] {
        filteredTasks.filter { !$0.isHighPriorityToday && !$0.isDone }
    }

    private var completedTasks: [TaskItem] {
        filteredTasks.filter(\.isDone)
    }

    var body: some View {
        KeyboardAnchoredLayout {
            VStack(spacing: 0) {
                FocusHeroCard(
                    compact: isCaptureActive,
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
                .animation(.easeInOut(duration: 0.2), value: isCaptureActive)
                .zIndex(10)

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            Color.clear
                                .frame(height: 1)
                                .id("top_anchor")

                            if !highPriorityTasks.isEmpty {
                                taskSection(
                                    title: "Приоритет",
                                    tasks: highPriorityTasks,
                                    labelColor: Theme.Colors.priority,
                                    makeHighPriority: true
                                )
                            }

                            if !regularTasks.isEmpty {
                                taskSection(
                                    title: "Задачи",
                                    tasks: regularTasks,
                                    labelColor: Theme.Colors.textMuted,
                                    makeHighPriority: false
                                )
                            } else if highPriorityTasks.isEmpty {
                                emptyState
                            }

                            if !completedTasks.isEmpty {
                                completedSection
                            }

                        }
                        .padding(.horizontal, Theme.Spacing.screenPadding)
                        .padding(.bottom, 4)
                    }
                    .refreshable {
                        do {
                            try await SupabaseSyncService.shared.sync(context: modelContext)
                            Haptics.success()
                        } catch {
                            print("[TodayView] Pull to refresh failed: \(error)")
                            Haptics.warning()
                        }
                    }
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .scrollDismissesKeyboard(.interactively)
                    .monoScrollEdge()
                    .onChange(of: scope) { _, _ in
                        scrollProxy.scrollTo("top_anchor", anchor: .top)
                    }
                }
            }
            .modelContainer(modelContext.container)
        } dock: {
            VStack(spacing: 0) {
                UndoDeletionToast()
                FastCaptureBar(
                    activeTag: activeTag,
                    isCaptureActive: $isCaptureActive
                )
            }
            .modelContainer(modelContext.container)
        } footer: {
            bottomNavigation
        }
        .ignoresSafeArea(.keyboard)
        .background(Theme.Colors.background.ignoresSafeArea())
        .sheet(item: $taskToEdit) { task in
            TaskEditSheet(task: task)
        }
        .clearCompletedAlert(isPresented: $showingClearCompleted, tasks: completedTasks)
        .onAppear {
            hideKeyboard()
            if NotificationService.shared.morningNavigationToken != nil { applyMorningScope() }
        }
        .onChange(of: NotificationService.shared.morningNavigationToken) { _, _ in applyMorningScope() }
        .onDisappear {
            isCaptureActive = false
            hideKeyboard()
        }
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
        default: scope = .focus
        }
    }

    // MARK: - Sections

    private func taskSection(title: String, tasks: [TaskItem], labelColor: Color, makeHighPriority: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: title, count: tasks.count, color: labelColor)
                .padding(.bottom, 6)

            Hairline()

            ForEach(tasks) { task in
                TaskRowView(
                    task: task,
                    allTags: tags,
                    isTargeted: targetedTaskId == task.id,
                    onEdit: { taskToEdit = $0 }
                )
                .dropDestination(for: String.self) { items, _ in
                    targetedTaskId = nil
                    guard let rawId = items.first,
                        let sourceId = UUID(uuidString: rawId),
                        sourceId != task.id
                    else { return false }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        modelContext.reorderTask(
                            sourceId, onto: task.id,
                            in: allTasks.filter { !TaskDeletionManager.shared.isPending($0) },
                            highPriority: makeHighPriority)
                    }
                    return true
                } isTargeted: { targeted in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        targetedTaskId = targeted ? task.id : (targetedTaskId == task.id ? nil : targetedTaskId)
                    }
                }

                Hairline()
            }
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.2)) {
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
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Haptics.selection()
                    showingClearCompleted = true
                } label: {
                    Text("ОЧИСТИТЬ")
                        .font(Theme.Typography.numeric(10, weight: .medium))
                        .tracking(0.6)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .overlay(Capsule().strokeBorder(Theme.Colors.ruleStrong, lineWidth: 1))
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)

            if showCompleted {
                Hairline()
                ForEach(completedTasks) { task in
                    TaskRowView(
                        task: task,
                        allTags: tags,
                        onEdit: { taskToEdit = $0 }
                    )
                    Hairline()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Нет открытых задач")
                .font(Theme.Typography.heading(26))
                .textCase(.uppercase)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(
                completedTasks.isEmpty
                    ? "В этом списке нет задач. Добавьте первую через строку внизу."
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

#Preview {
    TodayView()
}

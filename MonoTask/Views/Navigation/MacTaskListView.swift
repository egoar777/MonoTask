import SwiftUI
import SwiftData

#if os(macOS)
struct MacTaskListView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\TaskItem.sortOrder), SortDescriptor(\TaskItem.createdAt, order: .reverse)]) private
        var allTasks: [TaskItem]
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]

    let scope: TaskScope
    let today: Date

    @State private var captureTag: Tag?
    @State private var hasCategoryOverride = false
    @State private var taskTitle: String = ""
    @State private var isHighPriority: Bool = false
    @State private var taskToEdit: TaskItem? = nil
    @State private var showCompleted: Bool = false
    @State private var showingClearCompleted: Bool = false
    @State private var targetedTaskId: UUID? = nil
    @FocusState private var isCaptureFocused: Bool

    private var scheduledTags: [Tag] {
        _ = today
        return FocusService.shared.currentFocusTags(allTags: tags, override: nil)
    }

    private var activeTag: Tag? {
        scope.defaultTag(tags: tags, scheduledTags: scheduledTags)
    }

    private var scopeColor: Color {
        switch scope {
        case .focus, .highPriority: return Theme.Colors.accent
        case .tag(let id): return tags.first { $0.id == id }?.color ?? Theme.Colors.textSecondary
        case .all: return Theme.Colors.textSecondary
        }
    }

    private var filteredTasks: [TaskItem] {
        scope.filter(allTasks, scheduledTags: scheduledTags)
            .filter { !TaskDeletionManager.shared.isPending($0) }
    }

    private var openTasks: [TaskItem] {
        filteredTasks.filter { !$0.isDone }
            .sorted { $0.priority.rank > $1.priority.rank }
    }

    private var completedTasks: [TaskItem] {
        filteredTasks.filter(\.isDone)
    }

    private var progress: Double {
        filteredTasks.isEmpty ? 0 : Double(completedTasks.count) / Double(filteredTasks.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                captureBar

                if !openTasks.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(openTasks) { task in
                            row(task, highPriority: nil)
                                .overlay(alignment: .bottom) {
                                    TaskRowSeparator()
                                }
                        }
                    }
                } else {
                    emptyState
                }

                if !completedTasks.isEmpty {
                    completedSection
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 30)
            .padding(.bottom, 48)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : Theme.Motion.standard, value: Set(filteredTasks.map(\.id)))
            .animation(reduceMotion ? nil : Theme.Motion.standard, value: Set(openTasks.map(\.id)))
            .animation(reduceMotion ? nil : Theme.Motion.standard, value: Set(completedTasks.map(\.id)))
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle(scope.title(tags: tags))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .macTriggerSync, object: nil)
                } label: {
                    Label("Синхронизировать", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Синхронизировать (⌘R)")
                .disabled(SupabaseService.shared.syncStatus.isSyncing)
            }
        }
        .sheet(item: $taskToEdit) { task in
            TaskEditSheet(task: task)
        }
        .clearCompletedAlert(isPresented: $showingClearCompleted, tasks: completedTasks)
        .onReceive(NotificationCenter.default.publisher(for: .macFocusNewTask)) { _ in
            isCaptureFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EyebrowLabel(text: today.formattedEyebrowDate)
                Spacer()
                if !completedTasks.isEmpty {
                    Button {
                        showingClearCompleted = true
                    } label: {
                        Text("Очистить выполненные")
                            .font(Theme.Typography.numeric(10, weight: .medium))
                            .tracking(0.6)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .overlay(Capsule().strokeBorder(Theme.Colors.ruleStrong, lineWidth: 1))
                    }
                    .buttonStyle(FullSurfaceButtonStyle())
                }
            }

            HStack(alignment: .center, spacing: 14) {
                if case .tag = scope {
                    Circle()
                        .fill(scopeColor)
                        .frame(width: 12, height: 12)
                }
                Text(headerTitle.uppercased())
                    .font(Theme.Typography.displayLarge)
                    .tracking(Theme.Typography.displayTracking)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.top, 16)

            HStack {
                Text("Выполнено \(completedTasks.count) из \(filteredTasks.count)")
                    .contentTransition(.numericText())
                Spacer()
                Text(progress, format: .percent.precision(.fractionLength(0)))
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.top, 16)
            ProgressLine(progress: progress).padding(.top, 8)
        }
    }

    private var headerTitle: String {
        scope == .focus ? "Сегодня" : scope.title(tags: tags)
    }

    private var headerSubtitle: String? {
        switch scope {
        case .focus:
            if scheduledTags.isEmpty { return nil }
            return scheduledTags.map(\.name).joined(separator: " · ")
        case .all: return "Все папки"
        case .highPriority: return "Высокий и средний приоритет"
        case .tag: return "Одна папка"
        }
    }

    // MARK: - Capture

    private var captureBar: some View {
        let canSubmit = !taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            PriorityToggleButton(isOn: $isHighPriority, size: 30)

            TextField(
                "",
                text: $taskTitle,
                prompt: Text("Новая задача  ⌘N").foregroundColor(Theme.Colors.textMuted)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundColor(Theme.Colors.textPrimary)
            .focused($isCaptureFocused)
            .onSubmit {
                handleCreateTask()
            }

            CaptureCategoryPicker(
                selection: Binding(
                    get: { hasCategoryOverride ? captureTag : activeTag },
                    set: {
                        captureTag = $0; hasCategoryOverride = true
                    }
                )
            )
            .onChange(of: scope) { _, _ in hasCategoryOverride = false }

            SubmitCircleButton(isEnabled: canSubmit, size: 26) {
                handleCreateTask()
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 46)
        .background(Theme.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isCaptureFocused ? Theme.Colors.accent.opacity(0.6) : Theme.Colors.ruleStrong, lineWidth: 1)
        )
    }

    // MARK: - Sections

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                    showCompleted.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SectionTitle(text: "Выполнено", count: completedTasks.count)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showCompleted ? 0 : -90))
                        .foregroundColor(Theme.Colors.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(FullSurfaceButtonStyle())
            .padding(.bottom, 6)

            if showCompleted {
                ForEach(completedTasks) { task in
                    row(task, highPriority: nil)
                        .overlay(alignment: .bottom) {
                            TaskRowSeparator()
                        }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Нет открытых задач")
                .font(Theme.Typography.heading(24))

                .foregroundColor(Theme.Colors.textPrimary)
            Text(
                completedTasks.isEmpty
                    ? "В этом списке нет задач. Нажмите ⌘N, чтобы добавить."
                    : "Открытых задач в этом списке не осталось."
            )
            .font(Theme.Typography.callout)
            .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.vertical, 24)
    }

    private func row(_ task: TaskItem, highPriority: Bool?) -> some View {
        MacTaskRowItem(
            task: task,
            isTargeted: targetedTaskId == task.id,
            allTags: tags,
            showsTag: !isTagScope,
            onEdit: { taskToEdit = $0 },
            onToggleDone: { toggleTaskDone(task) }
        )
        .dropDestination(for: String.self) { items, _ in
            targetedTaskId = nil
            guard let rawId = items.first,
                let sourceId = UUID(uuidString: rawId),
                sourceId != task.id
            else { return false }
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                modelContext.reorderTask(sourceId, onto: task.id, in: allTasks, highPriority: highPriority)
            }
            return true
        } isTargeted: { targeted in
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                targetedTaskId = targeted ? task.id : (targetedTaskId == task.id ? nil : targetedTaskId)
            }
        }
    }

    private var isTagScope: Bool {
        if case .tag = scope { return true }
        return false
    }

    // MARK: - Actions

    private func handleCreateTask() {
        let created = modelContext.createTask(
            title: taskTitle,
            tag: hasCategoryOverride ? captureTag : activeTag,
            highPriority: isHighPriority || scope == .highPriority
        )
        guard created != nil else { return }
        taskTitle = ""
        isHighPriority = false
        isCaptureFocused = true
    }

    private func toggleTaskDone(_ task: TaskItem) {
        withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
            modelContext.setCompleted(task, !task.isDone)
        }
    }
}

// MARK: - Mac Task Row

struct MacTaskRowItem: View {
    @Bindable var task: TaskItem
    let isTargeted: Bool
    let allTags: [Tag]
    var showsTag: Bool = true
    let onEdit: (TaskItem) -> Void
    let onToggleDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("monotask_show_task_notes") private var showNotes = true
    @AppStorage("monotask_compact_rows") private var compactRows = false
    @State private var completing = false
    @State private var isHovered: Bool = false
    private var textExpansion = TaskTextExpansion()

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                guard !completing else { return }
                if task.isDone || reduceMotion {
                    onToggleDone()
                } else {
                    withAnimation(reduceMotion ? nil : Theme.Motion.quick) { completing = true }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(180))
                        guard task.modelContext != nil else { return }
                        onToggleDone()
                        completing = false
                    }
                }
            } label: {
                TaskCheckbox(
                    isDone: task.isDone || completing, size: 19,
                    priorityColor: task.priority == .none ? nil : task.priority.color
                )
                    .scaleEffect(completing ? 0.98 : 1)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FullSurfaceButtonStyle())
            .help(task.isDone ? "Вернуть в работу" : "Отметить выполненной")
            .accessibilityValue(task.isDone ? "" : task.priority.title)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    TaskPreviewText(
                        lineLimit: 2, expansion: textExpansion.presentation,
                        expandedTrailingInset: TaskTextCollapseAccessory.textInset
                    ) {
                        Text(task.title)
                            .font(.system(size: 15))
                            .tracking(0)
                            .strikethrough(task.isDone, color: Theme.Colors.textMuted)
                            .foregroundColor(task.isDone ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                    }
                    if showNotes && !task.notes.isEmpty {
                        TaskPreviewText(
                            lineLimit: 1, expansion: textExpansion.presentation,
                            expandedTrailingInset: TaskTextCollapseAccessory.textInset
                        ) {
                            Text(task.notes).font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
                .modifier(TaskTextCollapseAccessory(expansion: textExpansion.presentation))

                Spacer(minLength: 12)

                if let date = task.dueDate, !task.isDone {
                    Label(date.taskReminderLabel(repeatsDaily: task.repeatsReminderDaily), systemImage: "calendar")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(
                            !task.repeatsReminderDaily && date < .now
                                ? Theme.Colors.warning : Theme.Colors.textSecondary)
                }
                if showNotes && !task.notes.isEmpty {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Colors.textMuted)
                }

                if task.hasSubtasks {
                    let allDone = task.completedSubtasksCount == task.subtasksCount
                    Text("\(task.completedSubtasksCount)/\(task.subtasksCount)")
                        .font(Theme.Typography.numeric(11))
                        .foregroundColor(allDone && !task.isDone ? Theme.Colors.accent : Theme.Colors.textMuted)
                }

                if showsTag, let tag = task.tags.first {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(task.isDone ? Theme.Colors.textMuted : tag.color)
                            .frame(width: 6, height: 6)
                        Text(tag.name)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit(task) }
        }
        .padding(.vertical, compactRows ? 6 : 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(
                    isTargeted
                        ? Theme.Colors.surfaceInteractive
                        : (isHovered ? Theme.Colors.surfaceElevated : Color.clear))
        )
        .onHover { isHovered = $0 }
        .draggable(task.id.uuidString) {
            Text(task.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        }
        .contextMenu {
            TaskContextMenu(task: task, allTags: allTags, onEdit: onEdit, onToggleDone: onToggleDone)
        }
    }
}
#endif

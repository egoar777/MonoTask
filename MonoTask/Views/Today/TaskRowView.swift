import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: TaskItem
    var allTags: [Tag] = []
    var showsTag: Bool = true
    var isTargeted: Bool = false
    let onEdit: (TaskItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("monotask_show_task_notes") private var showNotes = true
    @AppStorage("monotask_compact_rows") private var compactRows = false
    @State private var completing = false
    @State private var checkboxConfirmed = false
    @State private var checkmarkProgress: CGFloat = 0
    @State private var titleCompletion: CGFloat = 0
    @State private var completionOffset: CGFloat = 0
    @State private var completionCommitted = false
    @State private var rowWidth: CGFloat = 0
    @State private var checkboxScale: CGFloat = 1.0
    @State private var lastToggleTime: Date = .distantPast
    private var textExpansion = TaskTextExpansion()

    private var isDeleting: Bool { TaskDeletionManager.shared.isPending(task) }

    private var isDone: Bool {
        task.isDone
    }

    private var primaryTag: Tag? {
        showsTag ? task.tags.first : nil
    }

    private var allSubtasksDone: Bool {
        task.hasSubtasks && task.completedSubtasksCount == task.subtasksCount
    }

    private var hasMeta: Bool {
        primaryTag != nil || task.hasSubtasks
            || (task.dueDate != nil && !isDone)
    }

    var body: some View {
        Group {
            #if os(iOS)
            interactiveRow
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive, action: deleteTask) {
                        Image(systemName: "trash")
                    }
                    .tint(Theme.Colors.danger)
                    .accessibilityLabel("Удалить")
                    .accessibilityIdentifier("task-swipe-delete")

                    Menu {
                        Picker(
                            "Приоритет",
                            selection: Binding(
                                get: { task.priority },
                                set: setSwipePriority
                            )
                        ) {
                            ForEach([Priority.none, .high, .medium]) { priority in
                                Label {
                                    Text(priority.title)
                                } icon: {
                                    priority.menuIcon
                                }
                                .tag(priority)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        Image(systemName: "star")
                    }
                    .menuOrder(.fixed)
                    .tint(Priority.medium.color)
                    .accessibilityLabel("Приоритет")
                    .accessibilityIdentifier("task-swipe-priority")

                    Button {
                        onEdit(task)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .tint(Theme.Colors.fillStrong)
                    .accessibilityLabel("Изменить")
                    .accessibilityIdentifier("task-swipe-edit")
                }
            #else
            interactiveRow
            #endif
        }
        .onDrag {
            NSItemProvider(object: task.id.uuidString as NSString)
        }
        .onAppear(perform: resetCompletionIfRestored)
        .onChange(of: isDone) { _, _ in resetCompletionIfRestored() }
        .task {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--screenshots"),
                ProcessInfo.processInfo.arguments.contains("--animate-completion"), task.sortOrder == 0, !task.isDone
            {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                toggleDone()
            }
            #endif
        }
    }

    private var interactiveRow: some View {
        taskRowContent
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            #if os(iOS)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            #endif
            .contextMenu {
                TaskContextMenu(task: task, allTags: allTags, onEdit: onEdit, onToggleDone: toggleDone)
            }
    }

    private var taskRowContent: some View {
        HStack(alignment: .center, spacing: 4) {

            Button {
                toggleDone()
            } label: {
                TaskCheckbox(
                    isDone: isDone || checkboxConfirmed,
                    priorityColor: task.priority == .none ? nil : task.priority.color,
                    checkmarkProgress: completing ? checkmarkProgress : nil
                )
                .scaleEffect(checkboxScale)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(FullSurfaceButtonStyle())
            .accessibilityLabel(isDone ? "Вернуть в работу" : "Отметить выполненной")
            .accessibilityValue(isDone ? "" : task.priority.title)
            .padding(.leading, 2)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    TaskPreviewText(
                        lineLimit: 2, expansion: textExpansion.presentation,
                        expandedTrailingInset: TaskTextCollapseAccessory.textInset
                    ) {
                        titleText(struck: isDone)
                            .overlay(alignment: .topLeading) {
                                if completing {
                                    titleText(struck: true)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .mask(alignment: .leading) {
                                            Rectangle().scaleEffect(x: titleCompletion, anchor: .leading)
                                        }
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if hasMeta {
                        metaRow
                            .padding(.trailing, textExpansion.isExpanded ? TaskTextCollapseAccessory.textInset : 0)
                    }
                    if showNotes && !task.notes.isEmpty {
                        TaskPreviewText(
                            lineLimit: 1, expansion: textExpansion.presentation,
                            expandedTrailingInset: TaskTextCollapseAccessory.textInset
                        ) {
                            Text(task.notes).font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onEdit(task) }
                .modifier(TaskTextCollapseAccessory(expansion: textExpansion.presentation))

            }
            .padding(.vertical, compactRows ? 8 : 12)
            .padding(.trailing, 14)
        }
        .frame(minHeight: 56)
        .background(isTargeted ? Theme.Colors.fillStrong : Color.clear)
        .contentShape(Rectangle())
        // Animate the SwiftUI content, inside the native List/swipe-action cell.
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            rowWidth = $0
        }
        // Move the checkbox and text as a single rendered row.
        .compositingGroup()
        .offset(x: completionOffset)
    }

    private func titleText(struck: Bool) -> some View {
        Text(task.title)
            .font(Theme.Typography.body)
            .tracking(Theme.Typography.bodyTracking)
            .strikethrough(struck, color: Theme.Colors.textMuted)
            .foregroundColor(isDone || titleCompletion > 0 ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
    }

    #if os(iOS)
    private func setSwipePriority(_ priority: Priority) {
        guard priority != task.priority else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            task.priority = priority
            modelContext.saveAndSync()
        }
    }
    #endif

    private func deleteTask() {
        guard !isDeleting, !completing else { return }
        Haptics.warning()
        withAnimation(.easeInOut(duration: 0.2)) {
            TaskDeletionManager.shared.requestDelete(task, context: modelContext)
        }
    }

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let date = task.dueDate, !isDone {
                Label(date.taskReminderLabel(repeatsDaily: task.repeatsReminderDaily), systemImage: "calendar")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(
                        !task.repeatsReminderDaily && date < .now ? Theme.Colors.warning : Theme.Colors.textSecondary)
            }
            HStack(spacing: 10) {
                if let tag = primaryTag {
                    HStack(spacing: 5) {
                        Circle().fill(isDone ? Theme.Colors.textMuted : tag.color).frame(width: 6, height: 6)
                        Text(tag.name).lineLimit(1)
                    }
                }
                if task.hasSubtasks {
                    Label("\(task.completedSubtasksCount)/\(task.subtasksCount)", systemImage: "checklist")
                        .foregroundStyle(allSubtasksDone && !isDone ? Theme.Colors.success : Theme.Colors.textSecondary)
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func toggleDone() {
        guard !completing, !isDeleting else { return }
        let now = Date.now
        guard now.timeIntervalSince(lastToggleTime) >= 0.4 else { return }
        lastToggleTime = now
        let next = !task.isDone
        if reduceMotion || !next {
            next ? Haptics.light() : Haptics.selection()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                modelContext.setCompleted(task, next)
            }
            return
        }
        completing = true
        withAnimation(.easeInOut(duration: 0.1)) {
            checkboxScale = 0.9
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard task.modelContext != nil else { return }
            Haptics.light()
            withAnimation(.easeInOut(duration: 0.2)) {
                checkboxConfirmed = true
                checkmarkProgress = 1
            }
            withAnimation(.smooth(duration: 0.28)) {
                checkboxScale = 1
            }
            // Overlap confirmation and text feedback so the gesture reads as one motion.
            try? await Task.sleep(for: .milliseconds(90))
            guard task.modelContext != nil else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                titleCompletion = 1
            }
            try? await Task.sleep(for: .milliseconds(220))
            guard task.modelContext != nil else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45), completionCriteria: .logicallyComplete) {
                completionOffset = rowWidth + 32
            } completion: {
                guard task.modelContext != nil else { return }
                // Keep the outgoing cell offscreen while the list removes it.
                completionCommitted = true
                withAnimation(.smooth(duration: 0.32)) {
                    modelContext.setCompleted(task, true)
                }
            }
        }
    }

    private func resetCompletionIfRestored() {
        // Native List can reuse the outgoing cell's state when the task is restored.
        guard completionCommitted, !task.isDone else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            completing = false
            checkboxConfirmed = false
            checkmarkProgress = 0
            titleCompletion = 0
            completionOffset = 0
            completionCommitted = false
        }
    }
}

/// Context menu shared by the iPhone and Mac task rows.
struct TaskContextMenu: View {
    @Environment(\.modelContext) private var modelContext
    let task: TaskItem
    let allTags: [Tag]
    let onEdit: (TaskItem) -> Void
    let onToggleDone: () -> Void

    var body: some View {
        Button {
            onEdit(task)
        } label: {
            Label("Изменить", systemImage: "square.and.pencil")
        }

        Button {
            onToggleDone()
        } label: {
            Label(
                task.isDone ? "Вернуть в работу" : "Выполнено",
                systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark.circle"
            )
        }

        Menu("Приоритет", systemImage: "star") {
            ForEach(Priority.selectable) { priority in
                Button {
                    task.priority = priority
                    modelContext.saveAndSync()
                } label: {
                    Label {
                        Text(priority.title)
                    } icon: {
                        priority.menuIcon
                    }
                }
            }
        }

        if !allTags.isEmpty {
            Menu {
                ForEach(allTags) { tag in
                    let isAssigned = task.tags.contains { $0.id == tag.id }
                    Button {
                        Haptics.selection()
                        modelContext.assign(task, to: isAssigned ? nil : tag)
                    } label: {
                        if isAssigned {
                            Label(tag.name, systemImage: "checkmark")
                        } else {
                            Text(tag.name)
                        }
                    }
                }
            } label: {
                Label("Папка", systemImage: "circle.grid.2x2")
            }
        }

        Divider()

        Button(role: .destructive) {
            Haptics.warning()
            withAnimation {
                TaskDeletionManager.shared.requestDelete(task, context: modelContext)
            }
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }
}

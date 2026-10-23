import SwiftUI
import SwiftData

struct TaskEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var availableTags: [Tag]

    @Bindable var task: TaskItem

    // Edits are buffered and committed once, on "Готово" or when the sheet is
    // swiped away, so every change is marked for sync and an emptied title never sticks.
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var isHighPriorityToday: Bool = false
    @State private var selectedTagId: UUID? = nil
    @State private var subtasksDirty: Bool = false
    @State private var didFinish: Bool = false
    @State private var reminderEnabled = false
    @State private var reminderDate = Date.now.addingTimeInterval(3600)
    @State private var notifications = NotificationService.shared

    @State private var newSubtaskTitle: String = ""
    @State private var targetedSubtaskId: UUID? = nil
    @State private var confirmingDelete: Bool = false
    @FocusState private var isSubtaskFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    titleAndNotes
                    propertiesCard
                    reminderCard
                    subtasksBlock
                    deleteButton
                }
                .padding(.horizontal, Theme.Spacing.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .monoScrollEdge()
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .tint(Theme.Colors.accent)
        #if os(iOS)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Colors.background)
        .presentationCornerRadius(Theme.Radius.sheet)
        #else
        .frame(minWidth: 520, idealWidth: 560, minHeight: 540, idealHeight: 620)
        #endif
        .preferredColorScheme(Theme.colorScheme)
        .onAppear {
            title = task.title
            notes = task.notes
            isHighPriorityToday = task.isHighPriorityToday
            selectedTagId = task.tags.first?.id
            reminderEnabled = task.dueDate != nil
            reminderDate = task.dueDate ?? Date.now.addingTimeInterval(3600)
        }
        .onDisappear {
            isSubtaskFieldFocused = false
            hideKeyboard()
            commitChanges()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissTaskEditor)) { _ in finish() }
        .confirmationDialog("Удалить задачу?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                deleteTask()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                EyebrowLabel(text: task.isDone ? "Задача · выполнена" : "Задача")
                Text("Создана \(task.createdAt.formattedRelative.lowercased())")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textMuted)
            }

            Spacer()

            Button {
                finish()
            } label: {
                Text("Готово")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.onInverse)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Theme.Colors.inverse)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.Spacing.screenPadding)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    // MARK: - Title & Notes

    private var titleAndNotes: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Что нужно сделать?", text: $title, axis: .vertical)
                .font(Theme.Typography.editorTitle)
                .tracking(-0.6)
                .foregroundColor(Theme.Colors.textPrimary)
                .textFieldStyle(.plain)

            TextField("Заметки", text: $notes, axis: .vertical)
                .font(Theme.Typography.callout)
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(2...10)
                .textFieldStyle(.plain)
        }
    }

    // MARK: - Properties

    private var propertiesCard: some View {
        GroupCard {

            HStack(spacing: 12) {
                Image(systemName: isHighPriorityToday ? "flame.fill" : "flame")
                    .font(.system(size: 15))
                    .foregroundColor(isHighPriorityToday ? Theme.Colors.priority : Theme.Colors.textMuted)
                    .frame(width: 20)

                Text("Высокий приоритет")
                    .font(Theme.Typography.callout)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { isHighPriorityToday },
                        set: { newValue in
                            Haptics.selection()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isHighPriorityToday = newValue
                            }
                        }
                    )
                )
                .labelsHidden()
                .tint(Theme.Colors.accent)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)

            if !availableTags.isEmpty {
                Hairline(leading: 46)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "circle.grid.2x2")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.Colors.textMuted)
                            .frame(width: 20)
                        Text("Категория")
                            .font(Theme.Typography.callout)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    .padding(.horizontal, 14)

                    // Scrolls edge to edge so chips are not clipped by the card's inner padding
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(availableTags) { tag in
                                ContextChip(
                                    title: tag.name,
                                    color: tag.color,
                                    isSelected: selectedTagId == tag.id
                                ) {
                                    Haptics.selection()
                                    selectedTagId = selectedTagId == tag.id ? nil : tag.id
                                }
                            }
                        }
                        .padding(.leading, 46)
                        .padding(.trailing, 14)
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Напоминание")
            GroupCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "Напомнить о задаче",
                        isOn: Binding(
                            get: { reminderEnabled },
                            set: { enabled in
                                reminderEnabled = enabled
                                if enabled { Task { await notifications.enableTaskReminders() } }
                            })
                    )
                    .disabled(task.isDone)
                    if reminderEnabled {
                        DatePicker(
                            "Дата и время", selection: $reminderDate,
                            displayedComponents: [.date, .hourAndMinute])
                        if reminderDate <= .now {
                            Text("Это время уже прошло. Выберите будущее время, чтобы получить напоминание.")
                                .foregroundColor(Theme.Colors.priority)
                        }
                        if notifications.authorization == .denied {
                            Text(
                                "Уведомления запрещены в настройках системы. Разрешите их в разделе уведомлений MonoTask."
                            )
                            .foregroundColor(Theme.Colors.priority)
                        } else if !notifications.preferences.enabled || !notifications.preferences.taskReminders {
                            Text("Напоминания задач выключены в настройках MonoTask.")
                                .foregroundColor(Theme.Colors.priority)
                        }
                    }
                    if task.isDone {
                        Text("Задача выполнена — напоминание отменено.")
                    } else {
                        Text(
                            "Время сохраняется вместе с задачей. Напоминание появится на устройствах, где разрешены уведомления."
                        )
                    }
                }
                .font(Theme.Typography.callout)
                .foregroundColor(Theme.Colors.textPrimary)
            }
        }
    }

    // MARK: - Subtasks

    private var subtasksBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Подзадачи")
                Spacer()
                if task.hasSubtasks {
                    Text("\(task.completedSubtasksCount)/\(task.subtasksCount)")
                        .font(Theme.Typography.numeric(12))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            if task.hasSubtasks {
                ProgressLine(progress: task.subtasksProgress)
                    .padding(.bottom, 2)
            }

            GroupCard {
                ForEach(Array(task.sortedSubtasks.enumerated()), id: \.element.id) { index, subtask in
                    if index > 0 {
                        Hairline(leading: 44)
                    }
                    subtaskRow(subtask)
                }

                if task.hasSubtasks {
                    Hairline(leading: 44)
                }

                addSubtaskRow
            }
        }
    }

    private func subtaskRow(_ subtask: SubtaskItem) -> some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(
                    KeyboardObserver.shared.isKeyboardVisible ? nil : .spring(response: 0.25, dampingFraction: 0.7)
                ) {
                    subtask.isCompleted.toggle()
                    subtask.touch()
                    subtasksDirty = true
                }
                subtask.isCompleted ? Haptics.success() : Haptics.light()
            } label: {
                TaskCheckbox(isDone: subtask.isCompleted, size: 19)
                    .frame(width: 32, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TextField(
                "Подзадача",
                text: Binding(
                    get: { subtask.title },
                    set: {
                        subtask.title = $0
                        subtask.touch()
                        subtasksDirty = true
                    }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .strikethrough(subtask.isCompleted, color: Theme.Colors.textMuted)
            .foregroundColor(subtask.isCompleted ? Theme.Colors.textMuted : Theme.Colors.textPrimary)

            Button {
                Haptics.light()
                withAnimation {
                    deleteSubtask(subtask)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.Colors.textMuted)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Colors.textMuted.opacity(0.6))
                .frame(width: 26, height: 36)
                .contentShape(Rectangle())
                .draggable(subtask.id.uuidString) {
                    Text(subtask.title.isEmpty ? "Подзадача" : subtask.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.Colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(minHeight: 44)
        .background(targetedSubtaskId == subtask.id ? Theme.Colors.fillStrong : Color.clear)
        .dropDestination(for: String.self) { items, _ in
            targetedSubtaskId = nil
            guard let rawId = items.first,
                let sourceId = UUID(uuidString: rawId),
                sourceId != subtask.id
            else { return false }
            reorderSubtasks(fromId: sourceId, toId: subtask.id)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                targetedSubtaskId = targeted ? subtask.id : (targetedSubtaskId == subtask.id ? nil : targetedSubtaskId)
            }
        }
    }

    private var addSubtaskRow: some View {
        let canAdd = !newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(canAdd ? Theme.Colors.textPrimary : Theme.Colors.textMuted)
                .frame(width: 32, height: 40)

            TextField("Добавить подзадачу", text: $newSubtaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(Theme.Colors.textPrimary)
                .focused($isSubtaskFieldFocused)
                .submitLabel(.next)
                .onSubmit {
                    handleAddSubtask()
                }

            if canAdd {
                SubmitCircleButton(isEnabled: true, size: 26) {
                    handleAddSubtask()
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(minHeight: 44)
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button {
            Haptics.warning()
            confirmingDelete = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                Text("Удалить задачу")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(Theme.Colors.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Theme.Colors.dangerMuted.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func finish() {
        isSubtaskFieldFocused = false
        hideKeyboard()
        commitChanges()
        Haptics.selection()
        dismiss()
    }

    /// Applies buffered edits once. Unchanged tasks are not marked for sync.
    private func commitChanges() {
        guard !didFinish, !task.isDeleted else { return }
        didFinish = true

        var changed = subtasksDirty

        // Compare trimmed to trimmed so merely opening a task never rewrites it
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty && trimmedTitle != task.title.trimmingCharacters(in: .whitespacesAndNewlines) {
            task.title = trimmedTitle
            changed = true
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNotes != task.notes.trimmingCharacters(in: .whitespacesAndNewlines) {
            task.notes = trimmedNotes
            changed = true
        }

        if isHighPriorityToday != task.isHighPriorityToday {
            task.isHighPriorityToday = isHighPriorityToday
            changed = true
        }

        if selectedTagId != task.tags.first?.id {
            task.tags = availableTags.filter { $0.id == selectedTagId }
            changed = true
        }

        let newReminder = reminderEnabled ? reminderDate : nil
        if task.dueDate != newReminder {
            task.dueDate = newReminder
            changed = true
        }

        if changed {
            task.touch()
            modelContext.saveAndSync(delaySeconds: 0.2)
        }
    }

    private func deleteTask() {
        didFinish = true
        isSubtaskFieldFocused = false
        hideKeyboard()
        withAnimation(.easeInOut(duration: 0.2)) {
            TaskDeletionManager.shared.requestDelete(task, context: modelContext)
        }
        dismiss()
    }

    private func deleteSubtask(_ subtask: SubtaskItem) {
        guard let idx = task.subtasks.firstIndex(where: { $0.id == subtask.id }) else { return }
        task.subtasks.remove(at: idx)
        modelContext.deleteWithSync(subtask)
        task.touch()
        modelContext.saveAndSync(delaySeconds: 0.2)
    }

    private func reorderSubtasks(fromId: UUID, toId: UUID) {
        var items = task.sortedSubtasks
        guard let fromIndex = items.firstIndex(where: { $0.id == fromId }),
            let toIndex = items.firstIndex(where: { $0.id == toId }),
            fromIndex != toIndex
        else { return }

        Haptics.selection()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            let moved = items.remove(at: fromIndex)
            items.insert(moved, at: toIndex)
            for (idx, item) in items.enumerated() where item.sortOrder != idx {
                item.sortOrder = idx
                item.touch()
            }
            subtasksDirty = true
        }
    }

    private func handleAddSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Haptics.selection()
        let nextOrder = (task.subtasks.map(\.sortOrder).max() ?? -1) + 1
        let newSubtask = SubtaskItem(title: trimmed, sortOrder: nextOrder)
        newSubtask.task = task
        task.subtasks.append(newSubtask)
        task.touch()
        modelContext.insert(newSubtask)
        modelContext.saveAndSync(delaySeconds: 0.3)

        newSubtaskTitle = ""

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            isSubtaskFieldFocused = true
        }
    }
}

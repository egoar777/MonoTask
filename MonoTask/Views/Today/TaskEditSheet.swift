import SwiftUI
import SwiftData

struct TaskEditSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var availableTags: [Tag]

    let task: TaskItem

    private struct SubtaskDraft: Identifiable, Equatable {
        let id: UUID
        var title: String
        var isCompleted: Bool
    }

    // The sheet only writes its draft when the user saves.
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var priority: Priority = .none
    @State private var selectedTagId: UUID? = nil
    @State private var originalSubtasks: [SubtaskDraft] = []
    @State private var subtasks: [SubtaskDraft] = []
    @State private var reminderEnabled = false
    @State private var repeatsReminderDaily = false
    @State private var reminderDate = Date.now.addingTimeInterval(3600)
    @State private var notifications = NotificationService.shared

    @State private var newSubtaskTitle: String = ""
    @State private var targetedSubtaskId: UUID? = nil
    @State private var confirmingDelete: Bool = false
    @FocusState private var isSubtaskFieldFocused: Bool

    @ViewBuilder var body: some View {
        #if os(iOS)
        let sheet = NavigationStack {
            editor
                .navigationTitle("Задача")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { cancelButton }
                    ToolbarItem(placement: .confirmationAction) { doneButton }
                }
        }
        .tint(Theme.Colors.accent)
        .interactiveDismissDisabled(hasChanges)
        .presentationDetents([.fraction(0.82)])
        .presentationDragIndicator(.visible)

        if reduceTransparency {
            sheet.presentationBackground(Theme.Colors.background)
        } else if #available(iOS 26.0, *) {
            sheet
        } else {
            sheet.presentationBackground(.ultraThinMaterial)
        }
        #else
        VStack(spacing: 0) {
            HStack {
                cancelButton
                Spacer()
                Text("Задача").font(.headline)
                Spacer()
                doneButton
            }
            .padding(Theme.Spacing.lg)
            editor
        }
        .background(Theme.Colors.background)
        .tint(Theme.Colors.accent)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 540, idealHeight: 620)
        #endif
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                titleAndNotes
                propertiesCard
                reminderCard
                subtasksBlock
                deleteButton
            }
            .padding(.horizontal, Theme.Spacing.screenPadding)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.Colors.textPrimary)
        .tint(Theme.Colors.accent)
        .preferredColorScheme(Theme.colorScheme)
        .onAppear {
            title = task.title
            notes = task.notes
            priority = task.priority
            selectedTagId = task.tags.first?.id
            originalSubtasks = task.sortedSubtasks.map {
                SubtaskDraft(id: $0.id, title: $0.title, isCompleted: $0.isCompleted)
            }
            subtasks = originalSubtasks
            reminderEnabled = task.dueDate != nil
            repeatsReminderDaily = reminderEnabled && task.repeatsReminderDaily
            reminderDate = task.dueDate ?? Date.now.addingTimeInterval(3600)
            Task { await notifications.checkAuthorization() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissTaskEditor)) { _ in finish() }
        .alert("Удалить задачу?", isPresented: $confirmingDelete) {
            Button("Удалить", role: .destructive) {
                deleteTask()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var cancelButton: some View {
        Button(role: .cancel) {
            dismiss()
        } label: {
            Text("Отмена").foregroundStyle(Theme.Colors.textPrimary)
        }
        .keyboardShortcut(.cancelAction)
    }

    private var doneButton: some View {
        Button("Готово", action: finish)
            .fontWeight(.semibold)
            .keyboardShortcut(.defaultAction)
            .disabled(trimmedTitle.isEmpty)
    }

    // MARK: - Details

    private var titleAndNotes: some View {
        GroupCard(padding: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                TextField("Название задачи", text: $title, axis: .vertical)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .frame(minHeight: Theme.Spacing.touchTargetMin)
                    .accessibilityIdentifier("task-editor-title")

                Hairline()

                TextField(
                    "Заметки",
                    text: $notes,
                    prompt: Text("Заметки").foregroundStyle(Theme.Colors.textSecondary),
                    axis: .vertical
                )
                .font(.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2...10)
                .textFieldStyle(.plain)
                .frame(minHeight: Theme.Spacing.touchTargetMin, alignment: .topLeading)
                .accessibilityIdentifier("task-editor-notes")
            }
        }
    }

    private var propertiesCard: some View {
        GroupCard {
            Menu {
                ForEach(Priority.selectable) { value in
                    Button {
                        priority = value
                    } label: {
                        Label {
                            Text(value.title)
                        } icon: {
                            value.menuIcon
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Приоритет").foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Label(priority.title, systemImage: priority.systemImage)
                        .foregroundStyle(priority.color)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Приоритет")
            .accessibilityIdentifier("task-editor-priority")
            .accessibilityValue(priority.title)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(minHeight: 52)

            if !availableTags.isEmpty {
                Hairline(leading: Theme.Spacing.lg)
                folderMenu
            }
        }
        .font(.body)
    }

    private var folderMenu: some View {
        let selectedTag = availableTags.first { $0.id == selectedTagId }
        return Menu {
            Picker("Папка", selection: $selectedTagId) {
                Text("Без папки").tag(nil as UUID?)
                ForEach(availableTags) { tag in
                    Label(tag.name, systemImage: tag.folderIconName).tag(Optional(tag.id))
                }
            }
        } label: {
            let layout =
                dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
            layout {
                Label("Папка", systemImage: "folder")
                folderValue(selectedTag)
                    .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Папка")
        .accessibilityValue(selectedTag?.name ?? "Без папки")
    }

    private func folderValue(_ tag: Tag?) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let tag {
                Circle().fill(tag.color).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Text(tag?.name ?? "Без папки")
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Colors.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeading("Напоминание")
            GroupCard {
                Toggle(isOn: $reminderEnabled) {
                    Label("Напомнить о задаче", systemImage: "bell")
                }
                .disabled(task.isDone)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: 52)
                .accessibilityIdentifier("task-reminder-enabled")

                if reminderEnabled && !task.isDone {
                    Hairline(leading: Theme.Spacing.lg)
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Toggle("Ежедневно", isOn: $repeatsReminderDaily)
                            .frame(minHeight: Theme.Spacing.touchTargetMin)
                            .accessibilityIdentifier("task-reminder-daily")
                        if !repeatsReminderDaily {
                            DatePicker("Дата", selection: $reminderDate, displayedComponents: .date)
                                .frame(minHeight: Theme.Spacing.touchTargetMin)
                        }
                        DatePicker("Время", selection: $reminderDate, displayedComponents: .hourAndMinute)
                            .frame(minHeight: Theme.Spacing.touchTargetMin)
                        if !repeatsReminderDaily && reminderDate <= .now {
                            Text("Выберите будущее время, чтобы получить напоминание.")
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.priority)
                        }
                    }
                    .environment(\.locale, Locale(identifier: "ru_RU"))
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }
            .font(.body)
            .toggleStyle(.switch)

            if task.isDone {
                reminderHint("Задача выполнена. Напоминание отменено.")
            } else if reminderEnabled, notifications.authorization == .denied {
                reminderHint("Разрешите уведомления MonoTask в настройках системы.")
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.standard, value: reminderEnabled)
    }

    private func reminderHint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.xs)
    }

    // MARK: - Subtasks

    private var subtasksBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Подзадачи")

            if !subtasks.isEmpty {
                let completed = subtasks.filter(\.isCompleted).count
                ProgressView(value: Double(completed), total: Double(subtasks.count))
                    .accessibilityLabel("Выполнено подзадач")
                    .accessibilityValue("\(completed) из \(subtasks.count)")
            }

            GroupCard {
                ForEach($subtasks) { $subtask in
                    if subtask.id != subtasks.first?.id {
                        Hairline(leading: 44)
                    }
                    subtaskRow($subtask)
                }

                if !subtasks.isEmpty {
                    Hairline(leading: 44)
                }

                addSubtaskRow
            }
        }
    }

    private func subtaskRow(_ draft: Binding<SubtaskDraft>) -> some View {
        let subtask = draft.wrappedValue
        return HStack(spacing: Theme.Spacing.xs) {
            Button {
                draft.isCompleted.wrappedValue.toggle()
                draft.isCompleted.wrappedValue ? Haptics.success() : Haptics.light()
            } label: {
                TaskCheckbox(isDone: subtask.isCompleted, size: 19)
                    .frame(width: Theme.Spacing.touchTargetMin, height: Theme.Spacing.touchTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isCompleted ? "Отметить как невыполненную" : "Отметить как выполненную")
            .accessibilityValue(subtask.title)

            TextField("Подзадача", text: draft.title)
                .textFieldStyle(.plain)
                .font(.body)
                .strikethrough(subtask.isCompleted, color: Theme.Colors.textSecondary)
                .foregroundStyle(subtask.isCompleted ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)

            Button(role: .destructive) {
                subtasks.removeAll { $0.id == subtask.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: Theme.Spacing.touchTargetMin, height: Theme.Spacing.touchTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить подзадачу")
            .accessibilityValue(subtask.title)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Colors.textMuted.opacity(0.6))
                .frame(width: Theme.Spacing.touchTargetMin, height: Theme.Spacing.touchTargetMin)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
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
        .accessibilityActions {
            if let index = subtasks.firstIndex(where: { $0.id == subtask.id }) {
                if index > 0 {
                    Button("Переместить выше") {
                        reorderSubtasks(fromId: subtask.id, toId: subtasks[index - 1].id)
                    }
                }
                if index + 1 < subtasks.count {
                    Button("Переместить ниже") {
                        reorderSubtasks(fromId: subtask.id, toId: subtasks[index + 1].id)
                    }
                }
            }
        }
        .dropDestination(for: String.self) { items, _ in
            targetedSubtaskId = nil
            guard let rawId = items.first,
                let sourceId = UUID(uuidString: rawId),
                sourceId != subtask.id
            else { return false }
            reorderSubtasks(fromId: sourceId, toId: subtask.id)
            return true
        } isTargeted: { targeted in
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                targetedSubtaskId = targeted ? subtask.id : (targetedSubtaskId == subtask.id ? nil : targetedSubtaskId)
            }
        }
    }

    private var addSubtaskRow: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "plus")
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: Theme.Spacing.touchTargetMin)
                .accessibilityHidden(true)

            TextField(
                "Добавить подзадачу",
                text: $newSubtaskTitle,
                prompt: Text("Добавить подзадачу").foregroundStyle(Theme.Colors.textSecondary)
            )
            .accessibilityIdentifier("task-editor-add-subtask")
            .textFieldStyle(.plain)
            .font(.body)
            .frame(minHeight: Theme.Spacing.touchTargetMin)
            .focused($isSubtaskFieldFocused)
            .submitLabel(.next)
            .onSubmit(handleAddSubtask)

            if !pendingSubtaskTitle.isEmpty {
                SubmitCircleButton(isEnabled: true, size: 26, label: "Добавить подзадачу", action: handleAddSubtask)
            }
        }
        .padding(.trailing, Theme.Spacing.sm)
    }

    private var deleteButton: some View {
        GroupCard {
            Button(role: .destructive) {
                Haptics.warning()
                confirmingDelete = true
            } label: {
                Label("Удалить задачу", systemImage: "trash")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.danger)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var pendingSubtaskTitle: String { newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var draftDeadline: Date? { reminderEnabled ? reminderDate : nil }
    private var draftRepeatsDaily: Bool { reminderEnabled && repeatsReminderDaily }
    private var hasChanges: Bool {
        trimmedTitle != task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            || trimmedNotes != task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            || priority != task.priority
            || selectedTagId != task.tags.first?.id
            || draftDeadline != task.dueDate
            || draftRepeatsDaily != task.repeatsReminderDaily
            || subtasks != originalSubtasks
            || !pendingSubtaskTitle.isEmpty
    }

    private func finish() {
        handleAddSubtask()
        isSubtaskFieldFocused = false
        hideKeyboard()
        commitChanges()
        Haptics.selection()
        dismiss()
    }

    /// Applies buffered edits once. Unchanged tasks are not marked for sync.
    private func commitChanges() {
        guard !task.isDeleted else { return }

        var changed = commitSubtasks()

        // Compare trimmed to trimmed so merely opening a task never rewrites it
        if !trimmedTitle.isEmpty && trimmedTitle != task.title.trimmingCharacters(in: .whitespacesAndNewlines) {
            task.title = trimmedTitle
            changed = true
        }

        if trimmedNotes != task.notes.trimmingCharacters(in: .whitespacesAndNewlines) {
            task.notes = trimmedNotes
            changed = true
        }

        if priority != task.priority {
            task.priority = priority
            changed = true
        }

        if selectedTagId != task.tags.first?.id {
            task.tags = availableTags.filter { $0.id == selectedTagId }
            changed = true
        }

        if task.dueDate != draftDeadline || task.repeatsReminderDaily != draftRepeatsDaily {
            task.dueDate = draftDeadline
            task.repeatsReminderDaily = draftRepeatsDaily
            changed = true
            if reminderEnabled && !task.isDone {
                Task { await notifications.enableTaskReminders() }
            }
        }

        if changed {
            task.touch()
            modelContext.saveAndSync(delaySeconds: 0.2)
        }
    }

    private func deleteTask() {
        isSubtaskFieldFocused = false
        hideKeyboard()
        withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
            TaskDeletionManager.shared.requestDelete(task, context: modelContext)
        }
        dismiss()
    }

    private func commitSubtasks() -> Bool {
        guard subtasks != originalSubtasks else { return false }
        let originals = Dictionary(uniqueKeysWithValues: originalSubtasks.map { ($0.id, $0) })
        let existing = Dictionary(uniqueKeysWithValues: task.subtasks.map { ($0.id, $0) })
        let draftIDs = Set(subtasks.map(\.id))
        let orderChanged = subtasks.map(\.id) != originalSubtasks.map(\.id)

        for item in task.subtasks where originals[item.id] != nil && !draftIDs.contains(item.id) {
            task.subtasks.removeAll { $0.id == item.id }
            modelContext.deleteWithSync(item)
        }
        for (index, draft) in subtasks.enumerated() {
            if let original = originals[draft.id] {
                guard let item = existing[draft.id] else { continue }
                let titleChanged = draft.title != original.title
                let completionChanged = draft.isCompleted != original.isCompleted
                let positionChanged = orderChanged && item.sortOrder != index
                if titleChanged { item.title = draft.title }
                if completionChanged { item.isCompleted = draft.isCompleted }
                if positionChanged { item.sortOrder = index }
                if titleChanged || completionChanged || positionChanged { item.touch() }
            } else {
                let item = SubtaskItem(title: draft.title, isCompleted: draft.isCompleted, sortOrder: index)
                modelContext.insert(item)
                task.subtasks.append(item)
            }
        }
        return true
    }

    private func reorderSubtasks(fromId: UUID, toId: UUID) {
        guard let fromIndex = subtasks.firstIndex(where: { $0.id == fromId }),
            let toIndex = subtasks.firstIndex(where: { $0.id == toId }),
            fromIndex != toIndex
        else { return }

        Haptics.selection()
        withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
            let moved = subtasks.remove(at: fromIndex)
            subtasks.insert(moved, at: toIndex)
        }
    }

    private func handleAddSubtask() {
        guard !pendingSubtaskTitle.isEmpty else { return }
        Haptics.selection()
        subtasks.append(SubtaskDraft(id: UUID(), title: pendingSubtaskTitle, isCompleted: false))
        newSubtaskTitle = ""
    }
}

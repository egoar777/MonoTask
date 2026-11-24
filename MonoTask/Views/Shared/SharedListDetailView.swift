import SwiftUI

struct SharedListDetailView: View {
    let listID: UUID
    var folderLayout = false
    @Binding var isCaptureActive: Bool
    private let canEditTask: () -> Bool
    @State private var store = SharedListStore.shared
    @State private var editingTask: SharedTask?
    @State private var managing = false
    private var list: SharedList? { store.lists.first { $0.id == listID } }

    init(
        listID: UUID, folderLayout: Bool = false, isCaptureActive: Binding<Bool> = .constant(false),
        canEditTask: @escaping () -> Bool = { true }
    ) {
        self.listID = listID
        self.folderLayout = folderLayout
        self._isCaptureActive = isCaptureActive
        self.canEditTask = canEditTask
    }

    var body: some View {
        Group {
            if let list {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        let tasks = store.tasks(in: listID)
                        if !folderLayout {
                            ScreenHeading(text: list.title).padding(.top, -24)
                            Label("Участников: \(store.members(in: listID).count)", systemImage: "person.2")
                                .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Выполнено \(tasks.filter(\.isDone).count) из \(tasks.count)")
                                    Spacer()
                                }.font(Theme.Typography.caption)
                                ProgressLine(
                                    progress: tasks.isEmpty
                                        ? 0 : Double(tasks.filter(\.isDone).count) / Double(tasks.count)
                                )
                            }.padding(.vertical, 8)
                        }
                        if let message = store.errorMessage {
                            Text(message).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        if store.pendingCount > 0 {
                            Text("Есть изменения, ожидающие синхронизации").font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        ForEach(store.conflicts(in: listID), id: \.task.id) { edit in conflictCard(edit) }
                        if tasks.isEmpty && !folderLayout {
                            ContentUnavailableView(
                                "В папке нет задач", systemImage: "checklist",
                                description: Text("Добавьте первую задачу — её увидят все участники."))
                        }
                        let open = tasks.filter { !$0.isDone }
                            .sorted { ($0.isHighPriority ? 1 : 0) > ($1.isHighPriority ? 1 : 0) }
                        let completed = tasks.filter(\.isDone)
                        VStack(spacing: 0) {
                            ForEach(open) { task in
                                taskRow(task)
                                    .overlay(alignment: .bottom) {
                                        TaskRowSeparator(leadingInset: 48, trailingInset: 0)
                                    }
                            }
                        }
                        if !completed.isEmpty {
                            SectionTitle(text: "Выполнено", count: completed.count).padding(.top, 8)
                            VStack(spacing: 0) {
                                ForEach(completed) { task in
                                    taskRow(task)
                                        .overlay(alignment: .bottom) {
                                            TaskRowSeparator(leadingInset: 48, trailingInset: 0)
                                        }
                                }
                            }
                        }
                        if !folderLayout {
                            ClassicInlineTaskInput(isCaptureActive: $isCaptureActive) { title, highPriority in
                                guard store.accountID != nil else { return false }
                                var task = SharedTask(listID: listID, title: title)
                                task.isHighPriority = highPriority
                                store.save(task)
                                Task { await store.sync() }
                                return true
                            }
                        }
                    }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
                        .background {
                            if folderLayout { ScrollBounceDisabler() }
                        }
                }
                .background(Theme.Colors.background)
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            managing = true
                        } label: {
                            Label("Участники", systemImage: "person.2")
                        }
                        .accessibilityIdentifier("shared-manage-members")
                    }
                }
                .sheet(isPresented: $managing) { SharedMembersView(listID: listID) }
                .sheet(item: $editingTask) { task in SharedTaskEditor(task: task) }
            } else {
                ContentUnavailableView(
                    "Список недоступен", systemImage: "person.crop.circle.badge.xmark",
                    description: Text("Папка удалена или доступ к ней закрыт."))
            }
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func taskRow(_ task: SharedTask) -> some View {
        SharedTaskRow(task: task, store: store) {
            guard canEditTask() else { return }
            editingTask = task
        }
    }

    private func conflictCard(_ edit: PendingSharedTask) -> some View {
        GroupCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Задача изменена другим участником", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.priority)
                Text("На устройстве: \(edit.task.deletedAt != nil ? "удалена — " : "")\(edit.task.title)").font(
                    Theme.Typography.body)
                if let remote = edit.remoteVersion {
                    Text(
                        remote.deletedAt != nil
                            ? "Общая задача удалена." : "Общая версия: \(remote.title)\n\(remote.notes)"
                    )
                    .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                    Button(remote.deletedAt != nil ? "Принять удаление" : "Использовать общую версию") {
                        store.resolve(edit.task.id, keepLocal: false)
                    }
                    Button(
                        remote.deletedAt != nil
                            ? "Сохранить мои правки копией"
                            : edit.task.deletedAt != nil ? "Удалить обновлённую задачу" : "Сохранить мои изменения"
                    ) {
                        store.resolve(edit.task.id, keepLocal: true)
                        Task { await store.sync() }
                    }
                }
            }
        }
    }
}

struct SharedTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = SharedListStore.shared
    @State private var draft: SharedTask
    @State private var subtaskTitle = ""
    @State private var deleting = false

    init(task: SharedTask) { _draft = State(initialValue: task) }
    private var valid: Bool {
        store.lists.contains(where: { $0.id == draft.listID })
            && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.title.count <= 500
            && draft.notes.count <= 20000
            && draft.subtasks.allSatisfy {
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 500
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { CurrentDateLabel() }
                Section("Задача") {
                    TextField("Что нужно сделать?", text: $draft.title, axis: .vertical).accessibilityIdentifier(
                        "shared-task-title")
                    TextField("Заметки", text: $draft.notes, axis: .vertical).lineLimit(3...10).accessibilityIdentifier(
                        "shared-task-notes")
                    Toggle("Выполнено", isOn: $draft.isDone)
                    Toggle("Высокий приоритет", isOn: $draft.isHighPriority)
                }
                Section("Ответственный") {
                    Picker("Участник", selection: $draft.assigneeID) {
                        Text("Без ответственного").tag(UUID?.none)
                        ForEach(store.members(in: draft.listID)) { member in
                            Text(member.userID == store.accountID ? "Вы" : member.displayName).tag(
                                Optional(member.userID))
                        }
                    }
                }
                Section("Подзадачи") {
                    ForEach($draft.subtasks) { $subtask in
                        HStack {
                            Toggle("Выполнить подзадачу", isOn: $subtask.isDone)
                                .labelsHidden()
                                .fixedSize()
                            TextField("Подзадача", text: $subtask.title)
                            Button {
                                draft.subtasks.removeAll { $0.id == subtask.id }
                            } label: {
                                Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(FullSurfaceButtonStyle()).accessibilityLabel("Удалить подзадачу")
                        }
                    }
                    if draft.subtasks.count < 100 {
                        HStack {
                            TextField("Новая подзадача", text: $subtaskTitle).accessibilityIdentifier(
                                "shared-subtask-input")
                            Button("Добавить") {
                                draft.subtasks.append(
                                    SharedSubtask(title: subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)))
                                subtaskTitle = ""
                            }.disabled(
                                subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || subtaskTitle.count > 500)
                        }
                    }
                }
                if store.cache.snapshot.tasks.contains(where: { $0.id == draft.id }) {
                    Section { Button("Удалить общую задачу", role: .destructive) { deleting = true } }
                }
                Section {
                    Text("Заметки, подзадачи и статус видны всем участникам этой папки.").foregroundStyle(
                        Theme.Colors.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .toggleStyle(.switch)
            .navigationTitle(draft.revision == 0 ? "Новая задача" : "Общая задача")
            #if os(macOS)
            .macNavigationHeader {
                Button("Отмена") { dismiss() }
                .keyboardShortcut(.cancelAction)
                Spacer()
                saveButton
            }
            #else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { saveButton }
            }
            #endif
            .confirmationDialog(
                "Удалить задачу для всех участников?", isPresented: $deleting, titleVisibility: .visible
            ) {
                Button("Удалить", role: .destructive) {
                    draft.deletedAt = .now
                    store.save(draft)
                    Task { await store.sync() }
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            }
        }
        .tint(Theme.Colors.accent).preferredColorScheme(Theme.colorScheme)
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 580)
        #endif
    }

    private var saveButton: some View {
        Button("Сохранить") {
            store.save(draft)
            Task { await store.sync() }
            dismiss()
        }
        .disabled(!valid)
        .accessibilityIdentifier("shared-save-task")
    }
}

private struct SharedTaskRow: View {
    let task: SharedTask
    let store: SharedListStore
    let onEdit: () -> Void

    private var textExpansion = TaskTextExpansion()

    var body: some View {
        Group {
            HStack(spacing: 4) {
                Button {
                    var edited = task
                    edited.isDone.toggle()
                    store.save(edited)
                    Haptics.selection()
                    Task { await store.sync() }
                } label: {
                    TaskCheckbox(
                        isDone: task.isDone,
                        priorityColor: task.isHighPriority ? Priority.high.color : nil
                    ).frame(width: 44, height: 44)
                }.buttonStyle(FullSurfaceButtonStyle()).accessibilityLabel(
                    task.isDone ? "Вернуть общую задачу" : "Выполнить общую задачу"
                )
                .accessibilityValue(task.isHighPriority && !task.isDone ? "Высокий приоритет" : "")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    taskDetails
                }
                .padding(.vertical, 8)
                .padding(.trailing, 6)
            }
        }
    }

    private var taskDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TaskPreviewText(lineLimit: 2, expansion: textExpansion.presentation) {
                    Text(task.title).font(Theme.Typography.body).strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                }
            }
            if !task.notes.isEmpty {
                TaskPreviewText(lineLimit: 2, expansion: textExpansion.presentation) {
                    Text(task.notes).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            HStack(spacing: 10) {
                if let member = store.members(in: task.listID).first(where: { $0.userID == task.assigneeID }) {
                    Label(
                        member.userID == store.accountID ? "Вы" : member.displayName, systemImage: "person")
                } else {
                    Text("Без ответственного")
                }
                if !task.subtasks.isEmpty {
                    Text("\(task.subtasks.filter(\.isDone).count)/\(task.subtasks.count) подзадач")
                }
            }.font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textMuted)
            if textExpansion.isExpanded {
                TaskTextCollapseButton(expansion: textExpansion.presentation)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .accessibilityIdentifier("shared-task-\(task.id)")
    }
}

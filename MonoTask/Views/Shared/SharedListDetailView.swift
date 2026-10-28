import SwiftUI

struct SharedListDetailView: View {
    let listID: UUID
    @State private var store = SharedListStore.shared
    @State private var editingTask: SharedTask?
    @State private var managing = false
    private var list: SharedList? { store.lists.first { $0.id == listID } }

    var body: some View {
        Group {
            if let list {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        let tasks = store.tasks(in: listID)
                        Text("\(tasks.filter(\.isDone).count) / \(tasks.count) выполнено")
                            .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                        if let message = store.errorMessage {
                            Text(message).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        if store.pendingCount > 0 {
                            Text("Есть изменения, ожидающие синхронизации").font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        ForEach(store.conflicts(in: listID), id: \.task.id) { edit in conflictCard(edit) }
                        if tasks.isEmpty {
                            ContentUnavailableView(
                                "В списке нет задач", systemImage: "checklist",
                                description: Text("Добавьте первую задачу — её увидят все участники."))
                        }
                        ForEach(tasks) { task in taskRow(task) }
                        Button {
                            editingTask = SharedTask(listID: listID, title: "")
                        } label: {
                            Label("Новая задача", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.plain).modifier(FloatingGlass(shape: Capsule()))
                        .accessibilityIdentifier("shared-add-task")
                    }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .refreshable { await store.sync() }
                .background(Theme.Colors.background)
                .navigationTitle(list.title)
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
                    description: Text("Список удалён или доступ к нему закрыт."))
            }
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func taskRow(_ task: SharedTask) -> some View {
        GroupCard(padding: 14) {
            HStack(spacing: 10) {
                Button {
                    var edited = task
                    edited.isDone.toggle()
                    store.save(edited)
                    Haptics.selection()
                    Task { await store.sync() }
                } label: {
                    TaskCheckbox(isDone: task.isDone).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(
                    task.isDone ? "Вернуть общую задачу" : "Выполнить общую задачу")
                Button {
                    editingTask = task
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if task.isHighPriority {
                                Image(systemName: "flame.fill").foregroundStyle(Theme.Colors.priority)
                            }
                            Text(task.title).font(Theme.Typography.body).strikethrough(task.isDone)
                        }
                        if !task.notes.isEmpty {
                            Text(task.notes).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(2)
                        }
                        HStack(spacing: 10) {
                            if let member = store.members(in: listID).first(where: { $0.userID == task.assigneeID }) {
                                Label(
                                    member.userID == store.accountID ? "Вы" : member.displayName, systemImage: "person")
                            } else {
                                Text("Без ответственного")
                            }
                            if !task.subtasks.isEmpty {
                                Text("\(task.subtasks.filter(\.isDone).count)/\(task.subtasks.count) подзадач")
                            }
                        }.font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textMuted)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("shared-task-\(task.id)")
            }
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
                            Toggle("Выполнить подзадачу", isOn: $subtask.isDone).labelsHidden().frame(width: 44)
                            TextField("Подзадача", text: $subtask.title)
                            Button {
                                draft.subtasks.removeAll { $0.id == subtask.id }
                            } label: {
                                Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain).accessibilityLabel("Удалить подзадачу")
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
                    Text("Заметки, подзадачи и статус видны всем участникам этого списка.").foregroundStyle(
                        Theme.Colors.textSecondary)
                }
            }
            .navigationTitle(draft.revision == 0 ? "Новая задача" : "Общая задача")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        store.save(draft); Task { await store.sync() }; dismiss()
                    }
                    .disabled(!valid).accessibilityIdentifier("shared-save-task")
                }
            }
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
}

import SwiftUI

struct SharedMembersView: View {
    let listID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = SharedListStore.shared
    @State private var invite: SharedInvite?
    @State private var error: String?
    @State private var removing: SharedMember?
    @State private var deleting = false
    @State private var renaming = false
    @State private var title = ""
    private var list: SharedList? { store.lists.first { $0.id == listID } }
    private var isOwner: Bool { list?.ownerID == store.accountID }

    var body: some View {
        NavigationStack {
            Form {
                if let list {
                    Section("Список") {
                        Text(list.title)
                        if isOwner {
                            Button("Переименовать") {
                                title = list.title; renaming = true
                            }.disabled(!store.canManage)
                        }
                    }
                    Section("Участники") {
                        ForEach(store.members(in: listID)) { member in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(
                                        member.userID == store.accountID
                                            ? "\(member.displayName) (вы)" : member.displayName)
                                    Text(member.userID == list.ownerID ? "Владелец" : "Участник")
                                        .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                if isOwner && member.userID != list.ownerID {
                                    Button("Удалить", role: .destructive) { removing = member }.disabled(
                                        !store.canManage)
                                }
                            }
                        }
                    }
                    if isOwner {
                        Section("Приглашение") {
                            Text(
                                "Приглашение одноразовое и действует 72 часа. Новое приглашение отменит предыдущее неиспользованное."
                            )
                            .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                            Button("Создать приглашение") {
                                Task {
                                    do { invite = try await store.createInvite(listID: listID) } catch {
                                        self.error = SharedListStore.message(for: error)
                                    }
                                }
                            }.disabled(!store.canManage).accessibilityIdentifier("shared-create-invite")
                            if let invite {
                                Text(invite.code).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                    .accessibilityIdentifier("shared-generated-code")
                                Text("До \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened))").font(
                                    Theme.Typography.caption)
                                ShareLink(item: invite.url, subject: Text("Приглашение в MonoTask")) {
                                    Label("Поделиться приглашением", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                        Section {
                            Button("Удалить общий список", role: .destructive) { deleting = true }.disabled(
                                !store.canManage)
                        }
                    } else if let own = store.members(in: listID).first(where: { $0.userID == store.accountID }) {
                        Section {
                            Button("Покинуть список", role: .destructive) { removing = own }.disabled(!store.canManage)
                        }
                    }
                } else {
                    ContentUnavailableView("Список недоступен", systemImage: "person.2.slash")
                }
            }
            .navigationTitle("Участники и доступ")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } } }
            .alert("Переименовать список", isPresented: $renaming) {
                TextField("Название", text: $title)
                Button("Сохранить") {
                    guard let list else { return }
                    Task {
                        do { try await store.updateList(list, title: title) } catch {
                            self.error = SharedListStore.message(for: error)
                        }
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
            .confirmationDialog(
                "Закрыть доступ к списку?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible
            ) {
                Button("Подтвердить", role: .destructive) {
                    guard let member = removing else { return }
                    Task {
                        do {
                            try await store.removeMember(member); if member.userID == store.accountID { dismiss() }
                        } catch { self.error = SharedListStore.message(for: error) }
                        removing = nil
                    }
                }
                Button("Отмена", role: .cancel) { removing = nil }
            } message: {
                Text(
                    "Участник больше не сможет просматривать и изменять общие задачи. Его личные задачи останутся на месте."
                )
            }
            .confirmationDialog(
                "Удалить список для всех участников?", isPresented: $deleting, titleVisibility: .visible
            ) {
                Button("Удалить", role: .destructive) {
                    guard let list else { return }
                    Task {
                        do { try await store.updateList(list, title: list.title, delete: true); dismiss() } catch {
                            self.error = SharedListStore.message(for: error)
                        }
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
        }
        .sharedErrorAlert($error)
        .tint(Theme.Colors.accent).preferredColorScheme(Theme.colorScheme)
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 600, minHeight: 560)
        #endif
    }
}

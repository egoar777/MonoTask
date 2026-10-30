import SwiftUI

struct SharedListsView: View {
    var isEmbedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = SharedListStore.shared
    @State private var path: [UUID] = []
    @State private var creating = false
    @State private var joining = false
    @State private var newTitle = ""
    @State private var code = ""
    @State private var error: String?
    @State private var joinError: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenHeading(text: "Общие списки")
                    Text("Списки для совместной работы. Личные задачи видны только вам.")
                        .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                    if store.accountID == nil {
                        ContentUnavailableView(
                            "Войдите в аккаунт", systemImage: "person.crop.circle",
                            description: Text("Совместные списки доступны после входа в MonoTask."))
                    } else {
                        status
                        if store.lists.isEmpty && !store.isSyncing {
                            ContentUnavailableView(
                                "Пока нет общих списков", systemImage: "person.2",
                                description: Text("Создайте список или примите приглашение другого пользователя."))
                        }
                        ForEach(store.lists) { list in
                            NavigationLink(value: list.id) {
                                GroupCard(padding: 18) {
                                    HStack {
                                        Image(systemName: "folder").font(.title2).foregroundStyle(
                                            Theme.Colors.tagColor(Theme.Colors.tagColors[0])
                                        )
                                        .frame(width: 36, height: 36)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(list.title).font(Theme.Typography.body)
                                            Text(
                                                "Участников: \(store.members(in: list.id).count) · Задач: \(store.tasks(in: list.id).filter { !$0.isDone }.count)"
                                            )
                                            .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(Theme.Colors.textMuted)
                                    }
                                }
                            }.buttonStyle(FullSurfaceButtonStyle()).accessibilityIdentifier("shared-list-\(list.id)")
                        }
                        GroupCard {
                            Button {
                                joining = true
                            } label: {
                                Label("Присоединиться по приглашению", systemImage: "link")
                                    .font(Theme.Typography.callout)
                                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                    .padding(.horizontal, 18)
                            }
                            .buttonStyle(FullSurfaceButtonStyle())
                            .disabled(!store.canManage)
                            .accessibilityIdentifier("shared-join-list")
                        }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 24).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(Theme.Colors.background)
            .refreshable { await store.sync() }
            .navigationDestination(for: UUID.self) { id in SharedListDetailView(listID: id) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creating = true
                    } label: {
                        Label("Новый список", systemImage: "plus")
                    }
                    .disabled(!store.canManage)
                    .accessibilityIdentifier("shared-create-list")
                }
                if !isEmbedded { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            }
            .alert("Новый список", isPresented: $creating) {
                TextField("Название списка", text: $newTitle)
                Button("Создать") { create() }.disabled(
                    newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Отмена", role: .cancel) {}
            }
            .sheet(isPresented: $joining, onDismiss: { store.pendingInviteCode = nil }) { joinSheet }
        }
        .tint(Theme.Colors.accent)
        .foregroundStyle(Theme.Colors.textPrimary)
        .preferredColorScheme(Theme.colorScheme)
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 700, minHeight: 580)
        #endif
        .sharedErrorAlert($error)
        .task(id: scenePhase) {
            store.activateAccount()
            if let pending = store.pendingInviteCode { code = pending; joining = true }
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.sync()
                do { try await Task.sleep(for: .seconds(6)) } catch { break }
            }
        }
        .onChange(of: store.pendingInviteCode) { _, value in
            if let value { code = value; joining = true }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.isSyncing { ProgressView("Обновляем общие списки…").font(Theme.Typography.caption) }
            if store.pendingCount > 0 {
                Text("Изменений на устройстве: \(store.pendingCount)").font(Theme.Typography.caption).foregroundStyle(
                    Theme.Colors.textSecondary)
            }
            if let message = store.errorMessage {
                Text(message).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                Button("Повторить") { Task { await store.sync() } }.disabled(store.isSyncing)
            }
        }
    }

    private var joinSheet: some View {
        NavigationStack {
            Form {
                Section { CurrentDateLabel() }
                Section("Приглашение") {
                    TextField("Код или ссылка MonoTask", text: $code).autocorrectionDisabled()
                        .accessibilityIdentifier("shared-invite-code")
                    Text("Код одноразовый. Приглашение действует 72 часа.").foregroundStyle(Theme.Colors.textSecondary)
                }
                if let joinError { Text(joinError).foregroundStyle(Theme.Colors.danger) }
            }
            .navigationTitle("Присоединиться")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { joining = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Принять") {
                        joinError = nil
                        Task {
                            do { let id = try await store.join(code: code); joining = false; path.append(id) } catch {
                                self.joinError = SharedListStore.message(for: error)
                            }
                        }
                    }.disabled(SharedInvite.parseCode(code) == nil || !store.canManage)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 300)
        #endif
    }

    private func create() {
        let title = newTitle
        Task {
            do { let id = try await store.createList(title: title); newTitle = ""; path.append(id) } catch {
                self.error = SharedListStore.message(for: error)
            }
        }
    }
}

extension View {
    func sharedErrorAlert(_ error: Binding<String?>) -> some View {
        alert(
            "Не удалось завершить действие",
            isPresented: Binding(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } })
        ) {
            Button("Понятно", role: .cancel) { error.wrappedValue = nil }
        } message: {
            Text(error.wrappedValue ?? "")
        }
    }
}

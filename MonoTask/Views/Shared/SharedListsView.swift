import SwiftUI

struct SharedListsView: View {
    var isEmbedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = SharedListStore.shared
    @State private var path: [UUID] = []
    @State private var creating = false
    @State private var joining: JoinRequest?
    @State private var destination: UUID?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    heading
                    if store.accountID == nil {
                        ContentUnavailableView(
                            "Войдите в аккаунт", systemImage: "person.crop.circle",
                            description: Text("Общие папки доступны после входа в MonoTask."))
                    } else {
                        actions
                        if store.errorMessage != nil || store.pendingCount > 0
                            || (store.isSyncing && store.lists.isEmpty)
                        {
                            status
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            SharedSectionTitle(title: "Ваши общие папки", detail: "\(store.lists.count)")
                            if store.lists.isEmpty && !store.isSyncing {
                                emptyState
                            } else {
                                ForEach(store.lists) { list in folderRow(list) }
                            }
                        }
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "lock").font(Theme.Typography.caption)
                            Text("Задачи общей папки видны её участникам. Ваши личные папки остаются личными.")
                                .font(Theme.Typography.caption).fixedSize(horizontal: false, vertical: true)
                        }.foregroundStyle(Theme.Colors.textSecondary).padding(.horizontal, 3)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenPadding).padding(.bottom, Theme.Spacing.xxl)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(Theme.Colors.background).scrollIndicators(.hidden)
            .refreshable { await store.sync() }
            .navigationTitle("")
            .navigationDestination(for: UUID.self) { id in
                SharedListDetailView(listID: id)
                    #if os(macOS)
                .navigationBarBackButtonHidden()
                .macNavigationHeader {
                    Button("Назад", systemImage: "chevron.left") {
                        if !path.isEmpty { path.removeLast() }
                    }
                    .accessibilityIdentifier("shared-list-back")
                    Spacer()
                    if !isEmbedded { closeButton }
                }
                    #else
                .toolbar {
                    if !isEmbedded {
                        ToolbarItem(placement: .cancellationAction) { closeButton }
                    }
                }
                    #endif
            }
            #if os(macOS)
            .macNavigationHeader(isVisible: !isEmbedded) { closeButton }
            #else
            .toolbar {
                if !isEmbedded {
                    ToolbarItem(placement: .cancellationAction) { closeButton }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .tint(Theme.Colors.accent).foregroundStyle(Theme.Colors.textPrimary).preferredColorScheme(Theme.colorScheme)
        .sheet(isPresented: $creating, onDismiss: openDestination) {
            SharedCreateFolderSheet { destination = $0 }
        }
        .sheet(
            item: $joining,
            onDismiss: {
                store.pendingInviteCode = nil
                openDestination()
            }
        ) { request in
            SharedJoinFolderSheet(initialCode: request.code) { destination = $0 }
        }
        .task(id: scenePhase) {
            store.activateAccount()
            if let pending = store.pendingInviteCode { joining = JoinRequest(code: pending) }
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.sync()
                do { try await Task.sleep(for: .seconds(6)) } catch { break }
            }
        }
        .onChange(of: store.pendingInviteCode) { _, value in
            if let value { joining = JoinRequest(code: value) }
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 740, minHeight: 660)
        #endif
    }

    private var closeButton: some View {
        Button("Закрыть") { dismiss() }
            #if os(macOS)
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("shared-lists-close")
            #endif
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ScreenHeading(text: "ОБЩИЕ ПАПКИ")
            Text("Создавайте задачи вместе и приглашайте участников по QR-коду или ссылке.")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var actions: some View {
        GroupCard {
            Button {
                creating = true
            } label: {
                actionRow(
                    title: "Новая общая папка", detail: "Создать папку и пригласить участников",
                    symbol: "folder.badge.plus")
            }.accessibilityIdentifier("shared-create-list")
            Hairline(leading: 58)
            Button {
                joining = JoinRequest(code: "")
            } label: {
                actionRow(
                    title: "Присоединиться", detail: "QR-код, ссылка или код приглашения", symbol: "qrcode.viewfinder")
            }.accessibilityIdentifier("shared-join-list")
        }
        .buttonStyle(FullSurfaceButtonStyle()).disabled(store.isMutating)
    }

    private func actionRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .font(Theme.Typography.title).foregroundStyle(Theme.Colors.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title).font(Theme.Typography.body.weight(.medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(detail).font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textMuted)
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.isSyncing && store.lists.isEmpty {
                ProgressView("Обновляем папки…").font(Theme.Typography.caption)
            }
            if store.pendingCount > 0 {
                Label("Изменений на устройстве: \(store.pendingCount)", systemImage: "arrow.triangle.2.circlepath")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
            if let message = store.errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "wifi.exclamationmark").font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Button("Повторить") { Task { await store.sync() } }.disabled(store.isSyncing)
                        .font(Theme.Typography.caption.weight(.medium))
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2").font(.system(size: 29, weight: .light)).foregroundStyle(Theme.Colors.accent)
            Text("Пока нет общих папок").font(Theme.Typography.body.weight(.medium))
            Text("Создайте папку для общих планов\nили примите приглашение.")
                .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary).multilineTextAlignment(
                    .center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func folderRow(_ list: SharedList) -> some View {
        let tasks = store.tasks(in: list.id)
        let done = tasks.filter(\.isDone).count
        return NavigationLink(value: list.id) {
            HStack(spacing: 14) {
                ClassicFolderArtwork(tint: Theme.Colors.tagColor(Theme.Colors.tagColors[1]), icon: "person.2.fill")
                    .frame(width: 74, height: 64)
                VStack(alignment: .leading, spacing: 7) {
                    Text(list.title).font(Theme.Typography.body.weight(.semibold)).foregroundStyle(
                        Theme.Colors.textPrimary
                    )
                    .lineLimit(2)
                    Text("\(tasks.count - done) открыто · \(store.members(in: list.id).count) участников")
                        .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    SharedMemberAvatars(members: store.members(in: list.id), size: 23)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(Theme.Typography.caption.weight(.medium))
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Colors.hairline, lineWidth: 0.6))
        }.buttonStyle(.plain).accessibilityIdentifier("shared-list-\(list.id)")
    }

    private struct JoinRequest: Identifiable { let id = UUID(); let code: String }

    private func openDestination() {
        if let destination { path.append(destination); self.destination = nil }
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

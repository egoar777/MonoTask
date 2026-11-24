import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct SharedPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.body.weight(.semibold))
            .foregroundStyle(Theme.Colors.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
    }
}

struct SharedSectionTitle: View {
    let title: String
    var detail: String?
    var body: some View {
        HStack {
            Text(title).font(Theme.Typography.section).foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            if let detail { Text(detail).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary) }
        }
    }
}

@MainActor
enum SharedClipboard {
    static func copy(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
    static var string: String? {
        #if os(iOS)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }
}

struct SharedInviteSheet: View {
    let listID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = SharedListStore.shared
    var body: some View {
        NavigationStack {
            ScrollView {
                SharedInvitationContent(listID: listID)
                    .padding(Theme.Spacing.screenPadding).frame(maxWidth: 510).frame(maxWidth: .infinity)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Пригласить в папку")
            #if os(macOS)
            .macNavigationHeader {
                Button("Закрыть", systemImage: "xmark") { dismiss() }
                .keyboardShortcut(.cancelAction)
            }
            #else
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .tint(Theme.Colors.accent).preferredColorScheme(Theme.colorScheme)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 720)
        #endif
    }
}

struct SharedInvitationContent: View {
    let listID: UUID
    var created = false
    @State private var store = SharedListStore.shared
    @State private var invite: SharedInvite?
    @State private var image: CGImage?
    @State private var loading = false
    @State private var copied = false
    @State private var replacing = false
    @State private var error: String?
    private var list: SharedList? { store.lists.first { $0.id == listID } }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(created ? "Папка создана" : "Приглашение в папку")
                    .font(Theme.Typography.title)
                Text(
                    created
                        ? "Пригласите участников по QR-коду или ссылке."
                        : "Покажите QR-код участнику или отправьте ссылку."
                )
                .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let valid = invite.map { $0.expiresAt > timeline.date } ?? false
                VStack(spacing: 0) {
                    HStack(spacing: 9) {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.Colors.accent)
                        Text(list?.title ?? "Общая папка").font(Theme.Typography.body.weight(.semibold)).lineLimit(2)
                        Spacer()
                        Image(systemName: "person.2.fill").foregroundStyle(Theme.Colors.textPrimary.opacity(0.65))
                    }.foregroundStyle(Theme.Colors.textPrimary).padding(20)
                    VStack(spacing: 17) {
                        if let image, valid {
                            Image(image, scale: 1, label: Text("QR-код приглашения в папку \(list?.title ?? "")"))
                                .interpolation(.none).resizable().scaledToFit()
                                .frame(maxWidth: 250).padding(8).background(
                                    .white, in: RoundedRectangle(cornerRadius: Theme.Radius.card)
                                )
                                .accessibilityLabel("QR-код приглашения в папку \(list?.title ?? "")")
                                .accessibilityIdentifier("shared-invite-qr")
                        } else {
                            VStack(spacing: 14) {
                                if loading {
                                    ProgressView().tint(Theme.Colors.onAccent)
                                    Text("Готовим приглашение…")
                                } else {
                                    Image(systemName: "qrcode").font(.system(size: 58, weight: .light))
                                    Text(invite == nil ? "Ваш код появится здесь" : "Срок действия истёк")
                                }
                            }
                            .font(Theme.Typography.callout.weight(.medium)).foregroundStyle(Theme.Colors.onAccent)
                            .frame(maxWidth: 250).frame(height: 250).padding(8)
                            .background(Theme.Colors.textPrimary, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                        }
                        HStack(spacing: 7) {
                            Circle().fill(valid ? Theme.Colors.accent : Theme.Colors.textPrimary.opacity(0.5))
                                .frame(width: 5, height: 5)
                            Text(valid ? "ОДНО ПРИГЛАШЕНИЕ · ОДИН УЧАСТНИК" : "ПРИГЛАШЕНИЕ В MONOTASK")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textPrimary.opacity(0.85))
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 22)
                    Hairline(leading: 20).padding(.trailing, 20)
                    HStack {
                        Image(systemName: "clock").foregroundStyle(Theme.Colors.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Действует 72 часа").font(Theme.Typography.caption.weight(.medium))
                            if let invite {
                                Text("До \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(Theme.Typography.caption).foregroundStyle(
                                        Theme.Colors.textPrimary.opacity(0.7))
                            }
                        }
                        Spacer()
                        Image(systemName: "lock").foregroundStyle(Theme.Colors.textMuted)
                    }.foregroundStyle(Theme.Colors.textPrimary).padding(20)
                }
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Colors.hairline, lineWidth: 1))
                if let invite, valid {
                    ShareLink(item: invite.url, subject: Text("Приглашение в \(list?.title ?? "MonoTask")")) {
                        Label("Поделиться приглашением", systemImage: "square.and.arrow.up")
                    }.buttonStyle(SharedPrimaryStyle()).disabled(loading)
                    Button {
                        SharedClipboard.copy(invite.url.absoluteString)
                        copied = true
                        Haptics.success()
                    } label: {
                        Label(
                            copied ? "Ссылка скопирована" : "Скопировать ссылку",
                            systemImage: copied ? "checkmark" : "link"
                        )
                        .font(Theme.Typography.callout.weight(.medium)).frame(minHeight: 38)
                    }.buttonStyle(.plain).foregroundStyle(Theme.Colors.accent)
                    DisclosureGroup("Код для ручного ввода") {
                        Text(invite.code).font(Theme.Typography.caption.monospaced()).textSelection(.enabled)
                            .padding(.vertical, 10).accessibilityIdentifier("shared-generated-code")
                    }.font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle").font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.danger).fixedSize(horizontal: false, vertical: true)
            }
            Button(invite == nil ? "Получить QR-код" : "Создать новый QR-код") {
                if invite == nil { generate() } else { replacing = true }
            }
            .font(Theme.Typography.caption.weight(.medium)).foregroundStyle(Theme.Colors.textSecondary)
            .disabled(loading || !store.canManage).accessibilityIdentifier("shared-create-invite")
            Text("Код одноразовый. Новый QR-код заменяет предыдущее неиспользованное приглашение.")
                .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary).multilineTextAlignment(
                    .center)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .task {
            if let cached = store.invitations[listID], cached.expiresAt > .now {
                invite = cached
                image = SharedQRCode.image(for: cached.url.absoluteString)
            } else {
                generate()
            }
        }
        .confirmationDialog("Заменить приглашение?", isPresented: $replacing, titleVisibility: .visible) {
            Button("Создать новый код") { generate() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Предыдущий неиспользованный QR-код и ссылка перестанут действовать.")
        }
    }

    private func generate() {
        guard !loading else { return }
        loading = true
        error = nil
        Task { @MainActor in
            defer { loading = false }
            do {
                let received = try await store.createInvite(listID: listID)
                invite = received
                image = SharedQRCode.image(for: received.url.absoluteString)
                copied = false
                if image == nil { error = "Не удалось нарисовать QR-код. Пригласите участника по ссылке." }
            } catch { self.error = SharedListStore.message(for: error) }
        }
    }

}

struct SharedCreateFolderSheet: View {
    var onOpen: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = SharedListStore.shared
    @State private var title = ""
    @State private var createdID: UUID?
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool
    private var valid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 100
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let createdID {
                        SharedInvitationContent(listID: createdID, created: true)
                    } else {
                        ClassicFolderArtwork(
                            tint: Theme.Colors.tagColor(Theme.Colors.tagColors[1]), icon: "person.2.fill"
                        )
                        .frame(width: 108, height: 88).padding(.top, 8)
                        VStack(spacing: 9) {
                            Text("Новая общая папка")
                                .font(Theme.Typography.title).multilineTextAlignment(
                                    .center)
                            Text("Участники смогут добавлять, редактировать и выполнять общие задачи.")
                                .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        GroupCard(padding: 18) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Название папки").font(Theme.Typography.caption.weight(.medium))
                                    Spacer()
                                    Text("\(title.count)/100").font(Theme.Typography.caption.monospacedDigit())
                                        .foregroundStyle(
                                            title.count > 100 ? Theme.Colors.danger : Theme.Colors.textMuted)
                                }
                                TextField("Например, наш большой проект", text: $title)
                                    .font(Theme.Typography.body).textFieldStyle(.plain)
                                    .focused($focused).submitLabel(.done).onSubmit { if valid { create() } }
                                    .accessibilityIdentifier("shared-folder-name")
                            }
                        }
                        if let error { Text(error).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.danger) }
                        Button(action: create) {
                            HStack(spacing: 8) {
                                if saving { ProgressView().tint(Theme.Colors.onAccent) }
                                Text(saving ? "Создаём папку…" : "Создать папку")
                                if !saving { Image(systemName: "arrow.right") }
                            }
                        }.buttonStyle(SharedPrimaryStyle()).disabled(!valid || saving || !store.canManage)
                            .accessibilityIdentifier("shared-confirm-create")
                        Label("После создания вы получите QR-код для приглашения.", systemImage: "qrcode")
                            .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }.padding(Theme.Spacing.screenPadding).frame(maxWidth: 510).frame(maxWidth: .infinity)
            }
            .background(Theme.Colors.background).scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if let createdID {
                    Button {
                        onOpen(createdID); dismiss()
                    } label: {
                        Label("Открыть папку", systemImage: "arrow.right")
                    }.buttonStyle(SharedPrimaryStyle()).padding(20).background(Theme.Colors.background)
                        .accessibilityIdentifier("shared-open-created-folder")
                }
            }
            .navigationTitle(createdID == nil ? "Новая папка" : "Готово")
            #if os(macOS)
            .macNavigationHeader {
                Button(createdID == nil ? "Отмена" : "Закрыть") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(saving)
            }
            #else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdID == nil ? "Отмена" : "Закрыть") { dismiss() }.disabled(saving)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .foregroundStyle(Theme.Colors.textPrimary).tint(Theme.Colors.accent).preferredColorScheme(Theme.colorScheme)
        .interactiveDismissDisabled(saving)
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 650)
        #endif
    }
    private func create() {
        guard valid, !saving else { return }
        saving = true; error = nil; focused = false
        Task { @MainActor in
            defer { saving = false }
            do { createdID = try await store.createList(title: title); Haptics.success() } catch {
                self.error = SharedListStore.message(for: error)
            }
        }
    }
}

struct SharedJoinFolderSheet: View {
    var initialCode = ""
    var onJoined: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = SharedListStore.shared
    @State private var code = ""
    @State private var scanning = false
    @State private var importing = false
    @State private var joining = false
    @State private var error: String?
    @State private var scanned = false
    @FocusState private var focused: Bool
    private var validCode: String? { SharedInvite.parseCode(code) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Присоединиться к папке").font(Theme.Typography.title)
                        Text("Отсканируйте приглашение или вставьте ссылку от другого участника.")
                            .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Button {
                        focused = false; scanning = true
                    } label: {
                        HStack(spacing: 18) {
                            Image(systemName: "qrcode.viewfinder").font(.title2)
                                .foregroundStyle(Theme.Colors.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Сканировать QR-код").font(Theme.Typography.title)
                                Text("Наведите камеру на приглашение").font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 15))
                        }.foregroundStyle(Theme.Colors.textPrimary).padding(22)
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(
                                    Theme.Colors.hairline, lineWidth: 1))
                    }.buttonStyle(SoftPressStyle()).accessibilityIdentifier("shared-scan-qr")
                    GroupCard(padding: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Ссылка или код").font(Theme.Typography.caption.weight(.semibold))
                                Spacer()
                                Button("Вставить") {
                                    if let value = SharedClipboard.string { code = value; scanned = false; error = nil }
                                }.font(Theme.Typography.caption.weight(.medium)).buttonStyle(.plain)
                                    .foregroundStyle(Theme.Colors.accent).accessibilityIdentifier("shared-paste-invite")
                            }
                            TextField("Код или ссылка MonoTask", text: $code, axis: .vertical)
                                .font(Theme.Typography.callout.monospaced()).textFieldStyle(.plain)
                                .autocorrectionDisabled().lineLimit(2...4).focused($focused)
                                .accessibilityIdentifier("shared-invite-code")
                                #if os(iOS)
                            .textInputAutocapitalization(.never)
                                #endif
                            if validCode != nil {
                                Label(
                                    scanned ? "QR-код считан" : "Приглашение готово к проверке",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .font(Theme.Typography.caption.weight(.medium)).foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Выбрать изображение с QR-кодом", systemImage: "photo")
                            .font(Theme.Typography.caption.weight(.medium)).frame(maxWidth: .infinity, minHeight: 32)
                    }.buttonStyle(.plain).foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("shared-import-qr")
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle").font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.danger).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(action: join) {
                        HStack(spacing: 8) {
                            if joining { ProgressView().tint(Theme.Colors.onAccent) }
                            Text(joining ? "Присоединяемся…" : "Присоединиться")
                            if !joining { Image(systemName: "arrow.right") }
                        }
                    }.buttonStyle(SharedPrimaryStyle()).disabled(validCode == nil || joining || !store.canManage)
                        .accessibilityIdentifier("shared-confirm-join")
                    Text(
                        "После подтверждения папка появится в вашем пространстве. Личные задачи останутся доступны только вам."
                    )
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }.padding(Theme.Spacing.screenPadding).frame(maxWidth: 530).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively).background(Theme.Colors.background)
            .navigationTitle("Присоединиться")
            #if os(macOS)
            .macNavigationHeader {
                Button("Отмена") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(joining)
            }
            #else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.disabled(joining) }
            }
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .tint(Theme.Colors.accent).foregroundStyle(Theme.Colors.textPrimary).preferredColorScheme(Theme.colorScheme)
        .interactiveDismissDisabled(joining)
        .onAppear { code = initialCode }
        .sheet(isPresented: $scanning) {
            SharedQRScannerView { value in
                code = value; scanned = true; error = nil
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                Task { @MainActor in
                    let allowed = url.startAccessingSecurityScopedResource()
                    defer { if allowed { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 20 * 1024 * 1024 else {
                            error = "Выберите изображение меньше 20 МБ."; return
                        }
                        let data = try Data(contentsOf: url)
                        let found = await Task.detached(priority: .userInitiated) { SharedQRCode.invitation(in: data) }
                            .value
                        guard let found else { error = "На изображении не найден QR-код приглашения MonoTask."; return }
                        code = found; scanned = true; error = nil; Haptics.success()
                    } catch { self.error = "Не удалось открыть изображение. Попробуйте другое или вставьте ссылку." }
                }
            case .failure: break
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 680)
        #endif
    }
    private func join() {
        guard let validCode, !joining else { return }
        joining = true; error = nil; focused = false
        Task { @MainActor in
            defer { joining = false }
            do { let id = try await store.join(code: validCode); Haptics.success(); onJoined(id); dismiss() } catch {
                self.error = SharedListStore.message(for: error)
            }
        }
    }
}

import SwiftUI
import SwiftData

private enum SettingsPage: String, Hashable {
    case categories = "Папки"
    case notifications = "Уведомления"
    case calendars = "Календари"
    case appearance = "Вид списка задач"
    case account = "Аккаунт и синхронизация"
}

struct SettingsView: View {
    var bottomContentMargin: CGFloat = 0
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Query private var tasks: [TaskItem]
    @Environment(\.modelContext) private var context
    @Environment(AuthManager.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var notifications = NotificationService.shared
    @State private var editingTag: Tag?
    @State private var addingTag = false
    @State private var deletingTag: Tag?
    @State private var confirmingSignOut = false
    @State private var showsAppearancePreview = false
    @AppStorage("monotask_show_task_notes") private var showNotes = true
    @AppStorage("monotask_compact_rows") private var compactRows = false
    @State private var path: [SettingsPage] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                overview
            }
            .refreshable {
                await SharedListStore.shared.sync()
                try? await SupabaseSyncService.shared.sync(context: context)
            }
            .background(Theme.Colors.background)
            .monoScrollEdge()
            .navigationDestination(for: SettingsPage.self) { page in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        MonoBrandTitle(text: page.rawValue)
                        switch page {
                        case .categories: categories
                        case .notifications: NotificationPreferencesView(showsCalendars: false)
                        case .calendars: NotificationPreferencesView(showsNotifications: false)
                        case .appearance: appearance
                        case .account: account
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
                .background(Theme.Colors.background)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #else
                .navigationTitle(page.rawValue)
                .navigationBarBackButtonHidden()
                .macNavigationHeader(maxWidth: 700) {
                    Button("Назад", systemImage: "chevron.left") {
                        if !path.isEmpty { path.removeLast() }
                    }
                    .accessibilityIdentifier("settings-back")
                }
                #endif
            }
        }
        .contentMargins(.bottom, bottomContentMargin, for: .scrollContent)
        .tint(Theme.Colors.accent)
        .preferredColorScheme(.dark)
        .task { await notifications.checkAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await notifications.checkAuthorization() } }
        }
        .sheet(item: $editingTag) { TagEditSheet(tagToEdit: $0) }
        .sheet(isPresented: $addingTag) { TagEditSheet(tagToEdit: nil) }
        .confirmationDialog(
            "Удалить папку «\(deletingTag?.name ?? "")»?",
            isPresented: Binding(get: { deletingTag != nil }, set: { if !$0 { deletingTag = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let tag = deletingTag { context.deleteWithSync(tag); context.saveAndSync() }
                deletingTag = nil
            }
        } message: {
            Text("Задачи останутся без этой папки.")
        }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                if auth.userID != nil { Task { await auth.signOut() } }
            }
            Button("Отмена", role: .cancel) {}
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--settings-categories") { path = [.categories] }
            if ProcessInfo.processInfo.arguments.contains("--settings-notifications") { path = [.notifications] }
            if ProcessInfo.processInfo.arguments.contains("--settings-calendars") { path = [.calendars] }
            if ProcessInfo.processInfo.arguments.contains("--settings-sync") { path = [.account] }
            if ProcessInfo.processInfo.arguments.contains("--settings-appearance") { path = [.appearance] }
            if ProcessInfo.processInfo.arguments.contains("--settings-edit") {
                path = [.categories]; editingTag = tags.first
            }
            #endif
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            ScreenTitle(text: "Настройки")
                .accessibilityIdentifier("settings-title")
            accountPreview
            settingsSections
            appearanceSection
            Text("MonoTask · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(.horizontal, Theme.Spacing.screenPadding)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: 700, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var settingsSections: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoBrandSectionTitle(text: SettingsPage.categories.rawValue)
            let columns =
                dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : Array(repeating: GridItem(.flexible(), spacing: 9, alignment: .top), count: 2)
            LazyVGrid(columns: columns, spacing: 9) {
                NavigationLink(value: SettingsPage.categories) {
                    folderTile(
                        "Личные папки", subtitle: "Цвета и значки", tint: MonoBrand.violet, icon: "star.fill")
                }
                .buttonStyle(MonoBrandPressStyle())
                .accessibilityIdentifier("settings-folders")

                Button {
                    SharedListStore.shared.isPresented = true
                } label: {
                    folderTile(
                        "Общие папки", subtitle: "Доступ и участники", tint: MonoBrand.mint, icon: "person.2.fill")
                }
                .buttonStyle(MonoBrandPressStyle())
                .accessibilityIdentifier("settings-shared-lists")

                utilityLink(.notifications, icon: "bell.fill", tint: MonoBrand.blue, subtitle: morningSummary)
                    .accessibilityIdentifier("settings-notifications")
                utilityLink(.calendars, icon: "calendar", tint: Theme.Colors.accent, subtitle: "Apple и Google")
                    .accessibilityIdentifier("settings-calendars")
            }
        }
    }

    private func folderTile(_ title: String, subtitle: String, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                ClassicFolderArtwork(tint: tint, icon: icon)
                    .frame(width: 72, height: 59)
                    .frame(maxWidth: .infinity, alignment: .leading)
                settingsChevron()
            }
            tileCopy(title, subtitle: subtitle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 133, alignment: .topLeading)
        .modifier(MonoBrandSurface(fill: tint.opacity(0.10), border: tint.opacity(0.27)))
    }

    private func utilityLink(_ page: SettingsPage, icon: String, tint: Color, subtitle: String) -> some View {
        NavigationLink(value: page) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Spacer()
                    settingsChevron()
                }
                tileCopy(page.rawValue, subtitle: subtitle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
            .modifier(MonoBrandSurface(radius: 21))
        }
        .buttonStyle(MonoBrandPressStyle())
        .animation(reduceMotion ? nil : MonoBrandMotion.control, value: subtitle)
    }

    private func tileCopy(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func settingsChevron(tint: Color = Theme.Colors.textSecondary) -> some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .accessibilityHidden(true)
    }

    private var accountPreview: some View {
        NavigationLink(value: SettingsPage.account) {
            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.onAccent)
                    .frame(width: 37, height: 37)
                    .background(Theme.Colors.accent, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.email ?? "Личное пространство")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(SettingsPage.account.rawValue)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                settingsChevron(tint: Theme.Colors.accent)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .modifier(MonoBrandSurface(border: Theme.Colors.accent.opacity(0.32), radius: 25))
        }
        .buttonStyle(MonoBrandPressStyle())
        .accessibilityIdentifier("settings-account")
    }

    private var morningSummary: String {
        guard notifications.preferences.morningPlan else { return "Утренний план выключен" }
        let time = String(
            format: "%02d:%02d", notifications.preferences.morningHour, notifications.preferences.morningMinute)
        return notifications.preferences.enabled ? "Утренний план в \(time)" : "План в \(time) · неактивен"
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoBrandSectionTitle(text: SettingsPage.appearance.rawValue)
            VStack(spacing: 0) {
                appearanceRows
                Hairline(leading: 16)
                Button {
                    showsAppearancePreview.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "eye")
                            .foregroundStyle(Theme.Colors.accent)
                            .accessibilityHidden(true)
                        Text("Предпросмотр")
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .rotationEffect(.degrees(showsAppearancePreview ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: Theme.Spacing.touchTargetMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(MonoBrandPressStyle())
                .accessibilityIdentifier("settings-appearance")
                .accessibilityValue(showsAppearancePreview ? "Развёрнуто" : "Свёрнуто")
                if showsAppearancePreview {
                    taskAppearancePreview
                        .padding(.horizontal, 12)
                        .modifier(MonoBrandSurface(fill: MonoBrand.inset, radius: 14))
                        .padding([.horizontal, .bottom], 8)
                        .transition(MonoBrandMotion.reveal(reduceMotion: reduceMotion, distance: 8))
                }
            }
            .clipped()
            .animation(reduceMotion ? MonoBrandMotion.fade : MonoBrandMotion.disclosure, value: showsAppearancePreview)
            .font(Theme.Typography.body)
            .modifier(MonoBrandSurface())
        }
    }

    private var appearanceRows: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $showNotes) {
                Label("Заметки в списке", systemImage: "text.alignleft")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityLabel("Показывать заметки в списке")
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            Hairline(leading: 16)
            Toggle(isOn: $compactRows) {
                Label("Компактные строки", systemImage: "line.3.horizontal")
            }
            .accessibilityLabel("Компактные строки задач")
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
        }
        .toggleStyle(.switch)
    }

    private var taskAppearancePreview: some View {
        HStack(spacing: 12) {
            TaskCheckbox(isDone: false)
                .frame(width: 24, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Пример задачи")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                Text("Подготовить план на завтра")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityIdentifier("settings-preview-task")
                if showNotes {
                    Text("Выбрать три главные задачи")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("settings-preview-notes")
                        .transition(MonoBrandMotion.reveal(reduceMotion: reduceMotion, distance: 4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, compactRows ? 8 : 12)
        .animation(reduceMotion ? nil : MonoBrandMotion.disclosure, value: showNotes)
        .animation(reduceMotion ? nil : MonoBrandMotion.control, value: compactRows)
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Выберите папку, чтобы настроить название, цвет и значок. Для изменения порядка перетащите строку.")
                .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
            VStack(spacing: 0) {
                ForEach(tags) { tag in
                    Button {
                        editingTag = tag
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(Theme.Colors.textSecondary)
                            ClassicFolderArtwork(tint: tag.color, icon: tag.iconName)
                                .frame(width: 38, height: 31)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tag.name).font(Theme.Typography.body).foregroundStyle(Theme.Colors.textPrimary)
                            }
                            Spacer()
                            Text("\(tasks.filter { !$0.isDone && $0.tags.contains { $0.id == tag.id } }.count)")
                                .font(Theme.Typography.numeric(13)).foregroundStyle(Theme.Colors.textSecondary)
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(
                                Theme.Colors.textSecondary)
                        }.padding(16).contentShape(Rectangle())
                    }
                    .buttonStyle(MonoBrandPressStyle())
                    .accessibilityIdentifier("settings-edit-category-\(tag.name)")
                    .draggable(tag.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first, let from = UUID(uuidString: raw) else { return false }
                        return reorder(from: from, onto: tag.id)
                    }
                    .contextMenu { Button("Удалить папку", role: .destructive) { deletingTag = tag } }
                    Hairline(leading: 48)
                }
                Button {
                    addingTag = true
                } label: {
                    Label("Новая папка", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }.buttonStyle(MonoBrandPressStyle()).foregroundStyle(Theme.Colors.accent)
            }
            .modifier(MonoBrandSurface())
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Настройте, как задачи отображаются в списке на главном экране.")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
            taskAppearancePreview
                .padding(16)
                .modifier(MonoBrandSurface())
            appearanceRows
                .modifier(MonoBrandSurface())
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(auth.email ?? "Локальное пространство")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .modifier(MonoBrandSurface())
            SyncDetailsView()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .modifier(MonoBrandSurface())
            if auth.userID != nil || SyncPresentation.isPreview {
                Button {
                    confirmingSignOut = true
                } label: {
                    Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.danger)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.Colors.dangerMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.card)
                                .strokeBorder(Theme.Colors.danger.opacity(0.3), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                }
                .buttonStyle(MonoBrandPressStyle())
                .accessibilityIdentifier("settings-sign-out")
                .disabled(auth.isBusy)
                .padding(.top, 4)
            }
            if let error = auth.errorMessage { Text(error).foregroundStyle(Theme.Colors.danger) }
        }
    }

    private func reorder(from: UUID, onto: UUID) -> Bool {
        guard let source = tags.firstIndex(where: { $0.id == from }),
            let target = tags.firstIndex(where: { $0.id == onto }), source != target
        else { return false }
        var result = tags
        result.insert(result.remove(at: source), at: target)
        for (index, tag) in result.enumerated() where tag.sortOrder != index { tag.sortOrder = index; tag.touch() }
        context.saveAndSync()
        return true
    }
}

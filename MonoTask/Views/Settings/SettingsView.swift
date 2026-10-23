import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Query private var allTasks: [TaskItem]
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var auth

    @State private var newTagName: String = ""
    @State private var selectedColorHex: String = Theme.Colors.tagColors.first ?? "#0A84FF"
    @State private var targetedTagId: UUID? = nil
    @State private var tagToEdit: Tag? = nil
    @State private var tagToDelete: Tag? = nil
    @FocusState private var isNewTagFocused: Bool

    private let orderedWeekdays = Weekday.orderedFromMonday

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                scheduleSection
                contextsSection
                NotificationPreferencesView()
                syncSection
                accountSection
                footer
            }
            .padding(.horizontal, Theme.Spacing.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 36)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            try? await SupabaseSyncService.shared.sync(context: modelContext)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollDismissesKeyboard(.interactively)
        .monoScrollEdge()
        .background(Theme.Colors.background.ignoresSafeArea())
        .tint(Theme.Colors.accent)
        .sheet(item: $tagToEdit) { tag in
            TagEditSheet(tagToEdit: tag)
        }
        .confirmationDialog(
            "Удалить категорию «\(tagToDelete?.name ?? "")»?",
            isPresented: Binding(get: { tagToDelete != nil }, set: { if !$0 { tagToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let tag = tagToDelete {
                    Haptics.warning()
                    modelContext.deleteWithSync(tag)
                    modelContext.saveAndSync(delaySeconds: 0.1)
                }
                tagToDelete = nil
            }
            Button("Отмена", role: .cancel) {
                tagToDelete = nil
            }
        } message: {
            Text("Задачи останутся, но потеряют эту категорию.")
        }
        .task {
            _ = await SupabaseService.shared.testConnection()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                EyebrowLabel(text: "уведомления и категории")
                Spacer()
                SyncIndicator()
            }
            Text("Настройки".uppercased())
                .font(Theme.Typography.display)
                .tracking(Theme.Typography.displayTracking)
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }

    private func sectionLabel(_ title: String, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionTitle(text: title)
            if let hint {
                Text(hint)
                    .font(Theme.Typography.subtitle)
                    .foregroundColor(Theme.Colors.textMuted)
            }
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Расписание", hint: "В какие дни категория попадает в «Фокус дня»")

            GroupCard(padding: 14) {
                if tags.isEmpty {
                    Text("Сначала добавьте категорию ниже")
                        .font(Theme.Typography.callout)
                        .foregroundColor(Theme.Colors.textMuted)
                } else {

                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(spacing: 3) {
                            ForEach(orderedWeekdays) { day in
                                Text(day.shortName.uppercased())
                                    .font(
                                        Theme.Typography.numeric(9.5, weight: day == Weekday.current ? .bold : .regular)
                                    )
                                    .foregroundColor(
                                        day == Weekday.current ? Theme.Colors.accent : Theme.Colors.textMuted
                                    )
                                    .frame(width: 28)
                            }
                        }
                    }
                    .padding(.bottom, 8)

                    ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                        if index > 0 {
                            Hairline()
                                .padding(.vertical, 6)
                        }
                        scheduleRow(tag)
                    }
                }
            }
        }
    }

    private func scheduleRow(_ tag: Tag) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tag.color)
                .frame(width: 7, height: 7)
            Text(tag.name)
                .font(Theme.Typography.callout)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 4)

            HStack(spacing: 3) {
                ForEach(orderedWeekdays) { day in
                    let isActive = tag.scheduledDays.contains(day)
                    Button {
                        Haptics.selection()
                        toggleDay(day, for: tag)
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isActive ? tag.color : Theme.Colors.fill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        day == Weekday.current && !isActive ? Theme.Colors.ruleStrong : Color.clear,
                                        lineWidth: 1)
                            )
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tag.name), \(day.fullName)")
                    .accessibilityValue(isActive ? "включено" : "выключено")
                }
            }
        }
    }

    // MARK: - Contexts

    private var contextsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Категории", hint: "Перетащите, чтобы изменить порядок")

            GroupCard {
                ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                    if index > 0 {
                        Hairline(leading: 44)
                    }
                    contextRow(tag)
                }

                if !tags.isEmpty {
                    Hairline()
                }

                addContextRow
            }
        }
    }

    private func contextRow(_ tag: Tag) -> some View {
        let openCount = allTasks.filter { task in
            !task.isDone && task.tags.contains { $0.id == tag.id }
        }.count

        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Colors.textMuted.opacity(0.6))
                .frame(width: 20)

            Button {
                tagToEdit = tag
            } label: {
                HStack(spacing: 9) {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 8, height: 8)
                    Text(tag.name)
                        .font(Theme.Typography.body)
                        .tracking(Theme.Typography.bodyTracking)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if openCount > 0 {
                        Text("\(openCount)")
                            .font(Theme.Typography.numeric(12))
                            .foregroundColor(Theme.Colors.textMuted)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.Colors.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                tagToDelete = tag
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Colors.textMuted)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить \(tag.name)")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(targetedTagId == tag.id ? Theme.Colors.fillStrong : Color.clear)
        .contentShape(Rectangle())
        .draggable(tag.id.uuidString) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tag.color)
                    .frame(width: 8, height: 8)
                Text(tag.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        }
        .dropDestination(for: String.self) { items, _ in
            targetedTagId = nil
            guard let sourceIdString = items.first,
                let sourceId = UUID(uuidString: sourceIdString),
                sourceId != tag.id
            else { return false }
            reorderTags(fromId: sourceId, toId: tag.id)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                targetedTagId = targeted ? tag.id : (targetedTagId == tag.id ? nil : targetedTagId)
            }
        }
    }

    private var addContextRow: some View {
        let canAdd = !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.Colors.tagColor(selectedColorHex))
                    .frame(width: 8, height: 8)
                    .frame(width: 20)

                TextField("Новая категория", text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .focused($isNewTagFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        handleAddTag()
                    }

                SubmitCircleButton(isEnabled: canAdd, size: 28) {
                    handleAddTag()
                }
            }

            HStack(spacing: 10) {
                ForEach(Theme.Colors.tagColors, id: \.self) { hex in
                    let isSelected = selectedColorHex == hex
                    Button {
                        Haptics.selection()
                        selectedColorHex = hex
                    } label: {
                        Circle()
                            .fill(Theme.Colors.tagColor(hex))
                            .frame(width: 18, height: 18)
                            .padding(3)
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? Theme.Colors.textPrimary : Color.clear, lineWidth: 1.5)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 26)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Sync

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Аккаунт")
            GroupCard {
                HStack {
                    Text(auth.email ?? "")
                        .font(Theme.Typography.callout)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Button("Выйти") {
                        Task { await auth.signOut() }
                    }
                    .disabled(auth.isBusy)
                }
                .padding(14)
            }
            if let error = auth.errorMessage {
                Text(error).foregroundColor(Theme.Colors.danger)
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Синхронизация")

            GroupCard {
                HStack(spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(Theme.Typography.callout.weight(.medium))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(2)

                        Text(lastSyncText)
                            .font(Theme.Typography.numeric(11))
                            .foregroundColor(Theme.Colors.textMuted)
                    }

                    Spacer()

                    Button {
                        Haptics.selection()
                        Task { @MainActor in
                            try? await SupabaseSyncService.shared.sync(context: modelContext)
                        }
                    } label: {
                        Group {
                            if SupabaseService.shared.syncStatus.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.Colors.textPrimary)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(Theme.Colors.ruleStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(SupabaseService.shared.syncStatus.isSyncing)
                    .help("Синхронизировать сейчас")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Hairline(leading: 46)

                HStack(spacing: 12) {
                    Image(systemName: "icloud")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Colors.textMuted)
                        .frame(width: 20)
                    Text("Задачи хранятся в Supabase и работают офлайн")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private var lastSyncText: String {
        guard let lastSync = SupabaseConfig.shared.lastSyncDate else {
            return "ЕЩЁ НЕ СИНХРОНИЗИРОВАНО"
        }
        return "ПОСЛЕДНЯЯ · \(lastSync.formattedDateTime)"
    }

    private var statusColor: Color {
        if SupabaseService.shared.syncStatus.isSyncing {
            return Theme.Colors.textSecondary
        }
        switch SupabaseService.shared.connectionStatus {
        case .connected: return Theme.Colors.success
        case .offline, .notConfigured: return Theme.Colors.warning
        case .checking: return Theme.Colors.textSecondary
        case .error: return Theme.Colors.danger
        }
    }

    private var statusTitle: String {
        if SupabaseService.shared.syncStatus.isSyncing {
            return "Синхронизация…"
        }
        switch SupabaseService.shared.connectionStatus {
        case .connected: return "Облако подключено"
        case .offline: return "Офлайн — изменения сохраняются локально"
        case .checking: return "Проверка соединения…"
        case .error(let msg): return "Ошибка: \(msg)"
        case .notConfigured: return "Облако не настроено"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 4) {
            Text("MONOTASK")
                .font(Theme.Typography.heading(13))
                .foregroundColor(Theme.Colors.textSecondary)
            EyebrowLabel(text: "версия \(appVersion)")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Actions

    private func reorderTags(fromId: UUID, toId: UUID) {
        guard let fromIndex = tags.firstIndex(where: { $0.id == fromId }),
            let toIndex = tags.firstIndex(where: { $0.id == toId }),
            fromIndex != toIndex
        else { return }

        Haptics.selection()
        var updated = tags
        let item = updated.remove(at: fromIndex)
        updated.insert(item, at: toIndex)

        for (index, tag) in updated.enumerated() where tag.sortOrder != index {
            tag.sortOrder = index
            // Without bumping updatedAt the next pull treats the server order as newer and reverts it
            tag.touch()
        }
        modelContext.saveAndSync(delaySeconds: 0.4)
    }

    private func toggleDay(_ day: Weekday, for tag: Tag) {
        if tag.scheduledDays.contains(day) {
            tag.scheduledDays.removeAll { $0 == day }
        } else {
            tag.scheduledDays.append(day)
        }
        modelContext.saveAndSync(delaySeconds: 0.3)
    }

    private func handleAddTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Haptics.success()
        let nextSortOrder = (tags.map(\.sortOrder).max() ?? -1) + 1
        let newTag = Tag(
            name: String(trimmed.prefix(24)),
            colorHex: selectedColorHex,
            iconName: "bookmark.fill",
            scheduledDays: [Weekday.current],
            sortOrder: nextSortOrder
        )
        modelContext.insert(newTag)
        modelContext.saveAndSync(delaySeconds: 0.3)

        newTagName = ""
        isNewTagFocused = false
    }
}

#Preview {
    SettingsView()
}

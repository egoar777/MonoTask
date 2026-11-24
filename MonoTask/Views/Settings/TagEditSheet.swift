import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct TagEditSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]

    var tagToEdit: Tag?
    var onCreate: ((Tag) -> Void)? = nil
    var allowsSharedCreation = false
    var onOpenShared: ((UUID) -> Void)? = nil

    @State private var isShared = false
    @State private var sharedStore = SharedListStore.shared
    @State private var createdSharedID: UUID?
    @State private var savingShared = false
    @State private var joiningShared = false
    @State private var joinedSharedID: UUID?
    @State private var sharedError: String?

    @State private var name: String = ""
    @State private var selectedIcon = "square.stack.3d.up.fill"
    @State private var selectedColorHex: String = Theme.Colors.tagColors[0]
    @State private var selectedWeekdays: Set<Weekday> = []
    @State private var confirmingDelete = false
    @State private var isIconPickerExpanded = false
    @State private var isChoosingCustomColor = false

    private static let folderIcons: [(symbol: String, name: String)] = [
        ("square.stack.3d.up.fill", "Проекты"),
        ("briefcase.fill", "Работа"),
        ("graduationcap.fill", "Учёба"),
        ("house.fill", "Дом"),
        ("heart.fill", "Личное"),
        ("paintpalette.fill", "Творчество"),
        ("airplane", "Путешествия"),
        ("book.closed.fill", "Книги"),
        ("leaf.fill", "Природа"),
        ("sparkles", "Вдохновение"),
        ("laptopcomputer", "Компьютер"),
        ("camera.fill", "Фото"),
        ("folder.fill", "Папка"),
        ("tray.fill", "Входящие"),
        ("checklist", "Список дел"),
        ("calendar", "Календарь"),
        ("target", "Цели"),
        ("star.fill", "Избранное"),
        ("flag.fill", "Важное"),
        ("bolt.fill", "Энергия"),
        ("lightbulb.fill", "Идеи"),
        ("pencil.and.ruler.fill", "Дизайн"),
        ("doc.text.fill", "Документы"),
        ("bookmark.fill", "Закладки"),
        ("globe", "Мир"),
        ("map.fill", "Карты"),
        ("location.fill", "Места"),
        ("car.fill", "Автомобиль"),
        ("bicycle", "Велосипед"),
        ("tram.fill", "Транспорт"),
        ("cup.and.saucer.fill", "Отдых"),
        ("fork.knife", "Еда"),
        ("cart.fill", "Покупки"),
        ("gift.fill", "Подарки"),
        ("creditcard.fill", "Финансы"),
        ("chart.bar.fill", "Аналитика"),
        ("banknote.fill", "Бюджет"),
        ("dumbbell.fill", "Спорт"),
        ("figure.run", "Бег"),
        ("cross.case.fill", "Здоровье"),
        ("pawprint.fill", "Питомцы"),
        ("music.note", "Музыка"),
        ("headphones", "Аудио"),
        ("gamecontroller.fill", "Игры"),
        ("film.fill", "Кино"),
        ("hammer.fill", "Ремонт"),
        ("wrench.and.screwdriver.fill", "Инструменты"),
        ("lock.fill", "Приватное"),
    ]

    private static let standardColors: [(hex: String, name: String)] = [
        (Theme.Colors.tagColors[0], "Синий"),
        (Theme.Colors.tagColors[1], "Фиолетовый"),
        (Theme.Colors.tagColors[2], "Зелёный"),
        (Theme.Colors.tagColors[3], "Жёлтый"),
        (Theme.Colors.tagColors[4], "Красный"),
        (Theme.Colors.tagColors[5], "Розовый"),
    ]

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(hex: selectedColorHex) },
            set: { color in
                #if os(iOS)
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
                #else
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let red = rgb.redComponent
                let green = rgb.greenComponent
                let blue = rgb.blueComponent
                #endif
                let channels = [red, green, blue].map { Int((min(1, max(0, $0)) * 255).rounded()) }
                selectedColorHex = String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
            })
    }

    private var isEditing: Bool {
        tagToEdit != nil
    }

    private var canSave: Bool {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && !savingShared && (!isShared || (title.count <= 100 && sharedStore.canManage))
    }

    private var title: String {
        if createdSharedID != nil { return "Готово" }
        return isEditing ? "Папка" : "Новая папка"
    }

    var body: some View {
        sheet
            .tint(isShared ? Theme.Colors.accent : Theme.Colors.tagColor(selectedColorHex))
            .interactiveDismissDisabled(savingShared)
            .sharedErrorAlert($sharedError)
            .sheet(
                isPresented: $joiningShared,
                onDismiss: {
                    if let id = joinedSharedID { joinedSharedID = nil; openSharedFolder(id) }
                }
            ) {
                SharedJoinFolderSheet { joinedSharedID = $0 }
            }
            .task { if allowsSharedCreation { await sharedStore.sync() } }
            .preferredColorScheme(Theme.colorScheme)
            .confirmationDialog("Удалить папку?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let tag = tagToEdit { modelContext.deleteWithSync(tag); modelContext.saveAndSync(); dismiss() }
                }
            } message: {
                Text("Задачи останутся без этой папки.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissTaskEditor)) { _ in dismiss() }
            .onAppear {
                if let tag = tagToEdit {
                    name = tag.name
                    selectedIcon = tag.folderIconName

                    selectedColorHex = Theme.Colors.normalizedTagHex(tag.colorHex)
                    selectedWeekdays = Set(tag.scheduledDays)
                }
            }
    }

    @ViewBuilder
    private var sheet: some View {
        #if os(iOS)
        let editorSheet = NavigationStack {
            editor
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { cancelButton }
                    ToolbarItem(placement: .confirmationAction) { saveButton }
                }
        }
        .presentationDetents([.fraction(0.88), .large])
        .presentationDragIndicator(.visible)

        if reduceTransparency {
            editorSheet.presentationBackground(Theme.Colors.background)
        } else if #available(iOS 26.0, *) {
            editorSheet
        } else {
            editorSheet
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        #else
        VStack(spacing: 0) {
            HStack {
                cancelButton.buttonStyle(ClassicGlassButtonStyle())
                Spacer()
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                saveButton.buttonStyle(ClassicGlassButtonStyle(prominent: true))
            }
            .padding(.horizontal, Theme.Spacing.screenPadding)
            .padding(.top, 22)
            .padding(.bottom, 16)
            editor.monoScrollEdge()
        }
        .background(.regularMaterial)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 600, idealHeight: 690)
        #endif
    }

    private var cancelButton: some View {
        Button("Отмена", systemImage: "xmark") { dismiss() }
            .disabled(savingShared)
            .labelStyle(.iconOnly)
            .keyboardShortcut(.cancelAction)
    }

    private var saveButton: some View {
        Button {
            if let id = createdSharedID {
                openSharedFolder(id)
            } else if isShared {
                createSharedFolder()
            } else {
                save()
                dismiss()
            }
        } label: {
            if savingShared {
                ProgressView()
            } else {
                Label("Сохранить", systemImage: "checkmark")
                    .font(.body.weight(.semibold))
                    .labelStyle(.iconOnly)
            }
        }
        .disabled(createdSharedID == nil && !canSave)
        .accessibilityIdentifier("folder-save")
        .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder
    private var editor: some View {
        #if os(iOS)
        ScrollViewReader { scroll in
            editorScrollView {
                withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                    scroll.scrollTo("folder-custom-color", anchor: .top)
                }
            }
        }
        #else
        editorScrollView()
        #endif
    }

    private func editorScrollView(onRevealCustomColor: @escaping () -> Void = {}) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let id = createdSharedID {
                    SharedInvitationContent(listID: id, created: true)
                    Button {
                        openSharedFolder(id)
                    } label: {
                        Label("Открыть папку", systemImage: "arrow.right")
                    }
                    .buttonStyle(SharedPrimaryStyle())
                    .accessibilityIdentifier("shared-open-created-folder")
                } else {
                    if allowsSharedCreation && !isEditing {
                        Picker("Тип папки", selection: $isShared) {
                            Text("Личная").tag(false)
                            Text("Общая").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .disabled(savingShared)
                        .accessibilityIdentifier("folder-type")
                    }

                    ClassicFolderArtwork(
                        tint: isShared
                            ? Theme.Colors.tagColor(Theme.Colors.tagColors[1])
                            : Theme.Colors.tagColor(selectedColorHex),
                        icon: isShared ? "person.2.fill" : selectedIcon
                    )
                    .frame(width: 160, height: 125).frame(maxWidth: .infinity)

                    HStack(spacing: 12) {
                        Circle()
                            .fill(
                                isShared
                                    ? Theme.Colors.tagColor(Theme.Colors.tagColors[1])
                                    : Theme.Colors.tagColor(selectedColorHex)
                            )
                            .frame(width: 12, height: 12)
                        TextField("Название", text: $name)
                            .textFieldStyle(.plain)
                            .font(Theme.Typography.heading(24))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .accessibilityLabel("Название папки")
                            .accessibilityIdentifier(isShared ? "shared-folder-name" : "personal-folder-name")
                            .disabled(savingShared)
                    }
                    .padding(16)
                    .modifier(FloatingGlass(shape: RoundedRectangle(cornerRadius: 18)))

                    if isShared {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(
                                "Участники смогут добавлять, редактировать и выполнять задачи. После создания появится QR-код приглашения.",
                                systemImage: "person.2"
                            )
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            if sharedStore.accountID == nil {
                                Label(
                                    "Для общей папки войдите в аккаунт в настройках.",
                                    systemImage: "person.crop.circle"
                                )
                                .foregroundStyle(Theme.Colors.textSecondary)
                            } else if let message = sharedStore.errorMessage {
                                Text(message).foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Button {
                                joiningShared = true
                            } label: {
                                Label("Присоединиться по QR-коду или ссылке", systemImage: "qrcode.viewfinder")
                            }
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                            .disabled(sharedStore.accountID == nil || savingShared)
                            .accessibilityIdentifier("classic-join-shared-folder")
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            EyebrowLabel(text: "Цвет")
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8
                            ) {
                                ForEach(Self.standardColors, id: \.hex) { option in
                                    let hex = option.hex
                                    let isSelected = selectedColorHex == hex
                                    Button {
                                        Haptics.selection()
                                        withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                                            selectedColorHex = hex
                                        }
                                    } label: {
                                        Circle()
                                            .fill(Theme.Colors.tagColor(hex))
                                            .frame(width: 26, height: 26)
                                            .overlay {
                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundStyle(.white)
                                                        .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                                                }
                                            }
                                            .frame(width: 32, height: 32)
                                    }
                                    .buttonStyle(ClassicGlassButtonStyle())
                                    .buttonBorderShape(.circle)
                                    .controlSize(.regular)
                                    .accessibilityLabel(option.name)
                                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                                    .accessibilityIdentifier("folder-color-\(hex)")
                                    .help(option.name)
                                }
                            }
                            customColorDisclosure(onReveal: onRevealCustomColor)
                        }

                        DisclosureGroup(isExpanded: $isIconPickerExpanded) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                                ForEach(Self.folderIcons, id: \.symbol) { option in
                                    let icon = option.symbol
                                    Button {
                                        Haptics.selection()
                                        withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                                            selectedIcon = icon
                                        }
                                    } label: {
                                        Image(systemName: icon)
                                            .font(.system(size: 19))
                                            .frame(width: 26, height: 32)
                                    }
                                    .buttonStyle(ClassicGlassButtonStyle(prominent: selectedIcon == icon))
                                    .tint(selectedIcon == icon ? Theme.Colors.tagColor(selectedColorHex) : nil)
                                    .buttonBorderShape(.roundedRectangle(radius: 14))
                                    .accessibilityLabel(option.name)
                                    .accessibilityAddTraits(selectedIcon == icon ? [.isSelected] : [])
                                    .accessibilityIdentifier("folder-icon-\(icon)")
                                    .help(option.name)
                                }
                            }
                            .padding(.top, 12)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIcon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Theme.Colors.tagColor(selectedColorHex))
                                    .frame(width: 28, height: 32)
                                Text("Значок папки")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(16)
                        .modifier(FloatingGlass(shape: RoundedRectangle(cornerRadius: 22)))
                        .accessibilityIdentifier("folder-icon-disclosure")
                        if tagToEdit != nil {
                            Button("Удалить папку", role: .destructive) { confirmingDelete = true }
                                .buttonStyle(ClassicGlassButtonStyle())
                                .controlSize(.large)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func createSharedFolder() {
        guard canSave else { return }
        savingShared = true
        hideKeyboard()
        Task { @MainActor in
            defer { savingShared = false }
            do {
                createdSharedID = try await sharedStore.createList(title: name)
                Haptics.success()
            } catch { sharedError = SharedListStore.message(for: error) }
        }
    }

    private func openSharedFolder(_ id: UUID) {
        onOpenShared?(id)
        dismiss()
    }

    private func customColorDisclosure(onReveal: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                    isChoosingCustomColor.toggle()
                } completion: {
                    if isChoosingCustomColor { onReveal() }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Colors.tagColor(selectedColorHex))
                        .frame(width: 28, height: 32)
                    Text("Свой цвет")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer(minLength: 12)
                    Circle()
                        .fill(Color(hex: selectedColorHex))
                        .frame(width: 28, height: 28)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(isChoosingCustomColor ? 90 : 0))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(16)
                .contentShape(.interaction, RoundedRectangle(cornerRadius: 22))
                .modifier(FloatingGlass(shape: RoundedRectangle(cornerRadius: 22), interactive: true))
            }
            .buttonStyle(.plain)
            .id("folder-custom-color")
            .accessibilityIdentifier("folder-custom-color")
            .accessibilityValue(selectedColorHex)
            .accessibilityAddTraits(isChoosingCustomColor ? .isSelected : [])

            if isChoosingCustomColor {
                customColorPalette
            }
        }
    }

    private var customColorPalette: some View {
        #if os(iOS)
        InlineFolderColorPicker(selection: customColor) {
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                isChoosingCustomColor = false
            }
        }
        .frame(height: 540)
        // Give the system palette the full scroll view width, including its own margins.
        .padding(.horizontal, -Theme.Spacing.screenPadding)
        #else
        ColorPicker("Выбрать цвет", selection: customColor, supportsOpacity: false)
            .controlSize(.large)
        #endif
    }

    private func toggleWeekday(_ weekday: Weekday) {
        if selectedWeekdays.contains(weekday) {
            selectedWeekdays.remove(weekday)
        } else {
            selectedWeekdays.insert(weekday)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // Keep a stable Monday-first order instead of Set iteration order
        let orderedDays = Weekday.orderedFromMonday.filter { selectedWeekdays.contains($0) }

        if let tag = tagToEdit {
            tag.name = trimmedName
            tag.colorHex = selectedColorHex
            tag.iconName = selectedIcon
            tag.scheduledDays = orderedDays
            tag.touch()
        } else {
            let newTag = Tag(
                name: trimmedName,
                colorHex: selectedColorHex,
                iconName: selectedIcon,
                scheduledDays: orderedDays,
                // New contexts go to the end instead of colliding with the first one at 0
                sortOrder: (tags.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(newTag)
            onCreate?(newTag)
        }

        modelContext.saveAndSync(delaySeconds: 0.3)
    }
}

#if os(iOS)
/// Embeds Apple's Grid, Spectrum and Sliders in the folder editor.
private struct InlineFolderColorPicker: UIViewControllerRepresentable {
    @Binding var selection: Color
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let controller = UIColorPickerViewController()
        controller.supportsAlpha = false
        controller.selectedColor = UIColor(selection)
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: UIColorPickerViewController, context: Context) {
        context.coordinator.parent = self
        let color = UIColor(selection)
        if controller.selectedColor != color { controller.selectedColor = color }
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: InlineFolderColorPicker
        init(parent: InlineFolderColorPicker) { self.parent = parent }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            parent.onFinish()
        }

        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            parent.selection = Color(uiColor: viewController.selectedColor)
        }
    }
}
#endif

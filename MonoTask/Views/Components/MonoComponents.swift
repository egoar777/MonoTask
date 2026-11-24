import SwiftUI
import SwiftData

// MARK: - Eyebrow Label
struct EyebrowLabel: View {
    let text: String
    var count: Int? = nil
    var color: Color = Theme.Colors.textSecondary

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
            if let count {
                Text("\(count)")
                    .opacity(0.7)
            }
        }
        .font(Theme.Typography.eyebrow)
        .tracking(Theme.Typography.eyebrowTracking)
        .foregroundColor(color)
        .lineLimit(1)
    }
}

// MARK: - Section Title
struct SectionTitle: View {
    let text: String
    var count: Int? = nil
    var color: Color = Theme.Colors.textSecondary

    var body: some View {
        HStack(spacing: 7) {
            Text(text)
                .foregroundColor(color)
            if let count {
                Text("\(count)")
                    .foregroundColor(Theme.Colors.textMuted)
            }
        }
        .font(Theme.Typography.section)
        .tracking(0)
        .lineLimit(1)
    }
}

// MARK: - Task Checkbox
struct TaskCheckbox: View {
    let isDone: Bool
    var size: CGFloat = 22
    var priorityColor: Color? = nil
    var checkmarkProgress: CGFloat? = nil

    var body: some View {
        ZStack {
            Circle()
                .fill(isDone ? Theme.Colors.inverse : (priorityColor?.opacity(0.12) ?? Color.clear))
            Circle()
                .strokeBorder(strokeColor, lineWidth: 1.5)

            // Keep the same shape through confirmation and the move to completed.
            // Replacing it with a symbol gives List a separate insertion/removal to animate.
            TaskCheckmark()
                .trim(from: 0, to: checkmarkProgress ?? (isDone ? 1 : 0))
                .stroke(
                    Theme.Colors.onInverse,
                    style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size * 0.48, height: size * 0.48)
        }
        .frame(width: size, height: size)
    }

    private var strokeColor: Color {
        if isDone { return Theme.Colors.inverse }
        return priorityColor ?? Theme.Colors.textMuted
    }
}

private struct TaskCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width * 0.36, y: rect.height * 0.84))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.14))
        }
    }
}

// MARK: - Scope Tab
struct ScopeTab: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    var color: Color? = nil
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color { Circle().fill(color).frame(width: 6, height: 6) }
                Text(title).font(.footnote.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
            .padding(.horizontal, 16)
            .frame(minHeight: 38)
            .background(isSelected ? Theme.Colors.accent : Theme.Colors.surfaceElevated, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(FullSurfaceButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(count.map { "Открытых задач: \($0)" } ?? "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: isSelected)
    }
}

// Categories share the same visual language as the main filters.
struct ContextChip: View {
    let title: String
    var color: Color? = nil
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        ScopeTab(title: title, color: color, count: count, isSelected: isSelected, action: action)
    }
}

// MARK: - Progress Line
struct ProgressLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: Double
    var tint: Color = Theme.Colors.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.hairline)
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: progress)
    }
}

// MARK: - Group Card
struct GroupCard<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Colors.hairline, lineWidth: 1)
        )
    }
}
struct Hairline: View {
    var leading: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(height: 1)
            .padding(.leading, leading)
    }
}

#if os(macOS)
extension View {
    func macNavigationHeader<Actions: View>(
        maxWidth: CGFloat = .infinity, isVisible: Bool = true, @ViewBuilder actions: () -> Actions
    ) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if isVisible {
                VStack(spacing: 0) {
                    HStack(spacing: 12, content: actions)
                        .buttonStyle(.bordered)
                        .padding(.horizontal, Theme.Spacing.screenPadding)
                        .frame(maxWidth: maxWidth, minHeight: 46, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    Hairline()
                }
                .background(Theme.Colors.background)
            }
        }
    }
}
#endif

// MARK: - Submit Button
struct SubmitCircleButton: View {
    let isEnabled: Bool
    var size: CGFloat = 32
    var label = "Добавить задачу"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isEnabled ? Theme.Colors.accent : Theme.Colors.fillStrong)
                Image(systemName: "arrow.up")
                    .font(.system(size: size * 0.45, weight: .heavy))
                    .foregroundColor(isEnabled ? Theme.Colors.onAccent : Theme.Colors.textMuted)
            }
            .frame(width: size, height: size)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(FullSurfaceButtonStyle())
        .modifier(FloatingGlass(shape: Circle().inset(by: (44 - size) / 2), interactive: true))
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Priority Toggle
struct PriorityToggleButton: View {
    @Binding var isOn: Bool
    var size: CGFloat = 32

    var body: some View {
        Button {
            Haptics.selection()
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? Priority.high.systemImage : "star")
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundColor(isOn ? Priority.high.color : Priority.none.color)
                .frame(width: size, height: size)
                .background(Circle().fill(isOn ? Priority.high.color.opacity(0.16) : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(FullSurfaceButtonStyle())
        .modifier(FloatingGlass(shape: Circle(), interactive: true))
        .accessibilityLabel(isOn ? "Снять высокий приоритет" : "Высокий приоритет")
        .accessibilityValue(isOn ? "Включён" : "Выключен")
        .help(isOn ? "Снять высокий приоритет" : "Высокий приоритет")
    }
}

struct FloatingGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    var id: String? = nil
    var namespace: Namespace.ID? = nil
    var interactive = false
    var tint: Color? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Theme.Colors.surfaceElevated, in: shape)
                .overlay(shape.stroke(Theme.Colors.ruleStrong, lineWidth: 1))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            if let namespace {
                content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
                    .glassEffectID(id, in: namespace)
                    .glassEffectTransition(.matchedGeometry)
            } else {
                content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
            }
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Theme.Colors.ruleStrong, lineWidth: 0.5))
        }
    }
}

struct ClassicGlassButtonStyle: PrimitiveButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var prominent = false

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), !reduceTransparency {
            if prominent {
                Button(configuration).buttonStyle(.glassProminent)
            } else {
                Button(configuration).buttonStyle(.glass)
            }
        } else if prominent {
            Button(configuration).buttonStyle(.borderedProminent)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}

/// Gives custom buttons a hit area covering their entire laid-out label.
struct FullSurfaceButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.contentShape(.interaction, Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CurrentDateLabel: View {
    var date: Date? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let value = (date ?? timeline.date).formatted(
                .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU")))
            Text(value.prefix(1).uppercased() + value.dropFirst())
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("current-date")
        }
    }
}

struct ScreenTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.display)
            .tracking(Theme.Typography.displayTracking)
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ScreenHeading: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CurrentDateLabel().frame(minHeight: 28, alignment: .leading)
            ScreenTitle(text: text)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CaptureCategoryPicker: View {
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Binding var selection: Tag?
    var usesFolderTerminology = false
    var onCreateFolder: (() -> Void)? = nil
    @State private var isCreatingFolder = false

    private var selectedID: Binding<UUID?> {
        Binding(
            get: { selection?.id },
            set: { id in selection = tags.first { $0.id == id } }
        )
    }

    var body: some View {
        Menu {
            Picker("Папка", selection: selectedID) {
                Text(usesFolderTerminology ? "Без папки" : "Без папки").tag(nil as UUID?)
                ForEach(tags) { tag in
                    Text(tag.name).tag(Optional(tag.id))
                }
            }
            Divider()
            Button {
                if let onCreateFolder { onCreateFolder() } else { isCreatingFolder = true }
            } label: {
                Label("Добавить папку", systemImage: "folder.badge.plus")
            }
            .accessibilityIdentifier("capture-create-folder")
        } label: {
            HStack(spacing: 6) {
                if usesFolderTerminology {
                    Image(systemName: "folder").foregroundStyle(selection?.color ?? Theme.Colors.textSecondary)
                } else {
                    Circle().fill(selection?.color ?? Theme.Colors.textMuted).frame(width: 7, height: 7)
                }
                Text(selection?.name ?? (usesFolderTerminology ? "Без папки" : "Без папки")).font(
                    Theme.Typography.caption
                ).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.Colors.fillStrong, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: !usesFolderTerminology, vertical: false)
        .accessibilityLabel(
            (usesFolderTerminology ? "Папка: " : "Папка: ")
                + (selection?.name ?? (usesFolderTerminology ? "Без папки" : "Без папки"))
        )
        .accessibilityIdentifier("capture-category-picker")
        .sheet(isPresented: $isCreatingFolder) {
            TagEditSheet(onCreate: { selection = $0 })
        }
    }
}

/// The priority heading also accepts tasks when the section is empty.
struct PrioritySectionTitle: View {
    var count: Int
    var color: Color
    var onDropTask: (UUID) -> Bool
    @State private var isTargeted = false

    var body: some View {
        HStack {
            SectionTitle(text: "Приоритет", count: count, color: isTargeted ? Theme.Colors.priority : color)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let rawID = items.first, let id = UUID(uuidString: rawID) else { return false }
            return onDropTask(id)
        } isTargeted: {
            isTargeted = $0
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Приоритет")
        .accessibilityValue("Задач: \(count)")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("priority-drop-target")
    }
}

struct ClassicInlineTaskInput: View {
    @Binding var isCaptureActive: Bool
    let onSubmit: (String, Bool) -> Bool
    @State private var title = ""
    @State private var highPriority = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            PriorityToggleButton(isOn: $highPriority, size: 36)
            TextField("Новая задача", text: $title)
                .font(Theme.Typography.body).textFieldStyle(.plain)
                .foregroundStyle(Theme.Colors.textPrimary)
                .focused($focused).submitLabel(.done)
                .onSubmit(submit)
                .accessibilityIdentifier("classic-folder-task-input")
            SubmitCircleButton(isEnabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, size: 34) {
                submit()
            }
            .accessibilityIdentifier("classic-folder-task-submit")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .modifier(FloatingGlass(shape: Capsule()))
        .onChange(of: isCaptureActive) { _, active in focused = active }
        .onChange(of: focused) { _, active in isCaptureActive = active }
        .onDisappear { isCaptureActive = false }
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, onSubmit(trimmed, highPriority) else { return }
        title = ""
        highPriority = false
        focused = true
    }
}

/// Shares the text transition between the title, notes and controls of a row.
struct TaskTextExpansion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private(set) var isExpanded = false

    var presentation: TaskTextPresentation {
        TaskTextPresentation(isExpanded: isExpanded, toggle: toggle)
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : Theme.Motion.taskTextExpansion) {
            isExpanded.toggle()
        }
    }
}

struct TaskTextPresentation {
    let isExpanded: Bool
    let toggle: () -> Void
}

struct TaskPreviewText<Content: View>: View {
    let lineLimit: Int
    let expansion: TaskTextPresentation
    var expandedTrailingInset: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        TaskTextRevealLayout(progress: expansion.isExpanded ? 1 : 0) {
            text(limit: lineLimit)
                .hidden()
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    visibleHeight = $0
                }

            text(limit: nil)
                .padding(.trailing, expandedTrailingInset)
                .hidden()
        }
        .accessibilityHidden(true)
        .overlay(alignment: .topLeading) {
            if expansion.isExpanded {
                text(limit: nil)
                    .padding(.trailing, expandedTrailingInset)
                    .transition(.opacity)
            } else {
                text(limit: lineLimit)
                    .transition(.opacity)
            }
        }
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if !expansion.isExpanded && visibleHeight > 0 && fullHeight > visibleHeight + 0.5 {
                // Overlay the native ellipsis without reserving another text column.
                Button(action: expansion.toggle) {
                    Color.clear
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FullSurfaceButtonStyle())
                .accessibilityLabel("Раскрыть задачу полностью")
                .accessibilityIdentifier("task-text-expansion")
                .accessibilityValue("Свёрнуто")
                .transition(.opacity)
            }
        }
        .background {
            if !expansion.isExpanded {
                GeometryReader { preview in
                    content()
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: preview.size.width, alignment: .leading)
                        .hidden()
                        .accessibilityHidden(true)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            fullHeight = $0
                        }
                }
            }
        }
    }

    private func text(limit: Int?) -> some View {
        content()
            .lineLimit(limit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Keeps each text variant wrapped at its own width as the row changes height.
private struct TaskTextRevealLayout: Layout {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let textProposal = ProposedViewSize(width: proposal.width, height: nil)
        let preview = subviews[0].sizeThatFits(textProposal)
        let expanded = subviews[1].sizeThatFits(textProposal)
        let fraction = min(1, max(0, progress))
        return CGSize(
            width: max(preview.width, expanded.width),
            height: preview.height + (expanded.height - preview.height) * fraction)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let textProposal = ProposedViewSize(width: bounds.width, height: nil)
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: textProposal)
        }
    }
}

struct TaskTextCollapseButton: View {
    let expansion: TaskTextPresentation

    var body: some View {
        Button(action: expansion.toggle) {
            Image(systemName: "chevron.up")
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(FullSurfaceButtonStyle())
        .accessibilityLabel("Свернуть задачу")
        .accessibilityIdentifier("task-text-expansion")
        .accessibilityValue("Развёрнуто")
        .fixedSize()
    }
}

/// A collapse control beside the first line, without adding a footer to the task.
struct TaskTextCollapseAccessory: ViewModifier {
    static let textInset: CGFloat = 36
    let expansion: TaskTextPresentation

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if expansion.isExpanded {
                    TaskTextCollapseButton(expansion: expansion)
                        // Use the row's existing insets for a full touch target.
                        .offset(x: 8, y: -12)
                        .transition(.opacity)
                }
            }
    }
}

/// Apple Music-style rules align with task text, leaving the checkbox column clear.
struct TaskRowSeparator: View {
    #if os(macOS)
    var leadingInset: CGFloat = 48
    var trailingInset: CGFloat = 10
    #else
    var leadingInset: CGFloat = 50
    var trailingInset: CGFloat = 16
    #endif

    var body: some View {
        Rectangle()
            .fill(Color(hex: "#282828"))
            .frame(height: 1)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

// MARK: - MonoTask branded screens

enum MonoBrand {
    static let panel = Color(hex: "#111210")
    static let inset = Color(hex: "#191B17")
    static let violet = Color(hex: "#B48CFF")
    static let mint = Color(hex: "#3DDC97")
    static let blue = Color(hex: "#5AA9FF")
}

struct MonoBrandTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.display)
            .tracking(Theme.Typography.displayTracking)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct MonoBrandSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.bold))
            .accessibilityAddTraits(.isHeader)
    }
}

struct MonoBrandSurface: ViewModifier {
    var fill = MonoBrand.panel
    var border = Theme.Colors.hairline
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(fill, in: shape)
            .overlay { shape.strokeBorder(border).allowsHitTesting(false) }
    }
}

struct MonoBrandPill: ViewModifier {
    var selected = false

    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: Theme.Spacing.touchTargetMin)
            .background(selected ? Theme.Colors.accent : MonoBrand.inset, in: .capsule)
            .contentShape(.capsule)
    }
}

enum MonoBrandMotion {
    static let page = Animation.smooth(duration: 0.34)
    static let disclosure = Animation.smooth(duration: 0.38)
    static let control = Animation.smooth(duration: 0.24)
    static let fade = Animation.easeInOut(duration: 0.16)

    static func reveal(reduceMotion: Bool, distance: CGFloat = 16) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: distance)).combined(with: .scale(scale: 0.98)),
            removal: .opacity.combined(with: .offset(y: -distance / 2))
        )
    }
}

struct MonoBrandPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.interaction, Rectangle())
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : MonoBrandMotion.control, value: configuration.isPressed)
    }
}

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

    var body: some View {
        ZStack {
            Circle()
                .fill(isDone ? Theme.Colors.inverse : Color.clear)
            Circle()
                .strokeBorder(strokeColor, lineWidth: 1.5)

            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.48, weight: .heavy))
                    .foregroundColor(Theme.Colors.onInverse)
            }
        }
        .frame(width: size, height: size)
    }

    private var strokeColor: Color {
        if isDone { return Theme.Colors.inverse }
        return Theme.Colors.textMuted
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

// MARK: - Submit Button
struct SubmitCircleButton: View {
    let isEnabled: Bool
    var size: CGFloat = 32
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
        .disabled(!isEnabled)
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
            ZStack {
                Image(systemName: "flag")
                    .opacity(isOn ? 0 : 1)
                Image(systemName: "flag.fill")
                    .opacity(isOn ? 1 : 0)
            }
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundColor(isOn ? Theme.Colors.priority : Theme.Colors.textMuted)
            .frame(width: size, height: size)
            .background(Circle().fill(isOn ? Theme.Colors.priority.opacity(0.16) : Color.clear))
            .contentShape(Circle())
        }
        .buttonStyle(FullSurfaceButtonStyle())
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

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Theme.Colors.surfaceElevated, in: shape)
                .overlay(shape.stroke(Theme.Colors.ruleStrong, lineWidth: 1))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            if let namespace {
                content.glassEffect(.regular.interactive(), in: shape)
                    .glassEffectID(id, in: namespace)
                    .glassEffectTransition(.matchedGeometry)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Theme.Colors.ruleStrong, lineWidth: 0.5))
        }
    }
}

/// Gives custom buttons a hit area covering their entire laid-out label.
struct FullSurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.interaction, Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
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

struct ScreenHeading: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CurrentDateLabel().frame(minHeight: 28, alignment: .leading)
            Text(text.uppercased())
                .font(Theme.Typography.display)
                .tracking(Theme.Typography.displayTracking)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CaptureCategoryPicker: View {
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Binding var selection: Tag?

    private var selectedID: Binding<UUID?> {
        Binding(
            get: { selection?.id },
            set: { id in selection = tags.first { $0.id == id } }
        )
    }

    var body: some View {
        Menu {
            Picker("Категория", selection: selectedID) {
                Text("Без категории").tag(nil as UUID?)
                ForEach(tags) { tag in
                    Text(tag.name).tag(Optional(tag.id))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(selection?.color ?? Theme.Colors.textMuted).frame(width: 7, height: 7)
                Text(selection?.name ?? "Без категории").font(Theme.Typography.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.Colors.fillStrong, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Категория: " + (selection?.name ?? "Без категории"))
        .accessibilityIdentifier("capture-category-picker")
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

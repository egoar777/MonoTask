import SwiftUI

/// Week-column activity grid (rows Monday → Sunday, newest week on the right).
/// The number of weeks adapts to the available width.
struct ActivityGrid: View {
    let counts: [Date: Int]
    var tint: Color = Theme.Colors.accent
    var cellSize: CGFloat = 12
    var gap: CGFloat = 3
    var showWeekdayLabels: Bool = true

    private let labelWidth: CGFloat = 18

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if showWeekdayLabels {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(row % 2 == 0 ? Weekday.orderedFromMonday[row].shortName.uppercased() : "")
                            .font(Theme.Typography.numeric(8.5))
                            .foregroundColor(Theme.Colors.textMuted)
                            .frame(width: labelWidth, height: cellSize, alignment: .leading)
                    }
                }
            }

            Canvas { context, size in
                let columns = max(1, Int((size.width + gap) / (cellSize + gap)))
                let calendar = Calendar.current
                let today = Date.now.startOfDay
                let currentWeek = today.startOfWeek

                for column in 0..<columns {
                    let weeksBack = columns - 1 - column
                    guard let weekStart = calendar.date(byAdding: .day, value: -7 * weeksBack, to: currentWeek) else {
                        continue
                    }
                    for row in 0..<7 {
                        guard let day = calendar.date(byAdding: .day, value: row, to: weekStart), day <= today else {
                            continue
                        }
                        let rect = CGRect(
                            x: CGFloat(column) * (cellSize + gap),
                            y: CGFloat(row) * (cellSize + gap),
                            width: cellSize,
                            height: cellSize
                        )
                        let path = Path(roundedRect: rect, cornerRadius: 2.5, style: .continuous)
                        context.fill(path, with: .color(color(for: counts[day] ?? 0)))
                        if day == today {
                            context.stroke(path, with: .color(Theme.Colors.textPrimary), lineWidth: 1.5)
                        }
                    }
                }
            }
            .frame(height: cellSize * 7 + gap * 6)
        }
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: return Theme.Colors.fillStrong
        case 1: return tint.opacity(0.32)
        case 2: return tint.opacity(0.55)
        case 3: return tint.opacity(0.78)
        default: return tint
        }
    }
}

/// Legend strip: "меньше ▢▢▢▢▢ больше"
struct ActivityLegend: View {
    var tint: Color = Theme.Colors.accent

    var body: some View {
        HStack(spacing: 3) {
            Text("МЕНЬШЕ")
                .padding(.trailing, 3)
            ForEach([0.05, 0.32, 0.55, 0.78, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(level == 0.05 ? Theme.Colors.fillStrong : tint.opacity(level))
                    .frame(width: 9, height: 9)
            }
            Text("БОЛЬШЕ")
                .padding(.leading, 3)
        }
        .font(Theme.Typography.numeric(9))
        .tracking(0.5)
        .foregroundColor(Theme.Colors.textMuted)
    }
}

/// One context's activity: name, totals and a compact grid in the context colour.
struct ContextHeatmapCard: View {
    let tag: Tag
    let counts: [Date: Int]

    private var totalCompleted: Int {
        counts.values.reduce(0, +)
    }

    private var activeDays: Int {
        counts.values.filter { $0 > 0 }.count
    }

    var body: some View {
        GroupCard(padding: 16) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 7, height: 7)
                    Text(tag.name.uppercased())
                        .font(Theme.Typography.heading(14))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 10) {
                    metric(value: totalCompleted, unit: "ЗАДАЧ")
                    metric(value: activeDays, unit: "ДН.")
                }
            }
            .padding(.bottom, 14)

            ActivityGrid(counts: counts, tint: tag.color, cellSize: 11, gap: 3)
        }
    }

    private func metric(value: Int, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(value)")
                .font(Theme.Typography.numeric(13, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(unit)
                .font(Theme.Typography.eyebrow)
                .foregroundColor(Theme.Colors.textMuted)
        }
    }
}

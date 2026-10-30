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

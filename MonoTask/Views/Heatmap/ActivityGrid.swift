import SwiftUI

/// Calendar weeks run left to right; weekdays run Monday to Sunday.
struct ActivityGrid: View {
    let counts: [Date: Int]
    var tint: Color = Theme.Colors.accent
    var cellSize: CGFloat = 24
    var gap: CGFloat = 4
    var showWeekdayLabels = true
    var weeks = 18
    var rangeStart: Date?
    var rangeEnd: Date?
    var onSelect: ((Date) -> Void)?

    @ScaledMetric(relativeTo: .caption2) private var weekdayWidth: CGFloat = 32

    var body: some View {
        GeometryReader { geometry in
            let labelWidth: CGFloat = showWeekdayLabels ? weekdayWidth + 4 : 0
            let side = max(2, (geometry.size.width - labelWidth - CGFloat(weeks - 1) * gap) / CGFloat(weeks))
            HStack(alignment: .top, spacing: showWeekdayLabels ? 4 : 0) {
                if showWeekdayLabels {
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            Text(row % 2 == 0 ? Weekday.orderedFromMonday[row].shortName : "")
                                .font(.caption2.monospaced())
                                .foregroundStyle(Theme.Colors.textMuted)
                                .frame(width: weekdayWidth, height: side, alignment: .leading)
                        }
                    }
                }
                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<weeks, id: \.self) { column in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                let day = Calendar.current.date(
                                    byAdding: .day, value: (column - weeks + 1) * 7 + row,
                                    to: (rangeEnd?.daysAgo(1) ?? Date.now).startOfWeek)!
                                let count = counts[day, default: 0]
                                Button {
                                    onSelect?(day)
                                } label: {
                                    RoundedRectangle(cornerRadius: min(3, side / 4))
                                        .fill(color(for: count))
                                        .overlay {
                                            if day.isToday {
                                                RoundedRectangle(cornerRadius: min(3, side / 4))
                                                    .strokeBorder(Theme.Colors.textPrimary, lineWidth: 1.5)
                                            }
                                        }
                                        .frame(width: side, height: side)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(MonoBrandPressStyle())
                                .opacity(
                                    (rangeStart.map { day < $0 } ?? false) || (rangeEnd.map { day >= $0 } ?? false)
                                        ? 0 : (day > Date.now.startOfDay ? (rangeEnd == nil ? 0 : 0.35) : 1)
                                )
                                .disabled(
                                    day > Date.now.startOfDay || onSelect == nil
                                        || (rangeStart.map { day < $0 } ?? false)
                                        || (rangeEnd.map { day >= $0 } ?? false)
                                )
                                .accessibilityLabel("\(day.formattedMediumDate): \(count) выполнено")
                            }
                        }
                    }
                }
            }
        }
        .aspectRatio(
            (CGFloat(weeks) * cellSize + CGFloat(weeks - 1) * gap + (showWeekdayLabels ? weekdayWidth + 4 : 0))
                / (7 * cellSize + 6 * gap), contentMode: .fit)
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: Theme.Colors.fillStrong
        case 1: tint.opacity(0.28)
        case 2: tint.opacity(0.5)
        case 3: tint.opacity(0.75)
        default: tint
        }
    }
}

import SwiftUI
import SwiftData

private enum ActivityPeriod: String, CaseIterable, Identifiable {
    case week = "Неделя", month = "Месяц", year = "Год"
    var id: String { rawValue }
    var start: Date {
        switch self {
        case .week: return Date.now.startOfWeek
        case .month: return Calendar.current.dateInterval(of: .month, for: .now)!.start
        case .year: return Calendar.current.dateInterval(of: .year, for: .now)!.start
        }
    }
}

struct HeatmapView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Query private var tasks: [TaskItem]
    @Query private var history: [CompletedHistoryEntry]
    @State private var period: ActivityPeriod = .month
    @State private var expanded: Set<UUID> = []
    @State private var selectedDay: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Completion {
        let taskID: UUID
        let day: Date
        let tagID: UUID?
    }
    private var completions: [Completion] {
        var seen = Set<UUID>()
        var result = history.filter { seen.insert($0.taskId).inserted }.map {
            Completion(taskID: $0.taskId, day: $0.completedAt.startOfDay, tagID: $0.tagId)
        }
        for task in tasks where task.isDone && !seen.contains(task.id) {
            if let date = task.completedAt {
                result.append(Completion(taskID: task.id, day: date.startOfDay, tagID: task.tags.first?.id))
            }
        }
        return result.filter { $0.day <= Date.now.startOfDay }
    }
    private var filtered: [Completion] { completions.filter { $0.day >= period.start } }
    private var counts: [Date: Int] { Dictionary(grouping: filtered, by: \.day).mapValues(\.count) }
    private var days: [Date] {
        let length = Calendar.current.dateComponents([.day], from: period.start, to: Date.now.startOfDay).day ?? 0
        return (0...max(0, length)).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: period.start) }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenHeading(text: "АНАЛИТИКА")
                    Picker(
                        "Период",
                        selection: Binding(
                            get: { period },
                            set: { value in
                                withAnimation(reduceMotion ? nil : Theme.Motion.standard) { period = value }
                            })
                    ) {
                        ForEach(ActivityPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        statistic("\(filtered.count)", label: "Выполнено", accent: true)
                        statistic("\(Set(filtered.map(\.day)).count)", label: "Активных дней")
                        statistic("\(streak)", label: "Серия, дн.")
                    }
                    GroupCard(padding: 16) {
                        HStack {
                            Text("По дням недели").font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Text("Задачи").font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                        }.padding(.bottom, 16)
                        weekdayBars
                    }
                    GroupCard(padding: 16) {
                        HStack {
                            Text("Календарь активности").font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }
                        Text(
                            period.start.formatted(
                                .dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU"))) + " — "
                                + Date.now.formatted(
                                    .dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "ru_RU")))
                        )
                        .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5).padding(.bottom, 14)
                        calendarGrid
                        Text("Нажмите на день, чтобы увидеть подробности")
                            .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                    }
                    if !tags.isEmpty {
                        SectionTitle(text: "По категориям", count: tags.count).id("categories")
                        GroupCard(padding: 16) {
                            VStack(spacing: 18) {
                                ForEach(tags) { tag in categoryRow(tag) }
                                let untagged = filtered.filter { record in
                                    record.tagID == nil || !tags.contains(where: { $0.id == record.tagID })
                                }.count
                                if untagged > 0 {
                                    HStack {
                                        Text("Без категории"); Spacer(); Text("\(untagged)")
                                    }
                                    .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20).frame(maxWidth: 860).frame(maxWidth: .infinity)
            }
            .background(Theme.Colors.background)
            .foregroundStyle(Theme.Colors.textPrimary)
            .refreshable { try? await SupabaseSyncService.shared.sync(context: context) }
            .monoScrollEdge()
            .sheet(isPresented: Binding(get: { selectedDay != nil }, set: { if !$0 { selectedDay = nil } })) {
                dayDetails
                    .padding(24)
                    .preferredColorScheme(.dark)
                    #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                    #else
                .frame(minWidth: 400, minHeight: 300)
                    #endif
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--activity-categories") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        scrollProxy.scrollTo("categories", anchor: .top)
                    }
                }
                let args = ProcessInfo.processInfo.arguments
                if args.contains("--activity-year") { period = .year }
                if args.contains("--activity-week") { period = .week }
                if args.contains("--activity-day") { selectedDay = Date.now.startOfDay.daysAgo(1) }
                #endif
            }
        }
    }

    private func statistic(_ value: String, label: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value).font(Theme.Typography.figure(24)).foregroundStyle(
                accent ? Theme.Colors.accent : Theme.Colors.textPrimary
            )
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : Theme.Motion.standard, value: value)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary).lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var weekdayValues: [Int] {
        Weekday.orderedFromMonday.map { weekday in
            filtered.filter { Calendar.current.component(.weekday, from: $0.day) == weekday.rawValue }.count
        }
    }
    private var weekdayBars: some View {
        let values = weekdayValues
        let maximum = max(values.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(Weekday.orderedFromMonday.enumerated()), id: \.element.id) { index, weekday in
                VStack(spacing: 7) {
                    Text("\(values[index])").font(Theme.Typography.numeric(12)).foregroundStyle(
                        Theme.Colors.textSecondary)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(weekday == .current ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.45))
                        .frame(height: max(4, 68 * Double(values[index]) / Double(maximum)))
                    Text(weekday.shortName).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                }.frame(maxWidth: .infinity)
            }
        }.frame(height: 110, alignment: .bottom)
    }

    private var calendarGrid: some View {
        let values = counts
        let calendarDays = days
        return VStack(spacing: 7) {
            if period != .year {
                HStack(spacing: 5) {
                    ForEach(Weekday.orderedFromMonday) { day in
                        Text(day.shortName).font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary).frame(
                            maxWidth: .infinity)
                    }
                }
            }
            if period != .year {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                    let offset = (Calendar.current.component(.weekday, from: period.start) + 5) % 7
                    ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 30) }
                    ForEach(calendarDays, id: \.self) { day in dayCell(day, count: values[day] ?? 0) }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 20) {
                            ForEach(1...Calendar.current.component(.month, from: Date.now), id: \.self) { month in
                                monthGrid(month, days: calendarDays, counts: values)
                                    .id(month)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(Calendar.current.component(.month, from: Date.now), anchor: .trailing) }
                }
            }
        }
    }

    private func monthGrid(_ month: Int, days: [Date], counts: [Date: Int]) -> some View {
        let monthStart = Calendar.current.date(bySetting: .month, value: month, of: period.start)!
        let monthDays = days.filter { Calendar.current.component(.month, from: $0) == month }
        let offset = (Calendar.current.component(.weekday, from: monthStart) + 5) % 7
        return VStack(alignment: .leading, spacing: 8) {
            Text(monthStart.formatted(.dateTime.month(.wide).locale(Locale(identifier: "ru_RU")))).font(
                Theme.Typography.caption
            ).foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: 4) {
                ForEach(Weekday.orderedFromMonday) { weekday in
                    Text(weekday.shortName).font(.system(size: 9)).frame(width: 18)
                }
            }.foregroundStyle(Theme.Colors.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 18) }
                ForEach(monthDays, id: \.self) { day in
                    Button {
                        selectedDay = day
                    } label: {
                        RoundedRectangle(cornerRadius: 3).fill(activityColor(counts[day] ?? 0)).frame(height: 18)
                    }.buttonStyle(FullSurfaceButtonStyle()).accessibilityLabel(
                        "\(day.formattedMediumDate): \(counts[day] ?? 0) выполнено")
                }
            }.frame(width: 150)
        }
    }

    private func dayCell(_ day: Date, count: Int) -> some View {
        Button {
            selectedDay = day
        } label: {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(count > 1 ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(activityColor(count), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6).strokeBorder(
                        day.isToday ? Theme.Colors.textPrimary : .clear, lineWidth: 1))
        }.buttonStyle(FullSurfaceButtonStyle()).accessibilityLabel("\(day.formattedMediumDate): \(count) выполнено")
    }
    private func activityColor(_ count: Int) -> Color {
        count == 0 ? Theme.Colors.fillStrong : Theme.Colors.accent.opacity(min(1, 0.25 + Double(count) * 0.2))
    }

    private func categoryRow(_ tag: Tag) -> some View {
        let records = filtered.filter { $0.tagID == tag.id }
        let total = records.count
        return VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                    if expanded.contains(tag.id) { expanded.remove(tag.id) } else { expanded.insert(tag.id) }
                }
            } label: {
                HStack {
                    Circle().fill(tag.color).frame(width: 8, height: 8)
                    Text(tag.name).font(Theme.Typography.callout)
                    Spacer()
                    Text("\(total)").font(Theme.Typography.numeric(14, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 11)).rotationEffect(
                        .degrees(expanded.contains(tag.id) ? 180 : 0))
                }.frame(minHeight: 32).contentShape(Rectangle())
            }.buttonStyle(FullSurfaceButtonStyle())
            ProgressLine(
                progress: filtered.isEmpty ? 0 : Double(total) / Double(filtered.count), tint: tag.color, height: 5)
            if expanded.contains(tag.id) {
                Text("\(Set(records.map(\.day)).count) активных дней за выбранный период")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                ActivityGrid(counts: Dictionary(grouping: records, by: \.day).mapValues(\.count), tint: tag.color)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }

    private var dayDetails: some View {
        let day = selectedDay ?? Date.now.startOfDay
        let records = completions.filter { $0.day == day }
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(day.formattedWeekdayAndDate).font(Theme.Typography.title)
                Text("Выполнено: \(records.count)").font(Theme.Typography.heading(24)).foregroundStyle(
                    Theme.Colors.accent)
                if records.isEmpty {
                    Text("В этот день выполненных задач нет.").foregroundStyle(Theme.Colors.textSecondary)
                }
                ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tasks.first { $0.id == record.taskID }?.title ?? "Выполненная задача")
                            Text(tags.first { $0.id == record.tagID }?.name ?? "Без категории")
                                .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var streak: Int {
        let overall = Dictionary(grouping: completions, by: \.day).mapValues(\.count)
        var day = Date.now.startOfDay
        if overall[day, default: 0] == 0 { day = day.daysAgo(1) }
        var count = 0
        while overall[day, default: 0] > 0 { count += 1; day = day.daysAgo(1) }
        return count
    }
}

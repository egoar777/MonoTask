import SwiftUI
import SwiftData

private enum ActivityPeriod: String, CaseIterable, Identifiable {
    case week = "Неделя", month = "Месяц", year = "Год"
    var id: String { rawValue }
    var end: Date {
        switch self {
        case .week: return start.daysAgo(-7)
        case .month: return Calendar.current.date(byAdding: .month, value: 1, to: start)!
        case .year: return Calendar.current.date(byAdding: .year, value: 1, to: start)!
        }
    }
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
    @State private var period: ActivityPeriod = .week
    @State private var expandedFolderID: UUID?
    @State private var selection: DetailSelection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var totalSize: CGFloat = 32
    @ScaledMetric(relativeTo: .title2) private var totalCircleSize: CGFloat = 78
    @ScaledMetric(relativeTo: .caption2) private var yearCellSize: CGFloat = 24
    @ScaledMetric(relativeTo: .caption2) private var yearLabelWidth: CGFloat = 36
    @ScaledMetric(relativeTo: .caption2) private var chartLabelSpace: CGFloat = 20

    private struct DetailSelection: Identifiable, Hashable {
        let interval: DateInterval
        var folderID: UUID? = nil
        var id: Self { self }
    }

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
    private var periodTitle: String {
        switch period {
        case .week: "Выполнено за неделю"
        case .month: "Выполнено за месяц"
        case .year: "Выполнено за год"
        }
    }

    var body: some View {
        let records = filtered
        let folderIDs = Set(tags.map(\.id))
        let groups = Dictionary(grouping: records) { record in
            record.tagID.flatMap { folderIDs.contains($0) ? $0 : nil }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenTitle(text: "Аналитика")
                periodPicker
                summary(records: records)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("analytics-all-tasks")
                chartPanel(records: records, folderIDs: folderIDs)

                VStack(alignment: .leading, spacing: 9) {
                    MonoBrandSectionTitle(text: "По папкам")
                    if tags.isEmpty && groups[nil] == nil {
                        Label("Здесь появится статистика ваших папок.", systemImage: "folder")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(15)
                            .modifier(MonoBrandSurface())
                    } else {
                        folderList(groups: groups, total: records.count)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenPadding)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .animation(reduceMotion ? MonoBrandMotion.fade : MonoBrandMotion.page, value: period)
            .frame(maxWidth: 860).frame(maxWidth: .infinity)
        }
        .background(Theme.Colors.background)
        .foregroundStyle(Theme.Colors.textPrimary)
        .refreshable { try? await SupabaseSyncService.shared.sync(context: context) }
        .monoScrollEdge()
        .sheet(item: $selection) { detail in
            NavigationStack {
                ScrollView { detailContent(detail).padding(24) }
                    .background(Theme.Colors.background)
                    #if os(macOS)
                .macNavigationHeader {
                    Button("Закрыть", systemImage: "xmark") { selection = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("analytics-detail-close")
                }
                    #else
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { selection = nil }
                    }
                }
                    #endif
            }
            .tint(Theme.Colors.accent)
            .preferredColorScheme(.dark)
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #else
            .frame(minWidth: 500, minHeight: 500)
            #endif
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--activity-year") { period = .year }
            if args.contains("--activity-week") { period = .week }
            if args.contains("--activity-day") { selectDay(Date.now.startOfDay.daysAgo(1)) }
            #endif
        }
    }

    private var periodPicker: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 5))
            : AnyLayout(HStackLayout(spacing: 5))
        return layout {
            ForEach(ActivityPeriod.allCases) { option in
                let selected = period == option
                Button {
                    period = option
                } label: {
                    Text(option.rawValue)
                        .modifier(MonoBrandPill(selected: selected))
                }
                .buttonStyle(MonoBrandPressStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityRepresentation {
            Picker("Период", selection: $period) {
                ForEach(ActivityPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func summary(records: [Completion]) -> some View {
        let completed = records.count
        let activeDays = Set(records.map(\.day)).count
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        return layout {
            Text("\(completed)")
                .font(.system(size: totalSize, weight: .black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(9)
                .frame(width: totalCircleSize, height: totalCircleSize)
                .foregroundStyle(Theme.Colors.accent)
                .background(Theme.Colors.accent.opacity(0.07), in: Circle())
                .overlay { Circle().strokeBorder(Theme.Colors.accent, lineWidth: 2) }
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(completed)))
                .accessibilityLabel("Выполнено задач: \(completed)")

            VStack(alignment: .leading, spacing: 8) {
                Text(periodTitle)
                    .font(.headline)
                    .contentTransition(.opacity)
                HStack(spacing: 6) {
                    Label("Активных дней", systemImage: "calendar")
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(activeDays)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(activeDays)))
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(MonoBrandSurface(border: Theme.Colors.accent.opacity(0.58), radius: 27))
    }

    private func chartPanel(records: [Completion], folderIDs: Set<UUID>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                MonoBrandSectionTitle(text: "Активность")
                Text(periodRangeTitle)
                    .contentTransition(.opacity)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            completionChart(records: records, folderIDs: folderIDs)
                .id(period)
                .transition(MonoBrandMotion.reveal(reduceMotion: reduceMotion, distance: 8))
            if records.isEmpty {
                Label("Выполните задачу, чтобы она появилась на графике.", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .modifier(MonoBrandSurface())
    }

    private struct ChartBucket: Identifiable {
        let id: Int
        let start: Date
        let end: Date
        let label: String
    }
    private var buckets: [ChartBucket] {
        let calendar = Calendar.current
        switch period {
        case .week:
            return (0..<7).map { index in
                let start = period.start.daysAgo(-index)
                return ChartBucket(
                    id: index, start: start, end: start.daysAgo(-1), label: Weekday.orderedFromMonday[index].shortName)
            }
        case .month:
            let days = calendar.range(of: .day, in: .month, for: .now)?.count ?? 30
            return stride(from: 0, to: days, by: 7).map { index in
                ChartBucket(
                    id: index, start: period.start.daysAgo(-index),
                    end: period.start.daysAgo(-min(index + 7, days)), label: "\(index + 1)–\(min(index + 7, days))")
            }
        case .year:
            return (0..<12).map { index in
                let start = calendar.date(byAdding: .month, value: index, to: period.start)!
                let end = calendar.date(byAdding: .month, value: 1, to: start)!
                let label = start.formatted(.dateTime.month(.narrow).locale(Locale(identifier: "ru_RU")))
                return ChartBucket(id: index, start: start, end: end, label: label)
            }
        }
    }
    private func completionChart(records: [Completion], folderIDs: Set<UUID>) -> some View {
        let columns = buckets.map { bucket in
            let items = records.filter { $0.day >= bucket.start && $0.day < bucket.end }
            let counts = Dictionary(grouping: items) { item in
                item.tagID.flatMap { folderIDs.contains($0) ? $0 : nil }
            }.mapValues(\.count)
            return (bucket: bucket, counts: counts, total: items.count)
        }
        let colors =
            tags.map { (id: Optional($0.id), tint: $0.color) }
            + [(id: nil, tint: Theme.Colors.accent)]
        let maximum = max(4, columns.map(\.total).max() ?? 0)
        let ceiling = Int(ceil(Double(maximum) / 4)) * 4
        let plotHeight: CGFloat = 100
        let columnSpacing: CGFloat = period == .year ? 3 : 7

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(ceiling)")
                Spacer(minLength: 0)
                Text("\(ceiling / 2)")
                Spacer(minLength: 0)
                Text("0")
            }
            .font(.caption2).monospacedDigit()
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(height: plotHeight + chartLabelSpace)
            .padding(.top, chartLabelSpace / 2)
            .accessibilityHidden(true)

            HStack(alignment: .top, spacing: columnSpacing) {
                ForEach(columns, id: \.bucket.id) { column in
                    let bucket = column.bucket
                    Button {
                        selection = DetailSelection(interval: DateInterval(start: bucket.start, end: bucket.end))
                    } label: {
                        VStack(spacing: 6) {
                            VStack(spacing: 3) {
                                if period != .year && column.total > 0 {
                                    Text("\(column.total)").font(.caption2.weight(.semibold)).monospacedDigit()
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                }
                                VStack(spacing: 0) {
                                    ForEach(colors, id: \.id) { series in
                                        Rectangle().fill(series.tint)
                                            .frame(
                                                height: CGFloat(column.counts[series.id, default: 0]) / CGFloat(ceiling)
                                                    * plotHeight)
                                    }
                                }
                                .frame(maxWidth: 34)
                                .clipShape(.rect(cornerRadius: 6))
                                .background(alignment: .bottom) {
                                    if column.total == 0 {
                                        Capsule()
                                            .fill(bucket.start > .now ? .clear : Theme.Colors.fillStrong)
                                            .frame(height: 4)
                                    }
                                }
                            }
                            .frame(height: plotHeight + chartLabelSpace, alignment: .bottom)

                            Text(bucket.label)
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MonoBrandPressStyle())
                    .opacity(bucket.start > .now ? 0.48 : 1)
                    .disabled(bucket.start > .now)
                    .accessibilityLabel(
                        "\(rangeTitle(from: bucket.start, to: bucket.end.daysAgo(1))): \(column.total) выполнено"
                    )
                    .accessibilityIdentifier("analytics-bucket-\(bucket.id)")
                }
            }
            .background(alignment: .top) {
                VStack(spacing: 0) {
                    Hairline()
                    Spacer(minLength: 0)
                    Hairline()
                    Spacer(minLength: 0)
                    Hairline()
                }
                .frame(height: plotHeight)
                .padding(.top, chartLabelSpace)
            }
        }
    }

    private func folderList(groups: [UUID?: [Completion]], total: Int) -> some View {
        VStack(spacing: 7) {
            ForEach(tags) { tag in
                let expanded = expandedFolderID == tag.id
                let records = groups[tag.id, default: []]
                VStack(spacing: 0) {
                    Button {
                        // Animate disclosure without moving the scroll view’s current anchor.
                        var transaction = Transaction(animation: reduceMotion ? nil : MonoBrandMotion.disclosure)
                        transaction.scrollContentOffsetAdjustmentBehavior = .disabled
                        withTransaction(transaction) {
                            expandedFolderID = expanded ? nil : tag.id
                        }
                    } label: {
                        folderSummary(
                            tag.name, tint: tag.color, icon: tag.iconName,
                            count: records.count, total: total, expanded: expanded
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MonoBrandPressStyle())
                    .accessibilityIdentifier("analytics-folder-\(tag.name)")
                    .accessibilityLabel("\(tag.name), \(records.count) выполнено")
                    .accessibilityValue(expanded ? "Развёрнуто" : "Свёрнуто")
                    .accessibilityHint("Показать или скрыть хитмап за выбранный период")
                    if expanded {
                        folderHeatmap(tag, records: records)
                            .id(period)
                            .padding([.horizontal, .bottom], 8)
                            .transition(MonoBrandMotion.reveal(reduceMotion: reduceMotion, distance: 8))
                    }
                }
                .clipped()
                .modifier(MonoBrandSurface(radius: 20))
            }
            if let uncategorized = groups[nil] {
                folderSummary(
                    "Без папки", tint: Theme.Colors.accent, icon: "checkmark", count: uncategorized.count, total: total
                )
                .modifier(MonoBrandSurface(radius: 20))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Без папки, \(uncategorized.count) выполнено")
            }
        }
    }

    private func folderSummary(
        _ name: String, tint: Color, icon: String, count: Int, total: Int, expanded: Bool? = nil
    ) -> some View {
        HStack(spacing: 10) {
            ClassicFolderArtwork(tint: tint, icon: icon)
                .frame(width: 35, height: 29)
            VStack(alignment: .leading, spacing: 7) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Colors.surfaceInteractive)
                        Capsule().fill(tint)
                            .frame(width: geometry.size.width * CGFloat(count) / CGFloat(max(1, total)))
                    }
                }
                .frame(height: 3)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(count)")
                .font(.subheadline.weight(.bold)).monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(count)))
            if let expanded {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 54, alignment: .leading)
    }

    private func folderHeatmap(_ folder: Tag, records: [Completion]) -> some View {
        let values = Dictionary(grouping: records, by: \.day).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 12) {
            Text(periodRangeTitle).font(.subheadline).foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("analytics-folder-heatmap-\(period.id)")
            if period == .year {
                let weeks =
                    (Calendar.current.dateComponents(
                        [.day], from: period.start.startOfWeek, to: period.end.daysAgo(1).startOfWeek
                    ).day ?? 364) / 7 + 1
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 6) {
                        HStack {
                            ForEach(1...12, id: \.self) { month in
                                Text(
                                    Calendar.current.date(byAdding: .month, value: month - 1, to: period.start)!
                                        .formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "ru_RU")))
                                )
                                .font(.caption2).frame(maxWidth: .infinity)
                            }
                        }.foregroundStyle(Theme.Colors.textSecondary).padding(.leading, yearLabelWidth)
                        ActivityGrid(
                            counts: values, tint: folder.color, cellSize: yearCellSize, weeks: weeks,
                            rangeStart: period.start, rangeEnd: period.end,
                            onSelect: { selectDay($0, folderID: folder.id) }
                        )
                    }.frame(width: CGFloat(weeks) * (yearCellSize + 4) + yearLabelWidth - 4)
                }
            } else if period == .week {
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        let day = period.start.daysAgo(-index)
                        VStack(spacing: 6) {
                            Text(Weekday.orderedFromMonday[index].shortName).font(.caption2)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            heatmapDay(day, count: values[day, default: 0], folder: folder)
                        }.frame(maxWidth: .infinity)
                    }
                }
            } else {
                let days = Calendar.current.range(of: .day, in: .month, for: period.start)?.count ?? 30
                let offset = (Calendar.current.component(.weekday, from: period.start) + 5) % 7
                let weeks = (offset + days + 6) / 7
                // Lay out every week when the chart opens so its height is known immediately.
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(Weekday.orderedFromMonday, id: \.self) { weekday in
                            Text(weekday.shortName)
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(0..<weeks, id: \.self) { week in
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { weekday in
                                let index = week * 7 + weekday - offset
                                if (0..<days).contains(index) {
                                    let day = period.start.daysAgo(-index)
                                    heatmapDay(day, count: values[day, default: 0], folder: folder)
                                } else {
                                    Color.clear.frame(maxWidth: .infinity).frame(height: 36)
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Меньше")
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(level == 0 ? Theme.Colors.fillStrong : folder.color.opacity(Double(level) / 4))
                        .frame(width: 9, height: 9)
                }
                Text("Больше")
                Spacer()
                Text("\(records.count) выполнено")
            }.font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(12)
        .modifier(MonoBrandSurface(fill: MonoBrand.inset, radius: 15))
    }

    private var periodRangeTitle: String {
        let locale = Locale(identifier: "ru_RU")
        switch period {
        case .week:
            return rangeTitle(from: period.start, to: period.end.daysAgo(1))
        case .month:
            let value = period.start.formatted(.dateTime.month(.wide).year().locale(locale))
            return value.prefix(1).uppercased() + value.dropFirst()
        case .year:
            return period.start.formatted(.dateTime.year().locale(locale))
        }
    }

    private func rangeTitle(from start: Date, to end: Date) -> String {
        let calendar = Calendar.current
        let dayAndMonth = Date.FormatStyle.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU"))
        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(dayAndMonth)
        }
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(calendar.component(.day, from: start))–\(end.formatted(dayAndMonth))"
        }
        return "\(start.formatted(dayAndMonth)) – \(end.formatted(dayAndMonth))"
    }

    private func selectDay(_ day: Date, folderID: UUID? = nil) {
        selection = DetailSelection(interval: DateInterval(start: day, end: day.daysAgo(-1)), folderID: folderID)
    }

    private func heatmapDay(_ day: Date, count: Int, folder: Tag) -> some View {
        Button {
            selectDay(day, folderID: folder.id)
        } label: {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(count > 1 ? Theme.Colors.background : Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity).frame(minHeight: 36)
                .background(
                    count == 0
                        ? Theme.Colors.fillStrong : folder.color.opacity(min(1, 0.28 + Double(count - 1) * 0.22)),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5).strokeBorder(day.isToday ? folder.color : .clear, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(MonoBrandPressStyle())
        .disabled(day > Date.now.startOfDay)
        .opacity(day > Date.now.startOfDay ? 0.35 : 1)
        .accessibilityLabel("\(day.formattedMediumDate): \(count) выполнено")
        .accessibilityIdentifier("analytics-day-\(Calendar.current.component(.day, from: day))")
    }

    private func detailContent(_ selection: DetailSelection) -> some View {
        let start = selection.interval.start
        let end = selection.interval.end
        let singleDay = Calendar.current.isDate(start, inSameDayAs: end.daysAgo(1))
        let records = completions.filter {
            $0.day >= start && $0.day < end && (selection.folderID == nil || $0.tagID == selection.folderID)
        }
        let taskTitles = Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let folderNames = Dictionary(tags.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        return VStack(alignment: .leading, spacing: 18) {
            MonoBrandTitle(
                text: singleDay
                    ? start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU")))
                    : rangeTitle(from: start, to: end.daysAgo(1))
            )
            Text("Выполнено: \(records.count)")
                .font(Theme.Typography.heading(24))
                .foregroundStyle(Theme.Colors.accent)
            if records.isEmpty {
                Text(singleDay ? "В этот день выполненных задач нет." : "За этот период выполненных задач нет.")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(taskTitles[record.taskID] ?? "Выполненная задача")
                            let folder = record.tagID.flatMap { folderNames[$0] } ?? "Без папки"
                            Text(singleDay ? folder : "\(folder) · \(record.day.formattedMediumDate)")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

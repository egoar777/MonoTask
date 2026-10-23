import SwiftUI
import SwiftData

struct HeatmapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Query private var tasks: [TaskItem]
    @Query private var completedHistory: [CompletedHistoryEntry]

    private struct Completion {
        let day: Date
        let tagId: UUID?
    }

    /// Persistent history plus completed tasks that predate the history table.
    private var completions: [Completion] {
        var seenTaskIds = Set<UUID>()
        var result: [Completion] = []
        for entry in completedHistory where seenTaskIds.insert(entry.taskId).inserted {
            result.append(Completion(day: entry.completedAt.startOfDay, tagId: entry.tagId))
        }
        for task in tasks where task.isDone && !seenTaskIds.contains(task.id) {
            if let completedAt = task.completedAt {
                result.append(Completion(day: completedAt.startOfDay, tagId: task.tags.first?.id))
            }
        }
        return result
    }

    var body: some View {
        let all = completions
        let overall = Dictionary(grouping: all, by: \.day).mapValues(\.count)
        let byTag = Dictionary(grouping: all, by: \.tagId)

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                statsCard(overall)
                overallCard(overall, total: all.count)

                if !tags.isEmpty {
                    SectionTitle(text: "По категориям", count: tags.count)
                        .padding(.top, 14)

                    ForEach(tags) { tag in
                        ContextHeatmapCard(
                            tag: tag,
                            counts: Dictionary(grouping: byTag[tag.id] ?? [], by: \.day).mapValues(\.count)
                        )
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            try? await SupabaseSyncService.shared.sync(context: modelContext)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .monoScrollEdge()
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                EyebrowLabel(text: "выполненные задачи")
                Spacer()
                SyncIndicator()
            }
            Text("Аналитика".uppercased())
                .font(Theme.Typography.display)
                .tracking(Theme.Typography.displayTracking)
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .padding(.bottom, 6)
    }

    private func statsCard(_ overall: [Date: Int]) -> some View {
        let today = Date.now.startOfDay
        let weekStart = today.startOfWeek
        let todayCount = overall[today] ?? 0
        let weekCount = overall.filter { $0.key >= weekStart }.values.reduce(0, +)

        return GroupCard(padding: 16) {
            HStack(alignment: .top, spacing: 0) {
                StatBlock(value: "\(todayCount)", label: "сегодня")
                divider
                StatBlock(value: "\(weekCount)", label: "неделя")
                divider
                StatBlock(value: "\(streak(overall))", label: "серия, дн.", tint: Theme.Colors.accent)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Colors.hairline)
            .frame(width: 1, height: 44)
            .padding(.horizontal, 14)
    }

    private func overallCard(_ overall: [Date: Int], total: Int) -> some View {
        GroupCard(padding: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Все задачи".uppercased())
                    .font(Theme.Typography.heading(14))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                EyebrowLabel(text: "\(total) выполнено", color: Theme.Colors.textSecondary)
            }
            .padding(.bottom, 14)

            ActivityGrid(counts: overall, cellSize: 13, gap: 3)

            HStack {
                Spacer()
                ActivityLegend()
            }
            .padding(.top, 12)
        }
    }

    /// Consecutive days with at least one completion, ending today (or yesterday if today is still empty).
    private func streak(_ overall: [Date: Int]) -> Int {
        let calendar = Calendar.current
        var day = Date.now.startOfDay
        if (overall[day] ?? 0) == 0 {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while (overall[day] ?? 0) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

#Preview {
    HeatmapView()
}

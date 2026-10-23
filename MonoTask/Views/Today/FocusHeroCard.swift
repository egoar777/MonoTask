import SwiftUI
struct FocusHeroCard: View {
    @State private var summaryHeight: CGFloat = 80
    var compact: Bool = false
    let tags: [Tag]
    let scheduledTags: [Tag]
    @Binding var scope: TaskScope
    let today: Date
    let doneCount: Int
    let totalCount: Int
    let openCount: (TaskScope) -> Int

    private var progress: Double {
        totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount)
    }

    private var title: String {
        scope == .focus ? "Сегодня" : scope.title(tags: tags)
    }

    private var subtitle: String? {
        guard scope == .focus else { return nil }
        if scheduledTags.isEmpty { return nil }
        return scheduledTags.map(\.name).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            HStack(spacing: 8) {
                EyebrowLabel(text: today.formattedEyebrowDate)
                Spacer()
                SyncIndicator()
            }
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)

            Text(title.uppercased())
                .font(Theme.Typography.display)
                .tracking(Theme.Typography.displayTracking)
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .scaleEffect(compact ? 22.0 / 34.0 : 1, anchor: .leading)
                .frame(height: compact ? 29 : 43, alignment: .leading)
                .padding(.top, compact ? 10 : 18)

            VStack(alignment: .leading, spacing: 0) {

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(doneCount)")
                        .font(Theme.Typography.figure(46))
                        .foregroundColor(Theme.Colors.accent)
                        .contentTransition(.numericText())
                    Text("/ \(totalCount) ГОТОВО")
                        .font(Theme.Typography.numeric(13))
                        .foregroundColor(Theme.Colors.textMuted)

                    if let subtitle {
                        Spacer(minLength: 8)
                        Text(subtitle.uppercased())
                            .font(Theme.Typography.eyebrow)
                            .tracking(Theme.Typography.eyebrowTracking)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.top, 4)

                ProgressLine(progress: progress)
                    .padding(.top, 14)
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                summaryHeight = $0
            }
            .opacity(compact ? 0 : 1)
            .frame(height: compact ? 0 : summaryHeight, alignment: .top)
            .clipped()
            .accessibilityHidden(compact)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        pill(.focus, title: "Фокус", color: nil)
                        pill(.all, title: "Все", color: nil)
                        ForEach(tags) { tag in
                            pill(.tag(tag.id), title: tag.name, color: tag.color)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screenPadding)
                    .padding(.vertical, 16)
                }
                .padding(.horizontal, -Theme.Spacing.screenPadding)
                .onChange(of: scope) { _, newScope in
                    withAnimation(KeyboardObserver.shared.isKeyboardVisible ? nil : .easeInOut(duration: 0.25)) {
                        proxy.scrollTo(pillId(newScope), anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.screenPadding)
        .background(Theme.Colors.background)
    }

    private func pill(_ pillScope: TaskScope, title: String, color: Color?) -> some View {
        ScopeTab(
            title: title,
            color: color,
            count: openCount(pillScope),
            isSelected: scope == pillScope
        ) {
            guard scope != pillScope else { return }
            Haptics.selection()
            scope = pillScope
        }
        .id(pillId(pillScope))
    }

    private func pillId(_ scope: TaskScope) -> String {
        switch scope {
        case .focus: return "focus"
        case .all: return "all"
        case .highPriority: return "priority"
        case .tag(let id): return id.uuidString
        }
    }
}
struct SyncIndicator: View {
    var body: some View {
        let service = SupabaseService.shared
        HStack(spacing: 6) {
            if service.syncStatus.isSyncing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(dotColor(service))
                    .frame(width: 6, height: 6)
            }
            Text(label(service))
                .font(Theme.Typography.eyebrow)
                .tracking(Theme.Typography.eyebrowTracking)
                .foregroundColor(Theme.Colors.textMuted)
        }
    }

    private func dotColor(_ service: SupabaseService) -> Color {
        if case .error = service.syncStatus { return Theme.Colors.danger }
        switch service.connectionStatus {
        case .offline: return Theme.Colors.warning
        case .error: return Theme.Colors.danger
        case .notConfigured: return Theme.Colors.textMuted
        default: return Theme.Colors.accent
        }
    }

    private func label(_ service: SupabaseService) -> String {
        if service.syncStatus.isSyncing { return "SYNC" }
        if case .error = service.syncStatus { return "ОШИБКА" }
        switch service.connectionStatus {
        case .offline: return "ОФЛАЙН"
        case .error: return "ОШИБКА"
        case .notConfigured: return "ЛОКАЛЬНО"
        default: return "ОНЛАЙН"
        }
    }
}

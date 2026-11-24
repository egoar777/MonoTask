import SwiftUI

/// A one-time introduction with local illustrations that never write to the task store.
struct OnboardingView: View {
    var isReady = true
    let onSkip: () -> Void
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @AccessibilityFocusState private var focusedHeading: Page?
    @GestureState(resetTransaction: Transaction(animation: MonoBrandMotion.page))
    private var swipeOffset: CGFloat = 0
    @State private var page = Page.tasks

    fileprivate enum Page: Int, CaseIterable {
        case tasks, folders, progress

        var title: String {
            switch self {
            case .tasks: "Задачи и приоритеты"
            case .folders: "Личные и общие папки"
            case .progress: "История выполненных задач"
            }
        }

        var detail: String {
            switch self {
            case .tasks:
                "Добавляйте задачи, задавайте приоритеты и напоминания. Отмечайте выполненное и следите за прогрессом."
            case .folders:
                "Собирайте задачи в личных папках. В общие папки приглашайте участников по QR-коду или ссылке."
            case .progress:
                "Смотрите, сколько задач вы выполнили за неделю, месяц или год, и сравнивайте активность по папкам."
            }
        }
    }

    private var direction: CGFloat { layoutDirection == .leftToRight ? 1 : -1 }

    var body: some View {
        VStack(spacing: 0) {
            header
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .padding(.horizontal, Theme.Spacing.screenPadding)
            pager
            footer
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .padding(.horizontal, Theme.Spacing.screenPadding)
        }
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Theme.Colors.textPrimary)
        .background(Theme.Colors.background.ignoresSafeArea())
        .onChange(of: page) { _, value in focusedHeading = value }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("LaunchLogo").resizable().scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text("MonoTask")
                .font(.custom("Unbounded-Black", size: 15, relativeTo: .headline))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Spacer(minLength: 8)
            Button(action: onSkip) {
                Text("Пропустить")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.leading, 8)
                    .frame(minHeight: Theme.Spacing.touchTargetMin)
            }
            .buttonStyle(MonoBrandPressStyle())
            .accessibilityIdentifier("onboarding-skip")
        }
        .padding(.top, 8)
    }

    private var pager: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Page.allCases, id: \.self) { step in
                    let isCurrent = step == page
                    ScrollView {
                        stepContent(step, isCurrent: isCurrent)
                            .frame(minHeight: geometry.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .offset(x: reduceMotion ? 0 : pageOffset(step, width: geometry.size.width))
                    .opacity(reduceMotion && !isCurrent ? 0 : 1)
                    .allowsHitTesting(isCurrent)
                    .accessibilityHidden(!isCurrent)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(pageSwipe)
        }
    }

    private func stepContent(_ step: Page, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                MonoBrandTitle(text: step.title)
                    .accessibilityIdentifier(isCurrent ? "onboarding-title" : "")
                    .accessibilityHidden(!isCurrent)
                    .accessibilityFocused($focusedHeading, equals: step)
                Text(step.detail)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(!isCurrent)
            }
            OnboardingIllustration(step: step, isActive: isCurrent && isReady)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screenPadding)
        .padding(.vertical, 20)
    }

    private var footer: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .leading) {
                HStack(spacing: 4) {
                    ForEach(Page.allCases, id: \.self) { _ in
                        Capsule().fill(Theme.Colors.fillStrong).frame(width: 20, height: 4)
                    }
                }
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: 20, height: 4)
                    .offset(x: CGFloat(page.rawValue) * 24 * direction)
                    .animation(reduceMotion ? nil : MonoBrandMotion.control, value: page)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Экран \(page.rawValue + 1) из \(Page.allCases.count)")

            HStack(spacing: 8) {
                if page != .tasks {
                    Button {
                        move(by: -1)
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                            .frame(width: 52, height: 52)
                            .background(MonoBrand.inset, in: Circle())
                            .overlay { Circle().strokeBorder(Theme.Colors.hairline) }
                    }
                    .buttonStyle(MonoBrandPressStyle())
                    .accessibilityLabel("Назад")
                    .transition(.opacity)
                }
                Button {
                    if page == .progress {
                        onFinish()
                    } else {
                        move(by: 1)
                    }
                } label: {
                    AuthActionLabel(title: page == .progress ? "Начать" : "Продолжить", prominent: true)
                        .contentTransition(.opacity)
                }
                .buttonStyle(MonoBrandPressStyle())
                .accessibilityIdentifier("onboarding-next")
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var pageSwipe: some Gesture {
        DragGesture(minimumDistance: 18)
            .updating($swipeOffset) { value, offset, transaction in
                guard !reduceMotion, isHorizontal(value.translation) else { return }
                let width = value.translation.width
                let towardNext = width * direction < 0
                let isAtEdge = towardNext ? page == .progress : page == .tasks
                offset = isAtEdge ? width * 0.18 : width
                transaction.animation = nil
            }
            .onEnded { value in
                guard isHorizontal(value.translation), abs(value.translation.width) > 44 else { return }
                move(by: value.translation.width * direction < 0 ? 1 : -1)
            }
    }

    private func pageOffset(_ step: Page, width: CGFloat) -> CGFloat {
        let distance = CGFloat(step.rawValue - page.rawValue) * direction * width
        return distance + min(max(swipeOffset, -width), width)
    }

    private func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * 1.4
    }

    private func move(by delta: Int) {
        guard let destination = Page(rawValue: page.rawValue + delta) else { return }
        withAnimation(reduceMotion ? MonoBrandMotion.fade : MonoBrandMotion.page) {
            page = destination
        }
    }
}

private struct OnboardingIllustration: View {
    let step: OnboardingView.Page
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRevealed = false

    private var revealed: Bool { reduceMotion || hasRevealed }
    private var playsReveal: Bool { isActive && !reduceMotion }

    var body: some View {
        Group {
            switch step {
            case .tasks: tasks
            case .folders: folders
            case .progress: analytics
            }
        }
        .frame(maxWidth: .infinity, minHeight: 248)
        .padding(16)
        .modifier(MonoBrandSurface())
        .task(id: playsReveal) {
            guard playsReveal else { return }
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { hasRevealed = false }
            // Let the page arrive before playing its demonstration.
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            hasRevealed = true
        }
    }

    private var tasks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("ВСЕ ЗАДАЧИ")
                    .font(.custom("Unbounded-Black", size: 16, relativeTo: .headline))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(revealed ? "1" : "0")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.Colors.accent)
                    .contentTransition(.numericText())
                Text("/ 4")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ProgressLine(progress: revealed ? 0.25 : 0, height: 6)
            HStack(spacing: 6) {
                taskShortcut("Папки", icon: "chevron.down")
                taskShortcut("Общие", icon: "person.2")
            }
            VStack(alignment: .leading, spacing: 0) {
                taskRow("Подготовить презентацию", priority: .high, reminder: "Сегодня, 18:00")
                TaskRowSeparator(leadingInset: 30, trailingInset: 0)
                taskRow("Выбрать время встречи", priority: .medium)
                TaskRowSeparator(leadingInset: 30, trailingInset: 0)
                taskRow("Обновить план проекта", note: "Добавить сроки для команды")
                HStack(spacing: 8) {
                    SectionTitle(text: "Выполнено", count: 1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textMuted)
                    Spacer(minLength: 4)
                    Text("Очистить")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay { Capsule().strokeBorder(Theme.Colors.ruleStrong) }
                }
                .padding(.top, 8)
                taskRow("Отправить черновик", done: revealed)
            }
            taskCapturePreview
        }
        .animation(revealAnimation(delay: 0.14), value: revealed)
    }

    private var taskCapturePreview: some View {
        HStack(spacing: 6) {
            Text("Новая задача").lineLimit(1)
            Spacer(minLength: 4)
            captureSymbol("star", color: Theme.Colors.accent)
            captureSymbol("xmark")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background(Theme.Colors.surfaceElevated, in: Capsule())
    }

    private func captureSymbol(_ name: String, color: Color = Theme.Colors.textSecondary) -> some View {
        Image(systemName: name)
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(Theme.Colors.fillStrong, in: Circle())
    }

    private func taskShortcut(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(Theme.Colors.surfaceElevated, in: Capsule())
    }

    private func taskRow(
        _ title: String, priority: Priority = .none, reminder: String? = nil, note: String? = nil, done: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            TaskCheckbox(
                isDone: done, size: 20,
                priorityColor: priority == .none ? nil : priority.color,
                checkmarkProgress: done ? 1 : 0
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.body)
                    .strikethrough(done, color: Theme.Colors.textMuted)
                    .foregroundStyle(done ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reminder {
                    Label(reminder, systemImage: "alarm")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(.vertical, 5)
        .frame(minHeight: 35)
    }

    private var folders: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("ПАПКИ")
                    .font(.custom("Unbounded-Black", size: 16, relativeTo: .headline))
                Spacer(minLength: 4)
                Text("Добавить папку")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.surfaceElevated, in: Capsule())
            }
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    folderTile(
                        "Все задачи", count: "7 открыто", icon: "tray.fill",
                        tint: Theme.Colors.accent, tilt: -9, delay: 0)
                    folderTile(
                        "Учёба", count: "2 открыто", icon: ActivityFolder.study.icon,
                        tint: ActivityFolder.study.tint, tilt: 9, delay: 0.07)
                }
                HStack(alignment: .top, spacing: 8) {
                    folderTile(
                        "Проекты", count: "2 открыто", icon: ActivityFolder.projects.icon,
                        tint: ActivityFolder.projects.tint, tilt: -9, delay: 0.12)
                    folderTile(
                        "Общие планы", count: "Общая · 3 открыто", icon: "person.2.fill",
                        tint: MonoBrand.mint, tilt: 9, delay: 0.17)
                }
            }
            folderInvite
        }
    }

    private var folderInvite: some View {
        HStack(spacing: 10) {
            Image(systemName: "qrcode")
                .font(.system(size: 29))
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: 44, height: 44)
                .background(Theme.Colors.textPrimary, in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text("Приглашение в папку")
                    .font(.footnote.weight(.semibold))
                Label("Скопировать ссылку", systemImage: "link")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.Colors.accent)
            }
            Spacer(minLength: 0)
            Image(systemName: "person.2.fill")
                .foregroundStyle(Theme.Colors.textSecondary)
                .font(.caption)
        }
        .padding(10)
        .modifier(MonoBrandSurface(fill: MonoBrand.inset, radius: 14))
        .offset(y: revealed ? 0 : 8)
        .opacity(revealed ? 1 : 0.35)
        .animation(revealAnimation(delay: 0.24), value: revealed)
    }

    private func folderTile(
        _ title: String, count: String, icon: String, tint: Color, tilt: Double, delay: Double
    ) -> some View {
        VStack(spacing: 3) {
            ClassicFolderArtwork(tint: tint, icon: icon)
                .frame(width: 92, height: 65)
                .rotationEffect(.degrees(revealed ? 0 : tilt))
                .scaleEffect(revealed ? 1 : 0.82)
                .offset(y: revealed ? 0 : 9)
                .opacity(revealed ? 1 : 0.35)
                .animation(revealAnimation(delay: delay), value: revealed)
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(count)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private enum ActivityFolder: String, CaseIterable {
        case study = "Учёба"
        case projects = "Проекты"
        case personal = "Личное"

        var tint: Color {
            switch self {
            case .study: MonoBrand.blue
            case .projects: MonoBrand.violet
            case .personal: MonoBrand.mint
            }
        }

        var icon: String {
            switch self {
            case .study: "graduationcap.fill"
            case .projects: "square.stack.3d.up.fill"
            case .personal: "heart.fill"
            }
        }
    }

    private static let activity: [[ActivityFolder]] = [
        [.study, .projects, .personal],
        [.study],
        [.study, .projects, .personal, .personal],
        [.study, .projects],
        [.study, .projects, .personal],
        [.personal],
        [],
    ]

    private var analytics: some View {
        let completions = Self.activity.flatMap { $0 }
        let total = completions.count
        let activeDays = Self.activity.filter { !$0.isEmpty }.count
        let count = revealed ? total : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(["Неделя", "Месяц", "Год"], id: \.self) { period in
                    let selected = period == "Неделя"
                    Text(period)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(selected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(selected ? Theme.Colors.accent : MonoBrand.inset, in: Capsule())
                }
            }
            HStack(spacing: 12) {
                Text("\(count)")
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 56, height: 56)
                    .background(Theme.Colors.accent.opacity(0.07), in: Circle())
                    .overlay { Circle().strokeBorder(Theme.Colors.accent) }
                    .animation(revealAnimation(delay: 0.10), value: count)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Выполнено за неделю").font(.headline)
                    Label("Активных дней: \(activeDays)", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .modifier(MonoBrandSurface(border: Theme.Colors.accent.opacity(0.5), radius: 16))
            activityChart
            VStack(alignment: .leading, spacing: 5) {
                Text("По папкам").font(.subheadline.weight(.semibold))
                ForEach(Array(ActivityFolder.allCases.enumerated()), id: \.element) { index, folder in
                    let completed = completions.filter { $0 == folder }.count
                    HStack(spacing: 8) {
                        ClassicFolderArtwork(tint: folder.tint, icon: folder.icon)
                            .frame(width: 29, height: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(folder.rawValue).font(.caption.weight(.medium))
                            ProgressLine(
                                progress: revealed ? Double(completed) / Double(total) : 0,
                                tint: folder.tint,
                                height: 3
                            )
                        }
                        Text("\(completed)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .modifier(MonoBrandSurface(fill: MonoBrand.inset, radius: 10))
                    .opacity(revealed ? 1 : 0.45)
                    .animation(revealAnimation(delay: 0.16 + Double(index) * 0.07), value: revealed)
                }
            }
        }
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Активность").font(.caption.weight(.semibold))
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Self.activity.indices, id: \.self) { index in
                    let segments = Self.activity[index]
                    VStack(spacing: 8) {
                        VStack(spacing: 0) {
                            if segments.isEmpty {
                                Capsule().fill(Theme.Colors.fillStrong).frame(height: 4)
                            } else {
                                ForEach(segments.indices, id: \.self) { segment in
                                    Rectangle().fill(segments[segment].tint).frame(height: 12)
                                }
                            }
                        }
                        .frame(maxWidth: 28)
                        .clipShape(.rect(cornerRadius: 5))
                        .scaleEffect(x: 1, y: revealed ? 1 : 0.04, anchor: .bottom)
                        .animation(revealAnimation(delay: Double(index) * 0.05), value: revealed)
                        .frame(height: 52, alignment: .bottom)

                        Text(Weekday.orderedFromMonday[index].shortName)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .background(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(Theme.Colors.hairline).frame(height: 1)
                    Spacer(minLength: 0)
                    Rectangle().fill(Theme.Colors.hairline).frame(height: 1)
                    Spacer(minLength: 0)
                    Rectangle().fill(Theme.Colors.hairline).frame(height: 1)
                }
                .frame(height: 52)
            }
        }
        .padding(10)
        .modifier(MonoBrandSurface(fill: MonoBrand.inset, radius: 16))
    }

    private func revealAnimation(delay: Double) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.42).delay(delay)
    }
}

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: TaskItem
    var allTags: [Tag] = []
    var isTargeted: Bool = false
    let onEdit: (TaskItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("monotask_show_task_notes") private var showNotes = true
    @AppStorage("monotask_compact_rows") private var compactRows = false
    @State private var completing = false
    @State private var completionWave: CGFloat = 0
    @State private var completionOpacity: Double = 1
    @State private var checkboxScale: CGFloat = 1.0
    @State private var lastToggleTime: Date = .distantPast
    @State private var settledSwipeOffset: CGFloat = 0
    @State private var liveSwipeOffset: CGFloat?
    @State private var isFullSwipeArmed = false
    @State private var rowSize = CGSize(width: 340, height: 56)
    @State private var isDeleting = false

    private let deleteButtonWidth: CGFloat = 88

    private var swipeOffset: CGFloat { liveSwipeOffset ?? settledSwipeOffset }
    private var deleteWidth: CGFloat { max(0, -swipeOffset) }
    private var fullSwipeThreshold: CGFloat { rowSize.width * 0.72 }

    private var isDone: Bool {
        task.isDone
    }

    private var primaryTag: Tag? {
        task.tags.first
    }

    private var allSubtasksDone: Bool {
        task.hasSubtasks && task.completedSubtasksCount == task.subtasksCount
    }

    private var hasMeta: Bool {
        (task.isHighPriorityToday && !isDone) || primaryTag != nil || task.hasSubtasks || !task.notes.isEmpty
            || (task.dueDate != nil && !isDone)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            taskRowContent
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: { _, size in
                    rowSize = size
                }
                .offset(x: swipeOffset)
            // Keep the revealed action above the translated row's compositing layer.
            deleteAction
                .opacity(swipeOffset < -0.5 ? 1 : 0)
                .allowsHitTesting(swipeOffset < -0.5)
        }
        .frame(minHeight: 56)
        .opacity(completionOpacity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .task {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--screenshots"),
                ProcessInfo.processInfo.arguments.contains("--animate-completion"), task.sortOrder == 0
            {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                toggleDone()
            }
            #endif
        }
        #if os(iOS)
        .gesture(swipeGesture)
        #endif
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        #if os(iOS)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        #endif
        .draggable(task.id.uuidString)
        .contextMenu {
            TaskContextMenu(task: task, allTags: allTags, onEdit: onEdit, onToggleDone: toggleDone)
        }
    }

    #if os(iOS)
    private var swipeGesture: some UIGestureRecognizerRepresentable {
        HorizontalTaskSwipe(
            onChanged: { translation in
                guard !completing, !isDeleting else { return }
                let nextOffset = min(0, max(-rowSize.width, settledSwipeOffset + translation))
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { liveSwipeOffset = nextOffset }
                let armed = shouldCompleteSwipe(translation: translation, offset: nextOffset)
                if armed && !isFullSwipeArmed { Haptics.impact() }
                isFullSwipeArmed = armed
            },
            onEnded: { translation in
                guard !completing, !isDeleting else { return }
                let finalOffset = min(0, max(-rowSize.width, settledSwipeOffset + translation))
                if shouldCompleteSwipe(translation: translation, offset: finalOffset) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        settledSwipeOffset = -rowSize.width
                        liveSwipeOffset = nil
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(220))
                        deleteTask()
                    }
                } else {
                    let shouldReveal = -finalOffset > deleteButtonWidth / 2
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        settledSwipeOffset = shouldReveal ? -deleteButtonWidth : 0
                        liveSwipeOffset = nil
                    }
                    isFullSwipeArmed = false
                }
            },
            onCancelled: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    liveSwipeOffset = nil
                    isFullSwipeArmed = false
                }
            }
        )
    }
    private func shouldCompleteSwipe(translation: CGFloat, offset: CGFloat) -> Bool {
        // Once the action is open, a second deliberate left swipe confirms deletion.
        let isActionOpen = settledSwipeOffset <= -deleteButtonWidth
        let repeatedSwipeThreshold = max(44, deleteButtonWidth * 0.75)
        return -offset >= fullSwipeThreshold
            || (isActionOpen && translation <= -repeatedSwipeThreshold)
    }
    #endif

    private var taskRowContent: some View {
        HStack(alignment: .center, spacing: 4) {

            Button {
                toggleDone()
            } label: {
                TaskCheckbox(isDone: isDone || completing)
                    .scaleEffect(checkboxScale)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FullSurfaceButtonStyle())
            .accessibilityLabel(isDone ? "Вернуть в работу" : "Отметить выполненной")
            .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(task.title)
                        .font(Theme.Typography.body)
                        .tracking(Theme.Typography.bodyTracking)
                        .strikethrough(isDone || completing, color: Theme.Colors.textMuted)
                        .foregroundColor(isDone ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                }

                if hasMeta {
                    metaRow
                }
                if showNotes && !task.notes.isEmpty {
                    Text(task.notes).font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary).lineLimit(1)
                }
            }
            .padding(.vertical, compactRows ? 8 : 12)
            .padding(.trailing, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                onEdit(task)
            }
        }
        .frame(minHeight: 56)
        .background(isTargeted ? Theme.Colors.fillStrong : Theme.Colors.surface)
        .overlay {
            GeometryReader { geometry in
                LinearGradient(
                    stops: [
                        .init(color: Theme.Colors.inverse, location: 0),
                        .init(color: Theme.Colors.inverse, location: 0.78),
                        .init(color: Theme.Colors.inverse.opacity(0), location: 1),
                    ], startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geometry.size.width * 1.3)
                .offset(x: geometry.size.width * 1.3 * (completionWave - 1))
                .opacity(completing ? 1 : 0)
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var deleteAction: some View {
        Button(action: deleteTask) {
            VStack(spacing: 4) {
                Image(systemName: isFullSwipeArmed ? "trash.fill" : "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .scaleEffect(isFullSwipeArmed ? 1.12 : 1)
                Text("Удалить")
                    .font(Theme.Typography.numeric(9, weight: .medium))
            }
            .foregroundColor(Theme.Colors.textPrimary)
            .fixedSize()
            .frame(width: deleteWidth, height: rowSize.height, alignment: .center)
            .background(Theme.Colors.danger)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(FullSurfaceButtonStyle())
        .accessibilityHidden(swipeOffset == 0)
    }

    private func deleteTask() {
        guard !isDeleting, !completing else { return }
        isDeleting = true
        Haptics.warning()
        withAnimation(.easeInOut(duration: 0.2)) {
            TaskDeletionManager.shared.requestDelete(task, context: modelContext)
        }
    }

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let date = task.dueDate, !isDone {
                Label(date.taskReminderLabel, systemImage: "calendar")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(date < .now ? Theme.Colors.warning : Theme.Colors.textSecondary)
            }
            HStack(spacing: 10) {
                if task.isHighPriorityToday && !isDone {
                    Image(systemName: "flag.fill").font(.caption).foregroundStyle(Theme.Colors.priority)
                        .accessibilityLabel("Высокий приоритет")
                }

                if let tag = primaryTag {
                    HStack(spacing: 5) {
                        Circle().fill(isDone ? Theme.Colors.textMuted : tag.color).frame(width: 6, height: 6)
                        Text(tag.name).lineLimit(1)
                    }
                }
                if task.hasSubtasks {
                    Label("\(task.completedSubtasksCount)/\(task.subtasksCount)", systemImage: "checklist")
                        .foregroundStyle(allSubtasksDone && !isDone ? Theme.Colors.success : Theme.Colors.textSecondary)
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func toggleDone() {
        guard !completing, !isDeleting else { return }
        let now = Date.now
        guard now.timeIntervalSince(lastToggleTime) >= 0.4 else { return }
        lastToggleTime = now
        let next = !task.isDone
        next ? Haptics.success() : Haptics.selection()
        if reduceMotion || !next {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                modelContext.setCompleted(task, next)
            }
            return
        }
        completing = true
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            checkboxScale = 1.14
        }
        withAnimation(.easeInOut(duration: 0.28)) {
            completionWave = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(290))
            guard task.modelContext != nil else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                checkboxScale = 1
                completionOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(120))
            guard task.modelContext != nil else { return }
            // Keep the row hidden until its removal transition has finished.
            withAnimation(.easeInOut(duration: 0.25), completionCriteria: .removed) {
                modelContext.setCompleted(task, true)
            } completion: {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) {
                    completing = false
                    completionWave = 0
                    completionOpacity = 1
                }
            }
        }
    }
}

/// Context menu shared by the iPhone and Mac task rows.
struct TaskContextMenu: View {
    @Environment(\.modelContext) private var modelContext
    let task: TaskItem
    let allTags: [Tag]
    let onEdit: (TaskItem) -> Void
    let onToggleDone: () -> Void

    var body: some View {
        Button {
            onEdit(task)
        } label: {
            Label("Открыть", systemImage: "square.and.pencil")
        }

        Button {
            onToggleDone()
        } label: {
            Label(
                task.isDone ? "Вернуть в работу" : "Выполнено",
                systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark.circle"
            )
        }

        Button {
            Haptics.selection()
            modelContext.toggleHighPriority(task)
        } label: {
            Label(
                task.isHighPriorityToday ? "Снять приоритет" : "Высокий приоритет",
                systemImage: task.isHighPriorityToday ? "flag.fill" : "flag"
            )
        }

        if !allTags.isEmpty {
            Menu {
                ForEach(allTags) { tag in
                    let isAssigned = task.tags.contains { $0.id == tag.id }
                    Button {
                        Haptics.selection()
                        modelContext.assign(task, to: isAssigned ? nil : tag)
                    } label: {
                        if isAssigned {
                            Label(tag.name, systemImage: "checkmark")
                        } else {
                            Text(tag.name)
                        }
                    }
                }
            } label: {
                Label("Категория", systemImage: "circle.grid.2x2")
            }
        }

        Divider()

        Button(role: .destructive) {
            Haptics.warning()
            withAnimation {
                TaskDeletionManager.shared.requestDelete(task, context: modelContext)
            }
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }
}

#if os(iOS)
/// Rejects vertical drags before recognition, so the parent list keeps scrolling.
private struct HorizontalTaskSwipe: UIGestureRecognizerRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void
    var onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> TaskSwipePanRecognizer {
        let pan = TaskSwipePanRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: TaskSwipePanRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(recognizer.horizontalTranslation)
        case .ended:
            onEnded(recognizer.horizontalTranslation)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view?.window)
            return abs(velocity.x) > abs(velocity.y) * 1.5
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let scroll = otherGestureRecognizer.view as? UIScrollView else { return false }
            return otherGestureRecognizer === scroll.panGestureRecognizer
        }
    }
}
/// Keeps the full touch displacement, including the movement that first starts recognition.
private final class TaskSwipePanRecognizer: UIPanGestureRecognizer {
    private var initialPoint = CGPoint.zero
    private var currentPoint = CGPoint.zero
    var horizontalTranslation: CGFloat { currentPoint.x - initialPoint.x }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first {
            initialPoint = touch.location(in: nil)
            currentPoint = initialPoint
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { currentPoint = touch.location(in: nil) }
        super.touchesMoved(touches, with: event)
    }

}
#endif

import Foundation
import SwiftData

extension ModelContext {
    /// Creates a task from a capture bar and schedules a sync.
    @MainActor
    @discardableResult
    func createTask(
        title: String, tag: Tag?, highPriority: Bool, reminderDate: Date? = nil, repeatsReminderDaily: Bool = false
    ) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let task = TaskItem(
            title: trimmed,
            bucket: .todo,
            priority: highPriority ? .high : .none,
            isHighPriorityToday: highPriority,
            dueDate: reminderDate,
            tags: tag.map { [$0] } ?? []
        )
        task.repeatsReminderDaily = reminderDate != nil && repeatsReminderDaily
        insert(task)
        saveAndSync(delaySeconds: 0.3)
        return task
    }

    /// Moves `sourceId` to the position of `targetId` in the global `ordered` list.
    /// Only tasks whose `sortOrder` actually changes are marked for sync.
    @MainActor
    func reorderTask(_ sourceId: UUID, onto targetId: UUID, in ordered: [TaskItem], highPriority: Bool? = nil) {
        guard let fromIndex = ordered.firstIndex(where: { $0.id == sourceId }),
            let toIndex = ordered.firstIndex(where: { $0.id == targetId }),
            fromIndex != toIndex
        else { return }

        var updated = ordered
        let moved = updated.remove(at: fromIndex)
        updated.insert(moved, at: toIndex)

        if let highPriority, moved.isPriority != highPriority {
            moved.priority = highPriority ? .high : .none
            moved.touch()
        }

        for (index, task) in updated.enumerated() where task.sortOrder != index {
            task.sortOrder = index
            task.touch()
        }
        saveAndSync(delaySeconds: 0.4)
    }

    /// Gives a dropped open task medium priority and places it first within that priority.
    @MainActor
    @discardableResult
    func prioritizeTask(_ id: UUID, in ordered: [TaskItem]) -> Bool {
        guard let task = ordered.first(where: { $0.id == id }),
            !task.isDone, !TaskDeletionManager.shared.isPending(task)
        else { return false }

        task.priority = .medium
        task.touch()
        let remaining = ordered.filter { $0.id != id }.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt > $1.createdAt
        }
        let updated = [task] + remaining
        for (index, item) in updated.enumerated() where item.sortOrder != index {
            item.sortOrder = index
            item.touch()
        }
        saveAndSync(delaySeconds: 0.4)
        return true
    }

    /// Moves a task to a single context (or removes its context when `tag` is nil).
    @MainActor
    func assign(_ task: TaskItem, to tag: Tag?) {
        let newTags = tag.map { [$0] } ?? []
        guard task.tags.map(\.id) != newTags.map(\.id) else { return }
        task.tags = newTags
        task.touch()
        saveAndSync(delaySeconds: 0.3)
    }

    @MainActor
    func toggleHighPriority(_ task: TaskItem) {
        task.priority = task.isPriority ? .none : .high
        task.touch()
        saveAndSync(delaySeconds: 0.3)
    }

    /// Deletes the given completed tasks. Completion history stays for the heatmap.
    @MainActor
    func clearCompleted(_ tasks: [TaskItem]) {
        TaskDeletionManager.shared.requestDelete(tasks.filter(\.isDone), context: self)
    }
}

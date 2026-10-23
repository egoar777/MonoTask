import Foundation
import SwiftData

extension ModelContext {
    /// Marks a task done or not done and keeps the activity heatmap data consistent.
    /// Callers wrap this in `withAnimation` if they want the row to animate.
    @MainActor
    func setCompleted(_ task: TaskItem, _ done: Bool) {
        guard task.isDone != done else { return }
        if done {
            task.bucket = .done
            recordCompletionActivity(for: task)
        } else {
            // Capture the completion date before the bucket setter clears it,
            // so the decrement lands on the day the task was actually completed.
            let completedAt = task.completedAt
            task.bucket = .todo
            recordUncompletionActivity(for: task, completedAt: completedAt)
        }
        saveAndSync(delaySeconds: 0.3)
    }

    func recordCompletionActivity(for task: TaskItem) {
        let day = (task.completedAt ?? Date.now).startOfDay
        let primaryTagId = task.tags.first?.id

        if let existing = activityEntry(on: day, tagId: primaryTagId) {
            existing.count += 1
            // Bump updatedAt so the next pull does not overwrite the new count with the server's older one
            existing.touch()
        } else {
            insert(ActivityEntry(date: day, tagId: primaryTagId, count: 1))
        }

        insert(
            CompletedHistoryEntry(
                taskId: task.id,
                tagId: primaryTagId,
                completedAt: task.completedAt ?? Date.now
            ))

        try? save()
    }

    func recordUncompletionActivity(for task: TaskItem, completedAt: Date? = nil) {
        let day = (completedAt ?? Date.now).startOfDay
        let primaryTagId = task.tags.first?.id

        if let existing = activityEntry(on: day, tagId: primaryTagId) {
            existing.count = max(0, existing.count - 1)
            existing.touch()
        }

        let taskId = task.id
        let historyDescriptor = FetchDescriptor<CompletedHistoryEntry>(
            predicate: #Predicate { $0.taskId == taskId }
        )
        if let histories = try? fetch(historyDescriptor) {
            for history in histories {
                deleteWithSync(history)
            }
        }

        try? save()
    }

    private func activityEntry(on day: Date, tagId: UUID?) -> ActivityEntry? {
        let descriptor = FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { $0.date == day }
        )
        return (try? fetch(descriptor))?.first { $0.tagId == tagId }
    }
}

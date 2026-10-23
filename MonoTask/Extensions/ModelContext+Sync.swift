import Foundation
import SwiftData

extension ModelContext {
    /// Saves the context and schedules an automatic background push/pull sync to Supabase.
    @MainActor
    func saveAndSync(delaySeconds: Double = 0.3) {
        try? save()
        NotificationService.shared.refresh(context: self)
        SupabaseSyncService.shared.scheduleSync(context: self, delaySeconds: delaySeconds)
    }

    /// Records a deletion tombstone so remote Supabase can safely reflect local deletions
    /// without clean installs deleting remote items.
    func recordTombstone(id: UUID, type: String) {
        let tombstone = SyncTombstone(recordId: id, recordType: type)
        insert(tombstone)
    }

    /// Safely deletes a task locally and registers tombstones for it and its subtasks.
    func deleteWithSync(_ task: TaskItem) {
        recordTombstone(id: task.id, type: "task")
        for subtask in task.subtasks {
            recordTombstone(id: subtask.id, type: "subtask")
        }
        delete(task)
    }

    /// Safely deletes a tag locally and registers a tombstone.
    func deleteWithSync(_ tag: Tag) {
        recordTombstone(id: tag.id, type: "tag")
        delete(tag)
    }

    /// Safely deletes a subtask locally and registers a tombstone.
    func deleteWithSync(_ subtask: SubtaskItem) {
        recordTombstone(id: subtask.id, type: "subtask")
        delete(subtask)
    }

    /// Safely deletes a daily note locally and registers a tombstone.
    func deleteWithSync(_ note: DailyNote) {
        recordTombstone(id: note.id, type: "daily_note")
        delete(note)
    }

    /// Safely deletes a weekly review locally and registers a tombstone.
    func deleteWithSync(_ review: WeeklyReview) {
        recordTombstone(id: review.id, type: "weekly_review")
        delete(review)
    }

    /// Safely deletes a focus schedule locally and registers a tombstone.
    func deleteWithSync(_ schedule: FocusSchedule) {
        recordTombstone(id: schedule.id, type: "focus_schedule")
        delete(schedule)
    }

    /// Safely deletes a completed history entry locally and registers a tombstone.
    func deleteWithSync(_ history: CompletedHistoryEntry) {
        recordTombstone(id: history.id, type: "completed_history")
        delete(history)
    }
}

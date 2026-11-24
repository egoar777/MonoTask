import Foundation
import SwiftData
import SwiftUI

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var bucketRaw: String = Bucket.inbox.rawValue
    var priorityRaw: String = Priority.none.rawValue
    var isHighPriorityToday: Bool = false
    var createdAt: Date = Date.now
    var completedAt: Date?
    var dueDate: Date?
    var repeatsReminderDaily: Bool = false
    // Preserve the current app's stored reminder fields when comparing the classic UI.
    var reminderMinutesBefore: Int? = 0
    var reminderSyncPending: Bool = false
    var sortOrder: Int = 0
    var updatedAt: Date = Date.now

    // Cloud storage & offline sync tracking
    var serverUpdatedAt: Date? = nil
    var isPendingOfflineSync: Bool = false

    @Relationship
    var tags: [Tag] = []

    @Relationship(deleteRule: .cascade)
    var subtasks: [SubtaskItem] = []

    init(
        title: String,
        notes: String = "",
        bucket: Bucket = .inbox,
        priority: Priority = .none,
        isHighPriorityToday: Bool = false,
        dueDate: Date? = nil,
        tags: [Tag] = [],
        subtasks: [SubtaskItem] = []
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.bucketRaw = bucket.rawValue
        self.priorityRaw = priority.rawValue
        self.isHighPriorityToday = isHighPriorityToday || priority == .high
        self.createdAt = Date.now
        self.updatedAt = Date.now
        self.serverUpdatedAt = nil
        self.isPendingOfflineSync = true
        self.completedAt = nil
        self.dueDate = dueDate
        self.sortOrder = 0
        self.tags = tags
        self.subtasks = subtasks
    }

    func touch() {
        updatedAt = Date.now
        isPendingOfflineSync = true
    }

    var bucket: Bucket {
        get { Bucket(rawValue: bucketRaw) ?? .inbox }
        set {
            bucketRaw = newValue.rawValue
            updatedAt = Date.now
            isPendingOfflineSync = true
            if newValue == .done && completedAt == nil {
                completedAt = Date.now
            } else if newValue != .done {
                completedAt = nil
            }
        }
    }

    var priority: Priority {
        get {
            let stored = Priority(rawValue: priorityRaw) ?? .none
            return isHighPriorityToday ? .high : stored
        }
        set {
            priorityRaw = newValue.rawValue
            isHighPriorityToday = newValue == .high
            updatedAt = Date.now
            isPendingOfflineSync = true
        }
    }

    /// Both visible priority levels belong to the priority section.
    var isPriority: Bool {
        priority == .high || priority == .medium
    }

    var isDone: Bool {
        bucket == .done
    }

    var subtasksCount: Int {
        subtasks.count
    }

    var completedSubtasksCount: Int {
        subtasks.filter(\.isCompleted).count
    }

    var hasSubtasks: Bool {
        !subtasks.isEmpty
    }

    var subtasksProgress: Double {
        hasSubtasks ? Double(completedSubtasksCount) / Double(subtasksCount) : 0
    }

    var sortedSubtasks: [SubtaskItem] {
        subtasks.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortOrder < $1.sortOrder
        }
    }
}

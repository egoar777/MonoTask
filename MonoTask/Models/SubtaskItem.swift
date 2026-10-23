import Foundation
import SwiftData

@Model
final class SubtaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var isCompleted: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Cloud storage & offline sync tracking
    var serverUpdatedAt: Date? = nil
    var isPendingOfflineSync: Bool = false

    @Relationship(inverse: \TaskItem.subtasks)
    var task: TaskItem?

    init(title: String, isCompleted: Bool = false, sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.createdAt = Date.now
        self.updatedAt = Date.now
        self.serverUpdatedAt = nil
        self.isPendingOfflineSync = true
    }

    func touch() {
        updatedAt = Date.now
        isPendingOfflineSync = true
    }
}

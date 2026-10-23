import Foundation
import SwiftData

@Model
final class CompletedHistoryEntry {
    var id: UUID = UUID()
    var taskId: UUID = UUID()
    var tagId: UUID?
    var completedAt: Date = Date.now
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(taskId: UUID, tagId: UUID? = nil, completedAt: Date = Date.now) {
        self.id = UUID()
        self.taskId = taskId
        self.tagId = tagId
        self.completedAt = completedAt
        self.createdAt = Date.now
        self.updatedAt = Date.now
    }

    func touch() {
        updatedAt = Date.now
    }
}

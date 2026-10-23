import Foundation
import SwiftData

@Model
final class WeeklyReview {
    var id: UUID = UUID()
    var weekStartDate: Date = Date.now
    var summary: String = ""
    var improvements: String = ""
    var completedTasksCount: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        weekStartDate: Date = Date.now,
        summary: String = "",
        improvements: String = "",
        completedTasksCount: Int = 0
    ) {
        self.id = UUID()
        self.weekStartDate = weekStartDate
        self.summary = summary
        self.improvements = improvements
        self.completedTasksCount = completedTasksCount
        self.createdAt = Date.now
        self.updatedAt = Date.now
    }

    func touch() {
        updatedAt = Date.now
    }
}

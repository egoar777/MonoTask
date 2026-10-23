import Foundation
import SwiftData

@Model
final class ActivityEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var tagId: UUID?
    var count: Int = 1
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(date: Date = Date.now, tagId: UUID? = nil, count: Int = 1) {
        self.id = UUID()
        self.date = date
        self.tagId = tagId
        self.count = count
        self.createdAt = Date.now
        self.updatedAt = Date.now
    }

    func touch() {
        updatedAt = Date.now
    }
}

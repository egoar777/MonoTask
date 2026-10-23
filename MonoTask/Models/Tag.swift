import Foundation
import SwiftData
import SwiftUI

@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#6366F1"
    var iconName: String = "tag.fill"
    var scheduledDaysRaw: [Int] = []
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(inverse: \TaskItem.tags)
    var tasks: [TaskItem] = []

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#6366F1",
        iconName: String = "tag.fill",
        scheduledDays: [Weekday] = [],
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.scheduledDaysRaw = scheduledDays.map(\.rawValue)
        self.sortOrder = sortOrder
        self.createdAt = Date.now
        self.updatedAt = Date.now
        self.tasks = []
    }

    func touch() {
        updatedAt = Date.now
    }

    var color: Color {
        Theme.Colors.tagColor(colorHex)
    }

    var scheduledDays: [Weekday] {
        get {
            scheduledDaysRaw.compactMap { Weekday(rawValue: $0) }
        }
        set {
            scheduledDaysRaw = newValue.map(\.rawValue)
            updatedAt = Date.now
        }
    }
}

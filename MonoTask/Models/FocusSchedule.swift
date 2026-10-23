import Foundation
import SwiftData

@Model
final class FocusSchedule {
    var id: UUID = UUID()
    var weekdayRaw: Int = 2
    @Relationship var tag: Tag?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(weekday: Weekday = .monday, tag: Tag? = nil) {
        self.id = UUID()
        self.weekdayRaw = weekday.rawValue
        self.tag = tag
        self.createdAt = Date.now
        self.updatedAt = Date.now
    }

    func touch() {
        updatedAt = Date.now
    }

    var weekday: Weekday {
        get { Weekday(rawValue: weekdayRaw) ?? .monday }
        set {
            weekdayRaw = newValue.rawValue
            updatedAt = Date.now
        }
    }
}

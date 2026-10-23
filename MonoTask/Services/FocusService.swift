import Foundation
import SwiftData

final class FocusService: Sendable {
    static let shared = FocusService()

    private init() {}

    /// Returns current focus tag(s) based on schedule and manual override
    func currentFocusTags(allTags: [Tag], override: Tag?) -> [Tag] {
        if let override {
            return [override]
        }
        let currentWeekday = Weekday.current
        return allTags.filter { $0.scheduledDays.contains(currentWeekday) }
    }

}

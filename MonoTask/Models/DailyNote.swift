import Foundation
import SwiftData

@Model
final class DailyNote {
    var id: UUID = UUID()
    var date: Date = Date.now
    var wins: String = ""
    var losses: String = ""
    var reason: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(date: Date = Date.now, wins: String = "", losses: String = "", reason: String = "") {
        self.id = UUID()
        self.date = date
        self.wins = wins
        self.losses = losses
        self.reason = reason
        self.createdAt = Date.now
        self.updatedAt = Date.now
    }

    func touch() {
        updatedAt = Date.now
    }
}

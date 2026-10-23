import SwiftUI

enum Bucket: String, Codable, CaseIterable, Identifiable {
    case inbox = "inbox"
    case todo = "todo"
    case inProgress = "in_progress"
    case done = "done"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: return "tray.fill"
        case .todo: return "checklist"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .inbox: return Theme.Colors.info
        case .todo: return Theme.Colors.accent
        case .inProgress: return Theme.Colors.warning
        case .done: return Theme.Colors.success
        }
    }
}

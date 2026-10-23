import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Задачи"
        case .activity: return "Аналитика"
        case .settings: return "Настройки"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "checkmark.circle"
        case .activity: return "square.grid.3x3"
        case .settings: return "slider.horizontal.3"
        }
    }

    var activeSystemImage: String {
        switch self {
        case .today: return "checkmark.circle.fill"
        case .activity: return "square.grid.3x3.fill"
        case .settings: return "slider.horizontal.3"
        }
    }
}

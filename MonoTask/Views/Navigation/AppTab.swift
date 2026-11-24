import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Папки"
        case .activity: return "Аналитика"
        case .settings: return "Настройки"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "folder"
        case .activity: return "chart.bar"
        case .settings: return "gearshape"
        }
    }

    var activeSystemImage: String {
        switch self {
        case .today: return "folder.fill"
        case .activity: return "chart.bar.fill"
        case .settings: return "gearshape"
        }
    }
}

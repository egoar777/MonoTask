import SwiftUI

enum Priority: String, Codable, CaseIterable, Identifiable {
    case none = "none"
    case medium = "medium"
    case high = "high"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Без приоритета"
        case .medium: return "Средний"
        case .high: return "Высокий"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "minus"
        case .medium: return "exclamationmark"
        case .high: return "exclamationmark.2"
        }
    }

    var color: Color {
        switch self {
        case .none: return Theme.Colors.textTertiary
        case .medium: return Theme.Colors.warning
        case .high: return Theme.Colors.danger
        }
    }
}

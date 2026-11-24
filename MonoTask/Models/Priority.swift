import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum Priority: String, Codable, CaseIterable, Identifiable {
    case high = "high"
    case medium = "medium"
    case low = "low"
    case none = "none"

    // Keep decoding previously saved low priorities, but no longer offer them in menus.
    static let selectable: [Priority] = [.high, .medium, .none]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Без приоритета"
        case .low: return "Низкий"
        case .medium: return "Средний"
        case .high: return "Высокий"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "xmark.circle"
        case .low: return "chart.line.uptrend.xyaxis"
        case .medium: return "star"
        case .high: return "target"
        }
    }

    // Preserve per-priority colours inside native menus, which otherwise apply a shared tint.
    var menuIcon: Image {
        #if os(iOS)
        let symbol = UIImage(systemName: systemImage)!
            .withTintColor(UIColor(color), renderingMode: .alwaysOriginal)
        return Image(uiImage: symbol).renderingMode(.original)
        #elseif os(macOS)
        let symbol = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)!
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor(self.color).setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        tinted.isTemplate = false
        return Image(nsImage: tinted).renderingMode(.original)
        #endif
    }

    var rank: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    var color: Color {
        switch self {
        case .none: return Theme.Colors.textMuted
        case .low: return Color(hex: "#50B364")
        case .medium: return Color(hex: "#F4BF00")
        case .high: return Theme.Colors.danger
        }
    }
}

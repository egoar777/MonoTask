import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// Initialize a Color from a HEX string (e.g. "#6366F1", "6366F1", or with alpha "#6366F1FF")
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3:  // RGB (12-bit)
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 6:  // RGB (24-bit)
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:  // RGBA (32-bit)
            (r, g, b, a) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (128, 128, 128, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }

    /// Converts SwiftUI Color to Hex String
    func toHex() -> String {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02lX%02lX%02lX", lroundf(Float(red * 255)), lroundf(Float(green * 255)),
            lroundf(Float(blue * 255)))
        #elseif canImport(AppKit)
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        nsColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02lX%02lX%02lX", lroundf(Float(red * 255)), lroundf(Float(green * 255)),
            lroundf(Float(blue * 255)))
        #else
        return "#6366F1"
        #endif
    }
}

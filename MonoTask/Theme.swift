import SwiftUI
import CoreText
enum Theme {
    static let colorScheme: ColorScheme = .dark
    static func registerFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: - Colors
    enum Colors {
        // Surfaces, darkest to lightest
        static let background = Color(hex: "#101110")
        static let sidebar = Color(hex: "#171917")
        static let surface = Color(hex: "#1C1E1B")
        static let surfaceElevated = Color(hex: "#242623")
        static let surfaceInteractive = Color(hex: "#30332E")

        // Translucent fills for chips and controls on any surface
        static let fill = Color.white.opacity(0.05)
        static let fillStrong = Color.white.opacity(0.09)

        // Rules
        static let hairline = Color(hex: "#2C2F29")
        static let ruleStrong = Color(hex: "#494E45")

        // Text
        static let textPrimary = Color(hex: "#F2F2EC")
        static let textSecondary = Color(hex: "#A3A39A")
        static let textMuted = Color(hex: "#93998E")
        static let textTertiary = textMuted
        static let accent = Color(hex: "#C8FF2E")
        static let onAccent = Color(hex: "#101110")
        static let inverse = accent
        static let onInverse = onAccent
        static let priority = Color(hex: "#FF9F43")
        static let info = textSecondary

        static let success = accent

        static let warning = Color(hex: "#FFB020")

        static let danger = Color(hex: "#FF4D4F")
        static let dangerMuted = danger.opacity(0.14)
        static let tagColors: [String] = [
            "#5AA9FF",  // Blue
            "#B48CFF",  // Violet
            "#3DDC97",  // Green
            "#FFB547",  // Amber
            "#FF6B5B",  // Red
            "#FF8AC6",  // Rose
            "#7C83FF",  // Indigo
            "#4FD8E8",  // Teal
        ]
        // Legacy colours stay compatible with existing databases.
        private static let previousTagPalettes: [[String]] = [
            ["#0A84FF", "#BF5AF2", "#30D158", "#FF9F0A", "#FF453A", "#FF375F", "#5E5CE6", "#40C8E0"],
            ["#2F5DA8", "#7A4FB5", "#3F8F5A", "#D98A1E", "#D2452B", "#C9577F", "#4B57C2", "#2A8C8C"],
        ]
        // Keep stored category colours legible against dark surfaces.
        static func tagColor(_ hex: String) -> Color {
            let normalized = normalizedTagHex(hex)
            var cleaned = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("#") { cleaned.removeFirst() }
            guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
                return Color(hex: normalized)
            }

            let r = Double((value >> 16) & 0xFF) / 255
            let g = Double((value >> 8) & 0xFF) / 255
            let b = Double(value & 0xFF) / 255
            let maxC = max(r, g, b)
            let delta = maxC - min(r, g, b)

            var hue = 0.0
            if delta > 0 {
                if maxC == r {
                    hue = (g - b) / delta
                } else if maxC == g {
                    hue = (b - r) / delta + 2
                } else {
                    hue = (r - g) / delta + 4
                }
                hue /= 6
                if hue < 0 { hue += 1 }
            }
            let saturation = maxC == 0 ? 0 : delta / maxC

            return Color(hue: hue, saturation: min(saturation, 0.85), brightness: max(maxC, 0.8))
        }
        static func normalizedTagHex(_ hex: String) -> String {
            for palette in previousTagPalettes {
                if let index = palette.firstIndex(where: { $0.caseInsensitiveCompare(hex) == .orderedSame }) {
                    return tagColors[index]
                }
            }
            return hex
        }
    }

    // MARK: - Typography
    enum Typography {
        // Brand type is reserved for screen headers; controls and content use system styles.
        static let display = Font.custom("Unbounded-Black", size: 24, relativeTo: .title2)
        static let displayLarge = Font.custom("Unbounded-Black", size: 28, relativeTo: .title)
        static let displayTracking: CGFloat = -0.6
        static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
        static func figure(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold).monospacedDigit() }
        static let editorTitle = Font.title2.weight(.semibold)
        static let title = Font.title3.weight(.semibold)
        static let body = Font.callout
        static let bodyTracking: CGFloat = -0.2
        static let callout = Font.subheadline
        static let caption = Font.caption
        static let section = Font.subheadline.weight(.semibold)
        static let eyebrow = Font.subheadline
        static let eyebrowTracking: CGFloat = 0
        static func numeric(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight).monospacedDigit()
        }
    }

    // MARK: - Spacing
    enum Spacing {
        static let lg: CGFloat = 16
        static let screenPadding: CGFloat = 20
    }

    // MARK: - Corner Radius
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let card: CGFloat = 16
        static let capturePill: CGFloat = 18
        static let sheet: CGFloat = 26
    }

    // MARK: - Animation
    enum Motion {
        static let standard = Animation.easeInOut(duration: 0.28)
        static let quick = Animation.easeInOut(duration: 0.18)
    }
}

private struct MonoScrollEdgeModifier: ViewModifier {
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, value in
                offset = value
            }
            .overlay {
                GeometryReader { geometry in
                    let top = geometry.safeAreaInsets.top
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(
                                        color: Theme.Colors.background.opacity(reduceTransparency ? 1 : 0.96),
                                        location: 0),
                                    .init(color: Theme.Colors.background.opacity(0.88), location: 0.34),
                                    .init(color: Theme.Colors.background.opacity(0.5), location: 0.68),
                                    .init(color: Theme.Colors.background.opacity(0), location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: top + 64)
                        .offset(y: -top)
                        .opacity(min(1, offset / 20))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

extension View {
    func monoScrollEdge() -> some View { modifier(MonoScrollEdgeModifier()) }
}

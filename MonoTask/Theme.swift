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
        static let background = Color(hex: "#0B0B0A")
        static let sidebar = Color(hex: "#111110")
        static let surface = Color(hex: "#141412")
        static let surfaceElevated = Color(hex: "#1B1B18")
        static let surfaceInteractive = Color(hex: "#262622")
        static let tabBarBackground = background

        // Translucent fills for chips and controls on any surface
        static let fill = Color.white.opacity(0.05)
        static let fillStrong = Color.white.opacity(0.09)

        // Rules
        static let hairline = Color(hex: "#222220")
        static let ruleStrong = Color(hex: "#3A3A35")
        static let border = Color.white.opacity(0.12)
        static let borderSubtle = Color.white.opacity(0.07)

        // Text
        static let textPrimary = Color(hex: "#F2F2EC")
        static let textSecondary = Color(hex: "#A3A39A")
        static let textMuted = Color(hex: "#6F6F66")
        static let textTertiary = textMuted
        static let accent = Color(hex: "#C8FF2E")
        static let primary = accent
        static let primaryMuted = accent.opacity(0.14)
        static let onAccent = Color(hex: "#0B0B0A")
        static let inverse = accent
        static let onInverse = onAccent
        static let priority = Color(hex: "#FF48A4")
        static let info = textSecondary

        static let success = accent
        static let accentGreen = accent
        static let successMuted = accent.opacity(0.14)

        static let warning = Color(hex: "#FFB020")
        static let warningMuted = warning.opacity(0.14)

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
        private static let unboundedBlack = "Unbounded-Black"
        private static let unboundedBold = "Unbounded-Bold"
        private static let monoRegular = "JetBrainsMono-Regular"
        private static let monoMedium = "JetBrainsMono-Medium"
        private static let monoBold = "JetBrainsMono-Bold"
        static let display = Font.custom(unboundedBlack, size: 34)
        static let displayLarge = Font.custom(unboundedBlack, size: 40)
        static let displayTracking: CGFloat = -0.5
        static func heading(_ size: CGFloat) -> Font {
            .custom(unboundedBold, size: size)
        }
        static func figure(_ size: CGFloat) -> Font {
            .custom(unboundedBold, size: size)
        }
        static let editorTitle = Font.system(size: 24, weight: .bold)

        static let title = Font.system(size: 20, weight: .semibold)
        static let titleTracking: CGFloat = -0.5

        static let body = Font.system(size: 16)
        static let bodyTracking: CGFloat = -0.2

        static let callout = Font.system(size: 14)
        static let caption = Font.system(size: 12)
        static let section = Font.custom(monoMedium, size: 11)
        static let eyebrow = Font.custom(monoRegular, size: 11)
        static let eyebrowTracking: CGFloat = 0.6
        static let subtitle = Font.custom(monoRegular, size: 12)
        static func numeric(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            switch weight {
            case .bold, .heavy, .black, .semibold: return .custom(monoBold, size: size)
            case .medium: return .custom(monoMedium, size: size)
            default: return .custom(monoRegular, size: size)
            }
        }
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let screenPadding: CGFloat = 20
        static let touchTargetMin: CGFloat = 44
    }

    // MARK: - Corner Radius
    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let card: CGFloat = 16
        static let xl: CGFloat = 18
        static let capturePill: CGFloat = 18
        static let sheet: CGFloat = 26
        static let full: CGFloat = 9999
    }
    typealias CornerRadius = Radius

    // MARK: - Animation
    enum Motion {
        static let standard = Animation.easeInOut(duration: 0.28)
        static let quick = Animation.easeInOut(duration: 0.18)
    }

    enum AnimationDuration {
        static let quick: Double = 0.15
        static let standard: Double = 0.25
    }
}

// MARK: - View Modifiers

struct MonoTaskCardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.lg
    var elevated: Bool = false
    var cornerRadius: CGFloat = Theme.Radius.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(elevated ? Theme.Colors.surfaceElevated : Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.Colors.hairline, lineWidth: 1)
            )
    }
}

struct MonoTaskBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.Colors.background.ignoresSafeArea())
            .preferredColorScheme(Theme.colorScheme)
    }
}

extension View {
    func monoTaskCard(
        padding: CGFloat = Theme.Spacing.lg,
        elevated: Bool = false,
        cornerRadius: CGFloat = Theme.Radius.card
    ) -> some View {
        modifier(MonoTaskCardModifier(padding: padding, elevated: elevated, cornerRadius: cornerRadius))
    }

    func monoTaskBackground() -> some View {
        modifier(MonoTaskBackgroundModifier())
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

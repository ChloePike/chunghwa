import AppKit
import SwiftUI

/// Design tokens for the "Bone & Brass on Patina" palette.
enum ChungHwa {
    enum Palette {
        // ── Brand constants (do not change with theme) ───────────────────
        static let ink       = hex(0x0E2A2A)   // deep teal text/ink
        static let patina    = hex(0x3F6B66)   // muted teal
        static let bone      = hex(0xF5F1E8)   // paper
        static let paper     = hex(0xFBFAF7)   // bright paper
        static let brass     = hex(0xC8A96E)   // brass accent
        static let brassDark = hex(0xa88c54)
        static let earth     = hex(0x9c4a3b)   // earthy red, semantic "bad"

        // ── Adaptive surfaces (light / dark) ─────────────────────────────
        static let bg          = adaptive(light: hex(0xFBFAF7),               dark: hex(0x0E2A2A))
        static let desk        = adaptive(light: hex(0xB9BCB3),               dark: hex(0x06181A))
        static let card        = adaptive(light: .white,                       dark: hex(0x13383A))
        static let cardSoft    = adaptive(light: hex(0xF5F1E8),               dark: hex(0x0F3032))

        static let line        = adaptive(light: hex(0x0E2A2A, alpha: 0.12),  dark: hex(0xF5F1E8, alpha: 0.10))
        static let lineSoft    = adaptive(light: hex(0x0E2A2A, alpha: 0.06),  dark: hex(0xF5F1E8, alpha: 0.05))

        static let text        = adaptive(light: hex(0x0E2A2A),               dark: hex(0xF5F1E8))
        static let dim         = adaptive(light: hex(0x3F6B66),               dark: hex(0xF5F1E8, alpha: 0.65))
        static let faint       = adaptive(light: hex(0x3F6B66, alpha: 0.55),  dark: hex(0xF5F1E8, alpha: 0.40))

        static let fill        = adaptive(light: hex(0x0E2A2A, alpha: 0.045), dark: hex(0xF5F1E8, alpha: 0.06))
        static let fillStrong  = adaptive(light: hex(0x0E2A2A, alpha: 0.08),  dark: hex(0xF5F1E8, alpha: 0.10))

        static let sidebar     = adaptive(light: hex(0xF5F1E8, alpha: 0.92),  dark: hex(0x0B2222, alpha: 0.92))
        static let sideHover   = adaptive(light: hex(0x0E2A2A, alpha: 0.04),  dark: hex(0xF5F1E8, alpha: 0.05))
        static let sideActive  = adaptive(light: hex(0xC8A96E, alpha: 0.18),  dark: hex(0xC8A96E, alpha: 0.14))

        static let pillBg      = adaptive(light: .white,                       dark: hex(0xF5F1E8, alpha: 0.10))
    }

    enum Typography {
        /// SwiftUI's `.serif` design maps to New York on macOS, which is the
        /// closest system font to the design's Newsreader. We can bundle the
        /// real Newsreader later if it ends up mattering visually.
        static func serif(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }

        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    private static func hex(_ rgb: UInt32, alpha: Double = 1) -> Color {
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >>  8) & 0xFF) / 255
        let b = Double( rgb        & 0xFF) / 255
        return Color(red: r, green: g, blue: b).opacity(alpha)
    }

    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}

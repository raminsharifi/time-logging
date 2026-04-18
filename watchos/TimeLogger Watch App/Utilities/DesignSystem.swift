import SwiftUI

/// TL design tokens — high-contrast dark, grid-based, monospaced-label system.
/// Shared verbatim across iOS, watchOS, and macOS.
enum TL {}

// MARK: - Color

extension TL {
    enum Palette {
        // Structural greyscale
        static let bg      = Color(red: 0.039, green: 0.039, blue: 0.043)  // #0A0A0B
        static let surface = Color(red: 0.078, green: 0.078, blue: 0.086)  // #141416
        static let raised  = Color(red: 0.106, green: 0.106, blue: 0.118)  // #1B1B1E
        static let line    = Color(red: 0.149, green: 0.149, blue: 0.165)  // #26262A
        static let lineHi  = Color(red: 0.208, green: 0.208, blue: 0.227)  // #35353A
        static let ink     = Color(red: 0.925, green: 0.925, blue: 0.925)  // #ECECEC
        static let mute    = Color(red: 0.541, green: 0.541, blue: 0.565)  // #8A8A90
        static let dim     = Color(red: 0.353, green: 0.353, blue: 0.376)  // #5A5A60

        // Semantic accents (approximations of the oklch hues in the prototype)
        static let accent  = hue(115)  // signal green-yellow — deep work
        static let amber   = hue(28)   // meetings
        static let violet  = hue(265)  // review
        static let sky     = hue(200)  // admin
        static let magenta = hue(330)  // learning
        static let danger  = Color(red: 0.95, green: 0.35, blue: 0.30)

        // Legacy names kept so existing call sites keep compiling while we
        // migrate every screen. Aliased to the semantic hues above.
        static let ember   = danger
        static let citrine = amber
        static let emerald = accent
        static let iris    = violet
        static let rose    = magenta
        static let mist    = mute

        /// Build a category color from an oklch-style hue (0-360°).
        /// Uses HSB with tuned saturation + brightness to match the
        /// "soft-neon on black" feel of the prototype's `oklch(0.78 0.16 hue)`.
        static func hue(_ hue: Double) -> Color {
            Color(hue: hue / 360.0, saturation: 0.55, brightness: 0.92)
        }

        /// Every palette hue in the order used across charts.
        static let all: [Color] = [accent, amber, violet, sky, magenta]
    }

    /// Deterministic category → hue mapping. Same category name always yields
    /// the same color across the app.
    static func categoryColor(_ name: String) -> Color {
        guard !name.isEmpty else { return Palette.sky }
        // Well-known categories land on the prototype's assigned hues.
        switch name.lowercased() {
        case "deep work", "deep", "focus", "general": return Palette.accent
        case "meeting", "meetings", "meet":            return Palette.amber
        case "review", "pr":                           return Palette.violet
        case "admin", "inbox", "ops":                  return Palette.sky
        case "learning", "learn", "study":             return Palette.magenta
        default:
            // Hash unknown names into the 5-slot palette deterministically.
            let hash = name.lowercased().unicodeScalars.reduce(UInt32(0)) { acc, s in
                acc &* 31 &+ s.value
            }
            return Palette.all[Int(hash % UInt32(Palette.all.count))]
        }
    }

    /// Stable palette name the server can echo for charts; kept for API parity.
    static func categoryColorName(_ name: String) -> String {
        switch name.lowercased() {
        case "deep work", "deep", "focus", "general": return "accent"
        case "meeting", "meetings", "meet":            return "amber"
        case "review", "pr":                           return "violet"
        case "admin", "inbox", "ops":                  return "sky"
        case "learning", "learn", "study":             return "magenta"
        default: return "accent"
        }
    }
}

// MARK: - Spacing / Radius

extension TL {
    enum Space {
        static let xs:   CGFloat = 4
        static let s:    CGFloat = 8
        static let m:    CGFloat = 12
        static let l:    CGFloat = 16
        static let xl:   CGFloat = 24
        static let xxl:  CGFloat = 32
        static let xxxl: CGFloat = 48
    }
    /// Tight, grid-based radii — no big pill shapes. 0 = flush, 4 = cards.
    enum Radius {
        static let xs: CGFloat = 1
        static let s:  CGFloat = 2
        static let m:  CGFloat = 3
        static let l:  CGFloat = 4
        static let xl: CGFloat = 6
    }
}

// MARK: - Typography

extension TL {
    enum TypeScale {
        // Sans (San Francisco) for running text and numerals that don't need
        // tabular alignment.
        static let display     = Font.system(size: 28, weight: .bold)
        static let title       = Font.system(size: 22, weight: .bold)
        static let title2      = Font.system(size: 20, weight: .semibold)
        static let title3      = Font.system(size: 17, weight: .semibold)
        static let headline    = Font.system(size: 15, weight: .semibold)
        static let subheadline = Font.system(size: 14, weight: .regular)
        static let body        = Font.system(size: 14, weight: .regular)
        static let callout     = Font.system(size: 13, weight: .regular)
        static let caption     = Font.system(size: 11, weight: .regular)
        static let caption2    = Font.system(size: 10, weight: .regular)

        /// Uppercase-tracked label (SF Mono) used for section headers and chrome.
        static func label(_ size: CGFloat = 10) -> Font {
            .system(size: size, weight: .medium, design: .monospaced)
        }

        /// Tabular digits for clocks + KPI numerals.
        static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }
}

// MARK: - Motion

extension TL {
    enum Motion {
        static let smooth = Animation.smooth(duration: 0.35)
        static let bouncy = Animation.bouncy(duration: 0.5)
        static let snappy = Animation.snappy(duration: 0.22)
    }
}

// MARK: - Duration formatter

extension TL {
    /// "HH:MM:SS" (always three pairs) for the hero clock, stable-width via
    /// tabular digits.
    static func clock(_ seconds: Int64) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }

    /// Compact "1h 23m" used in summaries and list rows.
    static func clockShort(_ seconds: Int64) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0          { return "\(h)h" }
        if m > 0          { return "\(m)m" }
        return "\(s)s"
    }
}

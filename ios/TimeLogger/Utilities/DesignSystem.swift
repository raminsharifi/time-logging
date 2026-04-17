import SwiftUI

/// GlassKit design tokens — shared verbatim across iOS, watchOS, and macOS.
/// Edit once, paste to all three Utilities folders.
enum TL {}

// MARK: - Color

extension TL {
    enum Palette {
        static let ink       = Color(red: 0.039, green: 0.043, blue: 0.071)  // #0A0B12
        static let surface   = Color.primary.opacity(0.04)

        static let ember     = Color(red: 1.000, green: 0.357, blue: 0.290)  // #FF5B4A
        static let citrine   = Color(red: 1.000, green: 0.710, blue: 0.278)  // #FFB547
        static let emerald   = Color(red: 0.184, green: 0.816, blue: 0.478)  // #2FD07A
        static let sky       = Color(red: 0.310, green: 0.765, blue: 1.000)  // #4FC3FF
        static let iris      = Color(red: 0.545, green: 0.424, blue: 1.000)  // #8B6CFF
        static let rose      = Color(red: 1.000, green: 0.435, blue: 0.663)  // #FF6FA9
        static let mist      = Color(red: 0.620, green: 0.690, blue: 0.780)  // neutral

        static let all: [Color] = [ember, citrine, emerald, sky, iris, rose, mist]
    }

    /// Deterministic category → palette color. Same category always returns same color.
    static func categoryColor(_ name: String) -> Color {
        guard !name.isEmpty else { return Palette.sky }
        let hash = name.lowercased().unicodeScalars.reduce(UInt32(0)) { acc, s in
            acc &* 31 &+ s.value
        }
        return Palette.all[Int(hash % UInt32(Palette.all.count))]
    }

    /// Matching "name" the backend can echo in AnalyticsResponse.
    static func categoryColorName(_ name: String) -> String {
        let palette = ["ember", "citrine", "emerald", "sky", "iris", "rose", "mist"]
        guard !name.isEmpty else { return "sky" }
        let hash = name.lowercased().unicodeScalars.reduce(UInt32(0)) { acc, s in
            acc &* 31 &+ s.value
        }
        return palette[Int(hash % UInt32(palette.count))]
    }
}

// MARK: - Spacing / Radius

extension TL {
    enum Space {
        static let xs: CGFloat = 4
        static let s:  CGFloat = 8
        static let m:  CGFloat = 12
        static let l:  CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }
    enum Radius {
        static let s:  CGFloat = 8
        static let m:  CGFloat = 14
        static let l:  CGFloat = 20
        static let xl: CGFloat = 28
    }
}

// MARK: - Typography

extension TL {
    enum TypeScale {
        static let display  = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let title    = Font.system(.title, design: .rounded).weight(.semibold)
        static let title2   = Font.system(.title2, design: .rounded).weight(.semibold)
        static let title3   = Font.system(.title3, design: .rounded).weight(.semibold)
        static let headline = Font.system(.headline, design: .rounded)
        static let subheadline = Font.system(.subheadline, design: .rounded)
        static let body     = Font.system(.body, design: .rounded)
        static let callout  = Font.system(.callout, design: .rounded)
        static let caption  = Font.system(.caption, design: .rounded)
        static let caption2 = Font.system(.caption2, design: .rounded)

        /// Durations always use SF Mono, tabular digits, so the clock doesn't jitter.
        static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }
}

// MARK: - Motion

extension TL {
    enum Motion {
        static let smooth  = Animation.smooth(duration: 0.35)
        static let bouncy  = Animation.bouncy(duration: 0.5)
        static let snappy  = Animation.snappy(duration: 0.22)
    }
}

// MARK: - Duration formatter (canonical, used across the app)

extension TL {
    /// "H:MM:SS" if >= 1h, else "MM:SS". Stable width thanks to zero-padding.
    static func clock(_ seconds: Int64) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%02d:%02d", m, sec)
    }

    /// "1h 23m" style, used in summaries.
    static func clockShort(_ seconds: Int64) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}

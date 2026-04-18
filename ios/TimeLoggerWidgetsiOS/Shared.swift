import Foundation
import SwiftUI
#if os(iOS)
import ActivityKit
#endif

// MARK: - App Group container

enum WidgetShared {
    static let appGroup = "group.com.raminsharifi.TimeLogger"
    static let snapshotFile = "widget_timer.json"

    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static func snapshotURL() -> URL? {
        containerURL()?.appendingPathComponent(snapshotFile)
    }
}

// MARK: - Widget design tokens (mirror TL.Palette in the main app)

enum WidgetTokens {
    static let bg      = Color(red: 0.039, green: 0.039, blue: 0.043)
    static let surface = Color(red: 0.078, green: 0.078, blue: 0.086)
    static let raised  = Color(red: 0.106, green: 0.106, blue: 0.118)
    static let line    = Color(red: 0.149, green: 0.149, blue: 0.165)
    static let lineHi  = Color(red: 0.208, green: 0.208, blue: 0.227)
    static let ink     = Color(red: 0.925, green: 0.925, blue: 0.925)
    static let mute    = Color(red: 0.541, green: 0.541, blue: 0.565)
    static let dim     = Color(red: 0.353, green: 0.353, blue: 0.376)
    static let accent  = Color(hue: 115/360, saturation: 0.55, brightness: 0.92)
    static let danger  = Color(red: 0.95, green: 0.35, blue: 0.30)

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func label(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

// MARK: - Snapshot

struct TodaySnapshotEntry: Codable, Equatable {
    var startedAt: Int64      // unix seconds
    var endedAt: Int64
    var activeSecs: Int64
    var category: String
}

struct TimerSnapshot: Codable, Equatable {
    var isRunning: Bool
    var name: String
    var category: String
    var startedAt: Date
    var activeSecs: Int

    // Day snapshot (defaults to zero for backward-compat).
    var dayStart: Int64 = 0             // unix secs of 00:00 local
    var todayTotalSecs: Int64 = 0
    var todayEntries: [TodaySnapshotEntry] = []

    static let idle = TimerSnapshot(
        isRunning: false, name: "", category: "",
        startedAt: .distantPast, activeSecs: 0
    )

    static let preview: TimerSnapshot = {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        let day = Int64(todayStart.timeIntervalSince1970)
        let entries: [TodaySnapshotEntry] = [
            .init(startedAt: day + 8*3600 + 12*60,  endedAt: day + 9*3600 + 48*60,  activeSecs: 94*60,  category: "Deep Work"),
            .init(startedAt: day + 9*3600 + 50*60,  endedAt: day + 10*3600 + 5*60,  activeSecs: 15*60,  category: "Meetings"),
            .init(startedAt: day + 10*3600 + 10*60, endedAt: day + 11*3600 + 2*60,  activeSecs: 52*60,  category: "Review"),
            .init(startedAt: day + 11*3600 + 30*60, endedAt: day + 12*3600,         activeSecs: 30*60,  category: "Meetings"),
            .init(startedAt: day + 13*3600 + 5*60,  endedAt: day + 13*3600 + 32*60, activeSecs: 27*60,  category: "Admin"),
        ]
        let total = entries.reduce(Int64(0)) { $0 + $1.activeSecs } + 48*60
        return TimerSnapshot(
            isRunning: true,
            name: "Spec: Sync protocol",
            category: "Deep Work",
            startedAt: .now.addingTimeInterval(-48*60),
            activeSecs: 48 * 60,
            dayStart: day,
            todayTotalSecs: total,
            todayEntries: entries
        )
    }()

    static func load() -> TimerSnapshot {
        guard let url = WidgetShared.snapshotURL(),
              let data = try? Data(contentsOf: url)
        else { return .idle }
        if let obj = try? Self.decoder().decode(TimerSnapshot.self, from: data) {
            return rollOverForToday(obj)
        }
        // Fallback: legacy dict format written by older main-app builds that
        // used JSONSerialization with 1970-based seconds.
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let isRunning = (dict["isRunning"] as? Bool) ?? false
            let startedAtTs = (dict["startedAt"] as? TimeInterval) ?? 0
            let snap = TimerSnapshot(
                isRunning: isRunning,
                name: (dict["name"] as? String) ?? "",
                category: (dict["category"] as? String) ?? "",
                startedAt: Date(timeIntervalSince1970: startedAtTs),
                activeSecs: (dict["activeSecs"] as? Int) ?? 0,
                dayStart: (dict["dayStart"] as? Int64) ?? 0,
                todayTotalSecs: (dict["todayTotalSecs"] as? Int64) ?? 0,
                todayEntries: decodeLegacyEntries(dict["todayEntries"])
            )
            return rollOverForToday(snap)
        }
        return .idle
    }

    private static func decodeLegacyEntries(_ raw: Any?) -> [TodaySnapshotEntry] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { e in
            guard let startedAt = (e["startedAt"] as? NSNumber)?.int64Value,
                  let endedAt = (e["endedAt"] as? NSNumber)?.int64Value,
                  let activeSecs = (e["activeSecs"] as? NSNumber)?.int64Value,
                  let category = e["category"] as? String
            else { return nil }
            return TodaySnapshotEntry(
                startedAt: startedAt, endedAt: endedAt,
                activeSecs: activeSecs, category: category
            )
        }
    }

    /// Rolls the snapshot forward so today's aggregates reflect the current
    /// calendar day, even if the main app hasn't republished overnight.
    /// Preserves a running timer that spans midnight and clamps its
    /// contribution to today.
    static func rollOverForToday(_ snap: TimerSnapshot) -> TimerSnapshot {
        let todayStart = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        if snap.dayStart == todayStart { return snap }
        var fresh = snap
        fresh.dayStart = todayStart
        fresh.todayEntries = []
        if snap.isRunning {
            let startTs = Int64(snap.startedAt.timeIntervalSince1970)
            let effective = max(startTs, todayStart)
            let running = max(0, Int64(Date().timeIntervalSince1970) - effective)
            fresh.todayTotalSecs = running
        } else {
            fresh.todayTotalSecs = 0
        }
        return fresh
    }

    static func write(_ snap: TimerSnapshot) {
        guard let url = WidgetShared.snapshotURL() else { return }
        if let data = try? Self.encoder().encode(snap) {
            try? data.write(to: url)
        }
    }

    /// JSON coders pinned to Unix epoch so the wire format matches what
    /// older JSONSerialization-based writers (and the watchOS widget reader)
    /// produce. Default `deferredToDate` uses 2001-epoch, which silently
    /// produces Dates decades in the future when reading a 1970-epoch value.
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}

// MARK: - Category color (mirror TL.categoryColor)

enum WidgetPalette {
    static let accent  = Color(hue: 115/360, saturation: 0.55, brightness: 0.92)
    static let amber   = Color(hue: 28/360,  saturation: 0.55, brightness: 0.92)
    static let violet  = Color(hue: 265/360, saturation: 0.55, brightness: 0.92)
    static let sky     = Color(hue: 200/360, saturation: 0.55, brightness: 0.92)
    static let magenta = Color(hue: 330/360, saturation: 0.55, brightness: 0.92)

    static let all: [Color] = [accent, amber, violet, sky, magenta]

    static func color(for name: String) -> Color {
        guard !name.isEmpty else { return sky }
        switch name.lowercased() {
        case "deep work", "deep", "focus", "general": return accent
        case "meeting", "meetings", "meet":            return amber
        case "review", "pr":                           return violet
        case "admin", "inbox", "ops":                  return sky
        case "learning", "learn", "study":             return magenta
        default:
            let hash = name.lowercased().unicodeScalars.reduce(UInt32(0)) { $0 &* 31 &+ $1.value }
            return all[Int(hash % UInt32(all.count))]
        }
    }
}

// MARK: - Live Activity attributes

#if os(iOS)
struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var name: String
        var category: String
        var startedAt: Date
        var isRunning: Bool
    }

    var activityId: String = UUID().uuidString
}
#endif

// MARK: - Clock formatters

func widgetClockShort(_ secs: Int) -> String {
    let h = secs / 3600
    let m = (secs % 3600) / 60
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    if h > 0 { return "\(h)h" }
    if m > 0 { return "\(m)m" }
    return "\(secs)s"
}

func widgetClockHHMM(_ secs: Int) -> String {
    let h = secs / 3600
    let m = (secs % 3600) / 60
    return String(format: "%02d:%02d", h, m)
}

import Foundation
import SwiftUI
import ActivityKit

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

// MARK: - Snapshot

struct TimerSnapshot: Codable, Equatable {
    var isRunning: Bool
    var name: String
    var category: String
    var startedAt: Date
    var activeSecs: Int

    static let idle = TimerSnapshot(
        isRunning: false, name: "", category: "",
        startedAt: .distantPast, activeSecs: 0
    )

    static let preview = TimerSnapshot(
        isRunning: true, name: "Focus", category: "Coding",
        startedAt: .now.addingTimeInterval(-1234), activeSecs: 1234
    )

    static func load() -> TimerSnapshot {
        guard let url = WidgetShared.snapshotURL(),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let running = obj["isRunning"] as? Bool,
              running,
              let name = obj["name"] as? String,
              let category = obj["category"] as? String,
              let startedAtTs = obj["startedAt"] as? TimeInterval
        else {
            return .idle
        }
        let active = (obj["activeSecs"] as? Int) ?? 0
        return TimerSnapshot(
            isRunning: true,
            name: name,
            category: category,
            startedAt: Date(timeIntervalSince1970: startedAtTs),
            activeSecs: active
        )
    }

    static func write(_ snap: TimerSnapshot) {
        guard let url = WidgetShared.snapshotURL() else { return }
        let dict: [String: Any] = [
            "isRunning": snap.isRunning,
            "name": snap.name,
            "category": snap.category,
            "startedAt": snap.startedAt.timeIntervalSince1970,
            "activeSecs": snap.activeSecs,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: url)
        }
    }
}

// MARK: - Category color (must match GlassKit)

enum WidgetPalette {
    static let all: [Color] = [
        Color(red: 1.000, green: 0.357, blue: 0.290),  // ember
        Color(red: 1.000, green: 0.710, blue: 0.278),  // citrine
        Color(red: 0.184, green: 0.816, blue: 0.478),  // emerald
        Color(red: 0.310, green: 0.765, blue: 1.000),  // sky
        Color(red: 0.545, green: 0.424, blue: 1.000),  // iris
        Color(red: 1.000, green: 0.435, blue: 0.663),  // rose
        Color(red: 0.620, green: 0.690, blue: 0.780),  // mist
    ]

    static func color(for name: String) -> Color {
        guard !name.isEmpty else { return all[3] }
        let hash = name.lowercased().unicodeScalars.reduce(UInt32(0)) { acc, s in
            acc &* 31 &+ s.value
        }
        return all[Int(hash % UInt32(all.count))]
    }
}

// MARK: - Live Activity attributes

struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var name: String
        var category: String
        var startedAt: Date
        var isRunning: Bool
    }

    var activityId: String = UUID().uuidString
}

// MARK: - Clock formatter

func widgetClockShort(_ secs: Int) -> String {
    let h = secs / 3600
    let m = (secs % 3600) / 60
    if h > 0 { return String(format: "%dh %02dm", h, m) }
    return String(format: "%d:%02d", m, secs % 60)
}

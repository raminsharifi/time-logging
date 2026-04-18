import WidgetKit
import SwiftUI

// MARK: - Shared container

private enum WidgetStore {
    static let appGroup = "group.com.raminsharifi.TimeLogger"

    static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget_timer.json")
    }

    static func load() -> TimerSnapshot {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .idle }

        // If the snapshot was written on a previous day, don't carry its
        // aggregates into today — show idle until the phone republishes.
        let todayStart = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let snapDayStart = (obj["dayStart"] as? Int64) ?? 0
        let stale = snapDayStart != 0 && snapDayStart != todayStart

        let isRunning = (obj["isRunning"] as? Bool) ?? false
        guard isRunning,
              let name = obj["name"] as? String,
              let category = obj["category"] as? String,
              let startedAtTs = obj["startedAt"] as? TimeInterval
        else { return .idle }
        // A running timer that started before today is yesterday's state.
        if stale && Int64(startedAtTs) < todayStart { return .idle }
        let activeSecs = (obj["activeSecs"] as? Int) ?? 0
        let todayTotal = stale ? 0 : ((obj["todayTotalSecs"] as? Int64) ?? 0)
        return TimerSnapshot(
            isRunning: true,
            name: name,
            category: category,
            startedAt: Date(timeIntervalSince1970: startedAtTs),
            activeSecs: activeSecs,
            todayTotalSecs: todayTotal
        )
    }
}

struct TimerSnapshot {
    let isRunning: Bool
    let name: String?
    let category: String?
    let startedAt: Date?
    let activeSecs: Int
    let todayTotalSecs: Int64

    static let idle = TimerSnapshot(
        isRunning: false, name: nil, category: nil,
        startedAt: nil, activeSecs: 0, todayTotalSecs: 0
    )
    static let preview = TimerSnapshot(
        isRunning: true, name: "Spec: Sync",
        category: "Deep Work",
        startedAt: .now.addingTimeInterval(-1234),
        activeSecs: 1234, todayTotalSecs: 4 * 3600
    )
}

// MARK: - Design tokens (mirror TL.Palette)

private enum W {
    static let ink     = Color(red: 0.925, green: 0.925, blue: 0.925)
    static let mute    = Color(red: 0.541, green: 0.541, blue: 0.565)
    static let dim     = Color(red: 0.353, green: 0.353, blue: 0.376)
    static let line    = Color(red: 0.208, green: 0.208, blue: 0.227)
    static let accent  = Color(hue: 115/360, saturation: 0.55, brightness: 0.92)
    static let amber   = Color(hue: 28/360,  saturation: 0.55, brightness: 0.92)
    static let violet  = Color(hue: 265/360, saturation: 0.55, brightness: 0.92)
    static let sky     = Color(hue: 200/360, saturation: 0.55, brightness: 0.92)
    static let magenta = Color(hue: 330/360, saturation: 0.55, brightness: 0.92)
    static let palette: [Color] = [accent, amber, violet, sky, magenta]

    static func color(_ name: String?) -> Color {
        guard let name, !name.isEmpty else { return sky }
        switch name.lowercased() {
        case "deep work", "deep", "focus", "general": return accent
        case "meeting", "meetings", "meet":            return amber
        case "review", "pr":                           return violet
        case "admin", "inbox", "ops":                  return sky
        case "learning", "learn", "study":             return magenta
        default:
            var hash: UInt64 = 5381
            for b in name.utf8 { hash = hash &* 33 &+ UInt64(b) }
            return palette[Int(hash % UInt64(palette.count))]
        }
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Timeline

struct TimerEntry: TimelineEntry {
    let date: Date
    let snapshot: TimerSnapshot
}

struct TimerTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(date: .now, snapshot: .preview)
    }
    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        completion(TimerEntry(date: .now, snapshot: WidgetStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let snap = WidgetStore.load()
        let now = Date()
        let entry = TimerEntry(date: now, snapshot: snap)
        let reloadMinutes = snap.isRunning ? 5 : 30
        let cal = Calendar.current
        let paced = cal.date(byAdding: .minute, value: reloadMinutes, to: now) ?? now.addingTimeInterval(1800)
        // Force a reload at midnight so idle state shows up even if the
        // phone hasn't republished overnight.
        let nextMidnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? paced
        completion(Timeline(entries: [entry], policy: .after(min(paced, nextMidnight))))
    }
}

// MARK: - Views

struct TimerWidgetView: View {
    let entry: TimerEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:    circularView
        case .accessoryCorner:      cornerView
        case .accessoryRectangular: rectangularView
        case .accessoryInline:      inlineView
        default:                    rectangularView
        }
    }

    // Circular — progress toward 8h goal + "Hh Mm"
    @ViewBuilder
    private var circularView: some View {
        let goalSecs = Int64(8 * 3600)
        let pct = Double(entry.snapshot.todayTotalSecs) / Double(goalSecs)
        let clamped = max(0.001, min(1, pct))
        let tint = W.color(entry.snapshot.category)
        ZStack {
            Circle().stroke(W.line, lineWidth: 3)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            if entry.snapshot.isRunning, let start = entry.snapshot.startedAt {
                VStack(spacing: 0) {
                    Text(start, style: .timer)
                        .font(W.mono(9, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(W.ink)
                    Text("\(entry.snapshot.todayTotalSecs / 3600)H")
                        .font(W.mono(7))
                        .foregroundStyle(W.mute)
                }
                .padding(2)
            } else {
                Text("\(entry.snapshot.todayTotalSecs / 3600)H")
                    .font(W.mono(11, weight: .semibold))
                    .foregroundStyle(W.ink)
            }
        }
    }

    // Corner — a number on the curve + label
    @ViewBuilder
    private var cornerView: some View {
        if entry.snapshot.isRunning, let start = entry.snapshot.startedAt {
            Text(start, style: .timer)
                .font(W.mono(14, weight: .semibold))
                .monospacedDigit()
                .widgetLabel { Text(entry.snapshot.name ?? "Timer") }
        } else {
            Text("IDLE")
                .font(W.mono(12, weight: .semibold))
                .widgetLabel { Text("No timer") }
        }
    }

    // Rectangular — tiny category bar + name + clock
    @ViewBuilder
    private var rectangularView: some View {
        let tint = W.color(entry.snapshot.category)
        if entry.snapshot.isRunning, let start = entry.snapshot.startedAt {
            HStack(spacing: 6) {
                Rectangle().fill(tint).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.snapshot.category?.uppercased() ?? "")
                        .font(W.mono(8, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    Text(entry.snapshot.name ?? "Timer")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(W.ink)
                        .lineLimit(1)
                    Text(start, style: .timer)
                        .font(W.mono(11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(W.ink)
                }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 6) {
                Rectangle().fill(W.mute).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("IDLE")
                        .font(W.mono(8, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(W.mute)
                    Text("No timer running")
                        .font(.system(size: 12))
                        .foregroundStyle(W.ink)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // Inline — compact text
    @ViewBuilder
    private var inlineView: some View {
        if entry.snapshot.isRunning,
           let name = entry.snapshot.name,
           let start = entry.snapshot.startedAt
        {
            Text("\(name) · \(start, style: .timer)")
        } else {
            Text("Timer · idle")
        }
    }
}

// MARK: - Widget configurations

struct TimeLoggerTimerWidget: Widget {
    let kind = "TimeLoggerTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimerTimelineProvider()) { entry in
            TimerWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Active Timer")
        .description("Shows the running timer in accessory families.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

@main
struct TimeLoggerWidgetBundle: WidgetBundle {
    var body: some Widget {
        TimeLoggerTimerWidget()
    }
}

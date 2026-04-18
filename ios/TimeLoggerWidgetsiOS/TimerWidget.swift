import WidgetKit
import SwiftUI

// MARK: - Timeline provider

struct TimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        completion(TimerEntry(date: .now, snapshot: TimerSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let snap = TimerSnapshot.load()
        let now = Date()
        var entries: [TimerEntry] = []

        let cal = Calendar.current
        let nextMidnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(3600)

        if snap.isRunning {
            for i in 0..<60 {
                let d = now.addingTimeInterval(Double(i) * 60)
                if d >= nextMidnight { break }
                entries.append(TimerEntry(date: d, snapshot: snap))
            }
            if entries.isEmpty {
                entries.append(TimerEntry(date: now, snapshot: snap))
            }
        } else {
            entries.append(TimerEntry(date: now, snapshot: snap))
        }

        // Append a post-midnight entry with a manually rolled-over snapshot so
        // the widget visually rolls over even if iOS delays calling
        // getTimeline at midnight.
        if nextMidnight > now {
            var rolled = snap
            rolled.dayStart = Int64(nextMidnight.timeIntervalSince1970)
            rolled.todayEntries = []
            rolled.todayTotalSecs = snap.isRunning ? 0 : 0
            entries.append(TimerEntry(date: nextMidnight, snapshot: rolled))
        }

        // Try to reload shortly after midnight (to pick up fresh main-app
        // data) or at the regular pacing interval, whichever comes first.
        let pacing: TimeInterval = snap.isRunning ? 3600 : 900
        let nextReload = min(now.addingTimeInterval(pacing),
                             nextMidnight.addingTimeInterval(60))
        completion(Timeline(entries: entries, policy: .after(nextReload)))
    }
}

struct TimerEntry: TimelineEntry {
    let date: Date
    let snapshot: TimerSnapshot
}

// MARK: - Shared primitives

/// Uppercase, tracked, mono label. Used for section captions and chrome.
struct WLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = WidgetTokens.mute

    init(_ text: String, size: CGFloat = 10, color: Color = WidgetTokens.mute) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(WidgetTokens.label(size))
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

/// A horizontally-laid 24h bar: past entries painted in category hue, the
/// active session overlaid, and a bright "now" marker.
struct WHorizon: View {
    let snapshot: TimerSnapshot
    var height: CGFloat = 36
    var showScale: Bool = false

    private let dayLen: Double = 24 * 3600

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(WidgetTokens.raised)

                    // Hour gridlines (every 6h)
                    ForEach([6, 12, 18], id: \.self) { h in
                        Rectangle()
                            .fill(WidgetTokens.line)
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                            .offset(x: geo.size.width * CGFloat(Double(h) / 24))
                    }

                    // Completed entries
                    ForEach(Array(snapshot.todayEntries.enumerated()), id: \.offset) { _, e in
                        let startPct = Double(e.startedAt - snapshot.dayStart) / dayLen
                        let widthPct = Double(e.endedAt - e.startedAt) / dayLen
                        Rectangle()
                            .fill(WidgetPalette.color(for: e.category))
                            .opacity(0.85)
                            .frame(width: max(1, geo.size.width * CGFloat(widthPct)),
                                   height: geo.size.height - 6)
                            .offset(x: geo.size.width * CGFloat(startPct), y: 3)
                    }

                    // Active timer. Clamp the start to the current day so a
                    // timer that crossed midnight renders from x=0 rather
                    // than spilling off the left edge.
                    if snapshot.isRunning {
                        let startTs = Int64(snapshot.startedAt.timeIntervalSince1970)
                        let nowTs = Int64(Date().timeIntervalSince1970)
                        let effectiveStart = max(startTs, snapshot.dayStart)
                        let startPct = max(0, Double(effectiveStart - snapshot.dayStart) / dayLen)
                        let widthPct = max(0, Double(nowTs - effectiveStart) / dayLen)
                        let color = WidgetPalette.color(for: snapshot.category)
                        Rectangle()
                            .fill(color)
                            .frame(width: max(1, geo.size.width * CGFloat(widthPct)),
                                   height: geo.size.height - 2)
                            .offset(x: geo.size.width * CGFloat(startPct), y: 1)
                    }

                    // Now marker
                    let nowPct = Double(Date().timeIntervalSince1970 - Double(snapshot.dayStart)) / dayLen
                    Rectangle()
                        .fill(WidgetTokens.ink)
                        .frame(width: 2, height: geo.size.height + 2)
                        .offset(x: max(0, geo.size.width * CGFloat(nowPct) - 1), y: -1)
                }
            }
            .frame(height: height)
            .overlay {
                Rectangle().strokeBorder(WidgetTokens.line, lineWidth: 1)
            }

            if showScale {
                HStack {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hr in
                        Text(String(format: "%02d", hr))
                            .font(WidgetTokens.mono(8))
                            .foregroundStyle(WidgetTokens.dim)
                        if hr != 24 { Spacer() }
                    }
                }
            }
        }
    }
}

/// Live pill that sits in widget headers.
struct WLivePill: View {
    var color: Color = WidgetTokens.accent

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("LIVE")
                .font(WidgetTokens.label(8))
                .tracking(1.2)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .overlay {
            RoundedRectangle(cornerRadius: 1)
                .strokeBorder(color.opacity(0.4), lineWidth: 1)
        }
    }
}

// MARK: - Widget views

struct TimerWidgetEntryView: View {
    var entry: TimerEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:      SmallActive(entry: entry)
            case .systemMedium:     MediumHorizon(entry: entry)
            case .systemLarge:      LargeToday(entry: entry)
            default:
                #if os(iOS)
                if family == .systemExtraLarge {
                    LargeToday(entry: entry)
                } else {
                    SmallActive(entry: entry)
                }
                #else
                SmallActive(entry: entry)
                #endif
            }
        }
        .containerBackground(for: .widget) { WidgetTokens.bg }
    }
}

// MARK: Small · active timer

private struct SmallActive: View {
    let entry: TimerEntry

    var body: some View {
        let snap = entry.snapshot
        let color = WidgetPalette.color(for: snap.category)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WLabel("Now", color: color)
                Spacer()
                if snap.isRunning {
                    WLivePill(color: color)
                } else {
                    WLabel("Idle", size: 9, color: WidgetTokens.mute)
                }
            }
            .padding(.bottom, 8)

            if snap.isRunning {
                Text(snap.startedAt, style: .timer)
                    .font(WidgetTokens.mono(30, weight: .semibold))
                    .foregroundStyle(WidgetTokens.ink)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.top, 2)

                Text(snap.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetTokens.ink)
                    .lineLimit(2)
                    .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer()
                    Text("NOTHING")
                        .font(WidgetTokens.mono(20, weight: .semibold))
                        .foregroundStyle(WidgetTokens.mute)
                    Text("RUNNING")
                        .font(WidgetTokens.mono(20, weight: .semibold))
                        .foregroundStyle(WidgetTokens.mute)
                    Spacer()
                }
            }

            Spacer(minLength: 0)

            WHorizon(snapshot: snap, height: 10)

            HStack {
                WLabel(snap.category.isEmpty ? "—" : snap.category, size: 8)
                Spacer()
                WLabel(widgetClockShort(Int(snap.todayTotalSecs)) + " today", size: 8)
            }
            .padding(.top, 6)
        }
        .padding(14)
    }
}

// MARK: Medium · horizon + active + top categories

private struct MediumHorizon: View {
    let entry: TimerEntry

    var body: some View {
        let snap = entry.snapshot
        let color = WidgetPalette.color(for: snap.category)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Rectangle().fill(color).frame(width: 6, height: 6)
                    WLabel("Today · 24h horizon", color: WidgetTokens.ink)
                }
                Spacer()
                if snap.isRunning {
                    WLivePill(color: color)
                } else {
                    WLabel(widgetClockShort(Int(snap.todayTotalSecs)), size: 10,
                           color: WidgetTokens.ink)
                }
            }
            .padding(.bottom, 10)

            WHorizon(snapshot: snap, height: 36, showScale: true)

            if snap.isRunning {
                HStack(spacing: 8) {
                    Rectangle().fill(color).frame(width: 6, height: 6)
                    Text(snap.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetTokens.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(snap.startedAt, style: .timer)
                        .font(WidgetTokens.mono(10, weight: .semibold))
                        .foregroundStyle(color)
                        .monospacedDigit()
                }
                .padding(.top, 10)
            }

            Spacer(minLength: 0)

            let top = Self.topCategories(snap: snap, limit: 3)
            if !top.isEmpty {
                Divider().background(WidgetTokens.line).padding(.bottom, 6)
                HStack(spacing: 12) {
                    ForEach(top, id: \.cat) { t in
                        HStack(spacing: 5) {
                            Rectangle()
                                .fill(WidgetPalette.color(for: t.cat))
                                .frame(width: 5, height: 5)
                            WLabel(shortCategory(t.cat), size: 9)
                            Text(widgetClockShort(Int(t.secs)))
                                .font(WidgetTokens.mono(9, weight: .semibold))
                                .foregroundStyle(WidgetTokens.ink)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
    }

    static func topCategories(snap: TimerSnapshot, limit: Int)
        -> [(cat: String, secs: Int64)]
    {
        var acc: [String: Int64] = [:]
        for e in snap.todayEntries { acc[e.category, default: 0] += e.activeSecs }
        if snap.isRunning {
            let running = max(0, Int64(Date().timeIntervalSince1970 - snap.startedAt.timeIntervalSince1970))
            acc[snap.category, default: 0] += running
        }
        return acc
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (cat: $0.key, secs: $0.value) }
    }
}

private func shortCategory(_ s: String) -> String {
    s.split(separator: " ").first.map { String($0) } ?? s
}

// MARK: Large · hero + horizon + stacked + recent sessions

private struct LargeToday: View {
    let entry: TimerEntry

    var body: some View {
        let snap = entry.snapshot
        let color = WidgetPalette.color(for: snap.category)
        let top = MediumHorizon.topCategories(snap: snap, limit: 4)
        let sumTop = max(top.reduce(0) { $0 + $1.secs }, 1)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    WLabel(Self.dateCaption(), size: 9, color: WidgetTokens.dim)
                        .tracking(1.6)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(widgetHourPart(Int(snap.todayTotalSecs)))
                            .font(WidgetTokens.mono(36, weight: .semibold))
                            .foregroundStyle(WidgetTokens.ink)
                        Text("H")
                            .font(WidgetTokens.mono(20, weight: .semibold))
                            .foregroundStyle(WidgetTokens.mute)
                        Text(widgetMinutePart(Int(snap.todayTotalSecs)))
                            .font(WidgetTokens.mono(36, weight: .semibold))
                            .foregroundStyle(WidgetTokens.ink)
                            .padding(.leading, 6)
                        Text("M")
                            .font(WidgetTokens.mono(20, weight: .semibold))
                            .foregroundStyle(WidgetTokens.mute)
                    }
                }
                Spacer()
                if snap.isRunning {
                    VStack(alignment: .trailing, spacing: 4) {
                        WLivePill(color: color)
                        Text(snap.startedAt, style: .timer)
                            .font(WidgetTokens.mono(18, weight: .semibold))
                            .foregroundStyle(WidgetTokens.ink)
                            .monospacedDigit()
                        WLabel("Active · \(shortCategory(snap.category))", size: 8, color: WidgetTokens.mute)
                    }
                }
            }
            .padding(.bottom, 14)

            WHorizon(snapshot: snap, height: 44, showScale: true)

            // Stacked 100% category bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(top, id: \.cat) { t in
                        Rectangle()
                            .fill(WidgetPalette.color(for: t.cat))
                            .frame(width: geo.size.width * CGFloat(Double(t.secs) / Double(sumTop)))
                    }
                }
            }
            .frame(height: 8)
            .overlay { Rectangle().strokeBorder(WidgetTokens.line, lineWidth: 1) }
            .padding(.top, 14)

            HStack(spacing: 14) {
                ForEach(top.prefix(4), id: \.cat) { t in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Rectangle()
                                .fill(WidgetPalette.color(for: t.cat))
                                .frame(width: 5, height: 5)
                            WLabel(shortCategory(t.cat), size: 8)
                        }
                        Text(widgetClockShort(Int(t.secs)))
                            .font(WidgetTokens.mono(12, weight: .semibold))
                            .foregroundStyle(WidgetTokens.ink)
                    }
                    Spacer()
                }
            }
            .padding(.top, 8)

            Divider().background(WidgetTokens.line).padding(.top, 12)

            WLabel("Recent sessions", size: 9, color: WidgetTokens.dim)
                .tracking(1.4)
                .padding(.top, 10)

            let recent = snap.todayEntries.sorted { $0.startedAt > $1.startedAt }.prefix(3)
            VStack(spacing: 6) {
                ForEach(Array(recent.enumerated()), id: \.offset) { _, e in
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(WidgetPalette.color(for: e.category))
                            .frame(width: 4, height: 4)
                        Text(e.category)
                            .font(.system(size: 11))
                            .foregroundStyle(WidgetTokens.ink)
                            .lineLimit(1)
                        Spacer()
                        Text(timeString(Int64(e.startedAt)))
                            .font(WidgetTokens.mono(10))
                            .foregroundStyle(WidgetTokens.mute)
                        Text(widgetClockShort(Int(e.activeSecs)))
                            .font(WidgetTokens.mono(10, weight: .semibold))
                            .foregroundStyle(WidgetTokens.ink)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private static func dateCaption() -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        let iso = Calendar(identifier: .iso8601).component(.weekOfYear, from: .now)
        return "\(df.string(from: .now).uppercased()) · W\(iso)"
    }

    private func timeString(_ ts: Int64) -> String {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}

// MARK: - Small helpers

private func widgetHourPart(_ secs: Int) -> String { String(secs / 3600) }
private func widgetMinutePart(_ secs: Int) -> String { String(format: "%02d", (secs % 3600) / 60) }

// MARK: - Widget configuration

struct TimerWidget: Widget {
    let kind = "TimeLoggerTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimerProvider()) { entry in
            TimerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today Horizon")
        .description("Your 24h timeline, today's total, and the active session.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

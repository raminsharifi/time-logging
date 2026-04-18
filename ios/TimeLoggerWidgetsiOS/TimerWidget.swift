import WidgetKit
import SwiftUI

// MARK: - Animation cycle

/// Timing for the zoom-in / hold / zoom-out / hold loop that rides on top of
/// the horizon bar. WidgetKit can't animate at 60fps inside a single entry,
/// so we pre-generate a dense timeline and let the system transition between
/// consecutive entries.
enum HorizonCycle {
    /// Seconds spent easing the window from 24h down to ±1h.
    static let zoomInDuration: TimeInterval = 3
    /// Seconds held at the zoomed-in ±1h window (seconds tick forward here).
    static let zoomedHoldDuration: TimeInterval = 30
    /// Seconds spent easing back out to the full 24h window.
    static let zoomOutDuration: TimeInterval = 3
    /// Seconds held at the 24h view before the next zoom-in.
    static let farHoldDuration: TimeInterval = 30

    static var totalDuration: TimeInterval {
        zoomInDuration + zoomedHoldDuration + zoomOutDuration + farHoldDuration
    }

    /// Returns progress (0 = far 24h view, 1 = zoomed ±1h view) for the given
    /// offset into a cycle. Smoothstep eased on the two transitions.
    static func zoom(at t: TimeInterval) -> Double {
        let zoomInEnd = zoomInDuration
        let holdEnd = zoomInEnd + zoomedHoldDuration
        let zoomOutEnd = holdEnd + zoomOutDuration
        if t < zoomInEnd {
            return smoothstep(from: 0, to: zoomInDuration, at: t)
        }
        if t < holdEnd {
            return 1
        }
        if t < zoomOutEnd {
            return 1 - smoothstep(from: 0, to: zoomOutDuration, at: t - holdEnd)
        }
        return 0
    }

    private static func smoothstep(from a: TimeInterval, to b: TimeInterval, at x: TimeInterval) -> Double {
        guard b > a else { return 0 }
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Timeline provider

struct TimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(date: .now, snapshot: .preview, zoom: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        completion(TimerEntry(date: .now, snapshot: TimerSnapshot.load(), zoom: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let snap = TimerSnapshot.load()
        let now = Date()

        let cal = Calendar.current
        let nextMidnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))
            ?? now.addingTimeInterval(3600)

        var entries: [TimerEntry] = []

        // Pre-generate one full zoom cycle. Denser sampling during the
        // transitions where the window is actually moving, sparser during
        // the two hold phases where only the "now" line advances.
        var t: TimeInterval = 0
        while t < HorizonCycle.totalDuration {
            let d = now.addingTimeInterval(t)
            if d >= nextMidnight { break }
            entries.append(TimerEntry(date: d, snapshot: snap, zoom: HorizonCycle.zoom(at: t)))
            t += isInTransition(t) ? 0.5 : 5
        }
        if entries.isEmpty {
            entries.append(TimerEntry(date: now, snapshot: snap, zoom: 0))
        }

        // Post-midnight rollover so the horizon visibly resets even if iOS
        // delays the reload call.
        if nextMidnight > now && nextMidnight < now.addingTimeInterval(HorizonCycle.totalDuration) {
            var rolled = snap
            rolled.dayStart = Int64(nextMidnight.timeIntervalSince1970)
            rolled.todayEntries = []
            rolled.todayTotalSecs = 0
            entries.append(TimerEntry(date: nextMidnight, snapshot: rolled, zoom: 0))
        }

        let cycleEnd = now.addingTimeInterval(HorizonCycle.totalDuration)
        let nextReload = min(cycleEnd, nextMidnight.addingTimeInterval(60))
        completion(Timeline(entries: entries, policy: .after(nextReload)))
    }

    private func isInTransition(_ t: TimeInterval) -> Bool {
        let zoomInEnd = HorizonCycle.zoomInDuration
        let holdEnd = zoomInEnd + HorizonCycle.zoomedHoldDuration
        let zoomOutEnd = holdEnd + HorizonCycle.zoomOutDuration
        return t < zoomInEnd || (t >= holdEnd && t < zoomOutEnd)
    }
}

struct TimerEntry: TimelineEntry {
    let date: Date
    let snapshot: TimerSnapshot
    /// 0 = full-day horizon; 1 = ±1h window centred on `date`. Interpolated
    /// by `HorizonCycle.zoom(at:)` between the two.
    let zoom: Double
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

/// A horizontally-laid horizon bar with an animated visible window. At
/// `zoom == 0` the bar covers the full 24h of today; at `zoom == 1` it
/// covers ±1h around the entry's date. Entries are clipped to the visible
/// window so the user sees the world zoom in and out over the loop.
struct WHorizon: View {
    let snapshot: TimerSnapshot
    let date: Date
    var height: CGFloat = 36
    var showScale: Bool = false
    var zoom: Double = 0

    var body: some View {
        let win = Self.window(snapshot: snapshot, date: date, zoom: zoom)
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(WidgetTokens.raised)

                    // Adaptive gridlines — density scales with window span.
                    ForEach(Self.ticks(windowStart: win.start, windowEnd: win.end), id: \.self) { tickTs in
                        let frac = (tickTs - win.start) / win.length
                        Rectangle()
                            .fill(WidgetTokens.line)
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                            .offset(x: geo.size.width * CGFloat(frac))
                    }

                    // Completed entries — clipped to the visible window.
                    ForEach(Array(snapshot.todayEntries.enumerated()), id: \.offset) { _, e in
                        let startTs = Double(e.startedAt)
                        let endTs = Double(e.endedAt)
                        if endTs > win.start && startTs < win.end {
                            let clippedStart = max(startTs, win.start)
                            let clippedEnd = min(endTs, win.end)
                            let startFrac = (clippedStart - win.start) / win.length
                            let widthFrac = (clippedEnd - clippedStart) / win.length
                            Rectangle()
                                .fill(WidgetPalette.color(for: e.category))
                                .opacity(0.85)
                                .frame(width: max(1, geo.size.width * CGFloat(widthFrac)),
                                       height: geo.size.height - 6)
                                .offset(x: geo.size.width * CGFloat(startFrac), y: 3)
                        }
                    }

                    // Active timer, clipped to the window so a midnight-spanning
                    // timer doesn't spill past the bar edges.
                    if snapshot.isRunning {
                        let startTs = snapshot.startedAt.timeIntervalSince1970
                        let nowTs = date.timeIntervalSince1970
                        if nowTs > win.start && startTs < win.end {
                            let clippedStart = max(startTs, win.start)
                            let clippedEnd = min(nowTs, win.end)
                            let startFrac = (clippedStart - win.start) / win.length
                            let widthFrac = (clippedEnd - clippedStart) / win.length
                            Rectangle()
                                .fill(WidgetPalette.color(for: snapshot.category))
                                .frame(width: max(1, geo.size.width * CGFloat(widthFrac)),
                                       height: geo.size.height - 2)
                                .offset(x: geo.size.width * CGFloat(startFrac), y: 1)
                        }
                    }

                    // Now marker — stays visible whenever the window contains
                    // the current moment.
                    let nowFrac = (date.timeIntervalSince1970 - win.start) / win.length
                    if nowFrac >= 0 && nowFrac <= 1 {
                        Rectangle()
                            .fill(WidgetTokens.ink)
                            .frame(width: 2, height: geo.size.height + 2)
                            .offset(x: max(0, geo.size.width * CGFloat(nowFrac) - 1), y: -1)
                    }
                }
            }
            .frame(height: height)
            .overlay {
                Rectangle().strokeBorder(WidgetTokens.line, lineWidth: 1)
            }

            if showScale {
                scaleRow(window: win)
            }
        }
    }

    @ViewBuilder
    private func scaleRow(window win: HorizonWindow) -> some View {
        let ticks = Self.ticks(windowStart: win.start, windowEnd: win.end)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                ForEach(ticks, id: \.self) { tickTs in
                    let frac = (tickTs - win.start) / win.length
                    Text(Self.label(for: tickTs, span: win.length))
                        .font(WidgetTokens.mono(8))
                        .foregroundStyle(WidgetTokens.dim)
                        .fixedSize()
                        .offset(x: geo.size.width * CGFloat(frac) - 10)
                }
            }
        }
        .frame(height: 10)
    }

    // MARK: Window math

    struct HorizonWindow {
        let start: Double
        let end: Double
        var length: Double { max(end - start, 1) }
    }

    static func window(snapshot: TimerSnapshot, date: Date, zoom: Double) -> HorizonWindow {
        let dayLen: Double = 24 * 3600
        let farStart = Double(snapshot.dayStart)
        let farEnd = farStart + dayLen
        let nearStart = date.timeIntervalSince1970 - 3600
        let nearEnd = date.timeIntervalSince1970 + 3600
        let clamped = max(0, min(1, zoom))
        let start = farStart + (nearStart - farStart) * clamped
        let end = farEnd + (nearEnd - farEnd) * clamped
        return HorizonWindow(start: start, end: end)
    }

    static func ticks(windowStart: Double, windowEnd: Double) -> [Double] {
        let span = max(windowEnd - windowStart, 1)
        let spacing: Double
        if span >= 12 * 3600 { spacing = 6 * 3600 }
        else if span >= 4 * 3600 { spacing = 3600 }
        else if span >= 1 * 3600 { spacing = 15 * 60 }
        else { spacing = 5 * 60 }
        let firstTick = ceil(windowStart / spacing) * spacing
        var ticks: [Double] = []
        var t = firstTick
        while t <= windowEnd + 0.0001 {
            ticks.append(t)
            t += spacing
        }
        return ticks
    }

    static func label(for ts: Double, span: Double) -> String {
        let df = DateFormatter()
        df.dateFormat = span >= 12 * 3600 ? "HH" : "HH:mm"
        return df.string(from: Date(timeIntervalSince1970: ts))
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

            WHorizon(snapshot: snap, date: entry.date, height: 10, zoom: entry.zoom)

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

            WHorizon(snapshot: snap, date: entry.date, height: 36, showScale: true, zoom: entry.zoom)

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

            WHorizon(snapshot: snap, date: entry.date, height: 44, showScale: true, zoom: entry.zoom)

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

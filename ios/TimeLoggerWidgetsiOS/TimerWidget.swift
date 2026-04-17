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

        if snap.isRunning {
            // Refresh every minute for an hour, then ask system to reload
            for i in 0..<60 {
                let d = now.addingTimeInterval(Double(i) * 60)
                entries.append(TimerEntry(date: d, snapshot: snap))
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
        } else {
            entries.append(TimerEntry(date: now, snapshot: snap))
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
        }
    }
}

struct TimerEntry: TimelineEntry {
    let date: Date
    let snapshot: TimerSnapshot
}

// MARK: - Widget views

struct TimerWidgetEntryView: View {
    var entry: TimerEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall: SmallView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        case .systemLarge: LargeView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

private struct SmallView: View {
    let entry: TimerEntry

    var body: some View {
        let tint = WidgetPalette.color(for: entry.snapshot.category)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(entry.snapshot.isRunning ? "RUNNING" : "IDLE")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if entry.snapshot.isRunning {
                Text(timerInterval: entry.snapshot.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(tint)
                Text(entry.snapshot.name)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Text(entry.snapshot.category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Spacer(minLength: 0)
                Text("No timer")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Tap to start")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [tint.opacity(0.25), tint.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct MediumView: View {
    let entry: TimerEntry

    var body: some View {
        let tint = WidgetPalette.color(for: entry.snapshot.category)
        HStack(spacing: 14) {
            MiniRing(tint: tint, running: entry.snapshot.isRunning)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.snapshot.isRunning ? "RUNNING" : "IDLE")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                if entry.snapshot.isRunning {
                    Text(timerInterval: entry.snapshot.startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(tint)
                    Text(entry.snapshot.name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(tint).frame(width: 6, height: 6)
                        Text(entry.snapshot.category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No timer running")
                        .font(.system(.headline, design: .rounded))
                    Text("Open TimeLogger to start")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [tint.opacity(0.2), tint.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct LargeView: View {
    let entry: TimerEntry

    var body: some View {
        let tint = WidgetPalette.color(for: entry.snapshot.category)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Circle().fill(tint).frame(width: 10, height: 10)
                Text(entry.snapshot.isRunning ? "RUNNING" : "IDLE")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("TimeLogger")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 16) {
                MiniRing(tint: tint, running: entry.snapshot.isRunning)
                    .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 4) {
                    if entry.snapshot.isRunning {
                        Text(timerInterval: entry.snapshot.startedAt...Date.distantFuture, countsDown: false)
                            .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                            .foregroundStyle(tint)
                        Text(entry.snapshot.name)
                            .font(.system(.headline, design: .rounded))
                            .lineLimit(1)
                        Text(entry.snapshot.category)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No timer")
                            .font(.system(.title2, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("Tap to open TimeLogger")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            if entry.snapshot.isRunning {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                        Text("Started \(entry.snapshot.startedAt, style: .time)")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())

                    Spacer()
                }
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [tint.opacity(0.22), tint.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct MiniRing: View {
    let tint: Color
    let running: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: running ? 0.75 : 0.05)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [tint, tint.opacity(0.6), tint]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: running ? "timer" : "pause")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Widget

struct TimerWidget: Widget {
    let kind = "TimeLoggerTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimerProvider()) { entry in
            TimerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Active Timer")
        .description("See your running timer at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

import WidgetKit
import SwiftUI

// MARK: - Shared container

/// Reads the `widget_timer.json` snapshot that the main app writes on every
/// timer mutation (see `updateWidget()` in TimerView.swift).
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
        else {
            return .idle
        }

        let isRunning = (obj["isRunning"] as? Bool) ?? false
        guard isRunning,
              let name = obj["name"] as? String,
              let category = obj["category"] as? String,
              let startedAtTs = obj["startedAt"] as? TimeInterval
        else {
            return .idle
        }
        let activeSecs = (obj["activeSecs"] as? Int) ?? 0
        return TimerSnapshot(
            isRunning: true,
            name: name,
            category: category,
            startedAt: Date(timeIntervalSince1970: startedAtTs),
            activeSecs: activeSecs
        )
    }
}

struct TimerSnapshot {
    let isRunning: Bool
    let name: String?
    let category: String?
    let startedAt: Date?
    let activeSecs: Int

    static let idle = TimerSnapshot(isRunning: false, name: nil, category: nil, startedAt: nil, activeSecs: 0)
    static let preview = TimerSnapshot(
        isRunning: true, name: "Focus", category: "Coding",
        startedAt: .now.addingTimeInterval(-1234), activeSecs: 1234
    )
}

// MARK: - Category palette (matches GlassKit)

private enum W {
    static let palette: [Color] = [
        Color(red: 1.00, green: 0.36, blue: 0.29),  // ember
        Color(red: 1.00, green: 0.71, blue: 0.28),  // citrine
        Color(red: 0.19, green: 0.82, blue: 0.48),  // emerald
        Color(red: 0.31, green: 0.76, blue: 1.00),  // sky
        Color(red: 0.55, green: 0.42, blue: 1.00),  // iris
        Color(red: 1.00, green: 0.44, blue: 0.66),  // rose
        Color(red: 0.78, green: 0.80, blue: 0.90),  // mist
    ]

    static func categoryColor(_ name: String?) -> Color {
        guard let name, !name.isEmpty else { return palette[3] }
        var hash: UInt64 = 5381
        for b in name.utf8 { hash = hash &* 33 &+ UInt64(b) }
        return palette[Int(hash % UInt64(palette.count))]
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
        let entry = TimerEntry(date: .now, snapshot: snap)
        // If running, use Date arithmetic on startedAt to tick without reloading.
        // Reload every 5 minutes to pick up any drift / external changes.
        let reloadMinutes = snap.isRunning ? 5 : 30
        let next = Calendar.current.date(byAdding: .minute, value: reloadMinutes, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Shared clock formatter

private func clockShort(_ secs: Int) -> String {
    let h = secs / 3600
    let m = (secs % 3600) / 60
    if h > 0 { return String(format: "%d:%02d", h, m) }
    return String(format: "%d:%02d", m, secs % 60)
}

// MARK: - Mini ring

private struct MiniRing<Content: View>: View {
    let tint: Color
    let lineWidth: CGFloat
    let content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.78)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [tint.opacity(0.9), tint, tint.opacity(0.6)]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            content()
        }
    }
}

// MARK: - Views

struct TimerWidgetView: View {
    let entry: TimerEntry
    @Environment(\.widgetFamily) var family

    private var tint: Color { W.categoryColor(entry.snapshot.category) }

    var body: some View {
        switch family {
        case .accessoryCircular:    circularView
        case .accessoryCorner:      cornerView
        case .accessoryRectangular: rectangularView
        case .accessoryInline:      inlineView
        default:                    rectangularView
        }
    }

    // MARK: Circular

    @ViewBuilder
    private var circularView: some View {
        if entry.snapshot.isRunning, let start = entry.snapshot.startedAt {
            MiniRing(tint: tint, lineWidth: 3) {
                VStack(spacing: 0) {
                    Image(systemName: "timer")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(start, style: .timer)
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
                .padding(2)
            }
        } else {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                Image(systemName: "timer")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Corner

    @ViewBuilder
    private var cornerView: some View {
        if entry.snapshot.isRunning, let start = entry.snapshot.startedAt {
            Text(start, style: .timer)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .widgetLabel {
                    Text(entry.snapshot.name ?? "Timer")
                }
        } else {
            Image(systemName: "timer")
                .widgetLabel {
                    Text("Idle")
                }
        }
    }

    // MARK: Rectangular

    @ViewBuilder
    private var rectangularView: some View {
        if entry.snapshot.isRunning, let start = entry.snapshot.startedAt {
            HStack(spacing: 6) {
                MiniRing(tint: tint, lineWidth: 2.5) {
                    Image(systemName: "timer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.snapshot.name ?? "Timer")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    Text(start, style: .timer)
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                    if let cat = entry.snapshot.category {
                        Text(cat)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                Text("No timer running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Inline

    @ViewBuilder
    private var inlineView: some View {
        if entry.snapshot.isRunning,
           let name = entry.snapshot.name,
           let start = entry.snapshot.startedAt {
            Text("\(Image(systemName: "timer")) \(name) \(start, style: .timer)")
        } else {
            Text("\(Image(systemName: "timer")) Idle")
        }
    }
}

// MARK: - Widget configurations

struct TimeLoggerTimerWidget: Widget {
    let kind = "TimeLoggerTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimerTimelineProvider()) { entry in
            TimerWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            W.categoryColor(entry.snapshot.category).opacity(0.35),
                            .black.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Active Timer")
        .description("Shows the currently running timer.")
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

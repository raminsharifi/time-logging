import Foundation
import WidgetKit

/// Bridges the APIClient's live view of timers and today's entries to the
/// widget extension's App Group container, and nudges WidgetKit to reload.
enum WidgetBridge {
    /// Build a snapshot from the running timer (if any) and today's entries,
    /// write it to the shared container, then trigger a widget reload.
    @MainActor
    static func publish(runningTimer: TimerResponse?, todayEntries: [EntryResponse]) {
        let now = Int64(Date().timeIntervalSince1970)
        let dayStart = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)

        var total: Int64 = 0
        let snapEntries: [TodaySnapshotEntry] = todayEntries
            .filter { $0.started_at >= dayStart }
            .map { e in
                total += e.active_secs
                return TodaySnapshotEntry(
                    startedAt: e.started_at,
                    endedAt: e.ended_at,
                    activeSecs: e.active_secs,
                    category: e.category
                )
            }

        let snap: TimerSnapshot
        if let t = runningTimer {
            total += max(0, now - max(t.started_at, dayStart))
            snap = TimerSnapshot(
                isRunning: true,
                name: t.name,
                category: t.category,
                startedAt: Date(timeIntervalSince1970: TimeInterval(t.started_at)),
                activeSecs: Int(t.active_secs),
                dayStart: dayStart,
                todayTotalSecs: total,
                todayEntries: snapEntries
            )
        } else {
            snap = TimerSnapshot(
                isRunning: false,
                name: "",
                category: "",
                startedAt: .distantPast,
                activeSecs: 0,
                dayStart: dayStart,
                todayTotalSecs: total,
                todayEntries: snapEntries
            )
        }

        TimerSnapshot.write(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

import Foundation
import SwiftData
import WidgetKit
import ActivityKit

/// Bridges SwiftData timer/entry state to the widget extension's App Group
/// container and manages the Live Activity lifecycle.
///
/// Publishes two pieces of state:
///   • the currently-running timer (for the live clock)
///   • today's completed entries (for the 24h horizon bar)
enum WidgetBridge {
    /// Writes the current timer + today's entries to the App Group and reloads
    /// widgets. `modelContext` is optional: when nil we skip the day snapshot.
    static func publish(
        runningTimer: ActiveTimerLocal?,
        modelContext: ModelContext? = nil
    ) {
        let now = Int64(Date().timeIntervalSince1970)
        let dayStart = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)

        var todayEntries: [TodaySnapshotEntry] = []
        var todayTotal: Int64 = 0
        if let ctx = modelContext {
            let d = FetchDescriptor<TimeEntryLocal>(
                predicate: #Predicate { $0.startedAt >= dayStart },
                sortBy: [SortDescriptor(\.startedAt)]
            )
            if let entries = try? ctx.fetch(d) {
                todayEntries = entries.map { e in
                    TodaySnapshotEntry(
                        startedAt: e.startedAt,
                        endedAt: e.endedAt,
                        activeSecs: e.activeSecs,
                        category: e.category
                    )
                }
                todayTotal = entries.reduce(0) { $0 + $1.activeSecs }
            }
        }

        if let t = runningTimer {
            todayTotal += max(0, now - max(t.startedAt, dayStart))
        }

        let snap: TimerSnapshot
        if let t = runningTimer {
            snap = TimerSnapshot(
                isRunning: true,
                name: t.name,
                category: t.category,
                startedAt: Date(timeIntervalSince1970: TimeInterval(t.startedAt)),
                activeSecs: Int(now - t.startedAt),
                dayStart: dayStart,
                todayTotalSecs: todayTotal,
                todayEntries: todayEntries
            )
        } else {
            snap = TimerSnapshot(
                isRunning: false,
                name: "",
                category: "",
                startedAt: .distantPast,
                activeSecs: 0,
                dayStart: dayStart,
                todayTotalSecs: todayTotal,
                todayEntries: todayEntries
            )
        }

        TimerSnapshot.write(snap)
        WidgetCenter.shared.reloadAllTimelines()
        updateLiveActivity(runningTimer: runningTimer)
    }

    // MARK: - Live Activity

    private static var currentActivityId: String?

    private static func updateLiveActivity(runningTimer: ActiveTimerLocal?) {
        if #available(iOS 16.2, *) {
            if let t = runningTimer {
                let state = TimerActivityAttributes.ContentState(
                    name: t.name,
                    category: t.category,
                    startedAt: Date(timeIntervalSince1970: TimeInterval(t.startedAt)),
                    isRunning: true
                )
                if let id = currentActivityId,
                   let existing = Activity<TimerActivityAttributes>.activities.first(where: { $0.id == id }) {
                    Task { await existing.update(ActivityContent(state: state, staleDate: nil)) }
                } else {
                    let attrs = TimerActivityAttributes()
                    do {
                        let activity = try Activity.request(
                            attributes: attrs,
                            content: ActivityContent(state: state, staleDate: nil),
                            pushType: nil
                        )
                        currentActivityId = activity.id
                    } catch {
                        // Live Activities may be disabled; silent failure is fine.
                    }
                }
            } else {
                if let id = currentActivityId,
                   let existing = Activity<TimerActivityAttributes>.activities.first(where: { $0.id == id }) {
                    let finalState = TimerActivityAttributes.ContentState(
                        name: existing.content.state.name,
                        category: existing.content.state.category,
                        startedAt: existing.content.state.startedAt,
                        isRunning: false
                    )
                    Task {
                        await existing.end(
                            ActivityContent(state: finalState, staleDate: nil),
                            dismissalPolicy: .immediate
                        )
                    }
                    currentActivityId = nil
                }
            }
        } else {
            _ = runningTimer
        }
    }
}

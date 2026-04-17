import Foundation
import WidgetKit
import ActivityKit

/// Bridges SwiftData timer state to the widget extension's App Group container,
/// plus manages the Live Activity lifecycle.
enum WidgetBridge {
    static let appGroup = "group.com.raminsharifi.TimeLogger"
    static let snapshotFile = "widget_timer.json"

    private static func snapshotURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(snapshotFile)
    }

    /// Writes the current running-timer state to the App Group and reloads widgets.
    static func publish(runningTimer: ActiveTimerLocal?) {
        guard let url = snapshotURL() else {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let dict: [String: Any]
        if let t = runningTimer {
            dict = [
                "isRunning": true,
                "name": t.name,
                "category": t.category,
                "startedAt": TimeInterval(t.startedAt),
                "activeSecs": Int(Date().timeIntervalSince1970) - Int(t.startedAt),
            ]
        } else {
            dict = [
                "isRunning": false,
                "name": "",
                "category": "",
                "startedAt": 0,
                "activeSecs": 0,
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: url)
        }
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

// MARK: - TimerActivityAttributes (must match widget extension copy)

struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var name: String
        var category: String
        var startedAt: Date
        var isRunning: Bool
    }

    var activityId: String = UUID().uuidString
}

import AppIntents
import WidgetKit

// Note: These intents post darwin notifications and rewrite the App Group
// snapshot so the main app can pick them up when next foregrounded. They
// work as Siri / Shortcuts entry points; the main app does the real DB work.

struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Timer"
    static var description = IntentDescription("Start a new TimeLogger timer.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Name", default: "Focus")
    var name: String

    @Parameter(title: "Category", default: "General")
    var category: String

    func perform() async throws -> some IntentResult {
        let snap = TimerSnapshot(
            isRunning: true,
            name: name,
            category: category,
            startedAt: Date(),
            activeSecs: 0
        )
        TimerSnapshot.write(snap)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct StopTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Timer"
    static var description = IntentDescription("Stop the current running timer.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        TimerSnapshot.write(.idle)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct TogglePomodoroIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Pomodoro"
    static var description = IntentDescription("Toggle a 25-minute focus pomodoro.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let current = TimerSnapshot.load()
        if current.isRunning {
            TimerSnapshot.write(.idle)
        } else {
            TimerSnapshot.write(TimerSnapshot(
                isRunning: true,
                name: "Pomodoro",
                category: "Focus",
                startedAt: Date(),
                activeSecs: 0
            ))
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct TimeLoggerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start a timer in \(.applicationName)",
                "Start \(.applicationName)",
            ],
            shortTitle: "Start Timer",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopTimerIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Stop my timer in \(.applicationName)",
            ],
            shortTitle: "Stop Timer",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: TogglePomodoroIntent(),
            phrases: [
                "Start a pomodoro in \(.applicationName)",
                "Toggle pomodoro in \(.applicationName)",
            ],
            shortTitle: "Pomodoro",
            systemImageName: "timer"
        )
    }
}

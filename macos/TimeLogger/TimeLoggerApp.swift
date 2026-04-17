import SwiftUI

@main
struct TimeLoggerApp: App {
    @StateObject private var api = APIClient()
    @StateObject private var daemon = DaemonManager.shared
    @State private var hotkeysInstalled = false

    var body: some Scene {
        WindowGroup("TimeLogger", id: "main") {
            ContentView()
                .environmentObject(api)
                .environmentObject(daemon)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear {
                    daemon.registerIfNeeded()
                    api.startPolling()
                    if !hotkeysInstalled {
                        installHotkeys()
                        hotkeysInstalled = true
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 720)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(api)
                .environmentObject(daemon)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }

    private func installHotkeys() {
        HotkeyManager.shared.install(
            toggle: { [api] in
                Task { @MainActor in
                    if let running = api.timers.first(where: { $0.isRunning }) {
                        _ = try? await api.stopTimer(id: running.id)
                    } else if let paused = api.timers.first(where: { $0.isPaused }) {
                        _ = try? await api.resumeTimer(id: paused.id)
                    } else {
                        _ = try? await api.startTimer(name: "Focus", category: "General", todoId: nil)
                    }
                    await api.refreshTimers()
                }
            },
            pause: { [api] in
                Task { @MainActor in
                    if let running = api.timers.first(where: { $0.isRunning }) {
                        _ = try? await api.pauseTimer(id: running.id)
                    } else if let paused = api.timers.first(where: { $0.isPaused }) {
                        _ = try? await api.resumeTimer(id: paused.id)
                    }
                    await api.refreshTimers()
                }
            }
        )
    }
}

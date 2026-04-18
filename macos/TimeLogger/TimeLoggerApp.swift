import SwiftUI

@main
struct TimeLoggerApp: App {
    @StateObject private var identity = DeviceIdentity.shared
    @StateObject private var api = APIClient()
    @StateObject private var daemon = DaemonManager.shared
    @StateObject private var peers = PeerDiscovery()
    @StateObject private var selection = ServerSelection()
    @StateObject private var widgetPublisher = WidgetPublisher()
    @State private var hotkeysInstalled = false

    var body: some Scene {
        WindowGroup("TimeLogger", id: "main") {
            ContentView()
                .environmentObject(identity)
                .environmentObject(api)
                .environmentObject(daemon)
                .environmentObject(peers)
                .environmentObject(selection)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear {
                    daemon.registerIfNeeded()
                    api.configure(endpoint: selection.endpoint)
                    api.startPolling()
                    peers.start()
                    widgetPublisher.start(api: api)
                    if !hotkeysInstalled {
                        installHotkeys()
                        hotkeysInstalled = true
                    }
                }
                .onChange(of: selection.endpoint) { _, newValue in
                    api.configure(endpoint: newValue)
                }
                .onChange(of: api.timers) { _, _ in
                    widgetPublisher.refresh(api: api)
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 720)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(identity)
                .environmentObject(api)
                .environmentObject(daemon)
                .environmentObject(peers)
                .environmentObject(selection)
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

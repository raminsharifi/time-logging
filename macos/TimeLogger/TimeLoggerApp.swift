import SwiftUI

extension Notification.Name {
    static let tlNewTimer = Notification.Name("tl.newTimer")
    static let tlToggleTimer = Notification.Name("tl.toggleTimer")
    static let tlPauseResume = Notification.Name("tl.pauseResume")
    static let tlStopTimer = Notification.Name("tl.stopTimer")
}

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
                .onReceive(NotificationCenter.default.publisher(for: .tlToggleTimer)) { _ in
                    toggleAction()
                }
                .onReceive(NotificationCenter.default.publisher(for: .tlPauseResume)) { _ in
                    pauseAction()
                }
                .onReceive(NotificationCenter.default.publisher(for: .tlStopTimer)) { _ in
                    stopAction()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Timer…") {
                    NotificationCenter.default.post(name: .tlNewTimer, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu("Timer") {
                Button("Start / Stop") {
                    NotificationCenter.default.post(name: .tlToggleTimer, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Pause / Resume") {
                    NotificationCenter.default.post(name: .tlPauseResume, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Stop") {
                    NotificationCenter.default.post(name: .tlStopTimer, object: nil)
                }
                .keyboardShortcut(".", modifiers: [.command])
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
        HotkeyManager.shared.install(toggle: { toggleAction() }, pause: { pauseAction() })
    }

    @MainActor
    private func toggleAction() {
        Task {
            if let running = api.timers.first(where: { $0.isRunning }) {
                _ = try? await api.stopTimer(id: running.id)
            } else if let paused = api.timers.first(where: { $0.isPaused }) {
                _ = try? await api.resumeTimer(id: paused.id)
            } else {
                _ = try? await api.startTimer(name: "Focus", category: "General", todoId: nil)
            }
            await api.refreshTimers()
        }
    }

    @MainActor
    private func pauseAction() {
        Task {
            if let running = api.timers.first(where: { $0.isRunning }) {
                _ = try? await api.pauseTimer(id: running.id)
            } else if let paused = api.timers.first(where: { $0.isPaused }) {
                _ = try? await api.resumeTimer(id: paused.id)
            }
            await api.refreshTimers()
        }
    }

    @MainActor
    private func stopAction() {
        Task {
            if let running = api.timers.first(where: { $0.isRunning }) {
                _ = try? await api.stopTimer(id: running.id)
                await api.refreshTimers()
            }
        }
    }
}

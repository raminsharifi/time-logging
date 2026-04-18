import Foundation

/// Periodically fetches today's entries from the daemon and mirrors the live
/// timer state into the widget extension's App Group container.
@MainActor
final class WidgetPublisher: ObservableObject {
    private var refreshTask: Task<Void, Never>?
    private var cachedEntries: [EntryResponse] = []
    private var lastEntriesFetch: Date = .distantPast
    private weak var api: APIClient?

    /// Call once at app launch. Starts a 60-second loop that keeps today's
    /// entries fresh even when no timer state changes fire.
    func start(api: APIClient) {
        guard refreshTask == nil else { return }
        self.api = api
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Publish immediately with the cached entries and the current running
    /// timer. Call whenever `api.timers` changes to keep the widget in sync.
    func refresh(api: APIClient) {
        self.api = api
        let running = api.timers.first(where: { $0.isRunning })
        WidgetBridge.publish(runningTimer: running, todayEntries: cachedEntries)
    }

    private func tick() async {
        guard let api else { return }
        // Refresh the cached entries at most once per tick. They change less
        // often than timer state, so this is plenty.
        if let entries = try? await api.getEntries(today: true) {
            cachedEntries = entries
            lastEntriesFetch = Date()
        }
        let running = api.timers.first(where: { $0.isRunning })
        WidgetBridge.publish(runningTimer: running, todayEntries: cachedEntries)
    }

    deinit {
        refreshTask?.cancel()
    }
}

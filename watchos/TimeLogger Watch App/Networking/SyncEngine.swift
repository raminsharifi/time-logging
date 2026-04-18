import Foundation
import SwiftData
import WidgetKit

enum SyncTransport: String {
    case ble = "BLE"
    case wifi = "Wi-Fi"
    case icloud = "iCloud"
    case offline = "Offline"
}

@Observable
final class SyncEngine {
    let apiClient: APIClient
    let bleManager: BLEManager
    var isOnline = false
    var transport: SyncTransport = .offline
    var lastSyncDate: Date?
    private var syncTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    init(apiClient: APIClient, bleManager: BLEManager) {
        self.apiClient = apiClient
        self.bleManager = bleManager
    }

    @MainActor
    func checkConnection() async {
        if bleManager.isConnected {
            isOnline = true
            transport = .ble
            return
        }
        if await apiClient.ping() {
            isOnline = true
            transport = .wifi
            return
        }
        isOnline = false
        transport = .offline
    }

    /// Best-available transport for a single sync round-trip.
    @MainActor
    private func bestTransport() async -> SyncTransport {
        if bleManager.isConnected {
            return .ble
        }
        if await apiClient.ping() {
            return .wifi
        }
        return .offline
    }

    func scheduleSyncAfterMutation() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await syncIfReachable(modelContainer: nil)
        }
    }

    @MainActor
    func syncIfReachable(modelContainer: ModelContainer?) async {
        guard let container = modelContainer else { return }

        let chosen = await bestTransport()
        guard chosen != .offline else {
            isOnline = false
            transport = .offline
            return
        }
        isOnline = true
        transport = chosen

        let context = container.mainContext

        do {
            let metadataDescriptor = FetchDescriptor<SyncMetadata>()
            var metadata = try context.fetch(metadataDescriptor).first
            if metadata == nil {
                let m = SyncMetadata()
                context.insert(m)
                try context.save()
                metadata = m
            }
            guard let meta = metadata else { return }

            let lastSyncTs = Int64(meta.lastSyncTimestamp.timeIntervalSince1970)

            let changes = try gatherLocalChanges(context: context)

            let request = APISyncRequest(
                client_id: meta.clientId,
                last_sync_ts: lastSyncTs,
                changes: changes
            )

            let response: APISyncResponse
            switch chosen {
            case .ble:
                response = try await bleManager.sync(request)
            case .wifi, .icloud:
                response = try await apiClient.sync(request)
            case .offline:
                return
            }

            try applyServerChanges(response: response, context: context)
            try applyIdMappings(response.id_mappings, context: context)
            try clearNeedsSyncFlags(context: context)

            meta.lastSyncTimestamp = Date(timeIntervalSince1970: Double(response.new_sync_ts))
            try context.save()
            lastSyncDate = .now

            // Update widget with current running timer state
            let runningDesc = FetchDescriptor<ActiveTimerLocal>(
                predicate: #Predicate { $0.state == "running" }
            )
            let runningTimer = try? context.fetch(runningDesc).first
            updateWidget(running: runningTimer)
        } catch {
        }
    }

    // MARK: - Gather local changes

    private func gatherLocalChanges(context: ModelContext) throws -> APISyncChanges {
        let timerDescriptor = FetchDescriptor<ActiveTimerLocal>(
            predicate: #Predicate { $0.needsSync }
        )
        let timers = try context.fetch(timerDescriptor)

        let entryDescriptor = FetchDescriptor<TimeEntryLocal>(
            predicate: #Predicate { $0.needsSync }
        )
        let entries = try context.fetch(entryDescriptor)

        let todoDescriptor = FetchDescriptor<TodoItemLocal>(
            predicate: #Predicate { $0.needsSync }
        )
        let todos = try context.fetch(todoDescriptor)

        let deletionDescriptor = FetchDescriptor<PendingDeletion>()
        let deletions = try context.fetch(deletionDescriptor)

        return APISyncChanges(
            active_timers: timers.map { t in
                APISyncTimer(
                    server_id: t.serverId,
                    local_id: t.localId.uuidString,
                    name: t.name,
                    category: t.category,
                    started_at: Int64(t.startedAt.timeIntervalSince1970),
                    state: t.state,
                    breaks: t.breaks.map { APIBreak(start_ts: $0.startTs, end_ts: $0.endTs) },
                    todo_id: t.todoId,
                    last_modified: Int64(t.lastModified.timeIntervalSince1970)
                )
            },
            time_entries: entries.map { e in
                APISyncEntry(
                    server_id: e.serverId,
                    local_id: e.localId.uuidString,
                    name: e.name,
                    category: e.category,
                    started_at: Int64(e.startedAt.timeIntervalSince1970),
                    ended_at: Int64(e.endedAt.timeIntervalSince1970),
                    active_secs: Int64(e.activeSecs),
                    breaks: e.breaks.map { APIBreak(start_ts: $0.startTs, end_ts: $0.endTs) },
                    todo_id: e.todoId,
                    last_modified: Int64(e.lastModified.timeIntervalSince1970)
                )
            },
            todos: todos.map { t in
                APISyncTodo(
                    server_id: t.serverId,
                    local_id: t.localId.uuidString,
                    text: t.text,
                    done: t.done,
                    created_at: Int64(t.createdAt.timeIntervalSince1970),
                    last_modified: Int64(t.lastModified.timeIntervalSince1970)
                )
            },
            deletions: deletions.map { d in
                APISyncDeletion(
                    table_name: d.tableName,
                    record_id: d.recordServerId,
                    deleted_at: Int64(d.deletedAt.timeIntervalSince1970)
                )
            }
        )
    }

    // MARK: - Apply server changes

    private func applyServerChanges(response: APISyncResponse, context: ModelContext) throws {
        // Apply timer changes from server
        for st in response.server_changes.active_timers {
            guard let serverId = st.server_id else { continue }
            let descriptor = FetchDescriptor<ActiveTimerLocal>(
                predicate: #Predicate<ActiveTimerLocal> { t in t.serverId == serverId }
            )
            let existing = try context.fetch(descriptor).first

            if let existing {
                if st.last_modified > Int64(existing.lastModified.timeIntervalSince1970) {
                    existing.name = st.name
                    existing.category = st.category
                    existing.startedAt = Date(timeIntervalSince1970: Double(st.started_at))
                    existing.state = st.state
                    existing.breaks = st.breaks.map { BreakPeriod(startTs: $0.start_ts, endTs: $0.end_ts) }
                    existing.todoId = st.todo_id
                    existing.lastModified = Date(timeIntervalSince1970: Double(st.last_modified))
                    existing.needsSync = false
                }
            } else {
                let timer = ActiveTimerLocal(
                    serverId: serverId,
                    name: st.name,
                    category: st.category,
                    startedAt: Date(timeIntervalSince1970: Double(st.started_at)),
                    state: st.state,
                    breaks: st.breaks.map { BreakPeriod(startTs: $0.start_ts, endTs: $0.end_ts) },
                    todoId: st.todo_id
                )
                timer.lastModified = Date(timeIntervalSince1970: Double(st.last_modified))
                timer.needsSync = false
                context.insert(timer)
            }
        }

        // Apply entry changes from server
        for se in response.server_changes.time_entries {
            guard let serverId = se.server_id else { continue }
            let descriptor = FetchDescriptor<TimeEntryLocal>(
                predicate: #Predicate<TimeEntryLocal> { e in e.serverId == serverId }
            )
            let existing = try context.fetch(descriptor).first

            if let existing {
                if se.last_modified > Int64(existing.lastModified.timeIntervalSince1970) {
                    existing.name = se.name
                    existing.category = se.category
                    existing.startedAt = Date(timeIntervalSince1970: Double(se.started_at))
                    existing.endedAt = Date(timeIntervalSince1970: Double(se.ended_at))
                    existing.activeSecs = Int(se.active_secs)
                    existing.breaks = se.breaks.map { BreakPeriod(startTs: $0.start_ts, endTs: $0.end_ts) }
                    existing.todoId = se.todo_id
                    existing.lastModified = Date(timeIntervalSince1970: Double(se.last_modified))
                    existing.needsSync = false
                }
            } else {
                let entry = TimeEntryLocal(
                    serverId: serverId,
                    name: se.name,
                    category: se.category,
                    startedAt: Date(timeIntervalSince1970: Double(se.started_at)),
                    endedAt: Date(timeIntervalSince1970: Double(se.ended_at)),
                    activeSecs: Int(se.active_secs),
                    breaks: se.breaks.map { BreakPeriod(startTs: $0.start_ts, endTs: $0.end_ts) },
                    todoId: se.todo_id
                )
                entry.lastModified = Date(timeIntervalSince1970: Double(se.last_modified))
                entry.needsSync = false
                context.insert(entry)
            }
        }

        // Apply todo changes from server
        for stodo in response.server_changes.todos {
            guard let serverId = stodo.server_id else { continue }
            let descriptor = FetchDescriptor<TodoItemLocal>(
                predicate: #Predicate<TodoItemLocal> { t in t.serverId == serverId }
            )
            let existing = try context.fetch(descriptor).first

            if let existing {
                if stodo.last_modified > Int64(existing.lastModified.timeIntervalSince1970) {
                    existing.text = stodo.text
                    existing.done = stodo.done
                    existing.lastModified = Date(timeIntervalSince1970: Double(stodo.last_modified))
                    existing.needsSync = false
                }
            } else {
                let todo = TodoItemLocal(
                    serverId: serverId,
                    text: stodo.text,
                    done: stodo.done,
                    createdAt: Date(timeIntervalSince1970: Double(stodo.created_at))
                )
                todo.lastModified = Date(timeIntervalSince1970: Double(stodo.last_modified))
                todo.needsSync = false
                context.insert(todo)
            }
        }

        // Apply deletions from server
        for del in response.server_changes.deletions {
            let serverId = del.record_id
            switch del.table_name {
            case "active_timers":
                let desc = FetchDescriptor<ActiveTimerLocal>(
                    predicate: #Predicate<ActiveTimerLocal> { t in t.serverId == serverId }
                )
                if let found = try context.fetch(desc).first {
                    context.delete(found)
                }
            case "time_entries":
                let desc = FetchDescriptor<TimeEntryLocal>(
                    predicate: #Predicate<TimeEntryLocal> { e in e.serverId == serverId }
                )
                if let found = try context.fetch(desc).first {
                    context.delete(found)
                }
            case "todos":
                let desc = FetchDescriptor<TodoItemLocal>(
                    predicate: #Predicate<TodoItemLocal> { t in t.serverId == serverId }
                )
                if let found = try context.fetch(desc).first {
                    context.delete(found)
                }
            default:
                break
            }
        }

        try context.save()
    }

    // MARK: - Apply ID mappings

    private func applyIdMappings(_ mappings: [APIIdMapping], context: ModelContext) throws {
        for mapping in mappings {
            guard let uuid = UUID(uuidString: mapping.local_id) else { continue }
            switch mapping.table_name {
            case "active_timers":
                let desc = FetchDescriptor<ActiveTimerLocal>(
                    predicate: #Predicate<ActiveTimerLocal> { t in t.localId == uuid }
                )
                if let found = try context.fetch(desc).first {
                    found.serverId = mapping.server_id
                }
            case "time_entries":
                let desc = FetchDescriptor<TimeEntryLocal>(
                    predicate: #Predicate<TimeEntryLocal> { e in e.localId == uuid }
                )
                if let found = try context.fetch(desc).first {
                    found.serverId = mapping.server_id
                }
            case "todos":
                let desc = FetchDescriptor<TodoItemLocal>(
                    predicate: #Predicate<TodoItemLocal> { t in t.localId == uuid }
                )
                if let found = try context.fetch(desc).first {
                    found.serverId = mapping.server_id
                }
            default:
                break
            }
        }
        try context.save()
    }

    // MARK: - Clear sync flags

    private func clearNeedsSyncFlags(context: ModelContext) throws {
        let timerDesc = FetchDescriptor<ActiveTimerLocal>(predicate: #Predicate { $0.needsSync })
        for t in try context.fetch(timerDesc) { t.needsSync = false }

        let entryDesc = FetchDescriptor<TimeEntryLocal>(predicate: #Predicate { $0.needsSync })
        for e in try context.fetch(entryDesc) { e.needsSync = false }

        let todoDesc = FetchDescriptor<TodoItemLocal>(predicate: #Predicate { $0.needsSync })
        for t in try context.fetch(todoDesc) { t.needsSync = false }

        let delDesc = FetchDescriptor<PendingDeletion>()
        for d in try context.fetch(delDesc) { context.delete(d) }

        try context.save()
    }
}

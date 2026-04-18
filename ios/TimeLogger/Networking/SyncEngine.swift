import Foundation
import SwiftData
import CloudKit

/// Active data transport — used by the UI to show which path sync is using.
enum SyncTransport: String {
    case ble = "BLE"
    case wifi = "Wi-Fi"
    case icloud = "iCloud"
    case offline = "Offline"
}

@MainActor
final class SyncEngine: ObservableObject {
    let bleManager: BLEManager
    let cloudKit: CloudKitManager
    let http: HTTPClient
    private var modelContext: ModelContext?
    private var syncDebounceTask: Task<Void, Never>?

    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    /// Mesh-friendly: reacting within half a second after any mutation so
    /// every device picks up start/pause/stop/break events near-instantly.
    /// The CloudKit + BLE peripheral + Wi-Fi paths then propagate outward.
    private let mutationDebounceNanos: UInt64 = 500_000_000

    /// True when any remote transport (Wi-Fi, BLE, or iCloud) is reachable.
    var isOnline: Bool {
        http.isReachable || bleManager.isConnected || cloudKit.iCloudAvailable
    }

    init(bleManager: BLEManager, cloudKit: CloudKitManager, http: HTTPClient) {
        self.bleManager = bleManager
        self.cloudKit = cloudKit
        self.http = http
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func scheduleSyncAfterMutation() {
        syncDebounceTask?.cancel()
        syncDebounceTask = Task {
            try? await Task.sleep(nanoseconds: mutationDebounceNanos)
            guard !Task.isCancelled else { return }
            await performSync()
        }
    }

    /// Main sync: fan out over every available transport so events ripple
    /// through the whole device mesh. Wi-Fi (direct HTTP to a chosen Mac) is
    /// fastest when the user has selected a peer; BLE is fastest when the
    /// Mac is nearby; iCloud is always-on and covers the rest.
    func performSync() async {
        syncError = nil

        if cloudKit.iCloudAvailable {
            await performCloudKitSync()
        }

        if http.baseURL != nil {
            await performHTTPSync()
        }

        if bleManager.isConnected {
            await performBLESync()
        }

        if !isOnline {
            syncError = "No sync transport available"
        }
    }

    // MARK: - Wi-Fi HTTP Sync

    private func performHTTPSync() async {
        guard let context = modelContext else { return }
        do {
            let meta = try getOrCreateSyncMetadata(context)
            let request = APISyncRequest(
                client_id: meta.clientId,
                last_sync_ts: meta.lastSyncTimestamp,
                changes: APISyncChanges(
                    active_timers: gatherTimerChanges(context),
                    time_entries: gatherEntryChanges(context),
                    todos: gatherTodoChanges(context),
                    deletions: gatherDeletions(context)
                )
            )
            let response = try await http.sync(request)

            applyBLEServerTimers(response.server_changes.active_timers, context: context)
            applyBLEServerEntries(response.server_changes.time_entries, context: context)
            applyBLEServerTodos(response.server_changes.todos, context: context)
            applyBLEServerDeletions(response.server_changes.deletions, context: context)

            for mapping in response.id_mappings {
                applyIdMapping(mapping, context: context)
            }

            clearSyncFlags(context)
            clearPendingDeletions(context)
            meta.lastSyncTimestamp = response.new_sync_ts
            try context.save()
            lastSyncDate = Date()
        } catch {
            if syncError == nil {
                syncError = "Wi-Fi: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - CloudKit Sync

    private func performCloudKitSync() async {
        guard let context = modelContext else { return }

        do {
            // 1. Push local changes to CloudKit
            try await pushToCloudKit(context)

            // 2. Fetch remote changes from CloudKit
            let changes = try await cloudKit.fetchChanges()

            // 3. Apply remote changes locally
            applyCloudKitChanges(changes, context: context)

            try context.save()
            lastSyncDate = Date()
        } catch {
            syncError = "iCloud: \(error.localizedDescription)"
        }
    }

    private func pushToCloudKit(_ context: ModelContext) async throws {
        // Push timers that have server IDs (synced with Mac)
        let timerDescriptor = FetchDescriptor<ActiveTimerLocal>(
            predicate: #Predicate { $0.needsSync == true }
        )
        let timers = (try? context.fetch(timerDescriptor)) ?? []
        let timerData = timers.compactMap { t -> (serverId: Int, name: String, category: String, startedAt: Int64, state: String, breaksJSON: String, todoId: Int?, lastModified: Int64)? in
            guard let sid = t.serverId else { return nil }
            let breaksJSON = String(data: t.breaksData, encoding: .utf8) ?? "[]"
            return (sid, t.name, t.category, t.startedAt, t.state, breaksJSON, t.todoId, t.lastModified)
        }
        if !timerData.isEmpty {
            try await cloudKit.pushTimers(timerData)
        }

        // Push entries
        let entryDescriptor = FetchDescriptor<TimeEntryLocal>(
            predicate: #Predicate { $0.needsSync == true }
        )
        let entries = (try? context.fetch(entryDescriptor)) ?? []
        let entryData = entries.compactMap { e -> (serverId: Int, name: String, category: String, startedAt: Int64, endedAt: Int64, activeSecs: Int64, breaksJSON: String, todoId: Int?, lastModified: Int64)? in
            guard let sid = e.serverId else { return nil }
            let breaksJSON = String(data: e.breaksData, encoding: .utf8) ?? "[]"
            return (sid, e.name, e.category, e.startedAt, e.endedAt, e.activeSecs, breaksJSON, e.todoId, e.lastModified)
        }
        if !entryData.isEmpty {
            try await cloudKit.pushEntries(entryData)
        }

        // Push todos
        let todoDescriptor = FetchDescriptor<TodoItemLocal>(
            predicate: #Predicate { $0.needsSync == true }
        )
        let todos = (try? context.fetch(todoDescriptor)) ?? []
        let todoData = todos.compactMap { t -> (serverId: Int, text: String, done: Bool, createdAt: Int64, lastModified: Int64)? in
            guard let sid = t.serverId else { return nil }
            return (sid, t.text, t.done, t.createdAt, t.lastModified)
        }
        if !todoData.isEmpty {
            try await cloudKit.pushTodos(todoData)
        }

        // Push deletions
        let delDescriptor = FetchDescriptor<PendingDeletion>()
        let deletions = (try? context.fetch(delDescriptor)) ?? []
        let delData = deletions.map { (tableName: $0.tableName, recordId: $0.recordServerId) }
        if !delData.isEmpty {
            try await cloudKit.pushDeletions(delData)
        }
    }

    private func applyCloudKitChanges(_ changes: CloudKitManager.FetchedChanges, context: ModelContext) {
        // Apply timer changes
        for record in changes.timers {
            guard let t = CloudKitManager.timerFromRecord(record) else { continue }
            let sid: Int? = t.serverId
            let descriptor = FetchDescriptor<ActiveTimerLocal>(
                predicate: #Predicate<ActiveTimerLocal> { timer in timer.serverId == sid }
            )
            let existing = try? context.fetch(descriptor).first

            if let timer = existing {
                if t.lastModified > timer.lastModified {
                    timer.name = t.name
                    timer.category = t.category
                    timer.startedAt = t.startedAt
                    timer.state = t.state
                    timer.breaksData = t.breaksJSON.data(using: .utf8) ?? Data()
                    timer.todoId = t.todoId
                    timer.lastModified = t.lastModified
                    timer.needsSync = false
                }
            } else {
                let timer = ActiveTimerLocal(name: t.name, category: t.category, todoId: t.todoId)
                timer.serverId = t.serverId
                timer.startedAt = t.startedAt
                timer.state = t.state
                timer.breaksData = t.breaksJSON.data(using: .utf8) ?? Data()
                timer.lastModified = t.lastModified
                timer.needsSync = false
                context.insert(timer)
            }
        }

        // Apply entry changes
        for record in changes.entries {
            guard let e = CloudKitManager.entryFromRecord(record) else { continue }
            let sid: Int? = e.serverId
            let descriptor = FetchDescriptor<TimeEntryLocal>(
                predicate: #Predicate<TimeEntryLocal> { entry in entry.serverId == sid }
            )
            let existing = try? context.fetch(descriptor).first

            if let entry = existing {
                if e.lastModified > entry.lastModified {
                    entry.name = e.name
                    entry.category = e.category
                    entry.startedAt = e.startedAt
                    entry.endedAt = e.endedAt
                    entry.activeSecs = e.activeSecs
                    entry.breaksData = e.breaksJSON.data(using: .utf8) ?? Data()
                    entry.todoId = e.todoId
                    entry.lastModified = e.lastModified
                    entry.needsSync = false
                }
            } else {
                let breaks = (try? JSONDecoder().decode([BreakPeriod].self, from: e.breaksJSON.data(using: .utf8) ?? Data())) ?? []
                let entry = TimeEntryLocal(
                    name: e.name, category: e.category,
                    startedAt: e.startedAt, endedAt: e.endedAt,
                    activeSecs: e.activeSecs, breaks: breaks, todoId: e.todoId
                )
                entry.serverId = e.serverId
                entry.lastModified = e.lastModified
                entry.needsSync = false
                context.insert(entry)
            }
        }

        // Apply todo changes
        for record in changes.todos {
            guard let t = CloudKitManager.todoFromRecord(record) else { continue }
            let sid: Int? = t.serverId
            let descriptor = FetchDescriptor<TodoItemLocal>(
                predicate: #Predicate<TodoItemLocal> { todo in todo.serverId == sid }
            )
            let existing = try? context.fetch(descriptor).first

            if let todo = existing {
                if t.lastModified > todo.lastModified {
                    todo.text = t.text
                    todo.done = t.done
                    todo.createdAt = t.createdAt
                    todo.lastModified = t.lastModified
                    todo.needsSync = false
                }
            } else {
                let todo = TodoItemLocal(text: t.text)
                todo.serverId = t.serverId
                todo.done = t.done
                todo.createdAt = t.createdAt
                todo.lastModified = t.lastModified
                todo.needsSync = false
                context.insert(todo)
            }
        }

        // Apply deletions
        for recordID in changes.deletedRecordIDs {
            guard let parsed = CloudKitManager.serverIdFromRecordID(recordID) else { continue }
            let sid: Int? = parsed.id
            switch parsed.table {
            case "active_timers":
                let descriptor = FetchDescriptor<ActiveTimerLocal>(
                    predicate: #Predicate<ActiveTimerLocal> { t in t.serverId == sid }
                )
                if let timer = try? context.fetch(descriptor).first { context.delete(timer) }
            case "time_entries":
                let descriptor = FetchDescriptor<TimeEntryLocal>(
                    predicate: #Predicate<TimeEntryLocal> { e in e.serverId == sid }
                )
                if let entry = try? context.fetch(descriptor).first { context.delete(entry) }
            case "todos":
                let descriptor = FetchDescriptor<TodoItemLocal>(
                    predicate: #Predicate<TodoItemLocal> { t in t.serverId == sid }
                )
                if let todo = try? context.fetch(descriptor).first { context.delete(todo) }
            default: break
            }
        }
    }

    // MARK: - BLE Sync (existing bidirectional protocol)

    private func performBLESync() async {
        guard let context = modelContext else { return }

        do {
            let meta = try getOrCreateSyncMetadata(context)

            let request = APISyncRequest(
                client_id: meta.clientId,
                last_sync_ts: meta.lastSyncTimestamp,
                changes: APISyncChanges(
                    active_timers: gatherTimerChanges(context),
                    time_entries: gatherEntryChanges(context),
                    todos: gatherTodoChanges(context),
                    deletions: gatherDeletions(context)
                )
            )

            let response = try await bleManager.sync(request: request)

            applyBLEServerTimers(response.server_changes.active_timers, context: context)
            applyBLEServerEntries(response.server_changes.time_entries, context: context)
            applyBLEServerTodos(response.server_changes.todos, context: context)
            applyBLEServerDeletions(response.server_changes.deletions, context: context)

            for mapping in response.id_mappings {
                applyIdMapping(mapping, context: context)
            }

            clearSyncFlags(context)
            clearPendingDeletions(context)

            meta.lastSyncTimestamp = response.new_sync_ts
            try context.save()
            lastSyncDate = Date()
        } catch {
            if syncError == nil {
                syncError = "BLE: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - BLE Helpers

    private func getOrCreateSyncMetadata(_ context: ModelContext) throws -> SyncMetadata {
        let descriptor = FetchDescriptor<SyncMetadata>()
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let meta = SyncMetadata()
        context.insert(meta)
        try context.save()
        return meta
    }

    private func gatherTimerChanges(_ context: ModelContext) -> [APISyncTimerData] {
        let descriptor = FetchDescriptor<ActiveTimerLocal>(predicate: #Predicate { $0.needsSync == true })
        let timers = (try? context.fetch(descriptor)) ?? []
        return timers.map { t in
            APISyncTimerData(
                server_id: t.serverId, local_id: t.localId,
                name: t.name, category: t.category, started_at: t.startedAt, state: t.state,
                breaks: t.breaks.map { APIBreakPeriod(start_ts: $0.startTs, end_ts: $0.endTs) },
                todo_id: t.todoId, last_modified: t.lastModified
            )
        }
    }

    private func gatherEntryChanges(_ context: ModelContext) -> [APISyncEntryData] {
        let descriptor = FetchDescriptor<TimeEntryLocal>(predicate: #Predicate { $0.needsSync == true })
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.map { e in
            APISyncEntryData(
                server_id: e.serverId, local_id: e.localId,
                name: e.name, category: e.category, started_at: e.startedAt, ended_at: e.endedAt,
                active_secs: e.activeSecs,
                breaks: e.breaks.map { APIBreakPeriod(start_ts: $0.startTs, end_ts: $0.endTs) },
                todo_id: e.todoId, last_modified: e.lastModified
            )
        }
    }

    private func gatherTodoChanges(_ context: ModelContext) -> [APISyncTodoData] {
        let descriptor = FetchDescriptor<TodoItemLocal>(predicate: #Predicate { $0.needsSync == true })
        let todos = (try? context.fetch(descriptor)) ?? []
        return todos.map { t in
            APISyncTodoData(
                server_id: t.serverId, local_id: t.localId,
                text: t.text, done: t.done, created_at: t.createdAt, last_modified: t.lastModified
            )
        }
    }

    private func gatherDeletions(_ context: ModelContext) -> [APISyncDeletion] {
        let descriptor = FetchDescriptor<PendingDeletion>()
        let deletions = (try? context.fetch(descriptor)) ?? []
        return deletions.map { APISyncDeletion(table_name: $0.tableName, record_id: $0.recordServerId, deleted_at: $0.deletedAt) }
    }

    private func applyBLEServerTimers(_ timers: [APISyncTimerData], context: ModelContext) {
        for st in timers {
            guard let serverId = st.server_id else { continue }
            let sid: Int? = serverId
            let descriptor = FetchDescriptor<ActiveTimerLocal>(
                predicate: #Predicate<ActiveTimerLocal> { t in t.serverId == sid }
            )
            if let timer = try? context.fetch(descriptor).first {
                if st.last_modified > timer.lastModified {
                    timer.name = st.name; timer.category = st.category
                    timer.startedAt = st.started_at; timer.state = st.state
                    timer.breaks = st.breaks.map { BreakPeriod(startTs: $0.start_ts, endTs: $0.end_ts) }
                    timer.todoId = st.todo_id; timer.lastModified = st.last_modified
                    timer.needsSync = false
                }
            } else {
                let timer = ActiveTimerLocal(name: st.name, category: st.category, todoId: st.todo_id)
                timer.serverId = serverId; timer.startedAt = st.started_at; timer.state = st.state
                timer.breaks = st.breaks.map { BreakPeriod(startTs: $0.start_ts, endTs: $0.end_ts) }
                timer.lastModified = st.last_modified; timer.needsSync = false
                context.insert(timer)
            }
        }
    }

    private func applyBLEServerEntries(_ entries: [APISyncEntryData], context: ModelContext) {
        for se in entries {
            guard let serverId = se.server_id else { continue }
            let sid: Int? = serverId
            let descriptor = FetchDescriptor<TimeEntryLocal>(
                predicate: #Predicate<TimeEntryLocal> { e in e.serverId == sid }
            )
            if let entry = try? context.fetch(descriptor).first {
                if se.last_modified > entry.lastModified {
                    entry.name = se.name; entry.category = se.category
                    entry.startedAt = se.started_at; entry.endedAt = se.ended_at
                    entry.activeSecs = se.active_secs
                    entry.breaks = se.breaks.map { BreakPeriod(startTs: $0.start_ts, endTs: $0.end_ts) }
                    entry.todoId = se.todo_id; entry.lastModified = se.last_modified
                    entry.needsSync = false
                }
            } else {
                let entry = TimeEntryLocal(
                    name: se.name, category: se.category,
                    startedAt: se.started_at, endedAt: se.ended_at,
                    activeSecs: se.active_secs,
                    breaks: se.breaks.map { BreakPeriod(startTs: $0.start_ts, endTs: $0.end_ts) },
                    todoId: se.todo_id
                )
                entry.serverId = serverId; entry.lastModified = se.last_modified; entry.needsSync = false
                context.insert(entry)
            }
        }
    }

    private func applyBLEServerTodos(_ todos: [APISyncTodoData], context: ModelContext) {
        for st in todos {
            guard let serverId = st.server_id else { continue }
            let sid: Int? = serverId
            let descriptor = FetchDescriptor<TodoItemLocal>(
                predicate: #Predicate<TodoItemLocal> { t in t.serverId == sid }
            )
            if let todo = try? context.fetch(descriptor).first {
                if st.last_modified > todo.lastModified {
                    todo.text = st.text; todo.done = st.done
                    todo.createdAt = st.created_at; todo.lastModified = st.last_modified
                    todo.needsSync = false
                }
            } else {
                let todo = TodoItemLocal(text: st.text)
                todo.serverId = serverId; todo.done = st.done
                todo.createdAt = st.created_at; todo.lastModified = st.last_modified; todo.needsSync = false
                context.insert(todo)
            }
        }
    }

    private func applyBLEServerDeletions(_ deletions: [APISyncDeletion], context: ModelContext) {
        for del in deletions {
            let recordId: Int? = del.record_id
            switch del.table_name {
            case "active_timers":
                let d = FetchDescriptor<ActiveTimerLocal>(predicate: #Predicate<ActiveTimerLocal> { t in t.serverId == recordId })
                if let timer = try? context.fetch(d).first { context.delete(timer) }
            case "time_entries":
                let d = FetchDescriptor<TimeEntryLocal>(predicate: #Predicate<TimeEntryLocal> { e in e.serverId == recordId })
                if let entry = try? context.fetch(d).first { context.delete(entry) }
            case "todos":
                let d = FetchDescriptor<TodoItemLocal>(predicate: #Predicate<TodoItemLocal> { t in t.serverId == recordId })
                if let todo = try? context.fetch(d).first { context.delete(todo) }
            default: break
            }
        }
    }

    private func applyIdMapping(_ mapping: APISyncIdMapping, context: ModelContext) {
        switch mapping.table_name {
        case "active_timers":
            let d = FetchDescriptor<ActiveTimerLocal>(predicate: #Predicate<ActiveTimerLocal> { t in t.localId == mapping.local_id })
            if let timer = try? context.fetch(d).first { timer.serverId = mapping.server_id }
        case "time_entries":
            let d = FetchDescriptor<TimeEntryLocal>(predicate: #Predicate<TimeEntryLocal> { e in e.localId == mapping.local_id })
            if let entry = try? context.fetch(d).first { entry.serverId = mapping.server_id }
        case "todos":
            let d = FetchDescriptor<TodoItemLocal>(predicate: #Predicate<TodoItemLocal> { t in t.localId == mapping.local_id })
            if let todo = try? context.fetch(d).first { todo.serverId = mapping.server_id }
        default: break
        }
    }

    private func clearSyncFlags(_ context: ModelContext) {
        let td = FetchDescriptor<ActiveTimerLocal>(predicate: #Predicate { $0.needsSync == true })
        for t in (try? context.fetch(td)) ?? [] { t.needsSync = false }
        let ed = FetchDescriptor<TimeEntryLocal>(predicate: #Predicate { $0.needsSync == true })
        for e in (try? context.fetch(ed)) ?? [] { e.needsSync = false }
        let tod = FetchDescriptor<TodoItemLocal>(predicate: #Predicate { $0.needsSync == true })
        for t in (try? context.fetch(tod)) ?? [] { t.needsSync = false }
    }

    private func clearPendingDeletions(_ context: ModelContext) {
        let d = FetchDescriptor<PendingDeletion>()
        for del in (try? context.fetch(d)) ?? [] { context.delete(del) }
    }
}

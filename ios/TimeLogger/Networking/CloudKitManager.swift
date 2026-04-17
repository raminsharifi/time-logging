import CloudKit
import Foundation

@MainActor
final class CloudKitManager: ObservableObject {
    static let containerID = "iCloud.com.raminsharifi.TimeLogger"
    static let zoneName = "TimeLoggerZone"

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID

    @Published var iCloudAvailable = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    // Server change token for incremental fetch
    private var changeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "ck_change_token") else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }
        set {
            if let token = newValue,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: "ck_change_token")
            } else {
                UserDefaults.standard.removeObject(forKey: "ck_change_token")
            }
        }
    }

    init() {
        container = CKContainer(identifier: Self.containerID)
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    func setup() async {
        do {
            let status = try await container.accountStatus()
            iCloudAvailable = (status == .available)
            if iCloudAvailable {
                try await ensureZoneExists()
            }
        } catch {
            iCloudAvailable = false
            syncError = error.localizedDescription
        }
    }

    private func ensureZoneExists() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
    }

    // MARK: - Push Records

    func pushTimers(_ timers: [(serverId: Int, name: String, category: String, startedAt: Int64, state: String, breaksJSON: String, todoId: Int?, lastModified: Int64)]) async throws {
        let records = timers.map { t -> CKRecord in
            let recordID = CKRecord.ID(recordName: "Timer-\(t.serverId)", zoneID: zoneID)
            let record = CKRecord(recordType: "ActiveTimer", recordID: recordID)
            record["serverId"] = t.serverId as CKRecordValue
            record["name"] = t.name as CKRecordValue
            record["category"] = t.category as CKRecordValue
            record["startedAt"] = t.startedAt as CKRecordValue
            record["state"] = t.state as CKRecordValue
            record["breaksJSON"] = t.breaksJSON as CKRecordValue
            record["todoId"] = (t.todoId ?? 0) as CKRecordValue
            record["lastModified"] = t.lastModified as CKRecordValue
            return record
        }
        if !records.isEmpty {
            _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys)
        }
    }

    func pushEntries(_ entries: [(serverId: Int, name: String, category: String, startedAt: Int64, endedAt: Int64, activeSecs: Int64, breaksJSON: String, todoId: Int?, lastModified: Int64)]) async throws {
        let records = entries.map { e -> CKRecord in
            let recordID = CKRecord.ID(recordName: "Entry-\(e.serverId)", zoneID: zoneID)
            let record = CKRecord(recordType: "TimeEntry", recordID: recordID)
            record["serverId"] = e.serverId as CKRecordValue
            record["name"] = e.name as CKRecordValue
            record["category"] = e.category as CKRecordValue
            record["startedAt"] = e.startedAt as CKRecordValue
            record["endedAt"] = e.endedAt as CKRecordValue
            record["activeSecs"] = e.activeSecs as CKRecordValue
            record["breaksJSON"] = e.breaksJSON as CKRecordValue
            record["todoId"] = (e.todoId ?? 0) as CKRecordValue
            record["lastModified"] = e.lastModified as CKRecordValue
            return record
        }
        if !records.isEmpty {
            _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys)
        }
    }

    func pushTodos(_ todos: [(serverId: Int, text: String, done: Bool, createdAt: Int64, lastModified: Int64)]) async throws {
        let records = todos.map { t -> CKRecord in
            let recordID = CKRecord.ID(recordName: "Todo-\(t.serverId)", zoneID: zoneID)
            let record = CKRecord(recordType: "TodoItem", recordID: recordID)
            record["serverId"] = t.serverId as CKRecordValue
            record["text"] = t.text as CKRecordValue
            record["done"] = (t.done ? 1 : 0) as CKRecordValue
            record["createdAt"] = t.createdAt as CKRecordValue
            record["lastModified"] = t.lastModified as CKRecordValue
            return record
        }
        if !records.isEmpty {
            _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys)
        }
    }

    func pushDeletions(_ deletions: [(tableName: String, recordId: Int)]) async throws {
        let recordIDs: [CKRecord.ID] = deletions.compactMap { del in
            let prefix: String
            switch del.tableName {
            case "active_timers": prefix = "Timer"
            case "time_entries": prefix = "Entry"
            case "todos": prefix = "Todo"
            default: return nil
            }
            return CKRecord.ID(recordName: "\(prefix)-\(del.recordId)", zoneID: zoneID)
        }
        if !recordIDs.isEmpty {
            _ = try await database.modifyRecords(saving: [], deleting: recordIDs)
        }
    }

    // MARK: - Fetch Changes

    struct FetchedChanges {
        var timers: [CKRecord] = []
        var entries: [CKRecord] = []
        var todos: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []
    }

    func fetchChanges() async throws -> FetchedChanges {
        var result = FetchedChanges()

        let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: changeToken)

        for (_, modResult) in changes.modificationResultsByID {
            if case .success(let modification) = modResult {
                let record = modification.record
                switch record.recordType {
                case "ActiveTimer": result.timers.append(record)
                case "TimeEntry": result.entries.append(record)
                case "TodoItem": result.todos.append(record)
                default: break
                }
            }
        }

        for deletion in changes.deletions {
            result.deletedRecordIDs.append(deletion.recordID)
        }

        changeToken = changes.changeToken

        return result
    }

    // MARK: - CKRecord Helpers

    static func timerFromRecord(_ record: CKRecord) -> (serverId: Int, name: String, category: String, startedAt: Int64, state: String, breaksJSON: String, todoId: Int?, lastModified: Int64)? {
        guard let serverId = record["serverId"] as? Int,
              let name = record["name"] as? String,
              let category = record["category"] as? String,
              let startedAt = record["startedAt"] as? Int64,
              let state = record["state"] as? String,
              let lastModified = record["lastModified"] as? Int64 else { return nil }
        let breaksJSON = record["breaksJSON"] as? String ?? "[]"
        let todoId = record["todoId"] as? Int
        return (serverId, name, category, startedAt, state, breaksJSON, todoId == 0 ? nil : todoId, lastModified)
    }

    static func entryFromRecord(_ record: CKRecord) -> (serverId: Int, name: String, category: String, startedAt: Int64, endedAt: Int64, activeSecs: Int64, breaksJSON: String, todoId: Int?, lastModified: Int64)? {
        guard let serverId = record["serverId"] as? Int,
              let name = record["name"] as? String,
              let category = record["category"] as? String,
              let startedAt = record["startedAt"] as? Int64,
              let endedAt = record["endedAt"] as? Int64,
              let activeSecs = record["activeSecs"] as? Int64,
              let lastModified = record["lastModified"] as? Int64 else { return nil }
        let breaksJSON = record["breaksJSON"] as? String ?? "[]"
        let todoId = record["todoId"] as? Int
        return (serverId, name, category, startedAt, endedAt, activeSecs, breaksJSON, todoId == 0 ? nil : todoId, lastModified)
    }

    static func todoFromRecord(_ record: CKRecord) -> (serverId: Int, text: String, done: Bool, createdAt: Int64, lastModified: Int64)? {
        guard let serverId = record["serverId"] as? Int,
              let text = record["text"] as? String,
              let done = record["done"] as? Int,
              let createdAt = record["createdAt"] as? Int64,
              let lastModified = record["lastModified"] as? Int64 else { return nil }
        return (serverId, text, done != 0, createdAt, lastModified)
    }

    /// Parse record name like "Timer-5" to extract the server ID
    static func serverIdFromRecordID(_ recordID: CKRecord.ID) -> (table: String, id: Int)? {
        let name = recordID.recordName
        if name.hasPrefix("Timer-"), let id = Int(name.dropFirst(6)) {
            return ("active_timers", id)
        }
        if name.hasPrefix("Entry-"), let id = Int(name.dropFirst(6)) {
            return ("time_entries", id)
        }
        if name.hasPrefix("Todo-"), let id = Int(name.dropFirst(5)) {
            return ("todos", id)
        }
        return nil
    }
}

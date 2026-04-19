import Foundation
import SwiftData

/// One-time local cleanup for pre-existing sync damage: earlier BLE timeouts
/// (before the response-chunk back-pressure fix) caused the same entry to be
/// re-sent every poll, producing duplicates on the daemon and, via fetch-back,
/// additional duplicate rows locally. Fold identical rows together so the next
/// sync payload stays small and pushes the deletions down to the daemon.
enum DedupeStore {
    @MainActor
    static func run(context: ModelContext) {
        dedupeEntries(context: context)
        dedupeActiveTimers(context: context)
        dedupeTodos(context: context)
        try? context.save()
    }

    @MainActor
    private static func dedupeEntries(context: ModelContext) {
        let descriptor = FetchDescriptor<TimeEntryLocal>()
        guard let entries = try? context.fetch(descriptor) else { return }

        let grouped = Dictionary(grouping: entries) { e in
            "\(e.name)|\(e.category)|\(e.startedAt)|\(e.endedAt)|\(e.activeSecs)"
        }

        for (_, group) in grouped where group.count > 1 {
            let sorted = group.sorted(by: rankForKeep)
            guard let keep = sorted.first else { continue }
            for extra in sorted.dropFirst() {
                if let sid = extra.serverId, sid != keep.serverId {
                    queueDeletion(
                        table: "time_entries",
                        serverId: sid,
                        localLastModified: extra.lastModified,
                        context: context
                    )
                }
                context.delete(extra)
            }
        }
    }

    @MainActor
    private static func dedupeActiveTimers(context: ModelContext) {
        let descriptor = FetchDescriptor<ActiveTimerLocal>()
        guard let timers = try? context.fetch(descriptor) else { return }

        let grouped = Dictionary(grouping: timers) { t in
            "\(t.name)|\(t.category)|\(t.startedAt)|\(t.state)"
        }

        for (_, group) in grouped where group.count > 1 {
            let sorted = group.sorted(by: rankForKeep)
            guard let keep = sorted.first else { continue }
            for extra in sorted.dropFirst() {
                if let sid = extra.serverId, sid != keep.serverId {
                    queueDeletion(
                        table: "active_timers",
                        serverId: sid,
                        localLastModified: extra.lastModified,
                        context: context
                    )
                }
                context.delete(extra)
            }
        }
    }

    @MainActor
    private static func dedupeTodos(context: ModelContext) {
        let descriptor = FetchDescriptor<TodoItemLocal>()
        guard let todos = try? context.fetch(descriptor) else { return }

        let grouped = Dictionary(grouping: todos) { t in
            "\(t.text)|\(t.createdAt)"
        }

        for (_, group) in grouped where group.count > 1 {
            let sorted = group.sorted(by: rankForKeep)
            guard let keep = sorted.first else { continue }
            for extra in sorted.dropFirst() {
                if let sid = extra.serverId, sid != keep.serverId {
                    queueDeletion(
                        table: "todos",
                        serverId: sid,
                        localLastModified: extra.lastModified,
                        context: context
                    )
                }
                context.delete(extra)
            }
        }
    }

    /// Keep-ranking: prefer entries that have already been synced (serverId
    /// set), then the lowest serverId (oldest daemon row), then the earliest
    /// lastModified for purely local duplicates.
    private static func rankForKeep<T>(_ a: T, _ b: T) -> Bool {
        let (aSid, aMod) = serverIdAndModified(a)
        let (bSid, bMod) = serverIdAndModified(b)
        if (aSid != nil) != (bSid != nil) { return aSid != nil }
        if let aSid, let bSid { return aSid < bSid }
        return aMod < bMod
    }

    private static func serverIdAndModified<T>(_ obj: T) -> (Int?, Int64) {
        if let e = obj as? TimeEntryLocal { return (e.serverId, e.lastModified) }
        if let t = obj as? ActiveTimerLocal { return (t.serverId, t.lastModified) }
        if let t = obj as? TodoItemLocal { return (t.serverId, t.lastModified) }
        return (nil, 0)
    }

    @MainActor
    private static func queueDeletion(
        table: String,
        serverId: Int,
        localLastModified: Int64,
        context: ModelContext
    ) {
        let now = Int64(Date().timeIntervalSince1970)
        let deletedAt = max(now, localLastModified + 1)
        context.insert(PendingDeletion(
            tableName: table,
            recordServerId: serverId,
            deletedAt: deletedAt
        ))
    }
}

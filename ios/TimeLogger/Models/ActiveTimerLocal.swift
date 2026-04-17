import Foundation
import SwiftData

@Model
final class ActiveTimerLocal {
    var localId: String = ""
    var serverId: Int?
    var name: String = ""
    var category: String = ""
    var startedAt: Int64 = 0
    var state: String = "running" // "running" or "paused"
    var breaksData: Data = Data()
    var todoId: Int?
    var lastModified: Int64 = 0
    var needsSync: Bool = true

    init(name: String, category: String, todoId: Int? = nil) {
        self.localId = UUID().uuidString
        self.serverId = nil
        self.name = name
        self.category = category
        self.startedAt = Int64(Date().timeIntervalSince1970)
        self.state = "running"
        self.breaksData = (try? JSONEncoder().encode([BreakPeriod]())) ?? Data()
        self.todoId = todoId
        self.lastModified = Int64(Date().timeIntervalSince1970)
        self.needsSync = true
    }

    var breaks: [BreakPeriod] {
        get { (try? JSONDecoder().decode([BreakPeriod].self, from: breaksData)) ?? [] }
        set { breaksData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var activeSecs: Int64 {
        let now = Int64(Date().timeIntervalSince1970)
        let elapsed = now - startedAt
        let breakSecs = breaks.reduce(Int64(0)) { $0 + $1.durationSecs(at: now) }
        return max(elapsed - breakSecs, 0)
    }

    var breakSecs: Int64 {
        let now = Int64(Date().timeIntervalSince1970)
        return breaks.reduce(Int64(0)) { $0 + $1.durationSecs(at: now) }
    }

    var isRunning: Bool { state == "running" }
    var isPaused: Bool { state == "paused" }

    func pause() {
        state = "paused"
        var b = breaks
        b.append(.now())
        breaks = b
        lastModified = Int64(Date().timeIntervalSince1970)
        needsSync = true
    }

    func resume() {
        state = "running"
        var b = breaks
        if var last = b.last, last.isOpen {
            last.close()
            b[b.count - 1] = last
        }
        breaks = b
        lastModified = Int64(Date().timeIntervalSince1970)
        needsSync = true
    }
}

import Foundation
import SwiftData

@Model
final class ActiveTimerLocal {
    #Unique<ActiveTimerLocal>([\.localId])

    var serverId: Int?
    var localId: UUID
    var name: String
    var category: String
    var startedAt: Date
    var state: String
    var breaks: [BreakPeriod]
    var todoId: Int?
    var lastModified: Date
    var needsSync: Bool

    init(
        serverId: Int? = nil,
        name: String,
        category: String,
        startedAt: Date = .now,
        state: String = "running",
        breaks: [BreakPeriod] = [],
        todoId: Int? = nil
    ) {
        self.serverId = serverId
        self.localId = UUID()
        self.name = name
        self.category = category
        self.startedAt = startedAt
        self.state = state
        self.breaks = breaks
        self.todoId = todoId
        self.lastModified = .now
        self.needsSync = true
    }

    var activeSecs: TimeInterval {
        let now = Date.now
        let elapsed = now.timeIntervalSince(startedAt)
        let breakTime = breaks.reduce(0.0) { total, b in
            let end = b.endTs == 0 ? Int64(now.timeIntervalSince1970) : b.endTs
            return total + Double(end - b.startTs)
        }
        return max(elapsed - breakTime, 0)
    }

    var breakSecs: TimeInterval {
        let now = Int64(Date.now.timeIntervalSince1970)
        return breaks.reduce(0.0) { total, b in
            let end = b.endTs == 0 ? now : b.endTs
            return total + Double(end - b.startTs)
        }
    }
}

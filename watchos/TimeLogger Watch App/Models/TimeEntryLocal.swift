import Foundation
import SwiftData

@Model
final class TimeEntryLocal {
    #Unique<TimeEntryLocal>([\.localId])

    var serverId: Int?
    var localId: UUID
    var name: String
    var category: String
    var startedAt: Date
    var endedAt: Date
    var activeSecs: Int
    var breaks: [BreakPeriod]
    var todoId: Int?
    var lastModified: Date
    var needsSync: Bool

    init(
        serverId: Int? = nil,
        name: String,
        category: String,
        startedAt: Date,
        endedAt: Date,
        activeSecs: Int,
        breaks: [BreakPeriod] = [],
        todoId: Int? = nil
    ) {
        self.serverId = serverId
        self.localId = UUID()
        self.name = name
        self.category = category
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSecs = activeSecs
        self.breaks = breaks
        self.todoId = todoId
        self.lastModified = .now
        self.needsSync = true
    }
}

import Foundation
import SwiftData

@Model
final class TimeEntryLocal {
    var localId: String = ""
    var serverId: Int?
    var name: String = ""
    var category: String = ""
    var startedAt: Int64 = 0
    var endedAt: Int64 = 0
    var activeSecs: Int64 = 0
    var breaksData: Data = Data()
    var todoId: Int?
    var lastModified: Int64 = 0
    var needsSync: Bool = true

    init(name: String, category: String, startedAt: Int64, endedAt: Int64, activeSecs: Int64, breaks: [BreakPeriod], todoId: Int? = nil) {
        self.localId = UUID().uuidString
        self.serverId = nil
        self.name = name
        self.category = category
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSecs = activeSecs
        self.breaksData = (try? JSONEncoder().encode(breaks)) ?? Data()
        self.todoId = todoId
        self.lastModified = Int64(Date().timeIntervalSince1970)
        self.needsSync = true
    }

    var breaks: [BreakPeriod] {
        get { (try? JSONDecoder().decode([BreakPeriod].self, from: breaksData)) ?? [] }
        set { breaksData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var breakSecs: Int64 {
        breaks.reduce(Int64(0)) { $0 + $1.durationSecs(at: endedAt) }
    }
}

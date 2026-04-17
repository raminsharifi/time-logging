import Foundation
import SwiftData

@Model
final class TodoItemLocal {
    #Unique<TodoItemLocal>([\.localId])

    var serverId: Int?
    var localId: UUID
    var text: String
    var done: Bool
    var createdAt: Date
    var lastModified: Date
    var needsSync: Bool

    init(
        serverId: Int? = nil,
        text: String,
        done: Bool = false,
        createdAt: Date = .now
    ) {
        self.serverId = serverId
        self.localId = UUID()
        self.text = text
        self.done = done
        self.createdAt = createdAt
        self.lastModified = .now
        self.needsSync = true
    }
}

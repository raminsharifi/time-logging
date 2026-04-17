import Foundation
import SwiftData

@Model
final class TodoItemLocal {
    var localId: String = ""
    var serverId: Int?
    var text: String = ""
    var done: Bool = false
    var createdAt: Int64 = 0
    var lastModified: Int64 = 0
    var needsSync: Bool = true

    init(text: String) {
        self.localId = UUID().uuidString
        self.serverId = nil
        self.text = text
        self.done = false
        self.createdAt = Int64(Date().timeIntervalSince1970)
        self.lastModified = Int64(Date().timeIntervalSince1970)
        self.needsSync = true
    }
}

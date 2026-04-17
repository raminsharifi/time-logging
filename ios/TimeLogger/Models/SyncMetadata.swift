import Foundation
import SwiftData

@Model
final class SyncMetadata {
    var id: String = "singleton"
    var clientId: String = ""
    var lastSyncTimestamp: Int64 = 0

    init() {
        self.id = "singleton"
        self.clientId = UUID().uuidString
        self.lastSyncTimestamp = 0
    }
}

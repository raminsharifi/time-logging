import Foundation
import SwiftData

@Model
final class SyncMetadata {
    var clientId: String
    var lastSyncTimestamp: Date

    init() {
        self.clientId = UUID().uuidString
        self.lastSyncTimestamp = Date(timeIntervalSince1970: 0)
    }
}

import Foundation
import SwiftData

@Model
final class PendingDeletion {
    var tableName: String
    var recordServerId: Int
    var deletedAt: Date

    init(tableName: String, recordServerId: Int) {
        self.tableName = tableName
        self.recordServerId = recordServerId
        self.deletedAt = .now
    }
}

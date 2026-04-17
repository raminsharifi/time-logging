import Foundation
import SwiftData

@Model
final class PendingDeletion {
    var tableName: String = ""
    var recordServerId: Int = 0
    var deletedAt: Int64 = 0

    init(tableName: String, recordServerId: Int) {
        self.tableName = tableName
        self.recordServerId = recordServerId
        self.deletedAt = Int64(Date().timeIntervalSince1970)
    }
}

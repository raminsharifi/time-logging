import Foundation

struct BreakPeriod: Codable, Hashable {
    var startTs: Int64
    var endTs: Int64

    static func now() -> BreakPeriod {
        BreakPeriod(startTs: Int64(Date.now.timeIntervalSince1970), endTs: 0)
    }

    mutating func close() {
        if endTs == 0 {
            endTs = Int64(Date.now.timeIntervalSince1970)
        }
    }
}

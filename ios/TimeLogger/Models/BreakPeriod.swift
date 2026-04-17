import Foundation

struct BreakPeriod: Codable, Equatable {
    var startTs: Int64
    var endTs: Int64

    static func now() -> BreakPeriod {
        BreakPeriod(startTs: Int64(Date().timeIntervalSince1970), endTs: 0)
    }

    mutating func close() {
        if endTs == 0 {
            endTs = Int64(Date().timeIntervalSince1970)
        }
    }

    var isOpen: Bool { endTs == 0 }

    func durationSecs(at now: Int64? = nil) -> Int64 {
        let end = endTs == 0 ? (now ?? Int64(Date().timeIntervalSince1970)) : endTs
        return end - startTs
    }
}

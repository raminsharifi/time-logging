import CoreBluetooth

enum BLEConstants {
    static let serviceUUID = CBUUID(string: "7B2C956E-9A32-4E00-9B8D-3C1A5E809F2A")
    static let requestCharUUID = CBUUID(string: "7B2C956E-9A32-4E00-9B8D-3C1A5E809F2B")
    static let responseCharUUID = CBUUID(string: "7B2C956E-9A32-4E00-9B8D-3C1A5E809F2C")

    // Chunk flags
    static let chunkFirst: UInt8 = 0x01
    static let chunkLast: UInt8 = 0x02
    static let chunkSingle: UInt8 = 0x03 // first + last
    // Payload-less push from the peripheral: "something changed, resync"
    static let chunkEvent: UInt8 = 0x04

    // Max chunk payload (conservative, most iOS devices negotiate 512+ MTU)
    static let maxChunkPayload = 500
}

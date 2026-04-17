import CoreBluetooth

enum BLEConstants {
    static let serviceUUID = CBUUID(string: "7B2C956E-9A32-4E00-9B8D-3C1A5E809F2A")
    static let requestCharUUID = CBUUID(string: "7B2C956E-9A32-4E00-9B8D-3C1A5E809F2B")
    static let responseCharUUID = CBUUID(string: "7B2C956E-9A32-4E00-9B8D-3C1A5E809F2C")

    // Chunk flags
    static let chunkFirst: UInt8 = 0x01
    static let chunkLast: UInt8 = 0x02
    static let chunkSingle: UInt8 = 0x03 // first + last

    // Match iOS: the Mac peripheral uses .withResponse writes, so Core Bluetooth will
    // fragment below the negotiated ATT MTU automatically. Keep the chunk size identical
    // to iOS so the server-side chunk assembly doesn't need a second code path.
    static let maxChunkPayload = 500
}

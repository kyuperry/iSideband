import Foundation

struct RNodePacket {
    let raw: Data

    var bytes: [UInt8] {
        Array(raw)
    }

    var length: Int {
        bytes.count
    }

    var startsWithFrame: Bool {
        bytes.first == 0xC0
    }

    var endsWithFrame: Bool {
        bytes.last == 0xC0
    }

    var command: UInt8? {
        guard bytes.count > 1 else { return nil }
        return bytes[1]
    }

    var hexString: String {
        bytes
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
    }
}


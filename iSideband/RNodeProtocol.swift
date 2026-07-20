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
    var commandType: RNodeCommand {
        RNodeCommand(byte: command)
    }
    

    var hexString: String {
        bytes
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
    }
}

enum RNodeCommand: UInt8 {
    case interfaceStatus = 0x25

    case unknown

    init(byte: UInt8?) {
        guard let byte else {
            self = .unknown
            return
        }

        self = RNodeCommand(rawValue: byte) ?? .unknown
    }

    var description: String {
        switch self {
        case .interfaceStatus:
            return "Interface Status"

        case .unknown:
            return "Unknown"
        }
    }
}

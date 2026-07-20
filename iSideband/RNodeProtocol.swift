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
    
    var payload: [UInt8] {
        guard bytes.count >= 3 else {
            return []
        }

        let payloadStart = 2
        let payloadEnd = endsWithFrame ? bytes.count - 1 : bytes.count

        guard payloadStart < payloadEnd else {
            return []
        }

        return Array(bytes[payloadStart..<payloadEnd])
    }

    var payloadHexString: String {
        payload
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
    }

    var summary: String {
        "\(commandType.description) | \(length) bytes | \(hexString)"
    }
    var hexString: String {
        bytes
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
    }
}

enum RNodeCommand: UInt8 {
    case data = 0x00
    case radioState = 0x06
    
    case receivedBytes = 0x21
    case transmittedBytes = 0x22
    case rssi = 0x23
    case snr = 0x24
    case channelTime = 0x25
    case physicalParameters = 0x26
    case batteryState = 0x27
    case temperature = 0x29
    
    case firmwareVersion = 0x50
    case unknown = 0xFE
    
    init(byte: UInt8?) {
        guard let byte else {
            self = .unknown
            return
        }
        
        self = RNodeCommand(rawValue: byte) ?? .unknown
    }
    
    
    var description: String {
        switch self {
        case .data:
            return "Radio Data"
            
        case .radioState:
            return "Radio State"
            
        case .receivedBytes:
            return "Received Bytes"
            
        case .transmittedBytes:
            return "Transmitted Bytes"
            
        case .rssi:
            return "RSSI"
            
        case .snr:
            return "SNR"
            
        case .channelTime:
            return "Channel Time"
            
        case .physicalParameters:
            return "Physical Parameters"
            
        case .batteryState:
            return "Battery State"
            
        case .temperature:
            return "Temperature"
            
        case .firmwareVersion:
            return "Firmware Version"
            
        case .unknown:
            return "Unknown"
        }
    }
}

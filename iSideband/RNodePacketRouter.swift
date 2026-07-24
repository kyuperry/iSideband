import Foundation

struct RNodeTelemetryUpdate {
    var firmwareVersion: String?
    var batteryPercent: Int?
    var temperature: Double?
    var radioReady: Bool?

    var frequency: UInt32?
    var bandwidth: UInt32?
    var transmitPower: Int?
    var spreadingFactor: Int?
    var codingRate: Int?
}

final class RNodePacketRouter {
    func route(_ packet: RNodePacket) -> RNodeTelemetryUpdate {
        switch packet.commandType {
        case .frequency:
            return RNodeTelemetryUpdate(
                frequency: decodeUInt32(from: packet)
            )

        case .bandwidth:
            return RNodeTelemetryUpdate(
                bandwidth: decodeUInt32(from: packet)
            )

        case .transmitPower:
            return RNodeTelemetryUpdate(
                transmitPower: packet.payload.first.map(Int.init)
            )

        case .spreadingFactor:
            return RNodeTelemetryUpdate(
                spreadingFactor: packet.payload.first.map(Int.init)
            )

        case .codingRate:
            return RNodeTelemetryUpdate(
                codingRate: packet.payload.first.map(Int.init)
            )
        case .firmwareVersion:
            return RNodeTelemetryUpdate(
                firmwareVersion: decodeFirmwareVersion(from: packet)
            )

        case .batteryState:
            return RNodeTelemetryUpdate(
                batteryPercent: decodeBatteryPercent(from: packet)
            )

        case .temperature:
            return RNodeTelemetryUpdate(
                temperature: decodeTemperature(from: packet)
            )

        case .radioState:
            return RNodeTelemetryUpdate(
                radioReady: true
            )

        default:
            return RNodeTelemetryUpdate()
        }
    }

    private func decodeFirmwareVersion(
        from packet: RNodePacket
    ) -> String? {
        guard packet.payload.count >= 2 else {
            return nil
        }

        return "\(packet.payload[0]).\(packet.payload[1])"
    }

    private func decodeBatteryPercent(
        from packet: RNodePacket
    ) -> Int? {
        guard packet.payload.count >= 2 else {
            return nil
        }

        let percent = Int(packet.payload[1])

        guard (0...100).contains(percent) else {
            return nil
        }

        return percent
    }

    private func decodeTemperature(
        from packet: RNodePacket
    ) -> Double? {
        guard packet.payload.count >= 2 else {
            return nil
        }

        let rawValue =
            Int16(packet.payload[0]) << 8 |
            Int16(packet.payload[1])

        return Double(rawValue) / 100.0
    }
    private func decodeUInt32(
        from packet: RNodePacket
    ) -> UInt32? {
        guard packet.payload.count >= 4 else {
            return nil
        }
        print(
            "UInt32 telemetry payload:",
            packet.payload.prefix(4)
                .map { String(format: "%02X", $0) }
                .joined(separator: " ")
        )

        return UInt32(packet.payload[0]) << 24
            | UInt32(packet.payload[1]) << 16
            | UInt32(packet.payload[2]) << 8
            | UInt32(packet.payload[3])
    }
}

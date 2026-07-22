import Foundation

struct RNodeTelemetryUpdate {
    var firmwareVersion: String?
    var batteryPercent: Int?
    var temperature: Double?
    var radioReady: Bool?
}

final class RNodePacketRouter {
    func route(_ packet: RNodePacket) -> RNodeTelemetryUpdate {
        switch packet.commandType {
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
        guard let value = packet.payload.first else {
            return nil
        }

        return min(Int(value), 100)
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
}

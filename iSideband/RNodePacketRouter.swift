import Foundation

enum RNodeBatteryState: UInt8 {
    case unknown = 0x00
    case discharging = 0x01
    case charging = 0x02
    case charged = 0x03

    var title: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .discharging:
            return "Discharging"
        case .charging:
            return "Charging"
        case .charged:
            return "Charged"
        }
    }
}

struct RNodeTelemetryUpdate {
    var firmwareVersion: String?
    var batteryPercent: Int?
    var batteryState: RNodeBatteryState?
    var batteryVoltage: Double?
    var temperature: Double?
    var radioReady: Bool?
    var radioLocked: Bool?
    var errorCode: UInt8?

    var frequency: UInt32?
    var bandwidth: UInt32?
    var transmitPower: Int?
    var spreadingFactor: Int?
    var codingRate: Int?
    var receivedBytes: UInt32?
    var transmittedBytes: UInt32?
    var packetRSSI: Int?
    var packetSNR: Double?
    var satelliteCount: Int?
    var uptimeSeconds: UInt32?
}

final class RNodePacketRouter {
    static func decodeBLEBatteryPercent(_ rawValue: UInt8) -> Int? {
        // Bluetooth Battery Service reserves 0xFF for an unknown level.
        // RNode firmware otherwise represents this as an integer percentage;
        // cap over-range readings the same way Reticulum caps CMD_STAT_BAT.
        guard rawValue != 0xFF else { return nil }
        return min(Int(rawValue), 100)
    }

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
                batteryPercent: decodeBatteryPercent(from: packet),
                batteryState: packet.payload.first.flatMap {
                    RNodeBatteryState(rawValue: $0)
                },
                batteryVoltage: decodeBatteryVoltage(from: packet)
            )

        case .temperature:
            return RNodeTelemetryUpdate(
                temperature: decodeTemperature(from: packet)
            )

        case .receivedBytes:
            return RNodeTelemetryUpdate(
                receivedBytes: decodeUInt32(from: packet)
            )

        case .transmittedBytes:
            return RNodeTelemetryUpdate(
                transmittedBytes: decodeUInt32(from: packet)
            )

        case .rssi:
            return RNodeTelemetryUpdate(
                packetRSSI: packet.payload.first.map {
                    Int($0) - 157
                }
            )

        case .snr:
            return RNodeTelemetryUpdate(
                packetSNR: packet.payload.first.map {
                    Double(Int8(bitPattern: $0)) * 0.25
                }
            )

        case .satelliteCount:
            return RNodeTelemetryUpdate(
                satelliteCount: packet.payload.first.map(Int.init)
            )

        case .uptime:
            return RNodeTelemetryUpdate(
                uptimeSeconds: decodeUInt32(from: packet)
            )

        case .radioState:
            return RNodeTelemetryUpdate(
                radioReady: packet.payload.first.map { $0 == 0x01 }
            )

        case .radioLock:
            return RNodeTelemetryUpdate(
                radioLocked: packet.payload.first.map { $0 != 0x00 }
            )

        case .error:
            return RNodeTelemetryUpdate(
                errorCode: packet.payload.first
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

        // Match Reticulum's RNodeInterface: the second status byte is the
        // battery percentage, clamped to the valid display range.
        return min(Int(packet.payload[1]), 100)
    }

    private func decodeBatteryVoltage(
        from packet: RNodePacket
    ) -> Double? {
        guard packet.payload.count >= 4 else { return nil }

        let millivolts =
            UInt16(packet.payload[2]) << 8 |
            UInt16(packet.payload[3])
        // Reject malformed extension data rather than showing a plausible-
        // looking but impossible single-cell battery voltage.
        guard (2_000...5_000).contains(millivolts) else { return nil }
        return Double(millivolts) / 1_000.0
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

import Foundation

enum ReticulumPacketDecodingError: LocalizedError {
    case packetTooShort
    case authenticatedInterfaceNotSupported
    case missingSecondAddress
    case malformedPacket

    var errorDescription: String? {
        switch self {
        case .packetTooShort:
            return "The Reticulum packet is too short."

        case .authenticatedInterfaceNotSupported:
            return "Packets containing an Interface Access Code are not supported yet."

        case .missingSecondAddress:
            return "The transport header is missing its second address."

        case .malformedPacket:
            return "The Reticulum packet is malformed."
        }
    }
}

struct DecodedReticulumPacket {
    let raw: Data

    let hasInterfaceAccessCode: Bool
    let headerType: ReticulumHeaderType
    let contextFlag: Bool
    let transportType: ReticulumTransportType
    let destinationType: ReticulumDestinationType
    let packetType: ReticulumPacketType

    let hops: UInt8

    let transportID: Data?
    let destinationHash: Data

    let contextRawValue: UInt8
    let payload: Data

    var context: ReticulumPacketContext? {
        ReticulumPacketContext(
            rawValue: contextRawValue
        )
    }

    var isAnnounce: Bool {
        packetType == .announce
    }

    var destinationHashHex: String {
        destinationHash
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var transportIDHex: String? {
        transportID?
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct ReticulumPacketDecoder {
    private static let addressByteCount = 16
    private static let minimumHeaderOneSize = 19

    func decode(
        _ data: Data
    ) throws -> DecodedReticulumPacket {
        guard data.count >= Self.minimumHeaderOneSize else {
            throw ReticulumPacketDecodingError.packetTooShort
        }

        let bytes = [UInt8](data)
        let flags = bytes[0]
        let hops = bytes[1]

        let hasInterfaceAccessCode =
            flags & 0b1000_0000 != 0

        /*
         The IFAC length is configured by the interface and
         cannot safely be inferred from the packet alone.

         The current direct RNode connection is expected to
         provide open-interface packets without an IFAC.
         */
        guard !hasInterfaceAccessCode else {
            throw ReticulumPacketDecodingError
                .authenticatedInterfaceNotSupported
        }

        let headerTypeRaw =
            (flags >> 6) & 0b0000_0001

        let contextFlag =
            flags & 0b0010_0000 != 0

        let transportTypeRaw =
            (flags >> 4) & 0b0000_0001

        let destinationTypeRaw =
            (flags >> 2) & 0b0000_0011

        let packetTypeRaw =
            flags & 0b0000_0011

        guard
            let headerType = ReticulumHeaderType(
                rawValue: headerTypeRaw
            ),
            let transportType = ReticulumTransportType(
                rawValue: transportTypeRaw
            ),
            let destinationType = ReticulumDestinationType(
                rawValue: destinationTypeRaw
            ),
            let packetType = ReticulumPacketType(
                rawValue: packetTypeRaw
            )
        else {
            throw ReticulumPacketDecodingError.malformedPacket
        }

        var cursor = 2
        var transportID: Data?

        if headerType == .transport {
            guard data.count >= 35 else {
                throw ReticulumPacketDecodingError
                    .missingSecondAddress
            }

            transportID = Data(
                bytes[
                    cursor..<(cursor + Self.addressByteCount)
                ]
            )

            cursor += Self.addressByteCount
        }

        guard data.count >=
                cursor + Self.addressByteCount + 1
        else {
            throw ReticulumPacketDecodingError.packetTooShort
        }

        let destinationHash = Data(
            bytes[
                cursor..<(cursor + Self.addressByteCount)
            ]
        )

        cursor += Self.addressByteCount

        let contextRawValue = bytes[cursor]
        cursor += 1

        let payload: Data

        if cursor < bytes.count {
            payload = Data(bytes[cursor..<bytes.count])
        } else {
            payload = Data()
        }

        return DecodedReticulumPacket(
            raw: data,
            hasInterfaceAccessCode:
                hasInterfaceAccessCode,
            headerType: headerType,
            contextFlag: contextFlag,
            transportType: transportType,
            destinationType: destinationType,
            packetType: packetType,
            hops: hops,
            transportID: transportID,
            destinationHash: destinationHash,
            contextRawValue: contextRawValue,
            payload: payload
        )
    }
}

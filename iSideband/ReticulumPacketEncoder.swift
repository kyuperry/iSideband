import Foundation

enum ReticulumEncodingError: LocalizedError {
    case emptyMessage
    case invalidDestinationHash
    case packetTooLarge
    case protocolNotImplemented

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "The LXMF message is empty."

        case .invalidDestinationHash:
            return "The destination hash must contain exactly 32 hexadecimal characters."

        case .packetTooLarge:
            return "The encrypted message is too large for one Reticulum packet."

        case .protocolNotImplemented:
            return "Real Reticulum packet encoding is not implemented yet."
        }
    }
}

struct ReticulumPacketEncoder {
    static let destinationHashByteCount = 16

    func encodeDataPacket(
        destinationHash: Data,
        encryptedPayload: Data
    ) throws -> Data {
        guard destinationHash.count ==
                Self.destinationHashByteCount
        else {
            throw ReticulumEncodingError
                .invalidDestinationHash
        }

        var packet = Data([
            0x00,
            0x00
        ])
        packet.append(destinationHash)
        packet.append(
            ReticulumPacketContext.none.rawValue
        )
        packet.append(encryptedPayload)

        guard packet.count <= 500 else {
            throw ReticulumEncodingError.packetTooLarge
        }

        return packet
    }
    
    func encodeProofPacket(
        proofDestinationHash: Data,
        proofPayload: Data
    ) throws -> Data {
        guard proofDestinationHash.count ==
                Self.destinationHashByteCount
        else {
            throw ReticulumEncodingError
                .invalidDestinationHash
        }

        guard proofPayload.count == 96 else {
            throw ReticulumEncodingError
                .emptyMessage
        }

        var packet = Data([
            0x03,
            0x00
        ])

        packet.append(proofDestinationHash)

        packet.append(
            ReticulumPacketContext.none.rawValue
        )

        packet.append(proofPayload)

        guard packet.count <= 500 else {
            throw ReticulumEncodingError
                .packetTooLarge
        }

        return packet
    }

    func destinationHashData(
        from destinationHash: String
    ) throws -> Data {
        let cleaned = destinationHash
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard cleaned.count ==
                Self.destinationHashByteCount * 2
        else {
            throw ReticulumEncodingError.invalidDestinationHash
        }

        var bytes = Data()
        bytes.reserveCapacity(Self.destinationHashByteCount)

        var index = cleaned.startIndex

        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(
                index,
                offsetBy: 2
            )

            let pair = cleaned[index..<nextIndex]

            guard let byte = UInt8(pair, radix: 16) else {
                throw ReticulumEncodingError.invalidDestinationHash
            }

            bytes.append(byte)
            index = nextIndex
        }

        return bytes
    }
    func encodeAnnouncePacket(
        destinationHash: Data,
        payload: Data,
        contextFlag: Bool = false
    ) throws -> Data {
        guard destinationHash.count ==
                Self.destinationHashByteCount
        else {
            throw ReticulumEncodingError
                .invalidDestinationHash
        }

        /*
         Reticulum header flags:

         Header type: normal        = 0
         Context flag: unset        = 0
         Transport type: broadcast = 0
         Destination type: single  = 0
         Packet type: announce     = 1

         Combined flags byte: 0x01
         */
        let flags: UInt8 =
            0x01 | (contextFlag ? 0x20 : 0x00)
        let hops: UInt8 = 0x00
        let context = ReticulumPacketContext.none.rawValue

        var packet = Data()
        packet.append(flags)
        packet.append(hops)
        packet.append(destinationHash)
        packet.append(context)
        packet.append(payload)

        print(
            """
            RETICULUM ANNOUNCE PACKET ENCODED
            Destination: \(destinationHash.map {
                String(format: "%02x", $0)
            }.joined())
            Payload bytes: \(payload.count)
            Total bytes: \(packet.count)
            """
        )

        return packet
    }
    func encodeLXMFMessage(
        text: String,
        destinationHash: String
    ) throws -> Data {
        let trimmedText = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedText.isEmpty else {
            throw ReticulumEncodingError.emptyMessage
        }

        _ = try destinationHashData(
            from: destinationHash
        )

        throw ReticulumEncodingError.protocolNotImplemented
    }
}

import Foundation

enum ReticulumEncodingError: LocalizedError {
    case emptyMessage
    case invalidDestinationHash
    case protocolNotImplemented

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "The LXMF message is empty."

        case .invalidDestinationHash:
            return "The destination hash must contain exactly 32 hexadecimal characters."

        case .protocolNotImplemented:
            return "Real Reticulum packet encoding is not implemented yet."
        }
    }
}

struct ReticulumPacketEncoder {
    static let destinationHashByteCount = 16

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

        // The next stage will implement the actual Reticulum
        // identity, encryption, signature and packet format.
        throw ReticulumEncodingError.protocolNotImplemented
    }
}

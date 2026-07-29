import CryptoKit
import Foundation

struct LXMFIncomingMessage: Identifiable, Hashable {
    let id: Data
    let destinationHash: Data
    let sourceHash: Data
    let timestamp: Date
    let title: String
    let content: String
    let attachmentPath: String?
    let attachmentName: String?
    let attachmentMIME: String?
    let attachmentType: LXMFIncomingAttachmentType?

    var sourceHashHex: String {
        sourceHash.map {
            String(format: "%02x", $0)
        }.joined()
    }
}

enum LXMFIncomingAttachmentType: String, Hashable {
    case photo
    case file
}

enum LXMFMessageCodecError: Error {
    case malformedMessage
    case unknownSource
    case invalidSignature
    case invalidDestination
    case unsupportedContent
}

struct LXMFMessageCodec {
    private static let hashByteCount = 16
    private static let signatureByteCount = 64

    func encodeAnnounceAppData(
        displayName: String
    ) -> Data {
        MessagePackWriter.pack(
            .array([
                .binary(Data(displayName.utf8)),
                .null,
                .array([
                    .integer(0)
                ])
            ])
        )
    }

    func decodeAnnounceDisplayName(
        _ appData: Data
    ) -> String? {
        var reader = MessagePackReader(data: appData)

        guard
            let value = try? reader.read(),
            case .array(let peerData) = value,
            let first = peerData.first,
            let nameData = first.dataValue,
            let name = String(
                data: nameData,
                encoding: .utf8
            )
        else {
            return String(
                data: appData,
                encoding: .utf8
            )?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        }

        let trimmed = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    func decode(
        _ data: Data,
        expectedDestinationHash: Data,
        sourcePublicKey: (String) -> Data?
    ) throws -> LXMFIncomingMessage {
        let headerByteCount =
            Self.hashByteCount * 2 +
            Self.signatureByteCount

        guard data.count > headerByteCount else {
            throw LXMFMessageCodecError.malformedMessage
        }

        let destinationHash =
            Data(data.prefix(Self.hashByteCount))
        guard destinationHash ==
                expectedDestinationHash else {
            throw LXMFMessageCodecError.invalidDestination
        }

        let sourceStart = Self.hashByteCount
        let sourceEnd = sourceStart + Self.hashByteCount
        let sourceHash =
            Data(data[sourceStart..<sourceEnd])
        let signatureEnd =
            sourceEnd + Self.signatureByteCount
        let signature =
            Data(data[sourceEnd..<signatureEnd])
        let packedPayload =
            Data(data.dropFirst(signatureEnd))

        var reader = MessagePackReader(
            data: packedPayload
        )
        guard case .array(let payload) = try reader.read(),
              payload.count >= 4,
              case .number(let timestamp) = payload[0],
              let titleData = payload[1].dataValue,
              let contentData = payload[2].dataValue
        else {
            throw LXMFMessageCodecError.unsupportedContent
        }

        var hashedPart = Data()
        hashedPart.append(destinationHash)
        hashedPart.append(sourceHash)
        hashedPart.append(packedPayload)
        let messageID =
            Data(SHA256.hash(data: hashedPart))

        var signedPart = hashedPart
        signedPart.append(messageID)

        let sourceHex = sourceHash.map {
            String(format: "%02x", $0)
        }.joined()
        guard let combinedPublicKey =
                sourcePublicKey(sourceHex),
              combinedPublicKey.count ==
                ReticulumIdentity.combinedKeyByteCount
        else {
            throw LXMFMessageCodecError.unknownSource
        }

        let signingKey =
            try Curve25519.Signing.PublicKey(
                rawRepresentation:
                    combinedPublicKey.suffix(
                        ReticulumIdentity
                            .signingKeyByteCount
                    )
            )
        guard signingKey.isValidSignature(
            signature,
            for: signedPart
        ) else {
            throw LXMFMessageCodecError.invalidSignature
        }

        guard let title = String(
                    data: titleData,
                    encoding: .utf8
              ),
              let content = String(
                    data: contentData,
                    encoding: .utf8
              )
        else {
            throw LXMFMessageCodecError.unsupportedContent
        }

        return LXMFIncomingMessage(
            id: messageID,
            destinationHash: destinationHash,
            sourceHash: sourceHash,
            timestamp: Date(
                timeIntervalSince1970: timestamp
            ),
            title: title,
            content: content,
            attachmentPath: nil,
            attachmentName: nil,
            attachmentMIME: nil,
            attachmentType: nil
        )
    }

    func encode(
        content: String,
        title: String = "",
        timestamp: Date = Date(),
        destinationHash: Data,
        sourceHash: Data,
        sourceIdentity: ReticulumIdentity
    ) throws -> Data {
        guard destinationHash.count ==
                Self.hashByteCount,
              sourceHash.count == Self.hashByteCount
        else {
            throw LXMFMessageCodecError.malformedMessage
        }

        let packedPayload = MessagePackWriter.pack(
            .array([
                .number(
                    timestamp.timeIntervalSince1970
                ),
                .binary(Data(title.utf8)),
                .binary(Data(content.utf8)),
                .map([])
            ])
        )

        var hashedPart = Data()
        hashedPart.append(destinationHash)
        hashedPart.append(sourceHash)
        hashedPart.append(packedPayload)
        let messageID =
            Data(SHA256.hash(data: hashedPart))

        var signedPart = hashedPart
        signedPart.append(messageID)
        let signature =
            try sourceIdentity.sign(signedPart)

        return destinationHash +
            sourceHash +
            signature +
            packedPayload
    }
}

private enum MessagePackValue {
    case number(Double)
    case binary(Data)
    case array([MessagePackValue])
    case map([(MessagePackValue, MessagePackValue)])
    case integer(Int64)
    case boolean(Bool)
    case null

    var dataValue: Data? {
        switch self {
        case .binary(let data):
            return data
        default:
            return nil
        }
    }
}

private struct MessagePackReader {
    let data: Data
    private var cursor = 0

    init(data: Data) {
        self.data = data
    }

    mutating func read() throws -> MessagePackValue {
        let prefix = try readByte()

        switch prefix {
        case 0x00...0x7f:
            return .integer(Int64(prefix))
        case 0x80...0x8f:
            return try readMap(count: Int(prefix & 0x0f))
        case 0x90...0x9f:
            return try readArray(count: Int(prefix & 0x0f))
        case 0xa0...0xbf:
            return .binary(
                try readData(count: Int(prefix & 0x1f))
            )
        case 0xc0:
            return .null
        case 0xc2:
            return .boolean(false)
        case 0xc3:
            return .boolean(true)
        case 0xc4:
            return .binary(
                try readData(count: Int(try readByte()))
            )
        case 0xc5:
            return .binary(
                try readData(count: Int(try readUInt16()))
            )
        case 0xc6:
            return .binary(
                try readData(count: Int(try readUInt32()))
            )
        case 0xcb:
            return .number(
                Double(
                    bitPattern: try readUInt64()
                )
            )
        case 0xcc:
            return .integer(Int64(try readByte()))
        case 0xcd:
            return .integer(Int64(try readUInt16()))
        case 0xce:
            return .integer(Int64(try readUInt32()))
        case 0xd9:
            return .binary(
                try readData(count: Int(try readByte()))
            )
        case 0xda:
            return .binary(
                try readData(count: Int(try readUInt16()))
            )
        case 0xdc:
            return try readArray(
                count: Int(try readUInt16())
            )
        case 0xde:
            return try readMap(
                count: Int(try readUInt16())
            )
        case 0xe0...0xff:
            return .integer(Int64(Int8(bitPattern: prefix)))
        default:
            throw LXMFMessageCodecError.malformedMessage
        }
    }

    private mutating func readArray(
        count: Int
    ) throws -> MessagePackValue {
        var values: [MessagePackValue] = []
        for _ in 0..<count {
            values.append(try read())
        }
        return .array(values)
    }

    private mutating func readMap(
        count: Int
    ) throws -> MessagePackValue {
        var values: [
            (MessagePackValue, MessagePackValue)
        ] = []
        for _ in 0..<count {
            values.append((try read(), try read()))
        }
        return .map(values)
    }

    private mutating func readByte() throws -> UInt8 {
        guard cursor < data.count else {
            throw LXMFMessageCodecError.malformedMessage
        }
        defer { cursor += 1 }
        return data[cursor]
    }

    private mutating func readData(
        count: Int
    ) throws -> Data {
        guard count >= 0,
              cursor + count <= data.count else {
            throw LXMFMessageCodecError.malformedMessage
        }
        defer { cursor += count }
        return Data(data[cursor..<(cursor + count)])
    }

    private mutating func readUInt16() throws -> UInt16 {
        let bytes = try readData(count: 2)
        return bytes.reduce(0) {
            ($0 << 8) | UInt16($1)
        }
    }

    private mutating func readUInt32() throws -> UInt32 {
        let bytes = try readData(count: 4)
        return bytes.reduce(0) {
            ($0 << 8) | UInt32($1)
        }
    }

    private mutating func readUInt64() throws -> UInt64 {
        let bytes = try readData(count: 8)
        return bytes.reduce(0) {
            ($0 << 8) | UInt64($1)
        }
    }
}

private enum MessagePackWriter {
    static func pack(
        _ value: MessagePackValue
    ) -> Data {
        switch value {
        case .number(let number):
            var bits = number.bitPattern.bigEndian
            return Data([0xcb]) + Data(
                bytes: &bits,
                count: MemoryLayout<UInt64>.size
            )
        case .binary(let data):
            if data.count <= 0xff {
                return Data([
                    0xc4,
                    UInt8(data.count)
                ]) + data
            }
            var length = UInt16(data.count).bigEndian
            return Data([0xc5]) + Data(
                bytes: &length,
                count: 2
            ) + data
        case .array(let values):
            var result = Data([
                0x90 | UInt8(values.count)
            ])
            values.forEach {
                result.append(pack($0))
            }
            return result
        case .map(let values):
            var result = Data([
                0x80 | UInt8(values.count)
            ])
            values.forEach {
                result.append(pack($0.0))
                result.append(pack($0.1))
            }
            return result
        case .integer(let integer):
            return Data([UInt8(truncatingIfNeeded: integer)])
        case .boolean(let value):
            return Data([value ? 0xc3 : 0xc2])
        case .null:
            return Data([0xc0])
        }
    }
}

import Foundation

struct ReticulumAnnounce: Identifiable, Codable, Hashable {
    let id: UUID

    let destinationHash: Data
    let publicKey: Data
    let ratchet: Data?
    let appData: Data?
    let receivedAt: Date

    init(
        id: UUID = UUID(),
        destinationHash: Data,
        publicKey: Data,
        ratchet: Data? = nil,
        appData: Data? = nil,
        receivedAt: Date = Date()
    ) throws {
        guard destinationHash.count ==
                ReticulumPacketEncoder.destinationHashByteCount
        else {
            throw ReticulumAnnounceError.invalidDestinationHash
        }

        guard publicKey.count ==
                ReticulumIdentity.combinedKeyByteCount
        else {
            throw ReticulumAnnounceError.invalidPublicKey
        }

        guard ratchet == nil ||
                ratchet?.count == 32
        else {
            throw ReticulumAnnounceError.invalidPublicKey
        }

        self.id = id
        self.destinationHash = destinationHash
        self.publicKey = publicKey
        self.ratchet = ratchet
        self.appData = appData
        self.receivedAt = receivedAt
    }

    var destinationHashHex: String {
        destinationHash
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var encryptionPublicKey: Data {
        Data(
            publicKey.prefix(
                ReticulumIdentity.encryptionKeyByteCount
            )
        )
    }

    var signingPublicKey: Data {
        Data(
            publicKey.suffix(
                ReticulumIdentity.signingKeyByteCount
            )
        )
    }

    var displayName: String? {
        guard let appData else {
            return nil
        }

        return LXMFMessageCodec()
            .decodeAnnounceDisplayName(appData)
    }
}

enum ReticulumAnnounceError: LocalizedError {
    case invalidDestinationHash
    case invalidPublicKey
    case malformedPacket
    case invalidSignature

    var errorDescription: String? {
        switch self {
        case .invalidDestinationHash:
            return "The announce destination hash is invalid."

        case .invalidPublicKey:
            return "The announce public key is invalid."

        case .malformedPacket:
            return "The announce packet is malformed."

        case .invalidSignature:
            return "The announce signature could not be verified."
        }
    }
}

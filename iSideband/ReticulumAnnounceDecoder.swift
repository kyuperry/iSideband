import Foundation
import CryptoKit

struct ReticulumAnnounceDecoder {
    private static let publicKeyByteCount =
        ReticulumIdentity.combinedKeyByteCount

    private static let nameHashByteCount = 10
    private static let randomHashByteCount = 10
    private static let signatureByteCount = 64

    private static let minimumPayloadByteCount =
        publicKeyByteCount
        + nameHashByteCount
        + randomHashByteCount
        + signatureByteCount

    func decode(
        _ packet: DecodedReticulumPacket
    ) throws -> ReticulumAnnounce {
        guard packet.isAnnounce else {
            throw ReticulumAnnounceError.malformedPacket
        }

        guard packet.payload.count >=
                Self.minimumPayloadByteCount
        else {
            throw ReticulumAnnounceError.malformedPacket
        }

        var cursor = 0

        let publicKey = Data(
            packet.payload[
                cursor..<(cursor + Self.publicKeyByteCount)
            ]
        )

        cursor += Self.publicKeyByteCount

        let nameHash = Data(
            packet.payload[
                cursor..<(cursor + Self.nameHashByteCount)
            ]
        )

        cursor += Self.nameHashByteCount

        let randomHash = Data(
            packet.payload[
                cursor..<(cursor + Self.randomHashByteCount)
            ]
        )

        cursor += Self.randomHashByteCount

        let signature = Data(
            packet.payload[
                cursor..<(cursor + Self.signatureByteCount)
            ]
        )

        cursor += Self.signatureByteCount

        let appData: Data?

        if cursor < packet.payload.count {
            appData = Data(
                packet.payload[cursor..<packet.payload.count]
            )
        } else {
            appData = nil
        }

        guard publicKey.count ==
                ReticulumIdentity.combinedKeyByteCount
        else {
            throw ReticulumAnnounceError.invalidPublicKey
        }

        let identityHash = Data(
            SHA256.hash(data: publicKey)
                .prefix(
                    ReticulumIdentity.truncatedHashByteCount
                )
        )

        var destinationHashMaterial = Data()
        destinationHashMaterial.append(nameHash)
        destinationHashMaterial.append(identityHash)

        let expectedDestinationHash = Data(
            SHA256.hash(data: destinationHashMaterial)
                .prefix(
                    ReticulumPacketEncoder
                        .destinationHashByteCount
                )
        )

        guard expectedDestinationHash ==
                packet.destinationHash
        else {
            throw ReticulumAnnounceError
                .invalidDestinationHash
        }

        var signedData = Data()
        signedData.append(packet.destinationHash)
        signedData.append(publicKey)
        signedData.append(nameHash)
        signedData.append(randomHash)

        if let appData {
            signedData.append(appData)
        }

        let signingPublicKeyData = Data(
            publicKey.suffix(
                ReticulumIdentity.signingKeyByteCount
            )
        )

        let signingPublicKey: Curve25519.Signing.PublicKey

        do {
            signingPublicKey =
                try Curve25519.Signing.PublicKey(
                    rawRepresentation:
                        signingPublicKeyData
                )
        } catch {
            throw ReticulumAnnounceError.invalidPublicKey
        }

        guard signingPublicKey.isValidSignature(
            signature,
            for: signedData
        ) else {
            throw ReticulumAnnounceError.invalidSignature
        }

        return try ReticulumAnnounce(
            destinationHash: packet.destinationHash,
            publicKey: publicKey,
            appData: appData
        )
    }
}

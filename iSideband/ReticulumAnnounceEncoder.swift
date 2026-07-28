import Foundation
import CryptoKit
import Security

struct EncodedReticulumAnnounce {
    let destinationHash: Data
    let payload: Data
}

enum ReticulumAnnounceEncodingError: LocalizedError {
    case invalidDestinationName
    case randomGenerationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidDestinationName:
            return "The Reticulum destination name is invalid."

        case .randomGenerationFailed(let status):
            return """
            Secure random-byte generation failed with status \
            \(status).
            """
        }
    }
}

struct ReticulumAnnounceEncoder {
    private static let nameHashByteCount = 10
    private static let randomByteCount = 5
    private static let timestampByteCount = 5

    func encode(
        identity: ReticulumIdentity,
        destinationName: String,
        appData: Data? = nil
    ) throws -> EncodedReticulumAnnounce {
        let destinationHash = try destinationHash(
            identity: identity,
            destinationName: destinationName
        )
        let cleanedDestinationName = destinationName
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !cleanedDestinationName.isEmpty else {
            throw ReticulumAnnounceEncodingError
                .invalidDestinationName
        }

        let nameData = Data(
            cleanedDestinationName.utf8
        )

        let nameHash = Data(
            SHA256.hash(data: nameData)
                .prefix(Self.nameHashByteCount)
        )

        let randomHash = try makeRandomHash()

        var signedData = Data()
        signedData.append(destinationHash)
        signedData.append(identity.publicKey)
        signedData.append(nameHash)
        signedData.append(randomHash)

        if let appData {
            signedData.append(appData)
        }

        let signature = try identity.sign(
            signedData
        )

        var announcePayload = Data()
        announcePayload.append(identity.publicKey)
        announcePayload.append(nameHash)
        announcePayload.append(randomHash)
        announcePayload.append(signature)

        if let appData {
            announcePayload.append(appData)
        }

        return EncodedReticulumAnnounce(
            destinationHash: destinationHash,
            payload: announcePayload
        )
    }

    func destinationHash(
        identity: ReticulumIdentity,
        destinationName: String
    ) throws -> Data {
        let cleanedDestinationName = destinationName
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !cleanedDestinationName.isEmpty else {
            throw ReticulumAnnounceEncodingError
                .invalidDestinationName
        }

        let nameHash = Data(
            SHA256.hash(
                data: Data(cleanedDestinationName.utf8)
            ).prefix(Self.nameHashByteCount)
        )
        var material = Data()
        material.append(nameHash)
        material.append(identity.identityHash)

        return Data(
            SHA256.hash(data: material)
                .prefix(
                    ReticulumPacketEncoder
                        .destinationHashByteCount
                )
        )
    }

    private func makeRandomHash() throws -> Data {
        var randomBytes = Data(
            repeating: 0,
            count: Self.randomByteCount
        )

        let status = randomBytes.withUnsafeMutableBytes {
            rawBuffer in

            guard let baseAddress =
                    rawBuffer.baseAddress else {
                return errSecParam
            }

            return SecRandomCopyBytes(
                kSecRandomDefault,
                Self.randomByteCount,
                baseAddress
            )
        }

        guard status == errSecSuccess else {
            throw ReticulumAnnounceEncodingError
                .randomGenerationFailed(status)
        }

        let timestamp = UInt64(
            Date().timeIntervalSince1970
        )

        var timestampBytes = Data()

        for shift in stride(
            from: 32,
            through: 0,
            by: -8
        ) {
            timestampBytes.append(
                UInt8(
                    truncatingIfNeeded:
                        timestamp >> UInt64(shift)
                )
            )
        }

        var randomHash = Data()
        randomHash.append(randomBytes)
        randomHash.append(timestampBytes)

        return randomHash
    }
}

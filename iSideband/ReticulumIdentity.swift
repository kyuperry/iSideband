import Foundation
import CryptoKit

enum ReticulumIdentityError: Error {
    case invalidPublicKeyLength
    case invalidPrivateKeyLength
    case invalidImportedPrivateKey
    case cryptographyFailure
}

struct ReticulumIdentity: Codable {
    static let encryptionKeyByteCount = 32
    static let signingKeyByteCount = 32

    static let combinedKeyByteCount =
        encryptionKeyByteCount + signingKeyByteCount

    static let truncatedHashByteCount = 16
    var identityHash: Data {
        let fullHash = SHA256.hash(data: publicKey)

        return Data(
            fullHash.prefix(Self.truncatedHashByteCount)
        )
    }

    var identityHashHex: String {
        identityHash
            .map { String(format: "%02x", $0) }
            .joined()
    }

    let publicKey: Data
    let privateKey: Data

    init(
        publicKey: Data,
        privateKey: Data
    ) throws {
        guard publicKey.count == Self.combinedKeyByteCount else {
            throw ReticulumIdentityError.invalidPublicKeyLength
        }

        guard privateKey.count == Self.combinedKeyByteCount else {
            throw ReticulumIdentityError.invalidPrivateKeyLength
        }

        self.publicKey = publicKey
        self.privateKey = privateKey
    }

    var encryptionPublicKey: Data {
        Data(publicKey.prefix(Self.encryptionKeyByteCount))
    }

    var signingPublicKey: Data {
        Data(publicKey.suffix(Self.signingKeyByteCount))
    }

    var encryptionPrivateKey: Data {
        Data(privateKey.prefix(Self.encryptionKeyByteCount))
    }

    var signingPrivateKey: Data {
        Data(privateKey.suffix(Self.signingKeyByteCount))
    }

    static func generate() throws -> ReticulumIdentity {
        let encryptionPrivateKey =
            Curve25519.KeyAgreement.PrivateKey()

        let signingPrivateKey =
            Curve25519.Signing.PrivateKey()

        let combinedPublicKey =
            encryptionPrivateKey.publicKey.rawRepresentation
            + signingPrivateKey.publicKey.rawRepresentation

        let combinedPrivateKey =
            encryptionPrivateKey.rawRepresentation
            + signingPrivateKey.rawRepresentation

        return try ReticulumIdentity(
            publicKey: combinedPublicKey,
            privateKey: combinedPrivateKey
        )
    }
    static func importPrivateKey(
        _ combinedPrivateKey: Data
    ) throws -> ReticulumIdentity {

        guard combinedPrivateKey.count == combinedKeyByteCount else {
            throw ReticulumIdentityError.invalidPrivateKeyLength
        }

        let encryptionPrivateBytes =
            Data(combinedPrivateKey.prefix(encryptionKeyByteCount))

        let signingPrivateBytes =
            Data(combinedPrivateKey.suffix(signingKeyByteCount))

        do {
            let encryptionPrivateKey =
                try Curve25519.KeyAgreement.PrivateKey(
                    rawRepresentation: encryptionPrivateBytes
                )

            let signingPrivateKey =
                try Curve25519.Signing.PrivateKey(
                    rawRepresentation: signingPrivateBytes
                )

            let combinedPublicKey =
                encryptionPrivateKey.publicKey.rawRepresentation
                + signingPrivateKey.publicKey.rawRepresentation

            return try ReticulumIdentity(
                publicKey: combinedPublicKey,
                privateKey: combinedPrivateKey
            )

        } catch {
            throw ReticulumIdentityError.invalidImportedPrivateKey
        }
    }

    func sign(_ data: Data) throws -> Data {
        do {
            let key = try Curve25519.Signing.PrivateKey(
                rawRepresentation: signingPrivateKey
            )

            return try key.signature(for: data)
        } catch {
            throw ReticulumIdentityError.cryptographyFailure
        }
    }

    func verify(
        signature: Data,
        for data: Data
    ) -> Bool {
        do {
            let key = try Curve25519.Signing.PublicKey(
                rawRepresentation: signingPublicKey
            )

            return key.isValidSignature(
                signature,
                for: data
            )
        } catch {
            return false
        }
    }

    func encrypt(
        _ data: Data,
        for destinationPublicKey: Data,
        ratchet: Data? = nil
    ) throws -> Data {
        guard destinationPublicKey.count ==
                Self.combinedKeyByteCount
        else {
            throw ReticulumIdentityError.invalidPublicKeyLength
        }

        return try ReticulumTokenCipher().encrypt(
            data,
            recipientPublicKey: ratchet ??
                Data(
                    destinationPublicKey.prefix(
                        Self.encryptionKeyByteCount
                    )
                ),
            salt: Data(
                SHA256.hash(data: destinationPublicKey)
                    .prefix(Self.truncatedHashByteCount)
            )
        )
    }

    func decrypt(_ data: Data) throws -> Data {
        return try ReticulumTokenCipher().decrypt(
            data,
            recipientPrivateKey: encryptionPrivateKey,
            salt: identityHash
        )
    }
}

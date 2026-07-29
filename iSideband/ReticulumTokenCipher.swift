import CommonCrypto
import CryptoKit
import Foundation
import Security

enum ReticulumTokenCipherError: Error {
    case invalidToken
    case authenticationFailed
    case encryptionFailed
}

final class ReticulumRatchet {
    static let shared = ReticulumRatchet()

    private let privateKey =
        Curve25519.KeyAgreement.PrivateKey()

    private init() {}

    var publicKey: Data {
        privateKey.publicKey.rawRepresentation
    }

    func decrypt(
        _ ciphertextToken: Data,
        identityHash: Data
    ) throws -> Data {
        try ReticulumTokenCipher().decrypt(
            ciphertextToken,
            recipientPrivateKey:
                privateKey.rawRepresentation,
            salt: identityHash
        )
    }
}

struct ReticulumTokenCipher {
    private static let ephemeralKeyByteCount = 32
    private static let ivByteCount = kCCBlockSizeAES128
    private static let hmacByteCount = 32
    private static let derivedKeyByteCount = 64

    func encrypt(
        _ plaintext: Data,
        recipientPublicKey: Data,
        salt: Data
    ) throws -> Data {
        let ephemeralKey =
            Curve25519.KeyAgreement.PrivateKey()
        let recipientKey =
            try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: recipientPublicKey
            )
        let sharedSecret = try ephemeralKey.sharedSecretFromKeyAgreement(
            with: recipientKey
        )
        let key = deriveKey(
            sharedSecret: sharedSecret,
            salt: salt
        )
        let token = try seal(plaintext, key: key)

        return ephemeralKey.publicKey.rawRepresentation + token
    }

    func decrypt(
        _ ciphertextToken: Data,
        recipientPrivateKey: Data,
        salt: Data
    ) throws -> Data {
        guard ciphertextToken.count >
                Self.ephemeralKeyByteCount else {
            throw ReticulumTokenCipherError.invalidToken
        }

        let ephemeralPublicKey =
            try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation:
                    ciphertextToken.prefix(
                        Self.ephemeralKeyByteCount
                    )
            )
        let privateKey =
            try Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: recipientPrivateKey
            )
        let sharedSecret =
            try privateKey.sharedSecretFromKeyAgreement(
                with: ephemeralPublicKey
            )
        let key = deriveKey(
            sharedSecret: sharedSecret,
            salt: salt
        )

        return try open(
            Data(
                ciphertextToken.dropFirst(
                    Self.ephemeralKeyByteCount
                )
            ),
            key: key
        )
    }

    private func deriveKey(
        sharedSecret: SharedSecret,
        salt: Data
    ) -> Data {
        let key = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data(),
            outputByteCount: Self.derivedKeyByteCount
        )

        return key.withUnsafeBytes { Data($0) }
    }

    private func seal(
        _ plaintext: Data,
        key: Data
    ) throws -> Data {
        var iv = Data(
            repeating: 0,
            count: Self.ivByteCount
        )
        let status = iv.withUnsafeMutableBytes {
            SecRandomCopyBytes(
                kSecRandomDefault,
                Self.ivByteCount,
                $0.baseAddress!
            )
        }
        guard status == errSecSuccess else {
            throw ReticulumTokenCipherError.encryptionFailed
        }

        let ciphertext = try crypt(
            plaintext,
            operation: CCOperation(kCCEncrypt),
            key: Data(key.suffix(32)),
            iv: iv
        )
        let signedData = iv + ciphertext
        let authenticationKey =
            SymmetricKey(data: key.prefix(32))
        let hmac = Data(
            HMAC<SHA256>.authenticationCode(
                for: signedData,
                using: authenticationKey
            )
        )

        return signedData + hmac
    }

    private func open(
        _ token: Data,
        key: Data
    ) throws -> Data {
        guard token.count >
                Self.ivByteCount + Self.hmacByteCount else {
            throw ReticulumTokenCipherError.invalidToken
        }

        let signedData =
            Data(token.dropLast(Self.hmacByteCount))
        let receivedHMAC =
            Data(token.suffix(Self.hmacByteCount))
        let authenticationKey =
            SymmetricKey(data: key.prefix(32))

        guard HMAC<SHA256>.isValidAuthenticationCode(
            receivedHMAC,
            authenticating: signedData,
            using: authenticationKey
        ) else {
            throw ReticulumTokenCipherError
                .authenticationFailed
        }

        return try crypt(
            Data(
                signedData.dropFirst(Self.ivByteCount)
            ),
            operation: CCOperation(kCCDecrypt),
            key: Data(key.suffix(32)),
            iv: Data(
                signedData.prefix(Self.ivByteCount)
            )
        )
    }

    private func crypt(
        _ input: Data,
        operation: CCOperation,
        key: Data,
        iv: Data
    ) throws -> Data {
        let outputCapacity =
            input.count + kCCBlockSizeAES128
        var output = Data(
            repeating: 0,
            count: outputCapacity
        )
        var outputLength = 0

        let status = output.withUnsafeMutableBytes {
            outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            input.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw ReticulumTokenCipherError.encryptionFailed
        }

        output.removeSubrange(outputLength..<output.count)
        return output
    }
}

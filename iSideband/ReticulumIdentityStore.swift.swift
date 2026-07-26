import Foundation
import Security

enum ReticulumIdentityStoreError: Error {
    case encodingFailed
    case decodingFailed
    case keychainFailure(OSStatus)
}

final class ReticulumIdentityStore {
    static let shared = ReticulumIdentityStore()

    private let service = "com.kyuperry.iSideband"
    private let account = "reticulum.identity"

    private init() {}

    func loadOrCreateIdentity() throws -> ReticulumIdentity {
        if let savedIdentity = try loadIdentity() {
            return savedIdentity
        }

        let newIdentity = try ReticulumIdentity.generate()
        try saveIdentity(newIdentity)

        return newIdentity
    }

    func importIdentity(
        from privateKeyData: Data
    ) throws -> ReticulumIdentity {
        let importedIdentity =
            try ReticulumIdentity.importPrivateKey(privateKeyData)

        try saveIdentity(importedIdentity)

        return importedIdentity
    }

    func saveIdentity(
        _ identity: ReticulumIdentity
    ) throws {
        let encoder = JSONEncoder()

        guard let encodedIdentity = try? encoder.encode(identity) else {
            throw ReticulumIdentityStoreError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: encodedIdentity,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw ReticulumIdentityStoreError.keychainFailure(
                updateStatus
            )
        }

        var insertQuery = query

        for (key, value) in attributes {
            insertQuery[key] = value
        }

        let insertStatus = SecItemAdd(
            insertQuery as CFDictionary,
            nil
        )

        guard insertStatus == errSecSuccess else {
            throw ReticulumIdentityStoreError.keychainFailure(
                insertStatus
            )
        }
    }

    func loadIdentity() throws -> ReticulumIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?

        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw ReticulumIdentityStoreError.keychainFailure(
                status
            )
        }

        guard let identityData = result as? Data else {
            throw ReticulumIdentityStoreError.decodingFailed
        }

        do {
            return try JSONDecoder().decode(
                ReticulumIdentity.self,
                from: identityData
            )
        } catch {
            throw ReticulumIdentityStoreError.decodingFailed
        }
    }
}

import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let iSidebandBackup = UTType(
        exportedAs: "com.kyleperry.iSideband.backup",
        conformingTo: .json
    )
}

nonisolated struct iSidebandBackup: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let identityPrivateKey: Data
    let identityHash: String
    let contacts: [LXMFContact]
    let discoveredPeers: [ReticulumDiscoveredPeer]
    let announces: [ReticulumAnnounce]
    let announceHistory: [ReticulumAnnounce]
}

struct iSidebandBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.iSidebandBackup]
    }

    let backup: iSidebandBackup

    init(backup: iSidebandBackup) {
        self.backup = backup
    }

    init(configuration: ReadConfiguration) throws {
        guard let data =
                configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        backup = try decoder.decode(
            iSidebandBackup.self,
            from: data
        )
    }

    func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]
        encoder.dateEncodingStrategy = .iso8601

        return FileWrapper(
            regularFileWithContents:
                try encoder.encode(backup)
        )
    }

    @MainActor
    static func create() throws
        -> iSidebandBackupDocument {
        let identity =
            try ReticulumIdentityStore.shared
                .loadOrCreateIdentity()

        return iSidebandBackupDocument(
            backup: iSidebandBackup(
                formatVersion: 1,
                exportedAt: Date(),
                identityPrivateKey:
                    identity.privateKey,
                identityHash:
                    identity.identityHashHex,
                contacts:
                    LXMFContactStore.shared.contacts,
                discoveredPeers:
                    ReticulumDiscoveredPeerStore
                        .shared.peers,
                announces:
                    ReticulumAnnounceStore
                        .shared.announces,
                announceHistory:
                    ReticulumAnnounceStore
                        .shared.history
            )
        )
    }
}

import Foundation

struct LXMFContact: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var destinationHash: String
    var notes: String
    var dateAdded: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        destinationHash: String,
        notes: String = "",
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        self.destinationHash = destinationHash
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        self.notes = notes
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        self.dateAdded = dateAdded
    }

    var isDestinationValid: Bool {
        guard destinationHash.count == 32 else {
            return false
        }

        let allowedCharacters = CharacterSet(
            charactersIn: "0123456789abcdef"
        )

        return destinationHash.unicodeScalars.allSatisfy {
            allowedCharacters.contains($0)
        }
    }

    var peer: LXMFPeer {
        LXMFPeer(
            displayName: displayName,
            destinationHash: destinationHash
        )
    }
}

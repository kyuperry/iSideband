import Foundation

struct LXMFPeer: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var destinationHash: String

    init(
        id: UUID = UUID(),
        displayName: String,
        destinationHash: String
    ) {
        self.id = id
        self.displayName = displayName
        self.destinationHash = destinationHash
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
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
}

import Foundation
import Combine

@MainActor
final class LXMFContactStore: ObservableObject {
    static let shared = LXMFContactStore()

    @Published private(set) var contacts: [LXMFContact] = []

    private let storageKey = "isideband.lxmf.contacts"

    private init() {
        loadContacts()
    }

    func add(_ contact: LXMFContact) throws {
        guard contact.isDestinationValid else {
            throw LXMFContactStoreError.invalidDestinationHash
        }

        guard !contains(destinationHash: contact.destinationHash) else {
            throw LXMFContactStoreError.duplicateContact
        }

        contacts.append(contact)

        contacts.sort {
            $0.displayName.localizedCaseInsensitiveCompare(
                $1.displayName
            ) == .orderedAscending
        }

        saveContacts()
    }

    func update(_ contact: LXMFContact) throws {
        guard contact.isDestinationValid else {
            throw LXMFContactStoreError.invalidDestinationHash
        }

        guard let index = contacts.firstIndex(
            where: { $0.id == contact.id }
        ) else {
            throw LXMFContactStoreError.contactNotFound
        }

        let duplicateExists = contacts.contains {
            $0.id != contact.id &&
            $0.destinationHash == contact.destinationHash
        }

        guard !duplicateExists else {
            throw LXMFContactStoreError.duplicateContact
        }

        contacts[index] = contact

        contacts.sort {
            $0.displayName.localizedCaseInsensitiveCompare(
                $1.displayName
            ) == .orderedAscending
        }

        saveContacts()
    }

    func remove(_ contact: LXMFContact) {
        contacts.removeAll {
            $0.id == contact.id
        }

        saveContacts()
    }

    func contains(destinationHash: String) -> Bool {
        let cleanedHash = destinationHash
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        return contacts.contains {
            $0.destinationHash == cleanedHash
        }
    }

    func contact(
        for destinationHash: String
    ) -> LXMFContact? {
        let cleanedHash = destinationHash
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        return contacts.first {
            $0.destinationHash == cleanedHash
        }
    }

    private func saveContacts() {
        do {
            let data = try JSONEncoder().encode(contacts)

            UserDefaults.standard.set(
                data,
                forKey: storageKey
            )
        } catch {
            print(
                "Failed to save LXMF contacts: " +
                error.localizedDescription
            )
        }
    }

    private func loadContacts() {
        guard let data = UserDefaults.standard.data(
            forKey: storageKey
        ) else {
            contacts = []
            return
        }

        do {
            contacts = try JSONDecoder().decode(
                [LXMFContact].self,
                from: data
            )

            contacts.sort {
                $0.displayName.localizedCaseInsensitiveCompare(
                    $1.displayName
                ) == .orderedAscending
            }
        } catch {
            contacts = []

            print(
                "Failed to load LXMF contacts: " +
                error.localizedDescription
            )
        }
    }
}

enum LXMFContactStoreError: LocalizedError {
    case invalidDestinationHash
    case duplicateContact
    case contactNotFound

    var errorDescription: String? {
        switch self {
        case .invalidDestinationHash:
            return "The destination hash is invalid."

        case .duplicateContact:
            return "A contact with this destination already exists."

        case .contactNotFound:
            return "The contact could not be found."
        }
    }
}

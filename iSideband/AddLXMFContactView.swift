import SwiftUI

struct AddLXMFContactView: View {
    @Environment(\.dismiss)
    private var dismiss

    @State private var displayName = ""
    @State private var destinationHash = ""
    @State private var notes = ""

    let onSave: (LXMFContact) -> Void

    private var trimmedName: String {
        displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var cleanedDestinationHash: String {
        destinationHash
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
    }

    private var contactToSave: LXMFContact {
        LXMFContact(
            displayName: trimmedName,
            destinationHash: cleanedDestinationHash,
            notes: notes
        )
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
            && contactToSave.isDestinationValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    TextField(
                        "Display Name",
                        text: $displayName
                    )

                    TextField(
                        "32-character destination hash",
                        text: $destinationHash
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .fontDesign(.monospaced)

                    if !cleanedDestinationHash.isEmpty,
                       !contactToSave.isDestinationValid {
                        Text(
                            "Enter a valid 32-character hexadecimal LXMF destination hash."
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }

                Section("Notes") {
                    TextField(
                        "Optional notes",
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                Section {
                    HStack {
                        Text("Destination length")

                        Spacer()

                        Text(
                            "\(cleanedDestinationHash.count) / 32"
                        )
                        .foregroundStyle(
                            cleanedDestinationHash.count == 32
                                ? Color.green
                                : Color.secondary
                        )
                    }
                }
            }
            .navigationTitle("Add LXMF Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Save") {
                        onSave(contactToSave)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview {
    AddLXMFContactView { contact in
        print(
            """
            Saved contact:
            \(contact.displayName)
            \(contact.destinationHash)
            """
        )
    }
}

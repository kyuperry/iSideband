import SwiftUI

struct LXMFContactPickerView: View {
    @ObservedObject var bluetooth: BluetoothManager

    @ObservedObject private var contactStore =
        LXMFContactStore.shared

    var body: some View {
        Group {
            if contactStore.contacts.isEmpty {
                ContentUnavailableView {
                    Label(
                        "No LXMF Contacts",
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                } description: {
                    Text(
                        "Add an LXMF contact before starting a direct conversation."
                    )
                }
            } else {
                List(contactStore.contacts) { contact in
                    NavigationLink {
                        MessagesView(
                            bluetooth: bluetooth,
                            contact: contact
                        )
                    } label: {
                        contactRow(contact)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Choose Contact")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func contactRow(
        _ contact: LXMFContact
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName: "person.crop.circle.fill"
            )
            .font(.system(size: 40))
            .foregroundStyle(.blue)

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(contact.displayName)
                    .font(.headline)

                Text(contact.destinationHash)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

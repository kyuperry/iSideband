import SwiftUI

struct DiscoveredPeersView: View {
    let focusedDestinationHash: String?

    @ObservedObject private var discoveredStore =
        ReticulumDiscoveredPeerStore.shared

    @ObservedObject private var contactStore =
        LXMFContactStore.shared

    @State private var errorMessage: String?

    init(focusedDestinationHash: String? = nil) {
        self.focusedDestinationHash =
            focusedDestinationHash?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if discoveredStore.peers.isEmpty {
                    ContentUnavailableView {
                        Label(
                            "No Discovered Peers",
                            systemImage:
                                "antenna.radiowaves.left.and.right"
                        )
                    } description: {
                        Text(
                            "Nearby Reticulum peers will appear here after iSideband receives their announcements."
                        )
                    }
                } else {
                    List {
                        ForEach(discoveredStore.peers) { peer in
                            peerRow(peer)
                                .id(peer.destinationHash)
                                .listRowBackground(
                                    isFocused(peer)
                                    ? Color.blue.opacity(0.14)
                                    : Color.clear
                                )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .onAppear {
                guard let focusedDestinationHash else {
                    return
                }

                DispatchQueue.main.async {
                    withAnimation {
                        proxy.scrollTo(
                            focusedDestinationHash,
                            anchor: .center
                        )
                    }
                }
            }
        }
        .navigationTitle("Discovered Peers")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Could Not Save Contact",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(
                errorMessage
                    ?? "Unknown error"
            )
        }
    }

    private func isFocused(
        _ peer: ReticulumDiscoveredPeer
    ) -> Bool {
        peer.destinationHash == focusedDestinationHash
    }

    private func peerRow(
        _ peer: ReticulumDiscoveredPeer
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack(spacing: 12) {
                Image(
                    systemName:
                        "antenna.radiowaves.left.and.right.circle.fill"
                )
                .font(.system(size: 40))
                .foregroundStyle(.blue)

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    HStack(spacing: 8) {
                        Text(
                            peer.resolvedDisplayName
                        )
                        .font(.headline)

                        if isNew(peer) {
                            Text("NEW")
                                .font(
                                    .caption2.bold()
                                )
                                .foregroundStyle(.green)
                                .padding(
                                    .horizontal,
                                    7
                                )
                                .padding(
                                    .vertical,
                                    3
                                )
                                .background {
                                    Capsule()
                                        .fill(
                                            Color.green
                                                .opacity(
                                                    0.15
                                                )
                                        )
                                }
                        }
                    }

                    Text(
                        peer.destinationHash
                    )
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            "First Seen: " +
                            peer.firstSeenAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )

                        Text(
                            "Last Seen: " +
                            peer.lastSeenAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if contactStore.contact(
                for: peer.destinationHash
            ) != nil {
                Label(
                    "Saved Contact",
                    systemImage:
                        "checkmark.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    saveContact(peer)
                } label: {
                    Label(
                        "Save Contact",
                        systemImage:
                            "person.crop.circle.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background {
            if isNew(peer) {
                RoundedRectangle(
                    cornerRadius: 12
                )
                .fill(
                    Color.green.opacity(0.10)
                )
            }
        }
    }

    private func isNew(
        _ peer: ReticulumDiscoveredPeer
    ) -> Bool {
        Date().timeIntervalSince(
            peer.firstSeenAt
        ) < 60
    }

    private func saveContact(
        _ peer: ReticulumDiscoveredPeer
    ) {
        let contact = LXMFContact(
            displayName:
                peer.resolvedDisplayName,
            destinationHash:
                peer.destinationHash,
            notes:
                "Discovered from Reticulum announce"
        )

        do {
            try contactStore.add(contact)
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }
}

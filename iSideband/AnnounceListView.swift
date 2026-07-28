import SwiftUI

struct AnnounceListView: View {
    @ObservedObject private var announceStore =
        ReticulumAnnounceStore.shared

    var body: some View {
        Group {
            if announceStore.history.isEmpty {
                ContentUnavailableView {
                    Label(
                        "No Announcements",
                        systemImage:
                            "antenna.radiowaves.left.and.right"
                    )
                } description: {
                    Text(
                        "Nodes will appear here after iSideband receives their Reticulum announcements."
                    )
                }
            } else {
                List {
                    Section(
                        "\(announceStore.history.count) Announcements"
                    ) {
                        ForEach(
                            announceStore.history
                        ) { announce in
                            VStack(
                                alignment: .leading,
                                spacing: 6
                            ) {
                                Text(
                                    announce.displayName
                                        ?? "Unknown Node"
                                )
                                .font(.headline)

                                Text(
                                    announce.destinationHashHex
                                )
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)

                                Text(
                                    announce.receivedAt,
                                    style: .relative
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Announce List")
        .navigationBarTitleDisplayMode(.inline)
    }
}

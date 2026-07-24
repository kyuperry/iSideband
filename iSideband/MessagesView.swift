import SwiftUI

struct MessagesView: View {
    @ObservedObject var bluetooth: BluetoothManager

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ChatView(
                        bluetooth: bluetooth,
                        title: "Broadcast"
                    )
                } label: {
                    Label(
                        "Broadcast",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                }

                NavigationLink {
                    ChatView(
                        bluetooth: bluetooth,
                        title: "Camp Node"
                    )
                } label: {
                    VStack(alignment: .leading) {
                        Text("Camp Node")
                            .font(.headline)

                        Text("Last heard • Just now")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    ChatView(
                        bluetooth: bluetooth,
                        title: "Test Node"
                    )
                } label: {
                    VStack(alignment: .leading) {
                        Text("Test Node")
                            .font(.headline)

                        Text("Offline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Messages")
        }
    }
}

import SwiftUI

struct ConversationsView: View {
    @ObservedObject var bluetooth: BluetoothManager

    var body: some View {
        List {
            NavigationLink {
                MessagesView(bluetooth: bluetooth)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "message.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            bluetooth.connectedDeviceName
                                ?? "Connected RNode"
                        )
                        .font(.headline)

                        Text(
                            bluetooth.connectedDeviceID == nil
                                ? "Disconnected"
                                : "Connected"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Messages")
    }
}

#Preview {
    ConversationsView(
        bluetooth: BluetoothManager()
    )
}

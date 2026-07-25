import SwiftUI

struct ConversationsView: View {
    @ObservedObject var bluetooth: BluetoothManager

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ConversationsView(bluetooth: bluetooth)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "message.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Test Conversation")
                                .font(.headline)

                            Text("Connected RNode")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Messages")
        }
    }
}

#Preview {
    ConversationsView(
        bluetooth: BluetoothManager()
    )
}

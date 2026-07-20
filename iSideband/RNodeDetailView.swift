import SwiftUI

struct RNodeDetailView: View {
    @ObservedObject var bluetooth: BluetoothManager

    var body: some View {
        List {

            Section("Connection") {
                Label(
                    bluetooth.connectedDeviceID != nil
                    ? "Connected"
                    : "Disconnected",
                    systemImage: bluetooth.connectedDeviceID != nil
                    ? "checkmark.circle.fill"
                    : "xmark.circle"
                )

                Label(
                    "RSSI: \(bluetooth.lastRSSI ?? 0) dBm",
                    systemImage: "dot.radiowaves.left.and.right"
                )

                Label(
                    "Packets: \(bluetooth.packetsReceived)",
                    systemImage: "shippingbox.fill"
                )

                if let lastPacket = bluetooth.lastPacketTime {
                    Label(
                        "Last Packet: \(lastPacket.formatted(date: .omitted, time: .standard))",
                        systemImage: "clock"
                    )
                }
            }

            Section("Radio") {
                Text("Firmware: Loading…")
                Text("Board: Loading…")
                Text("Battery: Loading…")
            }
        }
        .navigationTitle(bluetooth.connectedDeviceName ?? "RNode")
    }
}

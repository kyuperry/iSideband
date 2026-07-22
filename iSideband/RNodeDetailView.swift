import SwiftUI

struct RNodeDetailView: View {
    @ObservedObject var bluetooth: BluetoothManager

    var body: some View {
        List {

            Section("Connection") {
                Label(
                    bluetooth.connectedDeviceName ?? "RNode",
                    systemImage: "antenna.radiowaves.left.and.right"
                )
                .font(.headline)
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
                Label(
                    "BLE Firmware: \(bluetooth.firmwareVersion)",
                    systemImage: "cpu"
                )

                Label(
                    "BLE Model: \(bluetooth.boardName)",
                    systemImage: "memorychip"
                )

                Label(
                    bluetooth.batteryPercent.map {
                        "Battery: \($0)%"
                    } ?? "Battery: Loading…",
                    systemImage: "battery.100"
                )
/*
                Label(
                    bluetooth.temperature.map {
                        "Temperature: \(String(format: "%.1f", $0))°C"
                    } ?? "Temperature: Loading…",
                    systemImage: "thermometer.medium"
                )*/
 
/*
                Label(
                    bluetooth.radioReady
                    ? "Radio Ready"
                    : "Radio Status: Loading…",
                    systemImage: bluetooth.radioReady
                    ? "checkmark.circle.fill"
                    : "antenna.radiowaves.left.and.right"
                )
*/
            }
        }
        .navigationTitle(bluetooth.connectedDeviceName ?? "RNode")
    }
}

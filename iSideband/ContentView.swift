import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header

                if bluetooth.devices.isEmpty {
                    emptyState
                } else {
                    deviceList
                }

                scanButton
            }
            .padding()
            .navigationTitle("RNode (\(bluetooth.packetsReceived))")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 54))
                .foregroundStyle(.blue)

            Text(bluetooth.connectionMessage)
            VStack(alignment: .leading, spacing: 4) {
                Text("Packets Received: \(bluetooth.packetsReceived)")
                    .font(.caption)

                Text("BLE RSSI: \(bluetooth.lastRSSI ?? 0) dBm")
                    .font(.caption)

                if let lastPacket = bluetooth.lastPacketTime {
                    Text("Last Packet: \(lastPacket.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                }
            }
            .padding(.top, 8)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Tap an RNode to connect")
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Devices Found",
            systemImage: "dot.radiowaves.left.and.right",
            description: Text(
                bluetooth.isScanning
                    ? "Scanning for nearby BLE devices…"
                    : "Tap Scan to search for your RNode."
            )
        )
        .frame(maxHeight: .infinity)
    }

    private var deviceList: some View {
        List(bluetooth.devices) { device in
            NavigationLink {
                RNodeDetailView(bluetooth: bluetooth)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("\(device.rssi) dBm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                            VStack(alignment: .leading, spacing: 10) {
                                Label("RNode Status", systemImage: "antenna.radiowaves.left.and.right")

                                Divider()

                                Label("Connected", systemImage: "checkmark.circle.fill")

                                Label("Packets: \(bluetooth.packetsReceived)", systemImage: "shippingbox.fill")

                                Label("RSSI: \(bluetooth.lastRSSI ?? 0) dBm", systemImage: "dot.radiowaves.left.and.right")

                                if let lastPacket = bluetooth.lastPacketTime {
                                    Label(
                                        "Last Packet: \(lastPacket.formatted(date: .omitted, time: .standard))",
                                        systemImage: "clock"
                                    )
                                }
                            }
                            .padding()
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    

                    Spacer()

                    if bluetooth.connectingDeviceID == device.id {
                        ProgressView()
                    } else if bluetooth.connectedDeviceID == device.id {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private var scanButton: some View {
        Button {
            if bluetooth.isScanning {
                bluetooth.stopScanning()
            } else {
                bluetooth.startScanning()
            }
        } label: {
            Label(
                bluetooth.isScanning ? "Stop Scanning" : "Scan for RNodes",
                systemImage: bluetooth.isScanning
                    ? "stop.circle"
                    : "magnifyingglass"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(bluetooth.bluetoothState != .poweredOn)
    }
}

#Preview {
    ContentView()
}

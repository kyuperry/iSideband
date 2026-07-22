import SwiftUI

struct RNodeDetailView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @State private var showDisconnectConfirmation = false

    private var isConnected: Bool {
        bluetooth.connectedDeviceID != nil
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(
                        systemName: isConnected
                            ? "checkmark.circle.fill"
                            : "xmark.circle.fill"
                    )
                    .foregroundStyle(isConnected ? .green : .red)

                    Text(
                        isConnected
                            ? "RNode Connected"
                            : "RNode Disconnected"
                    )
                    .fontWeight(.semibold)

                    Spacer()
                }
            }
            Section("Connection") {
                HStack {
                    Label(
                        bluetooth.connectedDeviceName ?? "RNode",
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                    .font(.headline)

                    Spacer()

                    Text(isConnected ? "Connected" : "Disconnected")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(isConnected ? .green : .red)
                }

                if let rssi = bluetooth.lastRSSI {
                    Label(
                        "Signal Strength: \(rssi) dBm",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                } else {
                    Label(
                        "Signal Strength: Unavailable",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section("Activity") {
                if bluetooth.packetsReceived == 0 {
                    Label(
                        "Waiting for RNode traffic…",
                        systemImage: "wave.3.right"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    Label(
                        "Packets Received: \(bluetooth.packetsReceived)",
                        systemImage: "shippingbox.fill"
                    )

                    if let lastPacket = bluetooth.lastPacketTime {
                        Label(
                            "Last Packet: \(lastPacket.formatted(date: .omitted, time: .standard))",
                            systemImage: "clock"
                        )
                    }
                }
            }

            Section("Hardware") {
                Label(
                    bluetooth.firmwareVersion == "Unknown"
                        ? "RNode Firmware: Not reported"
                        : "RNode Firmware: \(bluetooth.firmwareVersion)",
                    systemImage: "cpu"
                )

                Label(
                    "Model: \(bluetooth.boardName)",
                    systemImage: "memorychip"
                )

                Label(
                    bluetooth.batteryPercent.map {
                        "Battery: \($0)%"
                    } ?? "Battery: Loading…",
                    systemImage: batteryIcon
                )
            }
            Section("Radio Settings") {
                Text(
                "These values will appear after the RNode reports its current radio configuration."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
                
                Label(
                    bluetooth.radioFrequency.map {
                        "Frequency: \($0) Hz"
                    } ?? "Frequency: Not reported",
                    systemImage: "waveform"
                )

                Label(
                    bluetooth.radioBandwidth.map {
                        "Bandwidth: \($0) Hz"
                    } ?? "Bandwidth: Not reported",
                    systemImage: "arrow.left.and.right"
                )

                Label(
                    bluetooth.transmitPower.map {
                        "Transmit Power: \($0) dBm"
                    } ?? "Transmit Power: Not reported",
                    systemImage: "bolt.horizontal"
                )

                Label(
                    bluetooth.spreadingFactor.map {
                        "Spreading Factor: SF\($0)"
                    } ?? "Spreading Factor: Not reported",
                    systemImage: "dot.radiowaves.up.forward"
                )

                Label(
                    bluetooth.codingRate.map {
                        "Coding Rate: 4/\($0)"
                    } ?? "Coding Rate: Not reported",
                    systemImage: "square.grid.3x3"
                )
            }

            Section {
                if isConnected {
                    Button(role: .destructive) {
                        showDisconnectConfirmation = true
                    } label: {
                        Label(
                            "Disconnect RNode",
                            systemImage: "xmark.circle"
                        )
                    }
                } else {
                    Button {
                        guard let device = bluetooth.devices.first else {
                            return
                        }

                        bluetooth.connect(to: device)
                    } label: {
                        Label(
                            "Reconnect RNode",
                            systemImage: "arrow.clockwise.circle"
                        )
                    }
                }
            }
        }
        .navigationTitle(
            bluetooth.connectedDeviceName ?? "RNode Details"
        )
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Disconnect from RNode?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                bluetooth.disconnect()
            }

            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text(
                "This will end the Bluetooth connection without restarting the RNode."
            )
        }
    }

    private var batteryIcon: String {
        guard let percent = bluetooth.batteryPercent else {
            return "battery.0"
        }

        switch percent {
        case 76...100:
            return "battery.100"
        case 51...75:
            return "battery.75"
        case 26...50:
            return "battery.50"
        case 1...25:
            return "battery.25"
        default:
            return "battery.0"
        }
    }
}

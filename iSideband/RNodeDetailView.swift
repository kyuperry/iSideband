import SwiftUI
import CryptoKit
import UIKit

struct RNodeDetailView: View {
    @ObservedObject var bluetooth: BluetoothManager

    @State private var showDisconnectConfirmation = false
    @State private var identityHash = "Loading…"
    @State private var destinationHash = "Loading…"

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
                    .foregroundStyle(
                        isConnected ? .green : .red
                    )

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
                        bluetooth.connectedDeviceName
                            ?? "RNode",
                        systemImage:
                            "antenna.radiowaves.left.and.right"
                    )
                    .font(.headline)

                    Spacer()

                    Text(
                        isConnected
                            ? "Connected"
                            : "Disconnected"
                    )
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        isConnected ? .green : .red
                    )
                }

                if let rssi = bluetooth.lastRSSI {
                    Label(
                        "Signal Strength: \(rssi) dBm",
                        systemImage:
                            "dot.radiowaves.left.and.right"
                    )
                } else {
                    Label(
                        "Signal Strength: Unavailable",
                        systemImage:
                            "dot.radiowaves.left.and.right"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section("Reticulum Identity") {
                identityRow(
                    title: "Destination Hash",
                    value: destinationHash,
                    systemImage:
                        "point.3.connected.trianglepath.dotted",
                    copyLabel: "Copy Destination Hash"
                )

                identityRow(
                    title: "Identity Hash",
                    value: identityHash,
                    systemImage: "person.text.rectangle",
                    copyLabel: "Copy Identity Hash"
                )

                Text(
                    """
                    Your identity is stored securely in the iPhone Keychain. The destination hash identifies your LXMF delivery destination.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
                        """
                        Packets Received: \
                        \(bluetooth.packetsReceived)
                        """,
                        systemImage: "shippingbox.fill"
                    )

                    if let lastPacket =
                        bluetooth.lastPacketTime {
                        Label(
                            """
                            Last Packet: \
                            \(lastPacket.formatted(
                                date: .omitted,
                                time: .standard
                            ))
                            """,
                            systemImage: "clock"
                        )
                    }
                }
            }

            Section("Hardware") {
                Label(
                    bluetooth.firmwareVersion == "Unknown"
                        ? "RNode Firmware: Not reported"
                        : """
                          RNode Firmware: \
                          \(bluetooth.firmwareVersion)
                          """,
                    systemImage: "cpu"
                )

                Label(
                    "Model: \(bluetooth.boardName)",
                    systemImage: "memorychip"
                )
            }

            Section("Radio Settings") {
                Text(
                    """
                    These values will appear after the RNode reports its current radio configuration.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(
                    bluetooth.radioFrequency.map {
                        String(
                            format:
                                "Frequency: %.3f MHz",
                            Double($0) / 1_000_000
                        )
                    } ?? "Frequency: Not reported",
                    systemImage: "waveform"
                )

                Label(
                    bluetooth.radioBandwidth.map {
                        String(
                            format:
                                "Bandwidth: %.0f kHz",
                            Double($0) / 1_000
                        )
                    } ?? "Bandwidth: Not reported",
                    systemImage:
                        "arrow.left.and.right"
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
                    systemImage:
                        "dot.radiowaves.up.forward"
                )

                Label(
                    bluetooth.codingRate.map {
                        "Coding Rate: 4/\($0)"
                    } ?? "Coding Rate: Not reported",
                    systemImage: "square.grid.3x3"
                )

                Label(
                    bluetooth.batteryPercent.map {
                        "Battery: \($0)%"
                    } ?? "Battery: Not reported",
                    systemImage: batteryIcon
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
                        guard
                            let device =
                                bluetooth.devices.first
                        else {
                            return
                        }

                        bluetooth.connect(to: device)
                    } label: {
                        Label(
                            "Reconnect RNode",
                            systemImage:
                                "arrow.clockwise.circle"
                        )
                    }
                }
            }
        }
        .navigationTitle(
            bluetooth.connectedDeviceName
                ?? "RNode Details"
        )
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadReticulumHashes()
        }
        .confirmationDialog(
            "Disconnect from RNode?",
            isPresented:
                $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "Disconnect",
                role: .destructive
            ) {
                bluetooth.disconnect()
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text(
                """
                This will end the Bluetooth connection without restarting the RNode.
                """
            )
        }
    }

    private func identityRow(
        title: String,
        value: String,
        systemImage: String,
        copyLabel: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Label(
                title,
                systemImage: systemImage
            )
            .font(.subheadline.weight(.semibold))

            HStack(
                alignment: .top,
                spacing: 10
            ) {
                Text(value)
                    .font(
                        .system(
                            .caption,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                Spacer(minLength: 4)

                Button {
                    copyHash(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(copyLabel)
                .disabled(
                    value == "Loading…"
                        || value == "Unavailable"
                )
            }
        }
        .padding(.vertical, 3)
    }

    private func loadReticulumHashes() {
        do {
            let identity =
                try ReticulumIdentityStore.shared
                    .loadOrCreateIdentity()

            identityHash =
                identity.identityHashHex

            destinationHash =
                makeLXMFDeliveryDestinationHash(
                    identityHash:
                        identity.identityHash
                )
        } catch {
            identityHash = "Unavailable"
            destinationHash = "Unavailable"

            print(
                """
                Could not load Reticulum identity: \
                \(error)
                """
            )
        }
    }

    private func makeLXMFDeliveryDestinationHash(
        identityHash: Data
    ) -> String {
        /*
         Reticulum destination:

         name_hash =
             SHA256("lxmf.delivery")
             truncated to 10 bytes

         destination_hash =
             SHA256(name_hash + identity_hash)
             truncated to 16 bytes
         */

        let destinationName =
            Data("lxmf.delivery".utf8)

        let fullNameHash =
            SHA256.hash(
                data: destinationName
            )

        let nameHash =
            Data(fullNameHash.prefix(10))

        var destinationMaterial = Data()
        destinationMaterial.append(nameHash)
        destinationMaterial.append(identityHash)

        let fullDestinationHash =
            SHA256.hash(
                data: destinationMaterial
            )

        return Data(
            fullDestinationHash.prefix(16)
        )
        .map {
            String(
                format: "%02x",
                $0
            )
        }
        .joined()
    }

    private func copyHash(
        _ value: String
    ) {
        guard
            value != "Loading…",
            value != "Unavailable"
        else {
            return
        }

        UIPasteboard.general.string = value
    }

    private var batteryIcon: String {
        guard
            let percent =
                bluetooth.batteryPercent
        else {
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

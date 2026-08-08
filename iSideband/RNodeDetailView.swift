import SwiftUI
import CryptoKit
import UIKit
import CoreLocation

struct RNodeDetailView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject private var locationTelemetry =
        LocationTelemetryManager.shared
    @ObservedObject private var reticulumCore =
        ReticulumCoreBridge.shared

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
            }

            Section("Reticulum Identity") {
                identityRow(
                    title: "Link Destination",
                    value:
                        reticulumCore.destinationHash.isEmpty
                            ? "Unavailable"
                            : reticulumCore.destinationHash,
                    systemImage: "link",
                    copyLabel:
                        "Copy Link Destination Hash"
                )

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
                if let lastPacket =
                    bluetooth.lastPacketTime {
                    Label(
                        "Last Reticulum Activity",
                        systemImage:
                            "antenna.radiowaves.left.and.right"
                    )

                    Label(
                        lastPacket.formatted(
                            date: .omitted,
                            time: .standard
                        ),
                        systemImage: "clock"
                    )
                } else {
                    Label(
                        "Waiting for Reticulum activity...",
                        systemImage:
                            "antenna.radiowaves.left.and.right"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section("iPhone GPS") {
                if !UserDefaults.standard.bool(
                    forKey: "gpsInterfaceEnabled"
                ) {
                    Label(
                        "GPS is disabled in iSideband Settings",
                        systemImage: "location.slash"
                    )
                    .foregroundStyle(.secondary)
                } else if let location = locationTelemetry.location {
                    telemetryRow(
                        title: "Coordinates",
                        value: String(
                            format: "%.6f, %.6f",
                            location.coordinate.latitude,
                            location.coordinate.longitude
                        ),
                        systemImage: "location"
                    )
                    telemetryRow(
                        title: "Accuracy",
                        value: String(
                            format: "±%.0f m",
                            location.horizontalAccuracy
                        ),
                        systemImage: "scope"
                    )
                    telemetryRow(
                        title: "Altitude",
                        value: String(
                            format: "%.0f m",
                            location.altitude
                        ),
                        systemImage: "mountain.2"
                    )
                } else {
                    Label(
                        locationTelemetry.errorMessage
                            ?? "Waiting for a location fix",
                        systemImage: "location.circle"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section("Radio Telemetry") {
                telemetryRow(
                    title: "Reticulum Received",
                    value: kilobyteString(
                        byteCount:
                            Int64(bluetooth.reticulumBytesReceived)
                    ),
                    systemImage: "arrow.down.circle"
                )
                telemetryRow(
                    title: "Reticulum Transmitted",
                    value: kilobyteString(
                        byteCount:
                            Int64(
                                bluetooth.reticulumBytesTransmitted
                            )
                    ),
                    systemImage: "arrow.up.circle"
                )
                telemetryRow(
                    title: "Inbound Diagnostic",
                    value: bluetooth.lastInboundDiagnostic,
                    systemImage: "stethoscope"
                )
                if let packetRSSI = bluetooth.packetRSSI {
                    telemetryRow(
                        title: "Last Packet RSSI",
                        value: "\(packetRSSI) dBm",
                        systemImage: "waveform.path.ecg"
                    )
                }
                if let packetSNR = bluetooth.packetSNR {
                    telemetryRow(
                        title: "Last Packet SNR",
                        value: String(format: "%.2f dB", packetSNR),
                        systemImage: "chart.bar"
                    )
                }
                if let temperature = bluetooth.temperature {
                    telemetryRow(
                        title: "Temperature",
                        value: String(format: "%.1f °C", temperature),
                        systemImage: "thermometer.medium"
                    )
                }
                if let satelliteCount = bluetooth.satelliteCount {
                    telemetryRow(
                        title: "Satellites",
                        value: String(satelliteCount),
                        systemImage: "location.north.circle"
                    )
                }
                if let uptimeSeconds = bluetooth.uptimeSeconds {
                    telemetryRow(
                        title: "Uptime",
                        value: Self.formatUptime(seconds: uptimeSeconds),
                        systemImage: "clock"
                    )
                }
            }

            Section("Hardware") {
                Label(
                    "RNode Firmware: Custom",
                    systemImage: "cpu"
                )

                Label(
                    "Model: \(bluetooth.boardName)",
                    systemImage: "memorychip"
                )

                bluetoothSignalRow
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
                            format: "Bandwidth: %.0f kHz",
                            Double($0) / 1_000
                        )
                    } ?? {
                        let savedBandwidth =
                            UserDefaults.standard.double(
                                forKey:
                                    "radioBandwidthKHz"
                            )

                        return savedBandwidth > 0
                            ? String(
                                format:
                                    "Bandwidth: %.0f kHz",
                                savedBandwidth
                            )
                            : "Bandwidth: Not reported"
                    }(),
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
                        "Spreading Factor: \($0)"
                    } ?? {
                        let savedSpreadingFactor =
                            UserDefaults.standard.integer(
                                forKey:
                                    "radioSpreadingFactor"
                            )

                        return savedSpreadingFactor > 0
                            ? "Spreading Factor: \(savedSpreadingFactor)"
                            : "Spreading Factor: Not reported"
                    }(),
                    systemImage:
                        "dot.radiowaves.left.and.right"
                )

                Label(
                    bluetooth.codingRate.map {
                        "Coding Rate: 4/\($0)"
                    } ?? {
                        let savedCodingRate =
                            UserDefaults.standard.integer(
                                forKey:
                                    "radioCodingRate"
                            )

                        return savedCodingRate > 0
                            ? "Coding Rate: 4/\(savedCodingRate)"
                            : "Coding Rate: Not reported"
                    }(),
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

            Button(
                "Cancel",
                role: .cancel
            ) { }
        } message: {
            Text(
                """
                This will end the Bluetooth connection without restarting the RNode.
                """
            )
        }
    }

    private var bluetoothSignalRow: some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    "antenna.radiowaves.left.and.right"
            )
            .foregroundStyle(.blue)
            .frame(width: 24)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text("Bluetooth Signal")

                Text(
                    bluetooth.lastRSSI.map {
                        "\($0) dBm"
                    } ?? "Not available"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let rssi = bluetooth.lastRSSI {
                VStack(
                    alignment: .trailing,
                    spacing: 4
                ) {
                    RSSISignalBars(
                        level: rssiSignalLevel(rssi)
                    )

                    Text(rssiQualityText(rssi))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            rssiSignalColor(rssi)
                        )
                }
            } else {
                Text("Unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func telemetryRow(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private static func formatUptime(seconds: UInt32) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    private func rssiSignalLevel(
        _ rssi: Int
    ) -> Int {
        switch rssi {
        case -60...0:
            return 4

        case -70..<(-60):
            return 3

        case -80..<(-70):
            return 2

        default:
            return 1
        }
    }

    private func rssiQualityText(
        _ rssi: Int
    ) -> String {
        switch rssiSignalLevel(rssi) {
        case 4:
            return "Excellent"

        case 3:
            return "Good"

        case 2:
            return "Fair"

        default:
            return "Weak"
        }
    }

    private func rssiSignalColor(
        _ rssi: Int
    ) -> Color {
        switch rssiSignalLevel(rssi) {
        case 4, 3:
            return .green

        case 2:
            return .yellow

        default:
            return .red
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

    private func kilobyteString(
        byteCount: Int64
    ) -> String {
        String(
            format: "%.2f KB",
            Double(byteCount) / 1_000
        )
    }
}

private struct RSSISignalBars: View {
    let level: Int

    private var barColor: Color {
        switch level {
        case 4, 3:
            return .green

        case 2:
            return .yellow

        default:
            return .red
        }
    }

    var body: some View {
        HStack(
            alignment: .bottom,
            spacing: 3
        ) {
            ForEach(
                1...4,
                id: \.self
            ) { bar in
                RoundedRectangle(
                    cornerRadius: 1.5,
                    style: .continuous
                )
                .fill(
                    bar <= level
                        ? barColor
                        : Color.secondary.opacity(0.25)
                )
                .frame(
                    width: 5,
                    height: CGFloat(5 + (bar * 4))
                )
            }
        }
        .frame(
            height: 22,
            alignment: .bottom
        )
        .accessibilityLabel(
            "Bluetooth signal strength"
        )
        .accessibilityValue(
            "\(level) of 4 bars"
        )
    }
}

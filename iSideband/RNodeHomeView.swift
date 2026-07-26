import SwiftUI
import CoreBluetooth

struct RNodeHomeView: View {
    @ObservedObject var bluetooth: BluetoothManager

    @State private var showSwitchConfirmation = false
    @State private var pendingConnectionID: UUID?

    var body: some View {
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
        .navigationTitle("RNode")
        .confirmationDialog(
            "Switch RNodes?",
            isPresented: $showSwitchConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "Disconnect and Connect",
                role: .destructive
            ) {
                guard
                    let pendingConnectionID,
                    let device = bluetooth.devices.first(
                        where: { $0.id == pendingConnectionID }
                    )
                else {
                    return
                }

                bluetooth.disconnect()

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.5
                ) {
                    bluetooth.connect(to: device)
                }

                self.pendingConnectionID = nil
            }

            Button("Cancel", role: .cancel) {
                pendingConnectionID = nil
            }
        } message: {
            Text(
                "Another RNode is already connected. This will disconnect it and connect to the selected RNode."
            )
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(
                systemName:
                    "antenna.radiowaves.left.and.right"
            )
            .font(.system(size: 54))
            .foregroundStyle(.blue)

            Text(bluetooth.connectionMessage)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(
                bluetooth.connectedDeviceID == nil
                    ? "Tap an RNode to connect"
                    : "Tap the RNode for details"
            )
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Devices Found",
            systemImage:
                "dot.radiowaves.left.and.right",
            description: Text(
                bluetooth.isScanning
                    ? "Scanning for nearby RNodes…"
                    : "Tap Scan to search for your RNode."
            )
        )
        .frame(maxHeight: .infinity)
    }

    private var deviceList: some View {
        List(bluetooth.devices) { device in
            if bluetooth.connectedDeviceID == device.id {
                NavigationLink {
                    RNodeDetailView(bluetooth: bluetooth)
                } label: {
                    HStack(spacing: 12) {
                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text(device.name)
                                .font(.headline)

                            Text("\(device.rssi) dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("Connected")
                            .foregroundStyle(.green)
                            .lineLimit(1)
                            .fixedSize()

                        Text("Details")
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.vertical, 6)
                }
            } else {
                HStack(spacing: 12) {
                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(device.name)
                            .font(.headline)

                        Text("\(device.rssi) dBm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if bluetooth.connectingDeviceID == device.id {
                        ProgressView()
                    } else {
                        Button("Connect") {
                            if bluetooth.connectedDeviceID != nil {
                                pendingConnectionID = device.id
                                showSwitchConfirmation = true
                            } else {
                                bluetooth.connect(to: device)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 6)
            }
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
                bluetooth.isScanning
                    ? "Stop Scanning"
                    : "Scan for RNodes",
                systemImage:
                    bluetooth.isScanning
                        ? "stop.circle"
                        : "magnifyingglass"
            )
            .frame(width: 220)
        }
        .buttonStyle(.borderedProminent)
        .disabled(
            bluetooth.bluetoothState != .poweredOn
        )
        .frame(maxWidth: .infinity)
    }
}

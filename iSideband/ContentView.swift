import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @State private var showRestartConfirmation = false
    @State private var showRadioOffConfirmation = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header

                if bluetooth.devices.isEmpty {
                    emptyState
                } else {
                    deviceList
                }

                VStack(spacing: 12) {
                    scanButton

                    if bluetooth.connectedDeviceID != nil {
                        HStack(spacing: 12) {
                            Button("Restart RNode") {
                                showRestartConfirmation = true
                            }
                            .buttonStyle(.bordered)

                            Button("Turn Radio Off") {
                                showRadioOffConfirmation = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("RNode")
            .confirmationDialog(
                "Restart RNode?",
                isPresented: $showRestartConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restart RNode", role: .destructive) {
                    bluetooth.restartRNode()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        statusMessage =
                            "RNode restarting — reconnect when available."
                    }
                }

                Button("Cancel", role: .cancel) {
                }
            } message: {
                Text(
                    "The Bluetooth connection will briefly disconnect while the RNode restarts."
                )
            }
            .confirmationDialog(
                "Turn Radio Off?",
                isPresented: $showRadioOffConfirmation,
                titleVisibility: .visible
            ) {
                Button("Turn Radio Off", role: .destructive) {
                    bluetooth.turnRadioOff()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        statusMessage = "RNode radio turned off."
                    }
                }

                Button("Cancel", role: .cancel) {
                }
            } message: {
                Text(
                    "This turns off the RNode radio, but does not completely power off the device."
                )
            }
            .alert(
                "RNode Status",
                isPresented: Binding(
                    get: {
                        statusMessage != nil
                    },
                    set: { isPresented in
                        if !isPresented {
                            statusMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    statusMessage = nil
                }
            } message: {
                Text(statusMessage ?? "")
            }
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

                    if bluetooth.connectingDeviceID
                        == device.id
                    {
                        ProgressView()
                    } else if bluetooth.connectedDeviceID
                        == device.id
                    {
                        Text("Connected")
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 6)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    if bluetooth.connectedDeviceID
                        != device.id
                    {
                        bluetooth.connect(to: device)
                    }
                }
            )
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
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(
            bluetooth.bluetoothState != .poweredOn
        )
    }
}

#Preview {
    ContentView()
}

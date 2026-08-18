import SwiftUI
import CoreBluetooth

struct MainMenuView: View {
    @ObservedObject var bluetooth: BluetoothManager

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SettingsView(bluetooth: bluetooth)
                } label: {
                    menuRow(
                        title: "Settings",
                        subtitle: "Identity, GPS, Bluetooth and LoRa settings",
                        icon: "gearshape.fill"
                    )
                }

                NavigationLink {
                    InterfacesView(bluetooth: bluetooth)
                } label: {
                    menuRow(
                        title: "Interfaces",
                        subtitle: "View connected network interfaces",
                        icon: "antenna.radiowaves.left.and.right"
                    )
                }

                NavigationLink {
                    AnnounceListView()
                } label: {
                    menuRow(
                        title: "Announcement List",
                        subtitle: "View Reticulum announcements heard over RF",
                        icon: "dot.radiowaves.left.and.right"
                    )
                }
            }
        }
        .navigationTitle("Menu")
    }

    private func menuRow(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
}

struct InterfacesView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject private var packetInterfaces =
        PacketInterfaceManager.shared
    @ObservedObject private var piInterface =
        PiHaLowInterfaceManager.shared

    @AppStorage("raspberryPiHost") private var piHost = ""
    @AppStorage("raspberryPiPort") private var piPort = "4242"

    var body: some View {
        Form {
            Section("Active Interface") {
                Toggle("Bluetooth RNode", isOn: bluetoothInterfaceBinding)
                    .disabled(
                        packetInterfaces.activeInterface == .raspberryPi
                    )

                Toggle("Raspberry Pi", isOn: raspberryPiInterfaceBinding)
                    .disabled(
                        packetInterfaces.activeInterface == .bluetoothRNode
                    )

                if packetInterfaces.activeInterface == .none {
                    Text("Both packet interfaces are off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        "Turn off \(packetInterfaces.activeInterface.title) before enabling the other interface."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("RNode Interface") {
                LabeledContent(
                    "Connection",
                    value: bluetooth.connectedDeviceID == nil
                        ? "Disconnected"
                        : "Connected"
                )

                LabeledContent(
                    "Bluetooth",
                    value: bluetooth.bluetoothState == .poweredOn
                        ? "Available"
                        : "Unavailable"
                )

                if packetInterfaces.activeInterface != .bluetoothRNode {
                    Text("Disabled while Raspberry Pi is selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Raspberry Pi Interface") {
                TextField("Host or IP address", text: $piHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("TCP port", text: $piPort)
                    .keyboardType(.numberPad)

                LabeledContent("Connection", value: piInterface.state.label)

                if piInterface.state == .connected || piInterface.state == .connecting {
                    Button("Disconnect", role: .destructive) {
                        piInterface.disconnect()
                    }
                } else {
                    Button("Connect to Raspberry Pi") {
                        piInterface.connect(host: piHost, port: piPort)
                    }
                    .disabled(
                        packetInterfaces.activeInterface != .raspberryPi ||
                        piHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .navigationTitle("Interfaces")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bluetoothInterfaceBinding: Binding<Bool> {
        Binding(
            get: { packetInterfaces.activeInterface == .bluetoothRNode },
            set: { enabled in
                packetInterfaces.select(enabled ? .bluetoothRNode : .none)
            }
        )
    }

    private var raspberryPiInterfaceBinding: Binding<Bool> {
        Binding(
            get: { packetInterfaces.activeInterface == .raspberryPi },
            set: { enabled in
                packetInterfaces.select(enabled ? .raspberryPi : .none)
            }
        )
    }
}

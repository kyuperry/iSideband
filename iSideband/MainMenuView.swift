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
    @ObservedObject private var piGateway =
        PiHaLowInterfaceManager.shared

    @AppStorage("piGatewayHost")
    private var piGatewayHost =
        "openmanet-rpi4.local"
    @AppStorage("piGatewayPort")
    private var piGatewayPort = "4242"
    @AppStorage("piGatewayMeshType")
    private var piGatewayMeshType = "OpenMANET"

    var body: some View {
        Form {
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
            }

            Section("Raspberry Pi / Wi-Fi HaLow") {
                Picker(
                    "Mesh Platform",
                    selection: $piGatewayMeshType
                ) {
                    Text("OpenMANET")
                        .tag("OpenMANET")
                    Text("BATMAN-adv")
                        .tag("BATMAN-adv")
                    Text("Other IP Mesh")
                        .tag("Other IP Mesh")
                }

                TextField(
                    "Gateway host",
                    text: $piGatewayHost
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                TextField(
                    "TCP port",
                    text: $piGatewayPort
                )
                .keyboardType(.numberPad)

                LabeledContent(
                    "Gateway",
                    value: piGateway.state.label
                )

                if piGateway.state == .connected {
                    Button(
                        "Disconnect",
                        role: .destructive
                    ) {
                        piGateway.disconnect()
                    }
                } else {
                    Button("Connect to Pi Gateway") {
                        piGateway.connect(
                            host: piGatewayHost,
                            port: piGatewayPort
                        )
                    }
                    .disabled(
                        piGateway.state == .connecting
                    )
                }

                Text(
                    "The Pi must be reachable from this iPhone and run a Reticulum TCP server. OpenMANET or BATMAN-adv carries the IP traffic across the HaLow mesh."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Interfaces")
        .navigationBarTitleDisplayMode(.inline)
    }
}

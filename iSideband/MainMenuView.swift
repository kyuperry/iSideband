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
                    MeshMapView()
                } label: {
                    menuRow(
                        title: "Mesh Map",
                        subtitle: "View geographic and topology maps",
                        icon: "map.fill"
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

    var body: some View {
        List {
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
        }
        .navigationTitle("Interfaces")
    }
}

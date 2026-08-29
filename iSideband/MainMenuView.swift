import SwiftUI
import CoreBluetooth
import WebKit

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
    @ObservedObject private var wifiLANInterface =
        WiFiLANInterfaceManager.shared
    @ObservedObject private var piHaLowInterface =
        PiHaLowInterfaceManager.shared

    @AppStorage("wifiLANHost") private var wifiLANHost = ""
    @AppStorage("wifiLANPort") private var wifiLANPort = "4242"
    @AppStorage("raspberryPiHost") private var raspberryPiHost = ""
    @AppStorage("raspberryPiPort") private var raspberryPiPort = "4242"
    @AppStorage("raspberryPiCameraStreamURL")
    private var piCameraStreamURL = ""

    var body: some View {
        Form {
            Section("Active Interface") {
                Toggle("Bluetooth RNode", isOn: bluetoothInterfaceBinding)

                Toggle("Wi-Fi / Local Network", isOn: wifiLANInterfaceBinding)

                Toggle(
                    "Raspberry Pi / Wi-Fi HaLow",
                    isOn: raspberryPiInterfaceBinding
                )

                if packetInterfaces.activeInterface == .none {
                    Text("All packet interfaces are off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        "Bluetooth RNode, Wi-Fi/LAN and Raspberry Pi/Wi-Fi HaLow can operate together for path diversity."
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

            }

            Section("Wi-Fi / Local Network Interface") {
                TextField("Reticulum TCP host or IP address", text: $wifiLANHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("TCP port", text: $wifiLANPort)
                    .keyboardType(.numberPad)

                LabeledContent("Connection", value: wifiLANInterface.state.label)

                if wifiLANInterface.state == .connected || wifiLANInterface.state == .connecting {
                    Button("Disconnect", role: .destructive) {
                        wifiLANInterface.disconnect()
                    }
                } else {
                    Button("Connect to Wi-Fi / Local Network") {
                        wifiLANInterface.connect(
                            host: wifiLANHost,
                            port: wifiLANPort
                        )
                    }
                    .disabled(
                        !packetInterfaces.isActive(.wifiLocalNetwork) ||
                        wifiLANHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                Text(
                    "Connects to any Reticulum TCP server on the local network. It is independent of Raspberry Pi camera features and can run alongside Bluetooth RNode."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Raspberry Pi / Wi-Fi HaLow Interface") {
                TextField("Raspberry Pi host or IP address", text: $raspberryPiHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Reticulum TCP port", text: $raspberryPiPort)
                    .keyboardType(.numberPad)

                LabeledContent(
                    "Connection",
                    value: piHaLowInterface.state.label
                )

                if piHaLowInterface.state == .connected
                    || piHaLowInterface.state == .connecting {
                    Button("Disconnect Raspberry Pi", role: .destructive) {
                        piHaLowInterface.disconnect()
                    }
                } else {
                    Button("Connect Raspberry Pi") {
                        piHaLowInterface.connect(
                            host: raspberryPiHost,
                            port: raspberryPiPort
                        )
                    }
                    .disabled(
                        !packetInterfaces.isActive(.raspberryPi)
                            || raspberryPiHost.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                }

                Text(
                    "A dedicated Reticulum TCP path to the Raspberry Pi over Ethernet, Wi-Fi or Wi-Fi HaLow. It remains independent of the generic Wi-Fi/LAN interface."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Raspberry Pi Camera") {
                TextField(
                    "http://pi-address:8080/stream.mjpg",
                    text: $piCameraStreamURL
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

                if let cameraURL {
                    NavigationLink {
                        PiCameraStreamView(
                            streamURL: cameraURL
                        )
                    } label: {
                        Label(
                            "View Live Camera",
                            systemImage: "video.fill"
                        )
                    }
                } else {
                    Label(
                        "Enter a valid HTTP or HTTPS camera stream URL.",
                        systemImage: "video.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text(
                    "Camera video uses the Raspberry Pi's Wi-Fi HaLow IP connection. Reticulum and LoRa remain available for messages, commands and telemetry. HTTP MJPEG and browser-compatible HLS streams are supported."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Interfaces")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var bluetoothInterfaceBinding: Binding<Bool> {
        Binding(
            get: { packetInterfaces.isActive(.bluetoothRNode) },
            set: { enabled in
                packetInterfaces.setEnabled(.bluetoothRNode, enabled)
            }
        )
    }

    private var cameraURL: URL? {
        let value = piCameraStreamURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private var wifiLANInterfaceBinding: Binding<Bool> {
        Binding(
            get: { packetInterfaces.isActive(.wifiLocalNetwork) },
            set: { enabled in
                packetInterfaces.setEnabled(.wifiLocalNetwork, enabled)
            }
        )
    }

    private var raspberryPiInterfaceBinding: Binding<Bool> {
        Binding(
            get: { packetInterfaces.isActive(.raspberryPi) },
            set: { enabled in
                packetInterfaces.setEnabled(.raspberryPi, enabled)
            }
        )
    }
}

private struct PiCameraStreamView: View {
    let streamURL: URL

    var body: some View {
        PiCameraWebView(url: streamURL)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Raspberry Pi Camera")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PiCameraWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(
        _ webView: WKWebView,
        context: Context
    ) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}

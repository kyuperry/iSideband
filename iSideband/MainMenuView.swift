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
    @ObservedObject private var piInterface =
        PiHaLowInterfaceManager.shared

    @AppStorage("raspberryPiHost") private var piHost = ""
    @AppStorage("raspberryPiPort") private var piPort = "4242"
    @AppStorage("raspberryPiCameraStreamURL")
    private var piCameraStreamURL = ""

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
            get: { packetInterfaces.activeInterface == .bluetoothRNode },
            set: { enabled in
                packetInterfaces.select(enabled ? .bluetoothRNode : .none)
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

    private var raspberryPiInterfaceBinding: Binding<Bool> {
        Binding(
            get: { packetInterfaces.activeInterface == .raspberryPi },
            set: { enabled in
                packetInterfaces.select(enabled ? .raspberryPi : .none)
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

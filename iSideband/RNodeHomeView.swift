import SwiftUI
import CoreBluetooth
import UIKit

struct RNodeHomeView: View {
    @ObservedObject var bluetooth: BluetoothManager

    @AppStorage(NightVisionPreferenceKey.enabled)
    private var nightVisionModeEnabled = false

    @State private var showSwitchConfirmation = false
    @State private var pendingConnectionID: UUID?
    @State private var liveActivityStatusMessage: String?
    @State private var showLiveActivityConfirmation = false
    @State private var requestedLiveActivityIsRunning = false

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle("NVG", isOn: $nightVisionModeEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption2.weight(.semibold))
                    .tint(.red)
                    .fixedSize()
                    .accessibilityLabel("NVG Mode")
                    .accessibilityHint(
                        "Turns the night vision display on or off"
                    )
            }
        }
        .overlay(alignment: .bottom) {
            if let liveActivityStatusMessage {
                Text(liveActivityStatusMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.82), in: Capsule())
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmationDialog(
            requestedLiveActivityIsRunning
                ? "Stop Live Activity?"
                : "Start Live Activity?",
            isPresented: $showLiveActivityConfirmation,
            titleVisibility: .visible
        ) {
            if requestedLiveActivityIsRunning {
                Button("Stop Live Activity", role: .destructive) {
                    setLiveActivityRunning(false)
                }
            } else {
                Button("Start Live Activity") {
                    setLiveActivityRunning(true)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
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
                        where: {
                            $0.id == pendingConnectionID
                        }
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
                """
                Another RNode is already connected. This will disconnect it and connect to the selected RNode.
                """
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
                    RNodeDetailView(
                        bluetooth: bluetooth
                    )
                } label: {
                    connectedDeviceRow(device)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.7)
                        .onEnded { _ in
                            requestedLiveActivityIsRunning =
                                RNodeLiveActivityManager.shared.isRunning
                            showLiveActivityConfirmation = true
                        }
                )
            } else {
                availableDeviceRow(device)
            }
        }
        .listStyle(.plain)
    }

    private func setLiveActivityRunning(_ shouldRun: Bool) {
        let message: String
        let feedback: UINotificationFeedbackGenerator.FeedbackType

        switch RNodeLiveActivityManager.shared.setRunning(shouldRun) {
        case .started:
            message = "Live Activity Started"
            feedback = .success
        case .stopped:
            message = "Live Activity Stopped"
            feedback = .success
        case .unavailable:
            message = "Live Activities Are Unavailable"
            feedback = .error
        }

        UINotificationFeedbackGenerator().notificationOccurred(feedback)
        withAnimation { liveActivityStatusMessage = message }

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard liveActivityStatusMessage == message else { return }
            withAnimation { liveActivityStatusMessage = nil }
        }
    }

    private func connectedDeviceRow(
        _ device: DiscoveredDevice
    ) -> some View {
        HStack(spacing: 12) {
            Text(device.name)
                .font(.headline)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

            Text("Connected")
                .fontWeight(.semibold)
                .foregroundStyle(.green)
                .lineLimit(1)
                .fixedSize()
                .frame(
                    maxWidth: .infinity,
                    alignment: .center
                )

            Text("Details")
                .foregroundStyle(.blue)
                .lineLimit(1)
                .fixedSize()
                .frame(
                    maxWidth: .infinity,
                    alignment: .trailing
                )
        }
        .padding(.vertical, 6)
    }

    private func availableDeviceRow(
        _ device: DiscoveredDevice
    ) -> some View {
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
            bluetooth.bluetoothState
                != .poweredOn
        )
        .frame(maxWidth: .infinity)
    }
}

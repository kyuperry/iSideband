import SwiftUI

struct SettingsView: View {
    @ObservedObject var bluetooth: BluetoothManager

    @Environment(\.dismiss) private var dismiss

    @State private var gpsEnabled = false
    @State private var bluetoothEnabled = true

    @State private var frequencyMHz = "915.000"
    @State private var bandwidthKHz = "125"
    @State private var transmitPowerDBm = "22"
    @State private var spreadingFactor = "7"
    @State private var codingRate = "5"

    @State private var showRestartConfirmation = false
    @State private var showRadioOffConfirmation = false
    @State private var showSavedConfirmation = false
    @State private var statusMessage: String?

    @State private var hasLoadedSettings = false

    var body: some View {
        Form {
            interfaceSettingsSection
            identitySection
            radioSettingsSection
            rnodeControlsSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveSettings()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            loadSettings()
        }
        .confirmationDialog(
            "Restart RNode?",
            isPresented: $showRestartConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restart RNode", role: .destructive) {
                bluetooth.restartRNode()

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.5
                ) {
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
            "Turn LoRa Radio Off?",
            isPresented: $showRadioOffConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "Turn LoRa Radio Off",
                role: .destructive
            ) {
                bluetooth.turnRadioOff()

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.5
                ) {
                    statusMessage =
                        "RNode LoRa radio turned off."
                }
            }

            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text(
                "This disables the RNode’s LoRa radio. It does not turn off Bluetooth or completely power off the RNode."
            )
        }
        .alert(
            "Settings Saved",
            isPresented: $showSavedConfirmation
        ) {
            Button("OK", role: .cancel) {
            }
        } message: {
            Text(
                "Your iSideband settings were saved."
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

    private var interfaceSettingsSection: some View {
        Section("Interfaces") {
            Toggle(isOn: $bluetoothEnabled) {
                Label(
                    "Bluetooth",
                    systemImage: "bluetooth"
                )
            }

            Toggle(isOn: $gpsEnabled) {
                Label(
                    "GPS",
                    systemImage: "location.fill"
                )
            }

            Text(
                "These switches control whether iSideband will use Bluetooth and GPS. They do not directly turn the iPhone’s system radios on or off."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var identitySection: some View {
        Section("Sideband Identity") {
            SidebandIdentityImporter()
        }
    }

    private var radioSettingsSection: some View {
        Section("LoRa Radio Settings") {
            settingsField(
                title: "Frequency",
                value: $frequencyMHz,
                unit: "MHz",
                keyboard: .decimalPad
            )

            settingsField(
                title: "Bandwidth",
                value: $bandwidthKHz,
                unit: "kHz",
                keyboard: .decimalPad
            )

            settingsField(
                title: "TX Power",
                value: $transmitPowerDBm,
                unit: "dBm",
                keyboard: .numberPad
            )

            settingsField(
                title: "Spreading Factor",
                value: $spreadingFactor,
                unit: "SF",
                keyboard: .numberPad
            )

            settingsField(
                title: "Coding Rate",
                value: $codingRate,
                unit: "CR",
                keyboard: .numberPad
            )

            Text(
                "These fields are editable and saved locally. They do not change the connected RNode configuration yet."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var rnodeControlsSection: some View {
        Section("RNode Controls") {
            Button {
                showRestartConfirmation = true
            } label: {
                Label(
                    "Restart RNode",
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(bluetooth.connectedDeviceID == nil)

            Button(role: .destructive) {
                showRadioOffConfirmation = true
            } label: {
                Label(
                    "Turn LoRa Radio Off",
                    systemImage:
                        "antenna.radiowaves.left.and.right.slash"
                )
            }
            .disabled(bluetooth.connectedDeviceID == nil)
        }
    }

    private func settingsField(
        title: String,
        value: Binding<String>,
        unit: String,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)

            Spacer()

            TextField("", text: value)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 92)

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    width: 38,
                    alignment: .leading
                )
        }
    }

    private func loadSettings() {
        guard !hasLoadedSettings else {
            return
        }

        let defaults = UserDefaults.standard

        if defaults.object(
            forKey: "gpsInterfaceEnabled"
        ) != nil {
            gpsEnabled = defaults.bool(
                forKey: "gpsInterfaceEnabled"
            )
        }

        if defaults.object(
            forKey: "bluetoothInterfaceEnabled"
        ) != nil {
            bluetoothEnabled = defaults.bool(
                forKey: "bluetoothInterfaceEnabled"
            )
        }

        frequencyMHz = defaults.string(
            forKey: "radioFrequencyMHz"
        ) ?? "915.000"

        bandwidthKHz = defaults.string(
            forKey: "radioBandwidthKHz"
        ) ?? "125"

        transmitPowerDBm = defaults.string(
            forKey: "radioTransmitPowerDBm"
        ) ?? "22"

        spreadingFactor = defaults.string(
            forKey: "radioSpreadingFactor"
        ) ?? "7"

        codingRate = defaults.string(
            forKey: "radioCodingRate"
        ) ?? "5"

        hasLoadedSettings = true
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard

        defaults.set(
            gpsEnabled,
            forKey: "gpsInterfaceEnabled"
        )

        defaults.set(
            bluetoothEnabled,
            forKey: "bluetoothInterfaceEnabled"
        )

        defaults.set(
            frequencyMHz,
            forKey: "radioFrequencyMHz"
        )

        defaults.set(
            bandwidthKHz,
            forKey: "radioBandwidthKHz"
        )

        defaults.set(
            transmitPowerDBm,
            forKey: "radioTransmitPowerDBm"
        )

        defaults.set(
            spreadingFactor,
            forKey: "radioSpreadingFactor"
        )

        defaults.set(
            codingRate,
            forKey: "radioCodingRate"
        )

        showSavedConfirmation = true
    }
}

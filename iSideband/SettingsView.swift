import SwiftUI
import CoreLocation

struct SettingsView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject private var locationTelemetry =
        LocationTelemetryManager.shared
    @ObservedObject private var discoveryMode =
        LXMFDiscoveryMode.shared

    @Environment(\.dismiss) private var dismiss

    @State private var gpsEnabled = false
    @State private var bluetoothEnabled = true
    @AppStorage(
        NotificationPreferenceKey.nearbyNodes
    ) private var nearbyNodeNotifications = true
    @AppStorage(
        NotificationPreferenceKey.lxmfMessages
    ) private var lxmfMessageNotifications = true
    @AppStorage(
        NotificationPreferenceKey.battery50
    ) private var battery50Notifications = true
    @AppStorage(
        NotificationPreferenceKey.battery25
    ) private var battery25Notifications = true
    @AppStorage(
        NotificationPreferenceKey.sounds
    ) private var notificationSounds = true
    @AppStorage(
        AutomaticAnnouncePreferenceKey.enabled
    ) private var automaticAnnounceEnabled = false
    @AppStorage(
        AutomaticAnnouncePreferenceKey.intervalMinutes
    ) private var automaticAnnounceIntervalMinutes =
        AutomaticAnnounceInterval.thirtyMinutes.rawValue

    @State private var frequencyMHz = "915.000"
    @State private var bandwidthKHz = "125"
    @State private var transmitPowerDBm = "22"
    @State private var spreadingFactor = "7"
    @State private var codingRate = "5"

    @State private var showRestartConfirmation = false
    @State private var showRadioOffConfirmation = false
    @State private var showSavedConfirmation = false
    @State private var statusMessage: String?
    @State private var showBackupWarning = false
    @State private var showBackupExporter = false
    @State private var backupDocument:
        iSidebandBackupDocument?
    @State private var backupStatusMessage: String?

    @State private var hasLoadedSettings = false

    var body: some View {
        Form {
            interfaceSettingsSection
            nearbyDiscoverySection
            automaticAnnouncementsSection
            notificationSettingsSection
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
            "Export Sensitive Backup?",
            isPresented: $showBackupWarning,
            titleVisibility: .visible
        ) {
            Button("Export Backup") {
                prepareBackup()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This file contains your private Reticulum identity. Anyone with the file can use your identity. Store it securely and do not share it."
            )
        }
        .fileExporter(
            isPresented: $showBackupExporter,
            document: backupDocument,
            contentType: .iSidebandBackup,
            defaultFilename:
                "iSideband-Backup"
        ) { result in
            switch result {
            case .success:
                backupStatusMessage =
                    "Backup exported successfully."
            case .failure(let error):
                backupStatusMessage =
                    "Backup export failed: \(error.localizedDescription)"
            }
        }
        .alert(
            "Backup",
            isPresented: Binding(
                get: { backupStatusMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        backupStatusMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                backupStatusMessage = nil
            }
        } message: {
            Text(backupStatusMessage ?? "")
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

    private var notificationSettingsSection: some View {
        Section("Notifications") {
            Toggle(
                "Nearby Reticulum Nodes",
                isOn: $nearbyNodeNotifications
            )

            Toggle(
                "LXMF Messages",
                isOn: $lxmfMessageNotifications
            )

            Toggle(
                "RNode Battery at 50%",
                isOn: $battery50Notifications
            )

            Toggle(
                "RNode Battery at 25%",
                isOn: $battery25Notifications
            )

            Toggle(
                "Notification Sounds",
                isOn: $notificationSounds
            )

            Text(
                "iPhone notification permission must also be enabled for iSideband in Settings."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var nearbyDiscoverySection: some View {
        Section("Nearby Users") {
            Toggle(
                isOn: Binding(
                    get: {
                        discoveryMode.isEnabled
                    },
                    set: { enabled in
                        if enabled {
                            discoveryMode.start()
                        } else {
                            discoveryMode.stop()
                        }
                    }
                )
            ) {
                Label(
                    "Find Nearby Users",
                    systemImage:
                        "antenna.radiowaves.left.and.right"
                )
            }

            Text(
                discoveryMode.isEnabled
                    ? discoveryMode.statusText
                    : "Automatically announce every 10 minutes and listen for nearby LXMF users."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if let lastAnnouncedAt =
                    discoveryMode.lastAnnouncedAt,
               discoveryMode.isEnabled {
                Text(
                    "Last announcement " +
                    lastAnnouncedAt.formatted(
                        date: .omitted,
                        time: .shortened
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            NavigationLink {
                DiscoveredPeersView()
            } label: {
                Label(
                    "View Discovered Peers",
                    systemImage: "person.2.fill"
                )
            }
        }
    }

    private var automaticAnnouncementsSection:
        some View {
        Section("Automatic Announcements") {
            Toggle(
                "Auto-Announce Identity",
                isOn: $automaticAnnounceEnabled
            )

            Picker(
                "Interval",
                selection:
                    $automaticAnnounceIntervalMinutes
            ) {
                ForEach(
                    AutomaticAnnounceInterval.allCases
                ) { interval in
                    Text(interval.title)
                        .tag(interval.rawValue)
                }
            }
            .disabled(!automaticAnnounceEnabled)

            Text(
                "iSideband announces on this schedule while running. If iOS suspends the app, an overdue announcement is sent the next time RNode Bluetooth activity wakes it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(
            of: automaticAnnounceEnabled
        ) { _, _ in
            ReticulumCoreBridge.shared
                .automaticAnnounceSettingsDidChange()
        }
        .onChange(
            of: automaticAnnounceIntervalMinutes
        ) { _, _ in
            ReticulumCoreBridge.shared
                .automaticAnnounceSettingsDidChange()
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
            .onChange(of: gpsEnabled) { _, enabled in
                guard hasLoadedSettings else {
                    return
                }
                locationTelemetry.setEnabled(enabled)
            }

            if gpsEnabled {
                if let location = locationTelemetry.location {
                    Label(
                        String(
                            format: "%.5f, %.5f (±%.0f m)",
                            location.coordinate.latitude,
                            location.coordinate.longitude,
                            location.horizontalAccuracy
                        ),
                        systemImage: "location.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let error = locationTelemetry.errorMessage {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else {
                    Label(
                        "Waiting for an iPhone location fix",
                        systemImage: "location.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
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

            Button {
                showBackupWarning = true
            } label: {
                Label(
                    "Export iSideband Backup",
                    systemImage:
                        "externaldrive.badge.plus"
                )
            }

            Text(
                "The backup includes your private identity, contacts, discovered peers, and announcement history."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func prepareBackup() {
        do {
            backupDocument =
                try iSidebandBackupDocument.create()
            showBackupExporter = true
        } catch {
            backupStatusMessage =
                "Could not create backup: \(error.localizedDescription)"
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
        locationTelemetry.setEnabled(gpsEnabled)
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard

        defaults.set(
            gpsEnabled,
            forKey: "gpsInterfaceEnabled"
        )
        locationTelemetry.setEnabled(gpsEnabled)

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

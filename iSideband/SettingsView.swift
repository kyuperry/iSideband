import SwiftUI
import CoreLocation

enum RNodePreferenceKey {
    static let displayName =
        "isideband.rnode.displayName"
}

struct SettingsView: View {
    @ObservedObject var bluetooth: BluetoothManager

    @ObservedObject private var locationTelemetry =
        LocationTelemetryManager.shared

    @ObservedObject private var discoveryMode =
        LXMFDiscoveryMode.shared

    @ObservedObject private var packetInterfaces =
        PacketInterfaceManager.shared

    @Environment(\.dismiss) private var dismiss

    @State private var gpsEnabled = false
    @State private var shareTimestampTelemetry = true
    @State private var shareLocationOnMesh = false

    @AppStorage(
        NotificationPreferenceKey.rnodeConnection
    )
    private var rnodeConnectionNotifications = true

    @AppStorage(
        NotificationPreferenceKey.nearbyNodes
    )
    private var nearbyNodeNotifications = true

    @AppStorage(
        NotificationPreferenceKey.lxmfMessages
    )
    private var lxmfMessageNotifications = true

    @AppStorage(
        NotificationPreferenceKey.sounds
    )
    private var notificationSounds = true

    @AppStorage(
        AutomaticAnnouncePreferenceKey.enabled
    )
    private var automaticAnnounceEnabled = false

    @AppStorage(
        AutomaticAnnouncePreferenceKey.intervalMinutes
    )
    private var automaticAnnounceIntervalMinutes =
        AutomaticAnnounceInterval
            .thirtyMinutes
            .rawValue

    @AppStorage(PushToTalkPreferenceKey.enabled)
    private var pushToTalkEnabled = false

    @AppStorage(NightVisionPreferenceKey.enabled)
    private var nightVisionModeEnabled = false

    @AppStorage(NightVisionPreferenceKey.dimming)
    private var nightVisionDimming = 0.78

    @State private var frequencyMHz = "915.000"
    @State private var bandwidthKHz = "125"
    @State private var transmitPowerDBm = "22"
    @State private var spreadingFactor = "7"
    @State private var codingRate = "5"
    @State private var rnodeDisplayName = "KPU5-1"

    @State private var showRestartConfirmation = false
    @State private var showRadioOffConfirmation = false
    @State private var showSavedConfirmation = false

    @State private var savedConfirmationMessage =
        "Your iSideband settings were saved."

    @State private var statusMessage: String?

    @State private var showBackupWarning = false
    @State private var showBackupExporter = false

    @State private var backupDocument:
        iSidebandBackupDocument?

    @State private var backupStatusMessage: String?
    @State private var hasLoadedSettings = false
    @State private var isApplyingRadioSettings = false

    private var isRNodeConnected: Bool {
        bluetooth.connectedDeviceID != nil
    }

    var body: some View {
        Form {
            interfaceSettingsSection
            displaySettingsSection
            nearbyDiscoverySection
            automaticAnnouncementsSection
            telemetrySettingsSection
            messagingSettingsSection
            notificationSettingsSection
            identitySection
            radioSettingsSection
            rnodeControlsSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(
                placement: .topBarTrailing
            ) {
                Button {
                    saveSettings()
                } label: {
                    if isApplyingRadioSettings {
                        ProgressView()
                    } else {
                        Text("Save")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(isApplyingRadioSettings)
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

            Button(
                "Cancel",
                role: .cancel
            ) { }
        } message: {
            Text(
                """
                This file contains your private Reticulum identity. Anyone with the file can use your identity. Store it securely and do not share it.
                """
            )
        }
        .fileExporter(
            isPresented: $showBackupExporter,
            document: backupDocument,
            contentType: .iSidebandBackup,
            defaultFilename: "iSideband-Backup"
        ) { result in
            switch result {
            case .success:
                backupStatusMessage =
                    "Backup exported successfully."

            case .failure(let error):
                backupStatusMessage =
                    """
                    Backup export failed: \
                    \(error.localizedDescription)
                    """
            }
        }
        .alert(
            "Backup",
            isPresented: Binding(
                get: {
                    backupStatusMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        backupStatusMessage = nil
                    }
                }
            )
        ) {
            Button(
                "OK",
                role: .cancel
            ) {
                backupStatusMessage = nil
            }
        } message: {
            Text(
                backupStatusMessage ?? ""
            )
        }
        .confirmationDialog(
            "Restart RNode?",
            isPresented: $showRestartConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "Restart RNode",
                role: .destructive
            ) {
                bluetooth.restartRNode()

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.5
                ) {
                    statusMessage =
                        """
                        RNode restarting — reconnect when available.
                        """
                }
            }

            Button(
                "Cancel",
                role: .cancel
            ) { }
        } message: {
            Text(
                """
                The Bluetooth connection will briefly disconnect while the RNode restarts.
                """
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

            Button(
                "Cancel",
                role: .cancel
            ) { }
        } message: {
            Text(
                """
                This disables the RNode’s LoRa radio. It does not turn off Bluetooth or completely power off the RNode.
                """
            )
        }
        .alert(
            "Settings Saved",
            isPresented: $showSavedConfirmation
        ) {
            Button(
                "OK",
                role: .cancel
            ) { }
        } message: {
            Text(savedConfirmationMessage)
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
            Button(
                "OK",
                role: .cancel
            ) {
                statusMessage = nil
            }
        } message: {
            Text(
                statusMessage ?? ""
            )
        }
    }

    private var notificationSettingsSection:
        some View {
        Section("Notifications") {
            Toggle(
                "RNode Connection",
                isOn: $rnodeConnectionNotifications
            )

            Toggle(
                "Nearby Reticulum Nodes",
                isOn: $nearbyNodeNotifications
            )

            Toggle(
                "LXMF Messages",
                isOn: $lxmfMessageNotifications
            )

            Toggle(
                "Notification Sounds",
                isOn: $notificationSounds
            )

            Text(
                """
                iPhone notification permission must also be enabled for iSideband in Settings.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var displaySettingsSection: some View {
        Section("Display") {
            Toggle(isOn: $nightVisionModeEnabled) {
                Label("NVG Mode", systemImage: "moon.stars.fill")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Night Vision Dimming")
                    Spacer()
                    Text("\(Int(nightVisionDimming * 100))%")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $nightVisionDimming,
                    in: 0.35...0.92,
                    step: 0.01
                ) {
                    Text("Night Vision Dimming")
                } minimumValueLabel: {
                    Image(systemName: "sun.min")
                } maximumValueLabel: {
                    Image(systemName: "moon.fill")
                }
                .disabled(!nightVisionModeEnabled)
            }

            Text(
                "For testing with night-vision equipment. The app uses a very dim red interface and temporarily lowers screen brightness. Triple-tap anywhere to exit immediately."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var messagingSettingsSection: some View {
        Section("Messaging") {
            Toggle(isOn: $pushToTalkEnabled) {
                Label("Push-to-Talk Button", systemImage: "mic.fill")
            }

            Text(
                "Replaces Voice with Push to Talk in the plus-button menu. It uses the same voice recording screen, 15-second limit, and Send or Cancel controls."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var nearbyDiscoverySection:
        some View {
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
                    : """
                      Automatically announce every 10 minutes and listen for nearby LXMF users.
                      """
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if
                let lastAnnouncedAt =
                    discoveryMode.lastAnnouncedAt,
                discoveryMode.isEnabled
            {
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
            .disabled(
                !automaticAnnounceEnabled
            )

            Text(
                """
                iSideband announces on this schedule while running. If iOS suspends the app, an overdue announcement is sent the next time RNode Bluetooth activity wakes it.
                """
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

    private var telemetrySettingsSection: some View {
        Section("Shared Telemetry") {
            Toggle(
                "Timestamp",
                isOn: $shareTimestampTelemetry
            )

            Toggle(
                "GPS",
                isOn: $gpsEnabled
            )
            .onChange(of: gpsEnabled) { _, enabled in
                if !enabled {
                    shareLocationOnMesh = false
                }
            }

            Toggle(
                "Share Location on Situation Map",
                isOn: $shareLocationOnMesh
            )
            .disabled(!gpsEnabled)

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
                "GPS controls location collection. Share Location on Situation Map controls whether your position is included with outgoing LXMF messages. Changes take effect when you press Save."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var interfaceSettingsSection:
        some View {
        Section("Interfaces") {
            Toggle(isOn: bluetoothInterfaceBinding) {
                Label("Bluetooth RNode", systemImage: "bluetooth")
            }
            .disabled(packetInterfaces.activeInterface == .raspberryPi)

            Toggle(isOn: raspberryPiInterfaceBinding) {
                Label("Raspberry Pi", systemImage: "network")
            }
            .disabled(packetInterfaces.activeInterface == .bluetoothRNode)

            if packetInterfaces.activeInterface != .none {
                Text(
                    "Turn off \(packetInterfaces.activeInterface.title) before enabling the other packet interface."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Both packet interfaces are off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
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

    private var identitySection:
        some View {
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
                """
                The backup includes your private identity, contacts, discovered peers, and announcement history.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var radioSettingsSection:
        some View {
        Section("LoRa Radio Settings") {
            HStack(spacing: 10) {
                Text("RNode Name")

                Spacer()

                TextField(
                    "KPU5-1",
                    text: $rnodeDisplayName
                )
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
                .disabled(isApplyingRadioSettings)
            }

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

            if isRNodeConnected {
                Label(
                    isApplyingRadioSettings
                        ? "Applying settings to the connected RNode…"
                        : "Press Save to apply these settings to the connected RNode.",
                    systemImage:
                        isApplyingRadioSettings
                            ? "arrow.triangle.2.circlepath"
                            : "antenna.radiowaves.left.and.right"
                )
                .font(.caption)
                .foregroundStyle(
                    isApplyingRadioSettings
                        ? .orange
                        : .green
                )
            } else {
                Label(
                    """
                    No RNode is connected. Save will retain these values locally.
                    """,
                    systemImage:
                        "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private var rnodeControlsSection:
        some View {
        Section("RNode Controls") {
            Button {
                showRestartConfirmation = true
            } label: {
                Label(
                    "Restart RNode",
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(!isRNodeConnected)

            Button(
                role: .destructive
            ) {
                showRadioOffConfirmation = true
            } label: {
                Label(
                    "Turn LoRa Radio Off",
                    systemImage:
                        "antenna.radiowaves.left.and.right.slash"
                )
            }
            .disabled(!isRNodeConnected)
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

            TextField(
                "",
                text: value
            )
            .keyboardType(keyboard)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: 92)
            .disabled(isApplyingRadioSettings)

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    width: 38,
                    alignment: .leading
                )
        }
    }

    private func prepareBackup() {
        do {
            backupDocument =
                try iSidebandBackupDocument
                    .create()

            showBackupExporter = true
        } catch {
            backupStatusMessage =
                """
                Could not create backup: \
                \(error.localizedDescription)
                """
        }
    }

    private func loadSettings() {
        guard !hasLoadedSettings else {
            return
        }

        let defaults =
            UserDefaults.standard

        if defaults.object(
            forKey: "gpsInterfaceEnabled"
        ) != nil {
            gpsEnabled =
                defaults.bool(
                    forKey:
                        "gpsInterfaceEnabled"
                )
        }

        shareTimestampTelemetry = defaults.object(
            forKey: TelemetryPreferenceKey.shareTimestamp
        ) == nil || defaults.bool(
            forKey: TelemetryPreferenceKey.shareTimestamp
        )
        shareLocationOnMesh = defaults.bool(
            forKey: TelemetryPreferenceKey.shareLocation
        )
        if shareLocationOnMesh {
            gpsEnabled = true
        }

        frequencyMHz =
            defaults.string(
                forKey:
                    "radioFrequencyMHz"
            ) ?? "915.000"

        bandwidthKHz =
            defaults.string(
                forKey:
                    "radioBandwidthKHz"
            ) ?? "125"

        transmitPowerDBm =
            defaults.string(
                forKey:
                    "radioTransmitPowerDBm"
            ) ?? "22"

        spreadingFactor =
            defaults.string(
                forKey:
                    "radioSpreadingFactor"
            ) ?? "7"

        codingRate =
            defaults.string(
                forKey:
                    "radioCodingRate"
            ) ?? "5"

        rnodeDisplayName =
            defaults.string(
                forKey: RNodePreferenceKey.displayName
            ) ?? "KPU5-1"

        hasLoadedSettings = true

        locationTelemetry.setEnabled(
            gpsEnabled
        )
    }

    private func saveSettings() {
        guard !isApplyingRadioSettings else {
            return
        }

        let cleanedRNodeName = rnodeDisplayName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedRNodeName.isEmpty else {
            statusMessage = "RNode name cannot be empty."
            return
        }

        guard cleanedRNodeName.count <= 32 else {
            statusMessage =
                "RNode name must be 32 characters or fewer."
            return
        }

        guard let validatedSettings =
            validatedRadioSettings()
        else {
            return
        }

        let defaults =
            UserDefaults.standard

        rnodeDisplayName = cleanedRNodeName
        defaults.set(
            cleanedRNodeName,
            forKey: RNodePreferenceKey.displayName
        )

        defaults.set(
            gpsEnabled,
            forKey: "gpsInterfaceEnabled"
        )

        defaults.set(
            shareTimestampTelemetry,
            forKey: TelemetryPreferenceKey.shareTimestamp
        )
        defaults.set(
            shareLocationOnMesh,
            forKey: TelemetryPreferenceKey.shareLocation
        )

        locationTelemetry.setEnabled(
            gpsEnabled || shareLocationOnMesh
        )

        if shareLocationOnMesh {
            locationTelemetry.refresh()
        }
        ReticulumCoreBridge.shared.setTelemetryTimeEnabled(
            shareTimestampTelemetry
        )
        ReticulumCoreBridge.shared.setAnnounceLocation(
            shareLocationOnMesh
                ? locationTelemetry.location
                : nil
        )

        frequencyMHz =
            String(
                format: "%.3f",
                validatedSettings.frequencyMHz
            )

        bandwidthKHz =
            formattedDecimal(
                validatedSettings.bandwidthKHz
            )

        transmitPowerDBm =
            String(
                validatedSettings.transmitPowerDBm
            )

        spreadingFactor =
            String(
                validatedSettings.spreadingFactor
            )

        codingRate =
            String(
                validatedSettings.codingRate
            )

        defaults.set(
            frequencyMHz,
            forKey:
                "radioFrequencyMHz"
        )

        defaults.set(
            bandwidthKHz,
            forKey:
                "radioBandwidthKHz"
        )

        defaults.set(
            transmitPowerDBm,
            forKey:
                "radioTransmitPowerDBm"
        )

        defaults.set(
            spreadingFactor,
            forKey:
                "radioSpreadingFactor"
        )

        defaults.set(
            codingRate,
            forKey:
                "radioCodingRate"
        )

        guard isRNodeConnected else {
            savedConfirmationMessage =
                """
                Your settings were saved locally. They will be applied when the RNode reconnects.
                """

            showSavedConfirmation = true
            return
        }

        let configuration =
            RNodeRadioConfiguration(
                frequencyHz:
                    UInt32(
                        (
                            validatedSettings
                                .frequencyMHz *
                            1_000_000
                        )
                        .rounded()
                    ),
                bandwidthHz:
                    UInt32(
                        (
                            validatedSettings
                                .bandwidthKHz *
                            1_000
                        )
                        .rounded()
                    ),
                transmitPowerDBm:
                    validatedSettings
                        .transmitPowerDBm,
                spreadingFactor:
                    validatedSettings
                        .spreadingFactor,
                codingRate:
                    validatedSettings
                        .codingRate
            )

        isApplyingRadioSettings = true

        bluetooth.applyRadioConfiguration(
            configuration
        ) { result in
            isApplyingRadioSettings = false

            switch result {
            case .success(let applied):
                frequencyMHz =
                    String(
                        format: "%.3f",
                        applied.frequencyMHz
                    )

                bandwidthKHz =
                    formattedDecimal(
                        applied.bandwidthKHz
                    )

                transmitPowerDBm =
                    String(
                        applied.transmitPowerDBm
                    )

                spreadingFactor =
                    String(
                        applied.spreadingFactor
                    )

                codingRate =
                    String(
                        applied.codingRate
                    )

                savedConfirmationMessage =
                    """
                    Settings saved and sent to the connected RNode.

                    RNode Name: \(rnodeDisplayName)
                    Frequency: \(frequencyMHz) MHz
                    Bandwidth: \(bandwidthKHz) kHz
                    TX Power: \(transmitPowerDBm) dBm
                    Spreading Factor: \(spreadingFactor)
                    Coding Rate: 4/\(codingRate)
                    """

                showSavedConfirmation = true

            case .failure(let error):
                statusMessage =
                    """
                    Settings were saved locally, but the RNode could not be configured.

                    \(error.localizedDescription)
                    """
            }
        }
    }

    private func validatedRadioSettings()
        -> ValidatedRadioSettings? {
        let cleanedFrequency =
            frequencyMHz.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let cleanedBandwidth =
            bandwidthKHz.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let cleanedPower =
            transmitPowerDBm.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let cleanedSpreadingFactor =
            spreadingFactor.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let cleanedCodingRate =
            codingRate.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard
            let frequency =
                Double(cleanedFrequency),
            frequency >= 137,
            frequency <= 1_020
        else {
            statusMessage =
                """
                Frequency must be between 137 and 1,020 MHz.
                """

            return nil
        }

        guard
            let bandwidth =
                Double(cleanedBandwidth),
            bandwidth >= 7.8,
            bandwidth <= 500
        else {
            statusMessage =
                """
                Bandwidth must be between 7.8 and 500 kHz.
                """

            return nil
        }

        guard
            let power =
                Int(cleanedPower),
            (0...30).contains(power)
        else {
            statusMessage =
                """
                TX power must be between 0 and 30 dBm.
                """

            return nil
        }

        guard
            let sf =
                Int(cleanedSpreadingFactor),
            (5...12).contains(sf)
        else {
            statusMessage =
                """
                Spreading factor must be between 5 and 12.
                """

            return nil
        }

        guard
            let cr =
                Int(cleanedCodingRate),
            (5...8).contains(cr)
        else {
            statusMessage =
                """
                Coding rate must be entered as a denominator from 5 through 8. Enter 6 for coding rate 4/6.
                """

            return nil
        }

        return ValidatedRadioSettings(
            frequencyMHz: frequency,
            bandwidthKHz: bandwidth,
            transmitPowerDBm: power,
            spreadingFactor: sf,
            codingRate: cr
        )
    }

    private func formattedDecimal(
        _ value: Double
    ) -> String {
        if value.rounded() == value {
            return String(
                format: "%.0f",
                value
            )
        }

        return String(
            format: "%.1f",
            value
        )
    }

    private struct ValidatedRadioSettings {
        let frequencyMHz: Double
        let bandwidthKHz: Double
        let transmitPowerDBm: Int
        let spreadingFactor: Int
        let codingRate: Int
    }
}

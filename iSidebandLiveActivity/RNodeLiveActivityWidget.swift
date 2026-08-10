import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RNodeLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget { RNodeLiveActivityWidget() }
}

struct RNodeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RNodeLiveActivityAttributes.self) { context in
            RNodeLockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    metric("IN", context.state.reticulumBytesIn, "arrow.down")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    metric("OUT", context.state.reticulumBytesOut, "arrow.up")
                }
                DynamicIslandExpandedRegion(.center) {
                    availability(context.state.isReticulumAvailable)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Label {
                            Text(timerInterval: context.state.uptimeStartedAt...Date.distantFuture,
                                 countsDown: false).monospacedDigit()
                        } icon: { Image(systemName: "clock") }
                        Spacer()
                        Label(
                            rssiString(context.state.bluetoothRSSI),
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                        LiveActivityRSSIBars(
                            level: context.state.bluetoothSignalLevel ?? 0
                        )
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(context.state.isReticulumAvailable ? Color.green : Color.orange)
            } compactTrailing: {
                Text(byteCountString(
                    context.state.reticulumBytesIn + context.state.reticulumBytesOut
                )).font(.caption2)
            } minimal: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(context.state.isReticulumAvailable ? Color.green : Color.orange)
            }
        }
    }

    private func availability(_ available: Bool) -> some View {
        Label(available ? "Reticulum Available" : "Reticulum Starting",
              systemImage: available ? "checkmark.circle.fill" : "clock.fill")
            .font(.caption.bold())
            .foregroundStyle(available ? Color.green : Color.orange)
    }

    private func metric(_ title: String, _ bytes: Int, _ image: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: image)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(byteCountString(bytes))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func byteCountString(_ bytes: Int) -> String {
        normalizedByteCountString(ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .file
        ))
    }

    private func normalizedByteCountString(_ value: String) -> String {
        value
            .replacingOccurrences(of: " bytes", with: " B")
            .replacingOccurrences(of: " byte", with: " B")
            .replacingOccurrences(of: " kB", with: " KB")
    }

    private func rssiString(_ rssi: Int?) -> String {
        rssi.map { "\($0) dBm" } ?? "RSSI unavailable"
    }
}

private struct RNodeLockScreenLiveActivityView: View {
    @Environment(\.colorScheme) private var colorScheme

    let context: ActivityViewContext<RNodeLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    context.attributes.rnodeName,
                    systemImage: "antenna.radiowaves.left.and.right"
                )
                .font(.headline)
                .foregroundStyle(.green)
                Spacer()
                availability
            }

            HStack(alignment: .top, spacing: 8) {
                metric(
                    "RETICULUM IN",
                    context.state.reticulumBytesIn,
                    "arrow.down.circle.fill"
                )
                metric(
                    "RETICULUM OUT",
                    context.state.reticulumBytesOut,
                    "arrow.up.circle.fill"
                )
                VStack(alignment: .leading, spacing: 3) {
                    Label("TIME UP", systemImage: "clock.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(
                        timerInterval:
                            context.state.uptimeStartedAt...Date.distantFuture,
                        countsDown: false
                    )
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Label(
                        "BLUETOOTH",
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    Text(rssiString(context.state.bluetoothRSSI))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    HStack(alignment: .center, spacing: 4) {
                        Text(context.state.bluetoothSignalQuality ?? "Unavailable")
                            .font(.caption2.bold())
                            .foregroundStyle(
                                signalColor(
                                    level: context.state.bluetoothSignalLevel
                                )
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        LiveActivityRSSIBars(
                            level: context.state.bluetoothSignalLevel ?? 0
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.72), lineWidth: 1.5)
            }
        }
        .activityBackgroundTint(
            colorScheme == .light ? .black : Color(white: 0.08)
        )
        .activitySystemActionForegroundColor(.white)
    }

    private var availability: some View {
        Label(
            context.state.isReticulumAvailable
                ? "Reticulum Available" : "Reticulum Starting",
            systemImage: context.state.isReticulumAvailable
                ? "checkmark.circle.fill" : "clock.fill"
        )
        .font(.caption.bold())
        .foregroundStyle(
            context.state.isReticulumAvailable
                ? Color.green : Color.orange
        )
    }

    private func metric(
        _ title: String,
        _ bytes: Int,
        _ image: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: image)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(byteCountString(bytes))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func byteCountString(_ bytes: Int) -> String {
        normalizedByteCountString(ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .file
        ))
    }

    private func normalizedByteCountString(_ value: String) -> String {
        value
            .replacingOccurrences(of: " bytes", with: " B")
            .replacingOccurrences(of: " byte", with: " B")
            .replacingOccurrences(of: " kB", with: " KB")
    }

    private func rssiString(_ rssi: Int?) -> String {
        rssi.map { "\($0) dBm" } ?? "Not available"
    }

    private func signalColor(level: Int?) -> Color {
        switch level {
        case 3, 4: .green
        case 2: .yellow
        case 1: .red
        default: .white.opacity(0.72)
        }
    }
}

private struct LiveActivityRSSIBars: View {
    let level: Int

    private var color: Color {
        switch level {
        case 3...4: .green
        case 2: .yellow
        case 1: .red
        default: .white.opacity(0.35)
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        bar <= level
                            ? color : Color.white.opacity(0.2)
                    )
                    .frame(
                        width: 3,
                        height: CGFloat(4 + (bar * 3))
                    )
            }
        }
        .frame(height: 16, alignment: .bottom)
        .accessibilityLabel("Bluetooth signal strength")
        .accessibilityValue("\(level) of 4 bars")
    }
}

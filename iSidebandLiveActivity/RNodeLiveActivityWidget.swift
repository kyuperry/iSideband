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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(context.attributes.rnodeName,
                          systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                    Spacer()
                    availability(context.state.isReticulumAvailable)
                }
                HStack(spacing: 24) {
                    metric("RETICULUM IN", context.state.reticulumBytesIn,
                           "arrow.down.circle.fill")
                    metric("RETICULUM OUT", context.state.reticulumBytesOut,
                           "arrow.up.circle.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Label("TIME UP", systemImage: "clock.fill")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(timerInterval: context.state.uptimeStartedAt...Date.distantFuture,
                             countsDown: false)
                            .font(.headline).monospacedDigit()
                    }
                }
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.88))
            .activitySystemActionForegroundColor(.white)
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
                    Label {
                        Text(timerInterval: context.state.uptimeStartedAt...Date.distantFuture,
                             countsDown: false).monospacedDigit()
                    } icon: { Image(systemName: "clock") }
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
            Label(title, systemImage: image).font(.caption2).foregroundStyle(.secondary)
            Text(byteCountString(bytes)).font(.headline).monospacedDigit()
        }
    }

    private func byteCountString(_ bytes: Int) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .file
        )
    }
}

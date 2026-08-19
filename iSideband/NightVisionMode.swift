import SwiftUI
import UIKit

enum NightVisionPreferenceKey {
    static let enabled = "nightVisionModeEnabled"
    static let dimming = "nightVisionModeDimming"
}

@MainActor
private final class NightVisionBrightnessController {
    static let shared = NightVisionBrightnessController()

    private var brightnessBeforeNightVision: CGFloat?

    func enable() {
        if brightnessBeforeNightVision == nil {
            brightnessBeforeNightVision = UIScreen.main.brightness
        }
        UIScreen.main.brightness = 0.04
    }

    func restore() {
        guard let brightnessBeforeNightVision else { return }
        UIScreen.main.brightness = brightnessBeforeNightVision
        self.brightnessBeforeNightVision = nil
    }
}

struct NightVisionModeModifier: ViewModifier {
    let scenePhase: ScenePhase

    @AppStorage(NightVisionPreferenceKey.enabled)
    private var isEnabled = false

    @AppStorage(NightVisionPreferenceKey.dimming)
    private var dimming = 0.78

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(isEnabled ? .dark : nil)
            .tint(isEnabled ? Color.red : nil)
            .colorMultiply(
                isEnabled
                    ? Color(red: 1, green: 0.055, blue: 0.025)
                    : Color.white
            )
            .overlay {
                if isEnabled {
                    Color.black
                        .opacity(min(max(dimming, 0.35), 0.92))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topLeading) {
                quickToggle
                    .padding(.top, 96)
                    .padding(.leading, 8)
            }
            .simultaneousGesture(
                TapGesture(count: 3).onEnded {
                    guard isEnabled else { return }
                    isEnabled = false
                }
            )
            .onAppear {
                updateBrightness()
            }
            .onChange(of: isEnabled) { _, _ in
                updateBrightness()
            }
            .onChange(of: scenePhase) { _, _ in
                updateBrightness()
            }
    }

    private var quickToggle: some View {
        Toggle("NVG", isOn: $isEnabled)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.red : Color.secondary)
            .tint(.red)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                .ultraThinMaterial,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        isEnabled
                            ? Color.red.opacity(0.65)
                            : Color.secondary.opacity(0.2),
                        lineWidth: 0.5
                    )
            }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .opacity(isEnabled ? 0.9 : 0.65)
            .accessibilityLabel("NVG Mode")
            .accessibilityHint("Turns the night vision display on or off")
    }

    private func updateBrightness() {
        if isEnabled, scenePhase == .active {
            NightVisionBrightnessController.shared.enable()
        } else {
            NightVisionBrightnessController.shared.restore()
        }
    }
}

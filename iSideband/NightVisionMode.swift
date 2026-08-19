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

    private func updateBrightness() {
        if isEnabled, scenePhase == .active {
            NightVisionBrightnessController.shared.enable()
        } else {
            NightVisionBrightnessController.shared.restore()
        }
    }
}

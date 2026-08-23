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

    func enable(dimming: Double) {
        if brightnessBeforeNightVision == nil {
            brightnessBeforeNightVision = UIScreen.main.brightness
        }
        let clampedDimming = min(max(dimming, 0.35), 0.92)
        UIScreen.main.brightness = 0.02 + (1 - clampedDimming) * 0.18
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
            .environment(\.nightVisionModeEnabled, isEnabled)
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
            .onChange(of: dimming) { _, _ in
                updateBrightness()
            }
            .onChange(of: scenePhase) { _, _ in
                updateBrightness()
            }
    }

    private func updateBrightness() {
        if isEnabled, scenePhase == .active {
            NightVisionBrightnessController.shared.enable(dimming: dimming)
        } else {
            NightVisionBrightnessController.shared.restore()
        }
    }
}

private struct NightVisionModeEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nightVisionModeEnabled: Bool {
        get { self[NightVisionModeEnvironmentKey.self] }
        set { self[NightVisionModeEnvironmentKey.self] = newValue }
    }
}

enum NightVisionPalette {
    static let primary = Color(red: 1.0, green: 0.42, blue: 0.24)
    static let secondary = Color(red: 1.0, green: 0.36, blue: 0.20)
    static let surface = Color(red: 0.09, green: 0.012, blue: 0.006)
    static let strongSurface = Color(red: 0.18, green: 0.018, blue: 0.008)
    static let field = Color(red: 0.04, green: 0.006, blue: 0.003)
    static let disabled = Color(red: 0.12, green: 0.018, blue: 0.008)
}

private struct NightVisionProminentButtonModifier: ViewModifier {
    @Environment(\.nightVisionModeEnabled) private var isNightVisionEnabled

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                isNightVisionEnabled
                    ? NightVisionPalette.primary
                    : Color.white
            )
            .tint(
                isNightVisionEnabled
                    ? NightVisionPalette.strongSurface
                    : Color.accentColor
            )
    }
}

extension View {
    func nightVisionProminentButton() -> some View {
        modifier(NightVisionProminentButtonModifier())
    }
}

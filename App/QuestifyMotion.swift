import SwiftUI

/// System preference is read-only. The local setting may reduce app motion further,
/// but turning it off cannot override iOS. DEBUG can still force the existing fallback.
@propertyWrapper
struct QuestifyReduceMotion: DynamicProperty {
    init() {}
    @Environment(\.accessibilityReduceMotion) private var systemValue
    @AppStorage(ReducedMotionPreference.storageKey) private var localValue = ReducedMotionPreference.defaultValue
    #if DEBUG
    private static let fixtureValue=ProcessInfo.processInfo.arguments.contains("--uitesting-reduce-motion")
    #endif
    var wrappedValue:Bool {
        #if DEBUG
        return ReducedMotionPreference.effective(system: systemValue, local: localValue) || Self.fixtureValue
        #else
        return ReducedMotionPreference.effective(system: systemValue, local: localValue)
        #endif
    }
}

/// Shared motion tokens, mirrored from the mini-program `--cy-motion-*` / `--cy-ease-*`
/// (docs/motion-tokens.json, checked by tools/check_native_motion_tokens.py). Change both ends together.
enum QuestifyMotionToken {
    static let press: Double = 0.08
    static let checkFill: Double = 0.12
    static let fast: Double = 0.14
    static let crossfade: Double = 0.15
    static let fadeSwap: Double = 0.20
    static let standard: Double = 0.22
    static let sheetIn: Double = 0.30
    static let sheetOut: Double = 0.25
    static let expand: Double = 0.30
    static let collapse: Double = 0.20
    static let slow: Double = 0.35
    static let celebrate: Double = 0.60
    static let spinnerCycle: Double = 0.70
    /// cubic-bezier control points (x1, y1, x2, y2).
    static let easeOut = (0.22, 0.61, 0.36, 1.0)
    static let easeStandard = (0.4, 0.0, 0.2, 1.0)
    static let easeAccelerate = (0.4, 0.0, 1.0, 1.0)
    static let easeEmphasizedDecelerate = (0.05, 0.7, 0.1, 1.0)
    static let easeSpring = (0.2, 1.4, 0.5, 1.0)
    static let easePageRise = (0.2, 0.82, 0.2, 1.0)

    static func curve(_ c: (Double, Double, Double, Double), _ duration: Double) -> Animation {
        .timingCurve(c.0, c.1, c.2, c.3, duration: duration)
    }
}

/// Small, interruptible feedback. Navigation and reads never wait for an animation.
enum QuestifyMotion {
    static let press = QuestifyMotionToken.curve(QuestifyMotionToken.easeOut, QuestifyMotionToken.fast)
    static let release = Animation.spring(duration: QuestifyMotionToken.standard, bounce: 0.08)
    /// Placeholder → content and local state swaps (mini-program cy-fade-in).
    static let content = QuestifyMotionToken.curve(QuestifyMotionToken.easeOut, QuestifyMotionToken.fadeSwap)
    /// Small geometry follow-ups (frame/position nudges).
    static let fast = QuestifyMotionToken.curve(QuestifyMotionToken.easeOut, QuestifyMotionToken.fast)
}

/// Native Button/NavigationLink semantics are preserved, including cancellation while scrolling.
struct QuestifyCardButtonStyle: ButtonStyle {
    @QuestifyReduceMotion private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion && isEnabled ? 0.98 : 1)
            .opacity(configuration.isPressed && isEnabled ? 0.88 : 1)
            .animation(reduceMotion ? nil : (configuration.isPressed ? QuestifyMotion.press : QuestifyMotion.release), value: configuration.isPressed)
    }
}

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

/// Small, interruptible feedback. Navigation and reads never wait for an animation.
enum QuestifyMotion {
    static let press = Animation.easeOut(duration: 0.12)
    static let release = Animation.spring(duration: 0.24, bounce: 0.08)
    static let content = Animation.easeOut(duration: 0.18)
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

import SwiftUI

/// Small, interruptible feedback. Navigation and reads never wait for an animation.
enum QuestifyMotion {
    static let press = Animation.easeOut(duration: 0.12)
    static let release = Animation.spring(duration: 0.24, bounce: 0.08)
    static let content = Animation.easeOut(duration: 0.18)
}

/// Native Button/NavigationLink semantics are preserved, including cancellation while scrolling.
struct QuestifyCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

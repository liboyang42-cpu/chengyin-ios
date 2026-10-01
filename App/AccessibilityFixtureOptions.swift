#if DEBUG
import SwiftUI

/// Explicit offline preview inputs, not evidence of real device settings or VoiceOver use.
struct AccessibilityFixtureOptions: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let args=ProcessInfo.processInfo.arguments
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(args.contains("--uitesting-dark") ? .dark : nil)
            .dynamicTypeSize(args.contains("--uitesting-large-text") ? .accessibility3 : size)
            .environment(\.accessibilityReduceMotion,reduceMotion || args.contains("--uitesting-reduce-motion"))
    }
}
#endif

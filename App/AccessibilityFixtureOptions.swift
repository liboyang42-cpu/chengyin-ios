#if DEBUG
import SwiftUI

/// Explicit offline preview inputs, not evidence of real device settings or VoiceOver use.
struct AccessibilityFixtureOptions: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    private let args=ProcessInfo.processInfo.arguments
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(args.contains("--uitesting-dark") ? .dark : nil)
            .dynamicTypeSize(args.contains("--uitesting-max-text") ? .accessibility5 : (args.contains("--uitesting-large-text") ? .accessibility3 : size))
    }
}

/// Read the effective descendant environment, never infer it from launch arguments.
/// Attached only to the existing offline fixture notice; absent from Release builds.
struct AccessibilityFixtureEnvironmentValue: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.accessibilityValue(Text(verbatim:
            "colorScheme=\(colorScheme == .dark ? "dark" : "light");dynamicTypeSize=\(sizeName)"))
    }

    private var sizeName: String {
        switch dynamicTypeSize {
        case .xSmall: return "xSmall"
        case .small: return "small"
        case .medium: return "medium"
        case .large: return "large"
        case .xLarge: return "xLarge"
        case .xxLarge: return "xxLarge"
        case .xxxLarge: return "xxxLarge"
        case .accessibility1: return "accessibility1"
        case .accessibility2: return "accessibility2"
        case .accessibility3: return "accessibility3"
        case .accessibility4: return "accessibility4"
        case .accessibility5: return "accessibility5"
        @unknown default: return "unknown"
        }
    }
}
#endif

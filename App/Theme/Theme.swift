import SwiftUI

/// Explicit domain roots, independent of the device's current appearance.
enum ThemeDomain: String, CaseIterable {
    case player, merchant, topicEditor, dark, game

    var colorScheme: ColorScheme {
        switch self {
        case .player, .dark: return .dark
        case .merchant, .topicEditor, .game: return .light
        }
    }
}

private struct ThemeDomainKey: EnvironmentKey {
    static let defaultValue = ThemeDomain.player
}

extension EnvironmentValues {
    var themeDomain: ThemeDomain {
        get { self[ThemeDomainKey.self] }
        set { self[ThemeDomainKey.self] = newValue }
    }
}

extension View {
    /// Set once at a domain root so native controls and content share appearance.
    func themeDomain(_ domain: ThemeDomain) -> some View {
        environment(\.themeDomain, domain)
            .environment(\.colorScheme, domain.colorScheme)
            .preferredColorScheme(domain.colorScheme)
    }
}

/// Additive facade; existing QuestifyPalette and QuestifyMotion remain available.
enum Theme {
    private static func color(_ name: String, in domain: ThemeDomain) -> SwiftUI.Color {
        guard let value = Generated.color(name, in: domain) else {
            preconditionFailure("Missing generated Theme color: \(name) / \(domain)")
        }
        return value
    }

    private static func length(_ name: String) -> CGFloat {
        guard let value = Generated.length(name, in: .player) else {
            preconditionFailure("Missing generated Theme length: \(name)")
        }
        return value
    }

    enum Color {
        static func bgPage(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-bg-page", in: domain) }
        static func bgSurface(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-bg-surface", in: domain) }
        static func bgElevated(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-bg-elevated", in: domain) }
        static func bgRaised(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-bg-raised", in: domain) }
        static func textPrimary(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-text-primary", in: domain) }
        static func textSecondary(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-text-secondary", in: domain) }
        static func textTertiary(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-text-tertiary", in: domain) }
        static func accent(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-brand", in: domain) }
        static func actionPrimaryBackground(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-action-primary-bg", in: domain) }
        static func actionPrimaryForeground(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-action-primary-fg", in: domain) }
        static func danger(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-status-danger", in: domain) }
        static func success(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-status-success", in: domain) }
        static func borderSubtle(in domain: ThemeDomain) -> SwiftUI.Color { Theme.color("--cy-color-border-subtle", in: domain) }
    }

    enum Space {
        static let s1 = Theme.length("--cy-space-1")
        static let s1_5 = Theme.length("--cy-space-1-5")
        static let s2 = Theme.length("--cy-space-2")
        static let s2_5 = Theme.length("--cy-space-2-5")
        static let s3 = Theme.length("--cy-space-3")
        static let s3_5 = Theme.length("--cy-space-3-5")
        static let s4 = Theme.length("--cy-space-4")
        static let s5 = Theme.length("--cy-space-5")
        static let s6 = Theme.length("--cy-space-6")
        static let s7 = Theme.length("--cy-space-7")
        static let s8 = Theme.length("--cy-space-8")
        static let pageX = Theme.length("--cy-page-x")
    }

    enum Radius {
        static let sm = Theme.length("--cy-radius-sm")
        static let md = Theme.length("--cy-radius-md")
        static let lg = Theme.length("--cy-radius-lg")
        static let xl = Theme.length("--cy-radius-xl")
        static let xxl = Theme.length("--cy-radius-2xl")
        /// Prefer Capsule for true pills. Source 999rpx is 499.5pt, not 999pt.
        static let pill = Theme.length("--cy-radius-pill")
    }

    enum Font {
        // Native semantic styles preserve SwiftUI's environment Dynamic Type,
        // including preview/fixture overrides and accessibility sizes.
        static let pageTitle = SwiftUI.Font.system(.title, weight: .semibold)
        static let sheetTitle = SwiftUI.Font.system(.title2, weight: .semibold)
        static let sectionTitle = SwiftUI.Font.system(.headline)
        static let cardTitle = SwiftUI.Font.system(.callout, weight: .semibold)
        static let button = SwiftUI.Font.system(.callout, weight: .semibold)
        static let body = SwiftUI.Font.system(.body)
        static let label = SwiftUI.Font.system(.caption)
        static let caption = SwiftUI.Font.system(.caption2)
        static let micro = SwiftUI.Font.system(.caption2)
        // Fixed source display sizes are separate from readable body typography.
        static let display = SwiftUI.Font.system(size: Theme.length("--cy-type-display"), weight: .semibold)
        static let dataXL = SwiftUI.Font.system(size: Theme.length("--cy-type-data-xl"), weight: .semibold, design: .rounded)
        static let data2XL = SwiftUI.Font.system(size: Theme.length("--cy-type-data-2xl"), weight: .semibold, design: .rounded)
    }

    enum Motion {
        /// Callers pass @QuestifyReduceMotion, which combines system and App policy.
        static func standard(reduceMotion: Bool) -> Animation? {
            animation("--cy-motion-standard", reduceMotion: reduceMotion)
        }
        static func press(reduceMotion: Bool) -> Animation? {
            animation("--cy-motion-press", reduceMotion: reduceMotion)
        }
        static func fast(reduceMotion: Bool) -> Animation? {
            animation("--cy-motion-fast", reduceMotion: reduceMotion)
        }
        private static func animation(_ name: String, reduceMotion: Bool) -> Animation? {
            guard !reduceMotion else { return nil }
            guard let duration = Generated.duration(name, in: .player),
                  let curve = Generated.easing("--cy-ease-standard", in: .player), curve.count == 4 else {
                preconditionFailure("Missing generated Theme motion: \(name)")
            }
            return .timingCurve(curve[0], curve[1], curve[2], curve[3], duration: duration)
        }
    }
}

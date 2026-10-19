import SwiftUI

/// Mini-program badge-wall header parity: lit/total caption, play-side focus readback and
/// the empty-wall explore action. Reads nothing; it only summarizes the loaded wall.
struct ObjectBadgeWallParityHeader: View {
    let wall: ProfileBadgeWall
    let focusBadgeCode: String?
    @Environment(\.growthExploreHomeAction) private var onExploreHome
    @State private var exploreConsumed = false
    var body: some View {
        let summary = ObjectBadgeWallSummary(wall: wall)
        Section {
            if !wall.isPartial {
                Text("badgeWall.summary \(summary.unlocked) \(summary.total) \(summary.locked)")
                    .accessibilityIdentifier("objects.badge.summary")
            }
            if let focus = ObjectBadgeWallFocus.resolve(code: focusBadgeCode, wall: wall) {
                Label { focusText(focus) } icon: { Image(systemName: "scope").accessibilityHidden(true) }
                    .accessibilityIdentifier("objects.badge.focus")
            }
            if wall.isEmpty, let onExploreHome {
                Button("badgeWall.explore") {
                    guard !exploreConsumed else { return }
                    exploreConsumed = true
                    onExploreHome()
                }.buttonStyle(.bordered).frame(minHeight: 44).disabled(exploreConsumed)
                    .accessibilityIdentifier("objects.badge.explore")
            }
        }
    }
    @ViewBuilder private func focusText(_ focus: ObjectBadgeWallFocus) -> some View {
        switch focus {
        case .unlocked(let name): Text("badgeWall.focus.onWall \(name)")
        case .locked(let name): Text("badgeWall.focus.locked \(name)")
        case .notOnWall: Text("badgeWall.focus.elsewhere")
        }
    }
}

/// The source's 查看 3D 徽章 entry, shown only for enamel city medals. It opens the existing
/// static preview (no WebGL/3D renderer ships natively) and closes when the account changes.
struct ObjectBadgeThreeDEntry: ViewModifier {
    let badge: ProfileBadgeSelection
    let reader: any ProfileReading
    let expectedIdentity: ProfileReadIdentity?
    var media: (any ObjectCardImageLoading)? = nil
    @State private var scope = UUID()
    private var parameters: ObjectBadgeDetailParameters? {
        guard case .medal(let medal) = badge, ObjectBadgePresentation.style(medal: medal) == "enamel" else { return nil }
        return ObjectBadgeDetailParameters(query: ["name": medal.medalName, "style": "enamel", "rarity": "1", "img": medal.medalImage],
                                           fallbackName: "")
    }
    func body(content: Content) -> some View {
        content.toolbar {
            if let parameters, expectedIdentity != nil, reader.identity == expectedIdentity {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        ObjectBadgeRoutePreview(parameters: parameters, expectedScope: scope,
                            currentScope: { reader.identity == expectedIdentity ? scope : UUID() }, media: media)
                    } label: { Label("badgeWall.threeD.open", systemImage: "cube") }
                        .accessibilityIdentifier("objects.badge.threeD")
                }
            }
        }
    }
}

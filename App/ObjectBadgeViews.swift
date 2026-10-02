import SwiftUI

/// Additive replacement for the old wall's unrestricted AsyncImage and static detail.
/// Same ProfileService two-endpoint/partial-result reads; no new endpoint or model assets.
@MainActor struct ObjectBadgeWallView: View {
    let reader: any ProfileReading
    var media: (any ObjectCardImageLoading)? = nil
    var body: some View {
        ProfileReadScreen(reader: reader, accessibilityPrefix: "profile.badges", load: { try await reader.profileBadges() }) { wall in
            List {
                if wall.isPartial {
                    Section {
                        Text("profile.badges.partial")
                        if let message = wall.medalFailureMessage, !message.isEmpty { Text(verbatim: message) }
                        Text("profile.badges.partialHint").foregroundStyle(.secondary)
                    }
                }
                if wall.isEmpty { Text("profile.badges.empty") }
                if !wall.identities.isEmpty {
                    Section("profile.badges.identities") {
                        ForEach(Array(wall.identities.enumerated()), id: \.offset) { index, badge in
                            link(.identity(badge), identifier: "profile.badge.identity.\(index)")
                        }
                    }
                }
                if let medals = wall.medals {
                    let city = medals.filter { !$0.isAchievement }
                    let achievements = medals.filter(\.isAchievement)
                    if !city.isEmpty {
                        Section("profile.badges.medals") {
                            ForEach(Array(city.enumerated()), id: \.offset) { index, badge in
                                link(.medal(badge), identifier: "profile.badge.medal.\(index)")
                            }
                        }
                    }
                    if !achievements.isEmpty {
                        Section("profile.badges.achievements") {
                            ForEach(Array(achievements.enumerated()), id: \.offset) { index, badge in
                                link(.medal(badge), identifier: "profile.badge.achievement.\(index)")
                            }
                        }
                    }
                }
            }
        }.appNavigationTitle("profile.badges.title")
    }
    private func link(_ badge: ProfileBadgeSelection, identifier: String) -> some View {
        let capturedIdentity = reader.identity
        return NavigationLink {
            ObjectBadgeDetailView(badge: badge, reader: reader, expectedIdentity: capturedIdentity, media: media)
        } label: {
            HStack {
                Image(systemName: badge.isLocked ? "lock" : "medal").accessibilityHidden(true)
                VStack(alignment: .leading) {
                    if badge.name.isEmpty { Text(badge.familyKey) } else { Text(verbatim: badge.name) }
                    Text(badge.isLocked ? "profile.badges.locked" : "profile.badges.unlocked").font(.caption)
                }
            }
        }.accessibilityIdentifier(identifier)
    }
}

@MainActor struct ObjectBadgeDetailView: View {
    let badge: ProfileBadgeSelection
    let reader: any ProfileReading
    let expectedIdentity: ProfileReadIdentity?
    var media: (any ObjectCardImageLoading)? = nil
    @State private var mediaScope = UUID()
    @State private var expiredScope = UUID()
    private var valid: Bool { expectedIdentity != nil && reader.identity == expectedIdentity }
    private var track: Int {
        switch badge { case .identity(let value): return ObjectBadgePresentation.track(category: value.category); case .medal: return 1 }
    }
    private var style: String {
        switch badge { case .identity: return "glow"; case .medal(let value): return ObjectBadgePresentation.style(medal: value) }
    }
    private var tint: Color { [.green, .secondary, .orange, .gray, .red][track] }
    var body: some View {
        List {
            if !valid { Text("objects.sessionChanged") }
            else {
                Section {
                    VStack(spacing: 16) {
                        ObjectCardArtwork(url: badge.image, label: badge.name, media: media,
                            expectedScope: mediaScope, currentScope: { valid ? mediaScope : expiredScope })
                            .frame(width: 188, height: 188).padding(6)
                            .background(tint.opacity(style == "glow" ? 0.16 : 0.05), in: Circle())
                            .overlay(Circle().stroke(tint, lineWidth: style == "enamel" ? 3 : 1))
                        if badge.name.isEmpty { Text(badge.familyKey).font(.headline) }
                        else { Text(verbatim: badge.name).font(.headline) }
                        Label(badge.isLocked ? "profile.badges.locked" : "profile.badges.unlocked",
                              systemImage: badge.isLocked ? "lock" : "checkmark.seal")
                        Text(style == "enamel" ? "objects.enamel" : "objects.glow").font(.footnote)
                        Text("objects.staticPreview").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 16)
                }
                Section("profile.badges.details") {
                    LabeledContent("profile.badges.family") { Text(badge.familyKey) }
                    switch badge {
                    case .identity(let value):
                        LabeledContent("profile.badges.category") { Text(LocalizedStringKey("objects.track." + (track))) }
                        ProfileOptionalRow(key: "profile.badges.statement", value: value.statement)
                        ProfileOptionalRow(key: "profile.badges.unlockHint", value: value.unlockHint)
                        if value.unlocked { ProfileOptionalRow(key: "profile.badges.obtained", value: ObjectBadgePresentation.date(value.unlockTime)) }
                    case .medal(let value):
                        ProfileOptionalRow(key: "profile.badges.condition", value: value.displayCondition)
                        ProfileOptionalRow(key: "profile.badges.obtained", value: ObjectBadgePresentation.date(value.getTime))
                    }
                }
            }
        }.appNavigationTitle("profile.badges.detail").privacySensitive()
            .accessibilityIdentifier("objects.badge.detail")
    }
}

/// For the existing /badge query route only. Identity category tracks are not rarity.
@MainActor struct ObjectBadgeRoutePreview: View {
    let parameters: ObjectBadgeDetailParameters
    let expectedScope: UUID
    let currentScope: () -> UUID
    var media: (any ObjectCardImageLoading)? = nil
    var body: some View {
        VStack(spacing: 16) {
            if currentScope() == expectedScope {
                ObjectCardArtwork(url: parameters.image, label: parameters.name, media: media,
                    expectedScope: expectedScope, currentScope: currentScope).frame(height: 200)
                Text(verbatim: parameters.name).font(.headline)
                if !parameters.subtitle.isEmpty { Text(verbatim: parameters.subtitle).font(.caption) }
                Text(LocalizedStringKey("objects.rarity." + (parameters.rarity)))
                Text(parameters.style == "enamel" ? "objects.enamel" : "objects.glow")
                Text("objects.staticPreview").font(.caption)
            } else { Text("objects.sessionChanged") }
        }.padding().appNavigationTitle("profile.badges.detail").privacySensitive()
    }
}

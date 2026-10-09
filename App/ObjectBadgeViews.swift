import SwiftUI

/// Local presentation choice over the same authorized badge result. No renderer or read capability is added.
enum ObjectBadgeWallLayout: String, CaseIterable {
    case list, wall
    var titleKey: String { "objects.badgeLayout." + rawValue }
}
struct ObjectBadgeWallLayoutOwner: Equatable {
    let readerID: ObjectIdentifier
    let identity: ProfileReadIdentity?
    let isConfigured: Bool
}
struct ObjectBadgeWallLayoutSelection {
    private var owner: ObjectBadgeWallLayoutOwner?
    private var layout: ObjectBadgeWallLayout = .list
    func value(for current: ObjectBadgeWallLayoutOwner) -> ObjectBadgeWallLayout {
        owner == current && current.identity != nil && current.isConfigured ? layout : .list
    }
    mutating func choose(_ next: ObjectBadgeWallLayout, rendered: ObjectBadgeWallLayoutOwner, current: ObjectBadgeWallLayoutOwner) {
        guard rendered == current, current.identity != nil, current.isConfigured else { return }
        owner = current; layout = next
    }
    mutating func retire() { owner = nil; layout = .list }
}

/// Additive replacement for the old wall's unrestricted AsyncImage and static detail.
/// Same ProfileService two-endpoint/partial-result reads; no new endpoint or model assets.
@MainActor struct ObjectBadgeWallView: View {
    let reader: any ProfileReading
    var media: (any ObjectCardImageLoading)? = nil
    @State private var layoutSelection = ObjectBadgeWallLayoutSelection()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var layoutOwner: ObjectBadgeWallLayoutOwner {
        .init(readerID: ObjectIdentifier(reader), identity: reader.identity, isConfigured: reader.isConfigured)
    }
    var body: some View {
        let owner = layoutOwner
        let layout = layoutSelection.value(for: owner)
        ProfileReadScreen(reader: reader, accessibilityPrefix: "profile.badges", load: { try await reader.profileBadges() }) { wall in
            List {
                Section {
                    ObjectBadgeWallLayoutControl(selection: Binding(
                        get: { layoutSelection.value(for: layoutOwner) },
                        set: { layoutSelection.choose($0, rendered: owner, current: layoutOwner) }))
                    if layout == .wall { Text("objects.badgeLayout.staticOnly").font(.caption).foregroundStyle(.secondary) }
                }
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
                        badgeRows(wall.identities.map { .identity($0) }, accessibilityPrefix: "profile.badge.identity", layout: layout)
                    }
                }
                if let medals = wall.medals {
                    let city = medals.filter { !$0.isAchievement }
                    let achievements = medals.filter(\.isAchievement)
                    if !city.isEmpty {
                        Section("profile.badges.medals") {
                            badgeRows(city.map { .medal($0) }, accessibilityPrefix: "profile.badge.medal", layout: layout)
                        }
                    }
                    if !achievements.isEmpty {
                        Section("profile.badges.achievements") {
                            badgeRows(achievements.map { .medal($0) }, accessibilityPrefix: "profile.badge.achievement", layout: layout)
                        }
                    }
                }
            }
        }.appNavigationTitle("profile.badges.title")
            .toolbar { NavigationLink("nativeNav.badge.open") { BadgeRouteEntryView(reader: reader, media: media) } }
            .onChange(of: layoutOwner) { _, _ in layoutSelection.retire() }
    }
    @ViewBuilder private func badgeRows(_ badges: [ProfileBadgeSelection], accessibilityPrefix: String, layout: ObjectBadgeWallLayout) -> some View {
        if layout == .wall {
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible(), alignment: .topLeading)]
                : [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .topLeading)], alignment: .leading, spacing: 12) {
                ForEach(Array(badges.enumerated()), id: \.offset) { index, badge in
                    link(badge, identifier: "\(accessibilityPrefix).\(index)", layout: layout).buttonStyle(.plain)
                }
            }.padding(.vertical, 4)
        } else {
            ForEach(Array(badges.enumerated()), id: \.offset) { index, badge in
                link(badge, identifier: "\(accessibilityPrefix).\(index)", layout: layout)
            }
        }
    }
    private func link(_ badge: ProfileBadgeSelection, identifier: String, layout: ObjectBadgeWallLayout) -> some View {
        let capturedIdentity = reader.identity
        return NavigationLink {
            ObjectBadgeDetailView(badge: badge, reader: reader, expectedIdentity: capturedIdentity, media: media)
        } label: {
            ObjectBadgeWallBadgeLabel(badge: badge, layout: layout)
        }.accessibilityIdentifier(identifier)
    }
}

/// This control is a separate list section, never nested inside a badge's navigation link.
struct ObjectBadgeWallLayoutControl: View {
    @Binding var selection: ObjectBadgeWallLayout
    var body: some View {
        Picker("objects.badgeLayout.title", selection: $selection) {
            ForEach(ObjectBadgeWallLayout.allCases, id: \.rawValue) { layout in
                Text(LocalizedStringKey(layout.titleKey)).tag(layout)
            }
        }.pickerStyle(.menu).frame(minHeight: 44)
            .accessibilityIdentifier("objects.badge.layout")
    }
}
struct ObjectBadgeWallBadgeLabel: View {
    let badge: ProfileBadgeSelection
    let layout: ObjectBadgeWallLayout
    var body: some View {
        if layout == .wall {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: badge.isLocked ? "lock" : "medal").font(.title2).accessibilityHidden(true)
                description.fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
        } else {
            HStack {
                Image(systemName: badge.isLocked ? "lock" : "medal").accessibilityHidden(true)
                description
            }
        }
    }
    private var description: some View {
        VStack(alignment: .leading) {
            if badge.name.isEmpty { Text(badge.familyKey) } else { Text(verbatim: badge.name) }
            Text(badge.isLocked ? "profile.badges.locked" : "profile.badges.unlocked").font(.caption)
        }
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
                        LabeledContent("profile.badges.category") { Text(LocalizedStringKey("objects.track." + String(track))) }
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
                if parameters.name.isEmpty { Text("profile.badges.detail").font(.headline) }
                else { Text(verbatim: parameters.name).font(.headline) }
                if !parameters.subtitle.isEmpty { Text(verbatim: parameters.subtitle).font(.caption) }
                Text(LocalizedStringKey("objects.rarity." + String(parameters.rarity)))
                Text(parameters.style == "enamel" ? "objects.enamel" : "objects.glow")
                Text("objects.staticPreview").font(.caption)
            } else { Text("objects.sessionChanged") }
        }.padding().appNavigationTitle("profile.badges.detail").privacySensitive()
    }
}

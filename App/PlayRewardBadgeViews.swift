import SwiftUI

/// Source completion card: stable code, explicit collection readback, and Continue.
/// No timer dismisses the card and no local completion/award mutation is performed.
@MainActor struct PlayRewardBadgeRows: View {
    let targets: [PlayRewardBadgeTarget]
    var destination: ((PlayRewardBadgeTarget) -> AnyView)? = nil
    @State private var continued = false
    var body: some View {
        if !targets.isEmpty && !continued {
            VStack(alignment: .leading, spacing: 12) {
                Text("playBadge.receipt").font(.headline)
                Text("playBadge.readbackHint").font(.footnote).foregroundStyle(.secondary)
                ForEach(targets) { target in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: target.name ?? target.code).fixedSize(horizontal: false, vertical: true)
                        if let destination {
                            NavigationLink { destination(target) } label: { Label("playBadge.open", systemImage: "medal") }
                                .accessibilityIdentifier("playBadge.open." + target.code)
                        } else { Text("playBadge.unavailable").font(.footnote) }
                    }
                }
                Button("playBadge.continue") { continued = true }
                    .accessibilityIdentifier("playBadge.continue")
            }.accessibilityIdentifier("playBadge.receipt")
        }
    }
}

@MainActor struct PlayRewardBadgeCollectionView: View {
    let reader: any ProfileReading
    var growthReader: (any GrowthCenterReading)? = nil
    @State private var model: PlayRewardBadgeReadModel
    @State private var reads = ManualMapReadTaskOwner()
    init(target: PlayRewardBadgeTarget, reader: any ProfileReading, growthReader: (any GrowthCenterReading)? = nil,
         isCurrent: @escaping () -> Bool = { true }) {
        self.reader = reader; self.growthReader = growthReader
        _model = State(initialValue: PlayRewardBadgeReadModel(target: target, reader: reader, isCurrent: isCurrent))
    }
    var body: some View {
        List {
            if model.identity == nil { Text("profile.signInRequired") }
            else if !model.isConfigured { Text("playBadge.unavailable") }
            else {
                Section {
                    Text(verbatim: model.target.name ?? model.target.code).font(.headline)
                    LabeledContent("playBadge.code", value: model.target.code)
                    Text("playBadge.readbackHint").font(.footnote).foregroundStyle(.secondary)
                }
                if model.isLoading { ProgressView("profile.loading") }
                else if model.failed { Text("playBadge.failed").accessibilityIdentifier("playBadge.failed") }
                else if let focus = model.focus { PlayRewardBadgeFocusContent(focus: focus) }
                if let growthReader {
                    Section {
                        NavigationLink("growth.title") { GrowthCenterView(reader: growthReader).id(growthReader.scope) }
                            .accessibilityIdentifier("playBadge.growth")
                    }
                }
            }
        }
        .privacySensitive().navigationTitle("playBadge.collection")
        .accessibilityIdentifier("playBadge.collection")
        .toolbar {
            Button("profile.refresh", systemImage: "arrow.clockwise") { reads.start { await model.load() } }
                .disabled(model.isLoading || model.identity == nil || !model.isConfigured)
                .accessibilityIdentifier("playBadge.refresh")
        }
        .task(id: PlayRewardBadgeViewKey(identity: model.identity, configured: model.isConfigured)) {
            guard !Task.isCancelled else { return }
            reads.activate(); model.activate(); await reads.run { await model.load() }
        }
        .refreshable { await reads.run { await model.load() } }
        .onDisappear { reads.deactivate(); model.deactivate() }
    }
}

@MainActor struct PlayRewardBadgeFocusContent: View {
    let focus: PlayRewardBadgeFocus
    var body: some View {
        Section {
            Text(LocalizedStringKey(focus.statusKey)).font(.headline)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(focus.statusKey)
            switch focus {
            case .identity(let badge):
                Text("profile.badges.identities").font(.caption)
                if !badge.badgeName.isEmpty { Text(verbatim: badge.badgeName) }
                ProfileOptionalRow(key: "profile.badges.statement", value: badge.statement)
                ProfileOptionalRow(key: "profile.badges.unlockHint", value: badge.unlockHint)
                if badge.unlocked { ProfileOptionalRow(key: "profile.badges.obtained", value: badge.unlockTime) }
            case .achievement(let badge):
                Text("profile.badges.achievements").font(.caption)
                if !badge.medalName.isEmpty { Text(verbatim: badge.medalName) }
                ProfileOptionalRow(key: "profile.badges.obtained", value: badge.getTime)
            case .missingFromWall, .incompleteWall, .ambiguous:
                Text("playBadge.notIssuanceProof").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlayRewardBadgeViewKey: Hashable {
    let identity: ProfileReadIdentity?
    let configured: Bool
}

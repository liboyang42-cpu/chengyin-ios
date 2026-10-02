import SwiftUI

/// Mount inside a NavigationStack. Identity resets clear drafts, private results, navigation and tasks.
@MainActor struct RoamExperienceHubView: View {
    let reader: any RoamExperienceReading
    var body: some View {
        RoamExperienceMenu(reader: reader).id(reader.identity)
    }
}
@MainActor private struct RoamExperienceMenu: View {
    let reader: any RoamExperienceReading
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "figure.walk.circle.fill").font(.system(size: 48)).foregroundStyle(.tint).accessibilityHidden(true)
                    Text("roam.experience.subtitle").font(.title3).bold()
                    RoamExperienceNotice(offline: reader.isOfflineExample)
                }.padding(.vertical, 8)
            }
            Section("roam.experience.yourRoam") {
                NavigationLink { RoamHistoryView(reader: reader) } label: { Label("roam.experience.history", systemImage: "clock.arrow.circlepath") }
                    .accessibilityIdentifier("roam.experience.history.open")
                NavigationLink { RoamRecoveryView(reader: reader) } label: { Label("roam.experience.recovery", systemImage: "arrow.clockwise.circle") }
                    .accessibilityIdentifier("roam.experience.recovery.open")
                NavigationLink { RoamLivePreparationView(reader: reader) } label: { Label("roam.experience.live", systemImage: "figure.walk") }
                    .accessibilityIdentifier("roam.experience.live.open")
            }
            Section("roam.experience.collect") {
                NavigationLink { RoamStampAlbumView(reader: reader) } label: { Label("roam.experience.album", systemImage: "rectangle.stack") }
                    .accessibilityIdentifier("roam.experience.album.open")
                NavigationLink { RoamCityStampDraftView(offline: reader.isOfflineExample) } label: { Label("roam.experience.cityStamp", systemImage: "envelope") }
                    .accessibilityIdentifier("roam.experience.cityStamp.open")
                NavigationLink { RoamVoucherEntryView() } label: { Label("roam.experience.voucher", systemImage: "ticket") }
                    .accessibilityIdentifier("roam.experience.voucher.open")
            }
            Section {
                NavigationLink { RoamHangoutUnavailableView() } label: { Label("roam.experience.hangout", systemImage: "person.3") }
                    .accessibilityIdentifier("roam.experience.hangout.open")
            }
        }.navigationTitle("roam.experience.title")
            .accessibilityIdentifier("roam.experience.hub")
    }
}
@MainActor struct RoamLivePreparationView: View {
    let reader: any RoamExperienceReading
    @State private var tiles: Set<String> = []
    @State private var cursor = 0
    @State private var hasMore = true
    @State private var loading = false
    @State private var loaded = false
    @State private var error: Error?
    @State private var generation = 0
    var body: some View {
        List {
            Section {
                RoamExperienceNotice(offline: reader.isOfflineExample)
                Label("roam.experience.liveUnavailable", systemImage: "location.slash")
                Text("roam.experience.liveHint").font(.subheadline).foregroundStyle(.secondary)
            }
            Section("roam.experience.tileMemory") {
                if loaded {
                    LabeledContent("roam.experience.loadedTiles", value: String(tiles.count))
                    Text(hasMore ? "roam.experience.tilePartial" : "roam.experience.tileComplete").font(.caption).foregroundStyle(.secondary)
                }
                if let error { RoamExperienceIssue(error: error) { Task { await loadTiles() } } }
                if loading { ProgressView("roam.loading") }
                if !loading && hasMore {
                    Button(loaded ? "roam.experience.loadMore" : "roam.experience.readTiles") { Task { await loadTiles() } }
                        .disabled(reader.identity == nil || !reader.isConfigured)
                        .accessibilityIdentifier("roam.experience.tiles.load")
                }
                if reader.identity == nil { Text("roam.signInRequired") }
                else if !reader.isConfigured { Text("roam.notConfigured") }
            }
            Section { Text("roam.experience.tileReadOnly").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("roam.experience.live")
            .onDisappear { generation += 1; loading = false }
            .accessibilityIdentifier("roam.experience.live")
    }
    private func loadTiles() async {
        guard !loading, hasMore else { return }
        generation += 1; let ticket = generation, identity = reader.identity
        loading = true; error = nil
        defer { if ticket == generation { loading = false } }
        do {
            let page = try await reader.tilePage(afterID: cursor, limit: 1000)
            guard !Task.isCancelled, ticket == generation, reader.identity == identity else { return }
            guard !page.hasMore || page.nextAfterId > cursor else { throw APIError.malformedResponse }
            tiles.formUnion(page.tiles); cursor = page.nextAfterId; hasMore = page.hasMore; loaded = true
        } catch {
            guard !Task.isCancelled, ticket == generation, reader.identity == identity else { return }; self.error = error
        }
    }
}

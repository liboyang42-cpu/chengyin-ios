import SwiftUI

/// Mount inside a NavigationStack. Identity resets clear drafts, private results, navigation and tasks.
@MainActor struct RoamExperienceHubView: View {
    let reader: any RoamExperienceReading
    var stampDestination: (() -> AnyView)? = nil
    var liveDestination: (() -> AnyView)? = nil
    var body: some View {
        RoamExperienceMenu(reader: reader, stampDestination: stampDestination, liveDestination: liveDestination).id(reader.identity)
    }
}
@MainActor private struct RoamExperienceMenu: View {
    let reader: any RoamExperienceReading
    let stampDestination: (() -> AnyView)?
    let liveDestination: (() -> AnyView)?
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
                NavigationLink { if let liveDestination { liveDestination() } else { AnyView(RoamLivePreparationView(reader: reader)) } } label: { Label("roam.experience.live", systemImage: "figure.walk") }
                    .accessibilityIdentifier("roam.experience.live.open")
            }
            Section("roam.experience.collect") {
                NavigationLink { RoamTileMemoryView(reader: reader) } label: { Label("roam.experience.tileMemory", systemImage: "map") }
                    .accessibilityIdentifier("roam.experience.tiles.open")
                NavigationLink { RoamStampAlbumView(reader: reader, stampDestination: stampDestination) } label: { Label("roam.experience.album", systemImage: "rectangle.stack") }
                    .accessibilityIdentifier("roam.experience.album.open")
                NavigationLink { if let stampDestination { stampDestination() } else { AnyView(RoamStampCameraView()) } } label: { Label("roam.experience.cityStamp", systemImage: "camera") }
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
    var body: some View { RoamTileMemoryView(reader: reader, showsLiveUnavailable: true) }
}
/// Always reachable independently of live GPS/presence capability. No reads until requested.
@MainActor struct RoamTileMemoryView: View {
    let reader: any RoamExperienceReading
    var showsLiveUnavailable = false
    var body: some View {
        RoamTileMemoryContent(reader: reader, showsLiveUnavailable: showsLiveUnavailable).id(reader.identity)
    }
}
@MainActor private struct RoamTileMemoryContent: View {
    let reader: any RoamExperienceReading
    let showsLiveUnavailable: Bool
    @State private var pager: RoamTileMemoryPager
    @State private var revision = 0
    @State private var loading = false
    init(reader: any RoamExperienceReading, showsLiveUnavailable: Bool) {
        self.reader = reader; self.showsLiveUnavailable = showsLiveUnavailable
        _pager = State(initialValue: RoamTileMemoryPager(reader: reader))
    }
    var body: some View {
        List {
            Section {
                RoamExperienceNotice(offline: reader.isOfflineExample)
                if showsLiveUnavailable {
                    Label("roam.experience.liveUnavailable", systemImage: "location.slash")
                    Text("roam.experience.liveHint").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Section("roam.experience.tileMemory") {
                if pager.loaded {
                    LabeledContent("roam.experience.loadedTiles", value: String(pager.tiles.count))
                    Text(pager.hasMore ? "roam.experience.tilePartial" : "roam.experience.tileComplete").font(.caption).foregroundStyle(.secondary)
                }
                if let error = pager.error { RoamExperienceIssue(error: error) { Task { await loadTiles() } } }
                if loading { ProgressView("roam.loading") }
                if !loading && pager.hasMore {
                    Button(pager.loaded ? "roam.experience.loadMore" : "roam.experience.readTiles") { Task { await loadTiles() } }
                        .disabled(reader.identity == nil || !reader.isConfigured)
                        .accessibilityIdentifier("roam.experience.tiles.load")
                }
                if reader.identity == nil { Text("roam.signInRequired") }
                else if !reader.isConfigured { Text("roam.notConfigured") }
            }
            Section { Text("roam.experience.tileReadOnly").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle(showsLiveUnavailable ? "roam.experience.live" : "roam.experience.tileMemory")
            .refreshable { revision += 1; loading = false; pager.reset(); await loadTiles() }
            .onDisappear { revision += 1; loading = false; pager.cancelPending() }
            .accessibilityIdentifier(showsLiveUnavailable ? "roam.experience.live" : "roam.experience.tileMemory")
    }
    private func loadTiles() async {
        guard !loading else { return }
        revision += 1; let ticket = revision
        loading = true
        await pager.loadNext()
        if revision == ticket { loading = false; revision += 1 }
    }
}

import SwiftUI

/// Mount inside a NavigationStack. Identity resets clear drafts, private results, navigation and tasks.
@MainActor struct RoamExperienceHubView: View {
    let reader: any RoamExperienceReading
    var albumMetadataReader: RoamAlbumMetadataReader? = nil
    var tileMemoryReader: RoamTileMemoryReader? = nil
    var sessionFactReader: RoamSessionFactReader? = nil
    var stampDestination: (() -> AnyView)? = nil
    var liveDestination: (() -> AnyView)? = nil
    /// Mini-program passport tools (那年今日 / 月度回顾). nil keeps the entries visible with an honest not-configured state.
    var toolsReader: (any RoamPassportToolsReading)? = nil
    /// 探索目标 / 时光胶囊 / 导出. nil keeps the entries with an honest not-configured state.
    var privateToolsReader: (any RoamPrivateToolsServing)? = nil
    /// Host's existing topic detail for an anniversary card's current route; nil = honestly unavailable.
    var anniversaryRouteDestination: ((String) -> AnyView)? = nil
    var body: some View {
        RoamExperienceMenu(reader: reader, albumMetadataReader: albumMetadataReader, tileMemoryReader: tileMemoryReader, sessionFactReader: sessionFactReader, stampDestination: stampDestination, liveDestination: liveDestination, toolsReader: toolsReader, privateToolsReader: privateToolsReader, anniversaryRouteDestination: anniversaryRouteDestination).id(reader.identity)
    }
}
@MainActor private struct RoamExperienceMenu: View {
    let reader: any RoamExperienceReading
    let albumMetadataReader: RoamAlbumMetadataReader?
    let tileMemoryReader: RoamTileMemoryReader?
    let sessionFactReader: RoamSessionFactReader?
    private var effectiveSessionReader: any RoamExperienceReading {
        if let sessionFactReader { return sessionFactReader }; return reader
    }
    let stampDestination: (() -> AnyView)?
    let liveDestination: (() -> AnyView)?
    let toolsReader: (any RoamPassportToolsReading)?
    let privateToolsReader: (any RoamPrivateToolsServing)?
    let anniversaryRouteDestination: ((String) -> AnyView)?
    private var effectiveTileReader: any RoamExperienceReading {
        if let tileMemoryReader { return tileMemoryReader }; return reader
    }
    @State private var passport = RoamPassportOverviewState()
    @AppStorage(ReducedMotionPreference.storageKey) private var reduceMotionLocally = ReducedMotionPreference.defaultValue
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @QuestifyReduceMotion private var effectiveReduceMotion
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "figure.walk.circle.fill").font(.largeTitle).imageScale(.large).foregroundStyle(.tint).accessibilityHidden(true)
                    Text("roam.experience.subtitle").font(.title3).bold()
                    RoamExperienceNotice(offline: reader.isOfflineExample)
                }.padding(.vertical, 8)
            }
            RoamPassportOverviewView(phase: passport.phase(reader: reader)) { passport.load(reader: reader) }
            Section("roam.experience.yourRoam") {
                NavigationLink { RoamEnrolledChaptersDestination(roamReader: reader) } label: { Label("roam.chapters.title", systemImage: "map.fill") }
                    .disabled(reader.identity == nil)
                    .accessibilityIdentifier("roam.chapters.open")
                NavigationLink { RoamOfficialTasksDestination(roamReader: reader) } label: { Label("roam.tasks.title", systemImage: "checklist") }
                    .disabled(reader.identity == nil)
                    .accessibilityIdentifier("roam.tasks.open")
                NavigationLink { RoamHistoryView(reader: reader, liveDestination: liveDestination, toolsReader: toolsReader, privateToolsReader: privateToolsReader, anniversaryRouteDestination: anniversaryRouteDestination) } label: { Label("roam.experience.history", systemImage: "clock.arrow.circlepath") }
                    .accessibilityIdentifier("roam.experience.history.open")
                NavigationLink { RoamRecoveryView(reader: effectiveSessionReader).id(sessionFactReader?.scope) } label: { Label("roam.experience.recovery", systemImage: "arrow.clockwise.circle") }
                    .accessibilityIdentifier("roam.experience.recovery.open")
                NavigationLink { if let liveDestination { liveDestination() } else { AnyView(RoamLivePreparationView(reader: reader)) } } label: { Label("roam.experience.live", systemImage: "figure.walk") }
                    .accessibilityIdentifier("roam.experience.live.open")
            }
            RoamPassportToolsSection(reader: toolsReader, routeDestination: anniversaryRouteDestination, privateTools: privateToolsReader)
            Section("roam.experience.collect") {
                NavigationLink { RoamTileMemoryView(reader: effectiveTileReader).id(tileMemoryReader?.scope) } label: { Label("roam.experience.tileMemory", systemImage: "map") }
                    .accessibilityIdentifier("roam.experience.tiles.open")
                NavigationLink {
                    if let albumMetadataReader { RoamAlbumMetadataDestination(reader: albumMetadataReader).id(albumMetadataReader.scope) }
                    else { RoamStampAlbumView(reader: reader, stampDestination: stampDestination) }
                } label: { Label("roam.experience.album", systemImage: "rectangle.stack") }
                    .accessibilityIdentifier("roam.experience.album.open")
                NavigationLink { RoamBadgeWallDestination(roamReader: reader) } label: { Label("profile.badges.title", systemImage: "medal") }
                    .disabled(reader.identity == nil)
                    .accessibilityIdentifier("roam.badgeWall.open")
                RoamPassportPrivateLinks(tools: privateToolsReader)
                NavigationLink { if let stampDestination { stampDestination() } else { AnyView(RoamStampCameraView()) } } label: { Label("roam.experience.cityStamp", systemImage: "camera") }
                    .accessibilityIdentifier("roam.experience.cityStamp.open")
                NavigationLink { RoamVoucherEntryView() } label: { Label("roam.experience.voucher", systemImage: "ticket") }
                    .accessibilityIdentifier("roam.experience.voucher.open")
            }
            Section {
                NavigationLink { RoamHangoutUnavailableView() } label: { Label("roam.experience.hangout", systemImage: "person.3") }
                    .accessibilityIdentifier("roam.experience.hangout.open")
            }
            Section {
                NavigationLink { RoamLocationSettingsDestination() } label: { Label("roam.locationSettings.title", systemImage: "location.circle") }
                    .accessibilityIdentifier("roam.locationSettings.open")
                NavigationLink { RoamPreflightRulesView() } label: { Label("roam.preflightRules.open", systemImage: "book.closed") }
                    .accessibilityIdentifier("roam.preflightRules.open")
            }
            Section("roam.motion.title") {
                Toggle("roam.motion.reduce", isOn: $reduceMotionLocally)
                    .accessibilityIdentifier("roam.motion.reduce")
                if systemReduceMotion {
                    Text("roam.motion.system").font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("roam.motion.system")
                }
                Text(LocalizedStringKey(effectiveReduceMotion ? "roam.motion.active" : "roam.motion.followsSystem"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(effectiveReduceMotion ? "roam.motion.status.reduced" : "roam.motion.status.system")
            }
        }.navigationTitle("roam.experience.title")
            .onAppear { passport.load(reader: reader) }
            .onChange(of: RoamPassportReadOwner(reader: reader)) { _, _ in passport.load(reader: reader) }
            .refreshable { passport.load(reader: reader) }
            .onDisappear { passport.invalidate() }
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
        RoamTileMemoryContent(reader: reader, showsLiveUnavailable: showsLiveUnavailable)
            .id(RoamTileMemoryPageOwner(reader: reader))
    }
}
/// This owner describes only the existing read capability, never location/reveal authority.
struct RoamTileMemoryPageOwner: Equatable, Hashable {
    let readerID: ObjectIdentifier
    let identity: RoamExperienceIdentity?
    let scope: UUID?
    let configured: Bool
    @MainActor init(reader: any RoamExperienceReading) {
        readerID = ObjectIdentifier(reader); identity = reader.identity
        scope = (reader as? RoamTileMemoryReader)?.scope; configured = reader.isConfigured
    }
}

/// A rendered read intent is consumed once. The original pager still owns its cursor and errors.
@MainActor final class RoamTileMemoryPresentation: ObservableObject {
    let reader: any RoamExperienceReading
    let pager: RoamTileMemoryPager
    private let owner: RoamTileMemoryPageOwner
    @Published private var revision = 0
    @Published private(set) var loading = false
    private var mounted = false
    private var foreground = false
    private var operation = UUID()
    private var work: Task<Void, Never>?
    var isVisible: Bool { mounted && foreground && owner == RoamTileMemoryPageOwner(reader: reader) }
    init(reader: any RoamExperienceReading) {
        self.reader = reader; owner = .init(reader: reader); pager = .init(reader: reader)
    }
    func appear(foreground: Bool) {
        mounted = true; self.foreground = foreground; retire()
    }
    func disappear() { mounted = false; retire() }
    func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value; retire()
        // Returning only offers a new explicit read. It never dispatches a request.
    }
    private func retire() {
        operation = UUID(); work?.cancel(); work = nil
        pager.reset(); loading = false; revision &+= 1
    }
    private func accepts(_ offered: UUID) -> Bool {
        isVisible && operation == offered && !Task.isCancelled && reader.identity != nil && reader.isConfigured
    }
    func readAction() -> () -> Void {
        let offered = operation
        return { [weak self] in
            guard let self, self.accepts(offered), !self.loading, self.pager.hasMore else { return }
            self.operation = UUID(); let issued = self.operation
            self.loading = true
            self.work = Task { [weak self] in
                guard let self else { return }
                await self.read(issued: issued)
            }
        }
    }
    func refreshAction() -> () async -> Void {
        let offered = operation
        return { [weak self] in
            guard let self, self.accepts(offered) else { return }
            self.retire(); let issued = self.operation
            self.loading = true
            await self.read(issued: issued)
        }
    }
    private func read(issued: UUID) async {
        guard operation == issued else { return }
        guard accepts(issued) else { retire(); return }
        await pager.loadNext()
        guard operation == issued else { return }
        guard accepts(issued) else { retire(); return }
        loading = false; work = nil; operation = UUID(); revision &+= 1
    }
}

@MainActor private struct RoamTileMemoryContent: View {
    let reader: any RoamExperienceReading
    let showsLiveUnavailable: Bool
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var presentation: RoamTileMemoryPresentation
    init(reader: any RoamExperienceReading, showsLiveUnavailable: Bool) {
        self.reader = reader; self.showsLiveUnavailable = showsLiveUnavailable
        _presentation = StateObject(wrappedValue: RoamTileMemoryPresentation(reader: reader))
    }
    private var pager: RoamTileMemoryPager { presentation.pager }
    var body: some View {
        let read = presentation.readAction(), refresh = presentation.refreshAction()
        List {
            Section {
                RoamExperienceNotice(offline: reader.isOfflineExample)
                if showsLiveUnavailable {
                    Label("roam.experience.liveUnavailable", systemImage: "location.slash")
                    Text("roam.experience.liveHint").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Section("roam.experience.tileMemory") {
                if presentation.isVisible {
                if pager.loaded {
                    LabeledContent("roam.experience.loadedTiles", value: String(pager.tiles.count))
                        .accessibilityIdentifier("roam.experience.tiles.loaded")
                    Text(pager.hasMore ? "roam.experience.tilePartial" : "roam.experience.tileComplete").font(.caption).foregroundStyle(.secondary)
                }
                if let error = pager.error {
                    if CollectionReadAccess(error) == .denied {
                        Label("roam.w208.entry.denied", systemImage: "lock")
                            .accessibilityIdentifier("roam.experience.tiles.denied")
                    } else { RoamExperienceIssue(error: error, retry: read) }
                }
                if presentation.loading { ProgressView("roam.loading") }
                if !presentation.loading && pager.hasMore {
                    Button(pager.loaded ? "roam.experience.loadMore" : "roam.experience.readTiles", action: read)
                        .disabled(reader.identity == nil || !reader.isConfigured)
                        .accessibilityIdentifier("roam.experience.tiles.load")
                }
                if reader.identity == nil { Text("roam.signInRequired") }
                else if !reader.isConfigured { Text("roam.notConfigured") }
                } else { ProgressView("roam.loading") }
            }
        }.navigationTitle(showsLiveUnavailable ? "roam.experience.live" : "roam.experience.tileMemory")
            .refreshable { await refresh() }
            .onAppear { presentation.appear(foreground: scenePhase == .active) }
            .onChange(of: scenePhase) { _, phase in presentation.setForeground(phase == .active) }
            .onDisappear { presentation.disappear() }
            .accessibilityIdentifier(showsLiveUnavailable ? "roam.experience.live" : "roam.experience.tileMemory")
    }
}

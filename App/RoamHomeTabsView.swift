import SwiftUI

/// Mini-program pages/roam/index top tabs: 开始漫游 | 漫游护照 (`introTabs`).
enum RoamHomeTab: String, CaseIterable, Hashable { case start, passport
    var titleKey: LocalizedStringKey { LocalizedStringKey("roam.w208.tab." + rawValue) }
}

struct RoamHomeTabPicker: View {
    @Binding var selection: RoamHomeTab
    var body: some View {
        Picker("roam.w208.tab.label", selection: $selection) {
            ForEach(RoamHomeTab.allCases, id: \.self) { tab in Text(tab.titleKey).tag(tab) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("roam.home.tabs")
    }
}

/// 开始漫游 intro cards. Each card only navigates; live start stays behind its own dormant destination.
@MainActor struct RoamHomeIntroCards: View {
    let start: () -> AnyView
    let nearby: (() -> AnyView)?
    let myTeams: (() -> AnyView)?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                card("roam.w208.intro.start", "roam.w208.intro.start.sub", "point.topleft.down.to.point.bottomright.curvepath", identifier: "roam.home.intro.start", destination: start)
                if let nearby { card("roam.w208.intro.map", "roam.w208.intro.map.sub", "map", identifier: "roam.home.intro.map", destination: nearby) }
                if let myTeams { card("roam.w208.intro.teams", "roam.w208.intro.teams.sub", "person.3", identifier: "roam.home.intro.teams", destination: myTeams) }
            }.padding(.vertical, 4)
        }
    }
    private func card(_ title: LocalizedStringKey, _ sub: LocalizedStringKey, _ symbol: String, identifier: String, destination: @escaping () -> AnyView) -> some View {
        NavigationLink { destination() } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12).frame(minWidth: 200, minHeight: 44, alignment: .leading)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// Local journal notice. Check and Continue only open their already-supplied destinations.
@MainActor struct RoamHomeRecoveryBannerView: View {
    let banner: RoamHomeRecoveryBanner
    var onContinue: (() -> Void)? = nil
    let destination: () -> AnyView
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(LocalizedStringKey(banner.titleKey), systemImage: banner == .needsCheck ? "exclamationmark.circle" : "arrow.uturn.backward.circle")
                .fixedSize(horizontal: false, vertical: true)
            if banner == .needsCheck {
                NavigationLink { destination() } label: { Text("roam.w208.recovery.check") }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("roam.home.recovery.check")
            } else if let onContinue {
                Button("roam.live.resume", action: onContinue)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("roam.home.recovery.continue")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(banner.accessibilityID)
    }
}

/// 附近活动 peek. Reads only through an approved, account-scoped reader at the manual roam centre.
@MainActor struct RoamEntryPeekView: View {
    let reader: any RoamEntryNearbyReading
    /// Optional team/nearby read at the same centre; nil result = that layer failed.
    var teams: ((RoamSearchArea) async -> [NearbyTeam]?)? = nil
    var onSignIn: (() -> Void)? = nil
    var onOpenMap: (() -> AnyView)? = nil
    var onChooseArea: (() -> Void)? = nil
    var onBeginRead: (() -> Void)? = nil
    var onOpenSelection: ((RoamNearbyEventsEntrySelection) -> Void)? = nil
    let onOpen: (RoamEntryActivityCard) -> Void
    @State private var model = RoamNearbyEventsEntryState()
    @State private var retryTask: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("roam.w208.entry.title").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("action.retry", systemImage: "arrow.clockwise", action: refresh)

                .disabled(RoamNearbyEventsEntryScope(reader: reader) == nil)
                .accessibilityIdentifier("roam.home.peek.refresh")
            }
            if reader.isSignedIn, reader.isConfigured, reader.searchArea == nil {
                RoamStatusView(issue: .areaRequired)
                    .accessibilityIdentifier("roam.home.peek.areaRequired")
                if let onChooseArea { Button("roam.area.title", action: onChooseArea) }
            } else { content }
            if model.visibleTeamState(reader: reader) == .loading {
                ProgressView { Text("roam.nearbyEvents.teamsLoading", tableName: "RoamNearbyEvents") }
                    .accessibilityIdentifier("roam.home.peek.teamsLoading")
            } else if model.visibleTeamState(reader: reader) == .failed {
                VStack(alignment: .leading, spacing: 6) {
                    Label { Text("roam.nearbyEvents.teamsFailed", tableName: "RoamNearbyEvents") } icon: { Image(systemName: "exclamationmark.triangle") }
                        .font(.caption).foregroundStyle(.secondary)
                    Button("action.retry", action: refresh).frame(minHeight: 44)

                        .accessibilityIdentifier("roam.home.peek.teamsRetry")
                }.accessibilityIdentifier("roam.home.peek.teamsFailed")
            }
        }
        .task(id: reader.readKey) { await load() }
        .onDisappear { retryTask?.cancel(); retryTask = nil; model.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roam.home.peek")
    }
    @ViewBuilder private var content: some View {
        switch model.visibleState(reader: reader) {
        case .unavailable:
            Label("roam.w208.entry.unavailable", systemImage: "lock.shield").font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("roam.home.peek.unavailable")
        case .login:
            VStack(alignment: .leading, spacing: 6) {
                Label("roam.w208.entry.login", systemImage: "person.crop.circle.badge.questionmark")
                if let onSignIn { Button("roam.w208.entry.signIn", action: onSignIn).frame(minHeight: 44).accessibilityIdentifier("roam.home.peek.signIn") }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("roam.home.peek.login")
        case .denied:
            Label("roam.w208.entry.denied", systemImage: "hand.raised").accessibilityIdentifier("roam.home.peek.denied")
        case .loading:
            ProgressView("roam.loading").accessibilityIdentifier("roam.home.peek.loading")
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Label("roam.w208.entry.failed", systemImage: "exclamationmark.triangle")
                Button("action.retry", action: refresh).frame(minHeight: 44).accessibilityIdentifier("roam.home.peek.retry")
            }.accessibilityElement(children: .contain).accessibilityIdentifier("roam.home.peek.failed")
        case .empty:
            VStack(alignment: .leading, spacing: 4) {
                Text("roam.w208.entry.empty").font(.subheadline)
                if let onOpenMap {
                    NavigationLink { onOpenMap() } label: { Text("roam.w208.entry.emptyHint").font(.caption) }
                        .accessibilityIdentifier("roam.home.peek.openMap")
                } else { Text("roam.w208.entry.emptyHint").font(.caption).foregroundStyle(.secondary) }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("roam.home.peek.empty")
        case .loaded(let cards):
            let rendered = model.loadedScope
            let readID = model.readID
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(cards) { card in
                        Button {
                            guard let selection = model.selection(card: card, rendered: rendered, readID: readID, reader: reader) else { return }
                            if let onOpenSelection { onOpenSelection(selection) } else { onOpen(card) }
                        } label: { RoamEntryCardView(card: card) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("roam.w208.entry.open \(card.activity.title)"))
                            .accessibilityIdentifier("roam.home.peek.card.\(card.id)")
                    }
                }.padding(.vertical, 4)
            }
        }
    }
    private func refresh() {
        retryTask?.cancel(); model.cancel(); onBeginRead?()
        retryTask = Task { await load() }
    }
    private func load() async {
        guard !Task.isCancelled else { return }
        onBeginRead?()
        await model.load(reader: reader, teams: teams)
    }
}

struct RoamEntryCardView: View {
    let card: RoamEntryActivityCard
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoamEntryCover(source: card.activity.coverURL).frame(width: 180, height: 96).clipShape(RoundedRectangle(cornerRadius: 12))
            Text(LocalizedStringKey(card.tagKey)).font(.caption2.bold()).foregroundStyle(.tint)
            title.font(.subheadline.bold()).lineLimit(2)
            RoamEntryMetaLine(card: card).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(width: 180, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var title: some View {
        if card.activity.title.isEmpty { Text("roam.w208.entry.untitled") } else { Text(verbatim: card.activity.title) }
    }
}

/// `activityView.meta`: 已结束 · 距你 X km · N 支队伍招募, falling back to the address, then 查看活动详情.
struct RoamEntryMetaLine: View {
    let card: RoamEntryActivityCard
    var body: some View {
        let parts = metaParts
        if parts.isEmpty {
            if let address = card.activity.addressName { Text(verbatim: address) } else { Text("roam.w208.entry.viewActivity") }
        } else {
            parts.dropFirst().reduce(parts[0]) { $0 + Text(verbatim: " · ") + $1 }
        }
    }
    private var metaParts: [Text] {
        var parts: [Text] = []
        if card.ended { parts.append(Text("roam.w208.entry.ended")) }
        if let km = card.distanceKilometers {
            parts.append(Text("roam.w208.entry.distance \(km.formatted(.number.precision(.fractionLength(1))))"))
        }
        if !card.ended && card.recruitingCount > 0 { parts.append(Text("roam.w208.entry.recruiting \(card.recruitingCount)")) }
        return parts
    }
}

/// Only an absolute https cover is loaded; anything else shows the source's empty-cover placeholder.
struct RoamEntryCover: View {
    let source: String?
    var body: some View {
        ZStack {
            Rectangle().fill(.secondary.opacity(0.12))
            if let source, let url = URL(string: source), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: "photo").foregroundStyle(.secondary) }
                }
            } else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .accessibilityHidden(true)
    }
}

/// Entry activity sheet: navigation only. 去报名 / 查看详情 / 发起组队 open the existing activity or topic
/// detail; a recruiting team opens the nearby team page focused on that team, where any apply is reviewed.
@MainActor struct RoamEntryActivitySheet: View {
    let card: RoamEntryActivityCard
    var eventDestination: ((RoamEventDestination) -> AnyView)? = nil
    var teamDestination: ((NearbyTeamID) -> AnyView)? = nil
    var readOnly = false
    var isCurrent: () -> Bool = { true }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if !isCurrent() {
                    ContentUnavailableView("roamEvent.changed", systemImage: "arrow.clockwise")
                        .accessibilityIdentifier("roam.home.sheet.stale")
                } else {
                    List {
                        Section {
                            RoamEntryCover(source: card.activity.coverURL).frame(height: 160).listRowInsets(EdgeInsets())
                            Text(LocalizedStringKey(card.tagKey)).font(.caption.bold()).foregroundStyle(.tint)
                            RoamEntryMetaLine(card: card).font(.subheadline).foregroundStyle(.secondary)
                            if readOnly { detailLink("roam.w208.entry.viewDetail", identifier: "roam.home.sheet.primary") }
                            else if let key = card.primaryKey { detailLink(LocalizedStringKey(key), identifier: "roam.home.sheet.primary") }
                            if card.participantCount > 0 {
                                Text("roam.w208.entry.participants \(card.participantCount)").accessibilityIdentifier("roam.home.sheet.participants")
                            }
                        }
                        if !readOnly && !card.teams.isEmpty {
                            Section {
                                ForEach(card.teams) { team in teamRow(team) }
                            } header: { Text("roam.w208.entry.teams \(card.teams.count)") }
                        }
                        if !readOnly && card.registered && !card.ended, card.destination != nil, eventDestination != nil {
                            Section { detailLink("roam.w208.entry.createTeam", identifier: "roam.home.sheet.createTeam") }
                        }
                        if readOnly { Section { Text("roam.readOnlyNotice").font(.footnote).foregroundStyle(.secondary) } }
                    }
                }
            }
            .navigationTitle(Text(verbatim: card.activity.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("roam.w208.entry.close") { dismiss() }.accessibilityIdentifier("roam.home.sheet.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("roam.home.sheet")
    }
    @ViewBuilder private func detailLink(_ title: LocalizedStringKey, identifier: String) -> some View {
        if let destination = card.destination, let eventDestination {
            NavigationLink {
                if isCurrent() { eventDestination(destination) }
                else { ContentUnavailableView("roamEvent.changed", systemImage: "arrow.clockwise") }
            } label: { Text(title).bold() }.disabled(!isCurrent()).accessibilityIdentifier(identifier)
        } else {
            Text(title).foregroundStyle(.secondary).accessibilityIdentifier(identifier)
        }
    }
    @ViewBuilder private func teamRow(_ team: RoamEntryActivityCard.Team) -> some View {
        let label = VStack(alignment: .leading, spacing: 4) {
            if team.title.isEmpty { Text("roam.w208.entry.teamUntitled").font(.headline) } else { Text(verbatim: team.title).font(.headline) }
            Text("roam.w208.entry.teamMembers \(team.joinedCount) \(team.maxMembers)").font(.caption).foregroundStyle(.secondary)
            // Source: 申请加入 once the viewer holds this activity's ticket, otherwise 报名后申请.
            Text(LocalizedStringKey(card.registered ? "roam.w208.entry.apply" : "roam.w208.entry.applyAfterRegister"))
                .font(.caption.bold()).foregroundStyle(card.registered ? Color.accentColor : Color.secondary)
        }
        if team.canApply, let teamDestination {
            NavigationLink { teamDestination(team.teamID) } label: { label }.accessibilityIdentifier("roam.home.sheet.team.\(team.teamID.rawValue)")
        } else if let destination = card.destination, let eventDestination {
            NavigationLink { eventDestination(destination) } label: { label }.accessibilityIdentifier("roam.home.sheet.team.\(team.teamID.rawValue)")
        } else {
            label.accessibilityElement(children: .combine).accessibilityIdentifier("roam.home.sheet.team.\(team.teamID.rawValue)")
        }
    }
}

/// Tools that exist in the mini-program but have no reviewed iOS read/write contract yet.
struct RoamToolUnavailableView: View {
    let titleKey: String
    var body: some View {
        ContentUnavailableView {
            Label(LocalizedStringKey(titleKey), systemImage: "hourglass")
        } description: {
            Text("roam.w208.tool.unavailable")
        }
        .appNavigationTitle(key: titleKey)
        .accessibilityIdentifier("roam.home.tool.unavailable")
    }
}

/// 漫游护照 tab: four readings, five tiles and two play cards, all from this device's saved records.
@MainActor struct RoamHomePassportView: View {
    let reader: (any RoamExperienceReading)?
    var albumMetadataReader: RoamAlbumMetadataReader? = nil
    var stampDestination: (() -> AnyView)? = nil
    var liveDestination: (() -> AnyView)? = nil
    var toolsReader: (any RoamPassportToolsReading)? = nil
    var discoverDestination: (() -> AnyView)? = nil
    /// Host's existing topic detail for an anniversary card's current route; nil = honestly unavailable.
    var anniversaryRouteDestination: ((String) -> AnyView)? = nil
    /// 探索目标 / 时光胶囊 / 导出 owner-only tools; nil keeps the tiles on their fallback page.
    var privateToolsReader: (any RoamPrivateToolsServing)? = nil
    @State private var homeScope: RoamPassportReaderScope?
    @State private var home: Result<RoamPassportHome, Error>?
    private var readerScope: RoamPassportReaderScope? { reader.map { RoamPassportReaderScope($0) } }
    private var currentHome: Result<RoamPassportHome, Error>? { homeScope == readerScope ? home : nil }
    var body: some View {
        List {
            Section {
                if let reader { stats(reader: reader) } else {
                    Text("roam.notConfigured").foregroundStyle(.secondary).accessibilityIdentifier("roam.home.passport.unavailable")
                }
            }
            Section {
                ForEach(RoamPassportHome.Tile.allCases.filter(tileAvailable)) { tile in tileLink(tile) }
            }
            Section {
                ForEach(RoamPassportHome.Play.allCases) { play in playCard(play) }
            }
            RoamPassportToolsSection(reader: toolsReader, routeDestination: anniversaryRouteDestination, privateTools: privateToolsReader)
        }
        .onAppear(perform: load)
        .refreshable { load() }
        .onChange(of: readerScope) { _, _ in
            home = nil; homeScope = nil
            load()
        }
        .accessibilityIdentifier("roam.home.passport")
    }
    private func load() {
        guard let reader else { home = nil; homeScope = nil; return }
        let captured = RoamPassportReaderScope(reader)
        let result = Result { try RoamPassportHome(records: try reader.history()) }
        guard captured == readerScope else { return }
        homeScope = captured; home = result
    }
    @ViewBuilder private func stats(reader: any RoamExperienceReading) -> some View {
        switch currentHome {
        case .none: ProgressView("roam.loading")
        case .failure(let error)?: RoamExperienceIssue(error: error, retry: load)
        case .success(let value)?:
            HStack(spacing: 8) {
                stat("roam.w208.passport.stat.trips", Text(value.summary.trips, format: .number), identifier: "trips")
                stat("roam.w208.passport.stat.shops", value.summary.knownShopVisits.map { Text($0, format: .number) } ?? Text(verbatim: "—"), identifier: "shops")
                stat("roam.w208.passport.stat.days", value.summary.activeDays.map { Text($0, format: .number) } ?? Text(verbatim: "—"), identifier: "days")
                stat("roam.w208.passport.stat.km", value.summary.knownKilometers.map { Text($0, format: .number.precision(.fractionLength(1))) } ?? Text(verbatim: "—"), identifier: "km")
            }.padding(.vertical, 6)
        }
    }
    private func stat(_ key: LocalizedStringKey, _ value: Text, identifier: String) -> some View {
        VStack(spacing: 2) {
            value.font(.title3.bold()).monospacedDigit()
            Text(key).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("roam.home.passport.stat.\(identifier)")
    }
    private func tileLink(_ tile: RoamPassportHome.Tile) -> some View {
        NavigationLink { tileDestination(tile) } label: {
            HStack(spacing: 12) {
                Image(systemName: tile.symbol).foregroundStyle(.tint).frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(LocalizedStringKey(tile.titleKey)).font(.headline)
                        if tile.isNew { Text(verbatim: "NEW").font(.caption2.bold()).padding(.horizontal, 6).background(.tint.opacity(0.2), in: Capsule()) }
                    }
                    caption(tile).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("roam.home.passport.tile.\(tile.rawValue)")
    }
    /// A tile is listed only when it opens something; goals and capsule always open.
    private func tileAvailable(_ tile: RoamPassportHome.Tile) -> Bool {
        switch tile {
        case .history, .badge: return reader != nil
        case .stamp: return reader != nil || albumMetadataReader != nil
        case .goals, .capsule: return true
        }
    }
    private func caption(_ tile: RoamPassportHome.Tile) -> Text {
        if let key = tile.subtitleKey { return Text(LocalizedStringKey(key)) }
        guard case .success(let value)? = currentHome, let count = value.count(tile) else { return Text(verbatim: "—") }
        return tile == .history ? Text("roam.w208.passport.tile.history.count \(count)") : Text("roam.w208.passport.tile.stamp.count \(count)")
    }
    @ViewBuilder private func tileDestination(_ tile: RoamPassportHome.Tile) -> some View {
        switch tile {
        case .history:
            if let reader { RoamHistoryView(reader: reader, liveDestination: liveDestination, toolsReader: toolsReader, privateToolsReader: privateToolsReader, anniversaryRouteDestination: anniversaryRouteDestination) }
        case .stamp:
            if let albumMetadataReader { RoamAlbumMetadataDestination(reader: albumMetadataReader).id(albumMetadataReader.scope) }
            else if let reader { RoamStampAlbumView(reader: reader, stampDestination: stampDestination) }
        case .badge:
            if let reader { RoamBadgeWallDestination(roamReader: reader) }
        case .goals:
            if let privateToolsReader { RoamExplorationGoalsView(tools: privateToolsReader) }
            else { RoamToolUnavailableView(titleKey: tile.titleKey) }
        case .capsule:
            if let privateToolsReader { RoamCapsuleView(tools: privateToolsReader) }
            else { RoamToolUnavailableView(titleKey: tile.titleKey) }
        }
    }
    /// 官方活动 opens the official roam tasks;
    /// 发现附近店铺 opens the nearby map. A card without a destination is not listed.
    @ViewBuilder private func playCard(_ play: RoamPassportHome.Play) -> some View {
        let label = HStack(spacing: 12) {
            Image(systemName: play == .event ? "calendar" : "storefront").foregroundStyle(.tint).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(play.titleKey)).font(.headline)
                Text(LocalizedStringKey(play.subtitleKey)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        switch play {
        case .event:
            if let reader {
                NavigationLink { RoamOfficialTasksDestination(roamReader: reader) } label: { label }
                    .accessibilityIdentifier("roam.home.passport.play.\(play.rawValue)")
            }
        case .discover:
            if let discoverDestination {
                NavigationLink { discoverDestination() } label: { label }
                    .accessibilityIdentifier("roam.home.passport.play.\(play.rawValue)")
            }
        }
    }
}

/// Volatile presentation identity only; it carries no token, result, permission or event ID.
struct RoamPassportReaderScope: Hashable {
    let readerID: ObjectIdentifier
    let identity: RoamExperienceIdentity?
    @MainActor init(_ reader: any RoamExperienceReading) {
        readerID = ObjectIdentifier(reader); identity = reader.identity
    }
}

/// Local read identity only. Remote read configuration is not permission to read one's local journal.
struct RoamHomeRecoveryOwner: Hashable {
    let readerID: ObjectIdentifier
    let scopeKey: String?
    let epoch: UInt64?
    @MainActor init(reader: any RoamExperienceReading) {
        readerID = ObjectIdentifier(reader)
        let identity = reader.identity
        scopeKey = identity?.scope.storageKey; epoch = identity?.epoch
    }
}

/// Restores the source's show-time local read and navigation-only Continue action.
/// The existing live destination remains the only owner of recovery, consent and location.
@MainActor struct RoamHomeRecoveryEntry {
    struct Target: Hashable {
        let id = UUID()
        let owner: RoamHomeRecoveryOwner
    }
    private var owner: RoamHomeRecoveryOwner?
    private var value: RoamHomeRecoveryBanner?
    private var visible = false
    private var foreground = false
    private(set) var revision = UUID()
    var target: Target?

    mutating func appear(reader: (any RoamExperienceReading)?, foreground: Bool, hasDestination: Bool) {
        visible = true; self.foreground = foreground
        reload(reader: reader, hasDestination: hasDestination)
    }
    mutating func disappear() {
        visible = false; revision = UUID(); owner = nil; value = nil
        // A push hides this origin; the immutable target stays until Back or an owner change.
    }
    mutating func setForeground(_ foreground: Bool, reader: (any RoamExperienceReading)?, hasDestination: Bool) {
        self.foreground = foreground; reload(reader: reader, hasDestination: hasDestination)
    }
    mutating func reload(reader: (any RoamExperienceReading)?, hasDestination: Bool) {
        revision = UUID(); owner = nil; value = nil
        if let target, !matches(target, reader: reader, hasDestination: hasDestination) { self.target = nil }
        guard visible, foreground, let reader else { return }
        let captured = RoamHomeRecoveryOwner(reader: reader)
        guard captured.scopeKey != nil else { return }
        do {
            let status = try reader.localWalkStatus()
            guard captured == RoamHomeRecoveryOwner(reader: reader) else { return }
            owner = captured; value = RoamHomeRecoveryBanner(status: status)
        } catch {
            // Unreadable metadata is not a missing/finished record. Preserve its bytes, show no stale notice.
        }
    }
    func banner(reader: (any RoamExperienceReading)?) -> RoamHomeRecoveryBanner? {
        guard visible, foreground, let reader, owner == RoamHomeRecoveryOwner(reader: reader) else { return nil }
        return value
    }
    mutating func continueToExistingDestination(reader: any RoamExperienceReading,
                                                hasDestination: Bool, rendered: UUID) {
        guard rendered == revision, target == nil, hasDestination,
              banner(reader: reader) == .recovered, let captured = owner else { return }
        // The banner is only metadata. Re-read at the tap; a new pending finish must use Check instead.
        reload(reader: reader, hasDestination: hasDestination)
        guard banner(reader: reader) == .recovered, owner == captured else { return }
        target = Target(owner: captured)
    }
    func matches(_ target: Target, reader: (any RoamExperienceReading)?, hasDestination: Bool) -> Bool {
        guard self.target == target, hasDestination, let reader, target.owner.scopeKey != nil else { return false }
        return target.owner == RoamHomeRecoveryOwner(reader: reader)
    }
}

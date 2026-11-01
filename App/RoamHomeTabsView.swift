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

/// 上次漫游需要核对 / 已找回本次漫游记录 from this device's journal only; the link opens the existing check.
@MainActor struct RoamHomeRecoveryBannerView: View {
    let banner: RoamHomeRecoveryBanner
    let destination: () -> AnyView
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(LocalizedStringKey(banner.titleKey), systemImage: banner == .needsCheck ? "exclamationmark.circle" : "arrow.uturn.backward.circle")
                .fixedSize(horizontal: false, vertical: true)
            if banner == .needsCheck {
                NavigationLink { destination() } label: { Text("roam.w208.recovery.check") }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("roam.home.recovery.check")
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
    let onOpen: (RoamEntryActivityCard) -> Void
    @State private var state: RoamEntryPeekState = .loading
    @State private var generation = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("roam.w208.entry.title").font(.headline).accessibilityAddTraits(.isHeader)
            content
        }
        .task(id: reader.readKey) { await load() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roam.home.peek")
    }
    @ViewBuilder private var content: some View {
        switch state {
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
                Button("action.retry") { Task { await load() } }.frame(minHeight: 44).accessibilityIdentifier("roam.home.peek.retry")
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(cards) { card in
                        Button { onOpen(card) } label: { RoamEntryCardView(card: card) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("roam.w208.entry.open \(card.activity.title)"))
                            .accessibilityIdentifier("roam.home.peek.card.\(card.id)")
                    }
                }.padding(.vertical, 4)
            }
        }
    }
    private func load() async {
        generation += 1; let ticket = generation
        guard reader.isSignedIn else { state = .login; return }
        guard reader.isConfigured else { state = .unavailable; return }
        guard let area = reader.searchArea else { state = .unavailable; return }
        state = .loading
        do {
            let rows = try await reader.entryNearby()
            guard ticket == generation, !Task.isCancelled else { return }
            var linked: [NearbyTeam] = []
            if let teams {
                // Same centre and radius as the source's team layer; a failed layer fails the peek.
                guard let read = await teams(area) else { if ticket == generation { state = .failed }; return }
                guard ticket == generation, !Task.isCancelled else { return }
                linked = read
            }
            state = RoamEntryPeekState(activities: rows, teams: linked)
        } catch is CancellationError {
        } catch {
            guard ticket == generation else { return }
            state = RoamEntryPeekState(error: error)
        }
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
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    RoamEntryCover(source: card.activity.coverURL).frame(height: 160).listRowInsets(EdgeInsets())
                    Text(LocalizedStringKey(card.tagKey)).font(.caption.bold()).foregroundStyle(.tint)
                    RoamEntryMetaLine(card: card).font(.subheadline).foregroundStyle(.secondary)
                    if let key = card.primaryKey { detailLink(LocalizedStringKey(key), identifier: "roam.home.sheet.primary") }
                    if card.participantCount > 0 {
                        Text("roam.w208.entry.participants \(card.participantCount)").accessibilityIdentifier("roam.home.sheet.participants")
                    }
                }
                if !card.teams.isEmpty {
                    Section {
                        ForEach(card.teams) { team in teamRow(team) }
                    } header: { Text("roam.w208.entry.teams \(card.teams.count)") }
                }
                if card.registered && !card.ended {
                    Section { detailLink("roam.w208.entry.createTeam", identifier: "roam.home.sheet.createTeam") }
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
        .accessibilityIdentifier("roam.home.sheet")
    }
    @ViewBuilder private func detailLink(_ title: LocalizedStringKey, identifier: String) -> some View {
        if let destination = card.destination, let eventDestination {
            NavigationLink { eventDestination(destination) } label: { Text(title).bold() }.accessibilityIdentifier(identifier)
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
    @State private var home: Result<RoamPassportHome, Error>?
    var body: some View {
        List {
            Section {
                if let reader { stats(reader: reader) } else {
                    Text("roam.notConfigured").foregroundStyle(.secondary).accessibilityIdentifier("roam.home.passport.unavailable")
                }
            }
            Section {
                ForEach(RoamPassportHome.Tile.allCases) { tile in tileLink(tile) }
            }
            Section {
                ForEach(RoamPassportHome.Play.allCases) { play in playCard(play) }
            }
            RoamPassportToolsSection(reader: toolsReader, routeDestination: anniversaryRouteDestination)
            Section {
                NavigationLink { RoamToolUnavailableView(titleKey: "roam.w208.tool.export") } label: {
                    Label("roam.w208.tool.export", systemImage: "square.and.arrow.up")
                }.accessibilityIdentifier("roam.home.tool.export.open")
            }
        }
        .onAppear(perform: load)
        .refreshable { load() }
        .accessibilityIdentifier("roam.home.passport")
    }
    private func load() {
        guard let reader else { home = nil; return }
        do { home = .success(try RoamPassportHome(records: try reader.history())) } catch { home = .failure(error) }
    }
    @ViewBuilder private func stats(reader: any RoamExperienceReading) -> some View {
        switch home {
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
        .disabled(reader == nil && tile != .goals && tile != .capsule)
        .accessibilityIdentifier("roam.home.passport.tile.\(tile.rawValue)")
    }
    private func caption(_ tile: RoamPassportHome.Tile) -> Text {
        if let key = tile.subtitleKey { return Text(LocalizedStringKey(key)) }
        guard case .success(let value)? = home, let count = value.count(tile) else { return Text(verbatim: "—") }
        return tile == .history ? Text("roam.w208.passport.tile.history.count \(count)") : Text("roam.w208.passport.tile.stamp.count \(count)")
    }
    @ViewBuilder private func tileDestination(_ tile: RoamPassportHome.Tile) -> some View {
        switch tile {
        case .history:
            if let reader { RoamHistoryView(reader: reader, liveDestination: liveDestination, toolsReader: toolsReader) }
        case .stamp:
            if let albumMetadataReader { RoamAlbumMetadataDestination(reader: albumMetadataReader).id(albumMetadataReader.scope) }
            else if let reader { RoamStampAlbumView(reader: reader, stampDestination: stampDestination) }
        case .badge:
            if let reader { RoamBadgeWallDestination(roamReader: reader) }
        case .goals, .capsule:
            RoamToolUnavailableView(titleKey: tile.titleKey)
        }
    }
    @ViewBuilder private func playCard(_ play: RoamPassportHome.Play) -> some View {
        let label = HStack(spacing: 12) {
            Image(systemName: play == .event ? "calendar" : "storefront").foregroundStyle(play.isClosed ? Color.secondary : Color.accentColor).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(play.titleKey)).font(.headline)
                Text(LocalizedStringKey(play.subtitleKey)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if play.isClosed { Text("roam.w208.passport.closed").font(.caption.bold()).foregroundStyle(.secondary) }
        }
        if !play.isClosed, let discoverDestination {
            NavigationLink { discoverDestination() } label: { label }.accessibilityIdentifier("roam.home.passport.play.\(play.rawValue)")
        } else {
            label.accessibilityElement(children: .combine).accessibilityIdentifier("roam.home.passport.play.\(play.rawValue)")
        }
    }
}

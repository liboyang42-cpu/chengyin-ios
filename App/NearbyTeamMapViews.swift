import SwiftUI

/// Mini-program subpackageRoam/nearby + my-teams presentation pieces. Read-only: every value comes from
/// already-read rows, the map centre is the manually selected point, and no device location is requested.
enum NearbyTeamViewMode: Hashable { case map, list }
struct NearbyMineLoad { var loading = false; var failed = false; var loaded = false }
enum NearbyRecruitingLoad: Equatable { case idle, loading, loaded, failed, noArea }

/// Dark count bar 附近的队伍 · N 支在招募 with the 地图 / 列表 switch.
struct NearbyTeamHeaderBar: View {
    let loaded: Bool
    let count: Int
    @Binding var mode: NearbyTeamViewMode
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                if loaded { Text("nearby.w208.header \(count)") } else { Text("nearby.w208.header.loading") }
            } icon: { Image(systemName: "circle.fill").font(.caption2).foregroundStyle(.tint) }
            .font(.subheadline.weight(.semibold)).accessibilityIdentifier("nearby.w208.header")
            Picker("nearby.w208.viewMode", selection: $mode) {
                Text("nearby.w208.mode.map").tag(NearbyTeamViewMode.map)
                Text("nearby.w208.mode.list").tag(NearbyTeamViewMode.list)
            }.pickerStyle(.segmented).accessibilityIdentifier("nearby.w208.viewMode")
        }
    }
}

/// xcx `nearbyReadAccess`: login / denied / load failure, each with its own action. The map stays usable.
struct NearbyLoadIssueCard: View {
    let issue: NearbyLoadIssue
    let onSignIn: (() -> Void)?
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(issue.titleKey)).font(.headline)
            Text("nearby.w208.issue.sub").font(.subheadline).foregroundStyle(.secondary)
            if issue == .signIn {
                if let onSignIn { Button(LocalizedStringKey(issue.actionKey), action: onSignIn).frame(minHeight: 44).accessibilityIdentifier("nearby.w208.issue.action") }
            } else {
                Button(LocalizedStringKey(issue.actionKey), action: retry).frame(minHeight: 44).accessibilityIdentifier("nearby.w208.issue.action")
            }
        }.fixedSize(horizontal: false, vertical: true).padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain).accessibilityIdentifier("nearby.w208.issue.\(issue.rawValue)")
    }
}

/// Team markers only. Hangout/activity markers need the separately approved roam events reader and are not mixed in here.
struct NearbyTeamMapSection: View {
    let center: RoamSearchArea
    let teams: [NearbyTeam]
    let focusedID: NearbyTeamID?
    let onFocus: (NearbyTeamID) -> Void
    private var markers: [NearbyTeamMarker] { NearbyTeamBridge.markers(teams) }
    private var pins: [SearchMapPin] {
        markers.compactMap { marker in
            guard let coordinate = RoamCoordinate(latitude: marker.latitude, longitude: marker.longitude) else { return nil }
            return SearchMapPin(id: marker.id, title: marker.title, coordinate: coordinate, symbol: marker.active ? "person.3.fill" : "person.3")
        }
    }
    var body: some View {
        QuestifyDensityMap(area: center, pins: pins, selectedID: markers.first { $0.teamID == focusedID }?.id,
            mapHeight: 270, initialSpan: 0.045, pinIdentifierPrefix: "nearby.pin.",
            pinHint: { id in
                guard let marker = markers.first(where: { $0.id == id }) else { return Text("") }
                return marker.active ? Text("nearby.w208.badge.joined") : Text("nearby.title")
            }, onSelect: { id in
                if case .team(let teamID)? = NearbyTeamBridge.markerDestination(id) { onFocus(teamID) }
            })
            .accessibilityIdentifier("nearby.w208.map")
    }
}

struct NearbyTeamListHeader: View {
    let radius: Int
    let count: Int
    var body: some View {
        Text("nearby.w208.listHeader \(NearbyTeamPresentation.rangeText(radius)) \(count)")
            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).accessibilityIdentifier("nearby.w208.listHeader")
    }
}

/// List mode row: name, sub line, badge and joined/max; tapping opens the same team card inline.
struct NearbyTeamListRow: View {
    let team: NearbyTeam
    let expanded: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if NearbyTeamPresentation.heading(team).isEmpty { Text("nearby.untitled").font(.headline) }
                    else { Text(verbatim: NearbyTeamPresentation.heading(team)).font(.headline) }
                    HStack(spacing: 8) { NearbyTeamSubLine(team: team); NearbyTeamBadgeView(badge: NearbyTeamBadge(mode: team.mode)) }
                }
                Spacer(minLength: 8)
                Text(verbatim: "\(team.joinedCount)/\(team.maxMembers)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(.secondary).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).frame(minHeight: 44).accessibilityIdentifier("nearby.w208.row.\(team.id.rawValue)")
    }
}

/// Corner controls 范围 N km · 我的队伍 (· N).
struct NearbyTeamCornerBar: View {
    let radius: Int
    let mineCount: Int
    let openMine: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Text("nearby.w208.range \(NearbyTeamPresentation.rangeText(radius))").font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 8).background(.secondary.opacity(0.1), in: Capsule())
                .accessibilityIdentifier("nearby.w208.range")
            Button(action: openMine) {
                if mineCount > 0 { Text("nearby.w208.myTeams.count \(mineCount)") } else { Text("nearby.w208.myTeams") }
            }.frame(minHeight: 44).accessibilityIdentifier("nearby.w208.myTeams")
        }
    }
}

struct NearbyTeamBadgeView: View {
    let badge: NearbyTeamBadge
    /// my-teams labels the viewer's own team 队长 rather than the map's 我带队.
    var captain = false
    var body: some View {
        Text(LocalizedStringKey(captain ? "nearby.w208.badge.captain" : badge.key))
            .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule()).foregroundStyle(tint)
            .accessibilityIdentifier("nearby.w208.badge.\(badge.rawValue)")
    }
    private var tint: Color {
        switch badge { case .joined: return .green; case .pending: return .orange; case .rejected: return .red; case .leader: return .accentColor; case .buy, .apply: return .secondary }
    }
}

/// `城市定向/自由探索 · {addr}集合/附近 · 距你 X km`.
struct NearbyTeamSubLine: View {
    let team: NearbyTeam
    private var line: Text {
        var line = Text(team.productType == 2 ? "nearby.freeExplore" : "nearby.urbanExplore")
        if !team.addressName.isEmpty {
            let place = NearbyTeamPresentation.placeIsGather(team) ? Text("nearby.w208.place.gather \(team.addressName)") : Text("nearby.w208.place.near \(team.addressName)")
            line = line + Text(verbatim: " · ") + place
        }
        if let distance = team.distance { line = line + Text(verbatim: " · ") + Text("nearby.w208.distance \(NearbyTeamPresentation.distanceText(distance))") }
        return line
    }
    var body: some View { line.font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

/// `队长 X · 已组 N 人 · 还差 M 人满员 / 已满员`.
struct NearbyTeamMembersLine: View {
    let team: NearbyTeam
    private var line: Text {
        let leader = team.leaderName.isEmpty ? Text("nearby.w208.members.leaderUnknown") : Text("nearby.w208.members.leader \(team.leaderName)")
        let left = NearbyTeamPresentation.remainingSeats(team)
        let seats = left > 0 ? Text("nearby.w208.members.left \(left)") : Text("nearby.w208.members.full")
        return leader + Text(verbatim: " · ") + Text("nearby.w208.members.joined \(team.joinedCount)") + Text(verbatim: " · ") + seats
    }
    var body: some View { line.font(.subheadline).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("nearby.w208.members") }
}

/// Default-face stack. Remote avatar URLs are display data only and are not fetched by this surface.
struct NearbyTeamFaces: View {
    let count: Int
    var body: some View {
        HStack(spacing: -8) {
            ForEach(0..<max(0, min(3, count)), id: \.self) { _ in
                Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.secondary)
                    .background(Circle().fill(Color(.systemBackground)))
            }
        }.accessibilityHidden(true)
    }
}

/// Card notice per read state (xcx `teamCardState`). Leader and unverified rows have none.
struct NearbyTeamNotice: View {
    let mode: String
    private var key: LocalizedStringKey? {
        switch mode {
        case "joined": return "nearby.w208.notice.joined"
        case "pending": return "nearby.w208.notice.pending"
        case "rejected": return "nearby.w208.notice.rejected"
        case "apply": return "nearby.w208.notice.apply"
        case "buy": return "nearby.w208.notice.buy"
        default: return nil
        }
    }
    var body: some View {
        if let key { Text(key).font(.subheadline.weight(.medium)).accessibilityIdentifier("nearby.w208.notice") }
    }
}

/// my-teams `members()`: 已组 j/m, or 已组 j 人 when capacity is unknown.
struct NearbyMineMembersText: View {
    let joined: Int?
    let maximum: Int?
    var body: some View {
        if let maximum { Text("nearby.w208.mine.members \(joined ?? 0) \(maximum)").font(.footnote).foregroundStyle(.secondary) }
        else { Text("nearby.w208.mine.membersOnly \(joined ?? 0)").font(.footnote).foregroundStyle(.secondary) }
    }
}

/// 附近在招募 under an empty 我的: NONE rows only, 需购票 / 可申请, 在地图上看.
struct NearbyRecruitingSection: View {
    let state: NearbyRecruitingLoad
    let teams: [NearbyTeam]
    let retry: () -> Void
    let openOnMap: (NearbyTeamID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("nearby.w208.recruit.title").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("nearby.w208.recruit.title")
            switch state {
            case .idle: EmptyView()
            case .loading: ProgressView("nearby.w208.recruit.loading")
            case .failed:
                Button(action: retry) { Text("nearby.w208.recruit.failed") }.frame(minHeight: 44).accessibilityIdentifier("nearby.w208.recruit.retry")
            case .noArea:
                Button(action: retry) { Text("nearby.w208.recruit.noArea") }.frame(minHeight: 44).accessibilityIdentifier("nearby.w208.recruit.retry")
            case .loaded:
                if teams.isEmpty { Text("nearby.w208.recruit.empty").accessibilityIdentifier("nearby.w208.recruit.empty") }
                ForEach(teams) { team in row(team) }
            }
        }
    }
    private func row(_ team: NearbyTeam) -> some View {
        Button { openOnMap(team.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    NearbyTeamFaces(count: NearbyTeamPresentation.faceCount(real: team.memberAvatars.count, members: team.joinedCount))
                    if team.title.isEmpty { Text("nearby.w208.mine.untitled").font(.headline) } else { Text(verbatim: team.title).font(.headline) }
                    Spacer(minLength: 8)
                    NearbyTeamBadgeView(badge: NearbyTeamBadge(mode: team.mode))
                }
                NearbyTeamSubLine(team: team)
                HStack {
                    NearbyMineMembersText(joined: team.joinedCount, maximum: team.maxMembers > 0 ? team.maxMembers : nil)
                    Spacer()
                    Text("nearby.w208.recruit.onMap").font(.footnote.weight(.semibold)).foregroundStyle(.tint)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("nearby.w208.recruit.\(team.id.rawValue)")
    }
}

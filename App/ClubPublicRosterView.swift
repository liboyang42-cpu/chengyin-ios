import SwiftUI

/// The public branch never constructs ClubGovernancePermissions or a member action.
/// Profiles reuse the existing public reader with chat/actions intentionally absent.
@MainActor struct ClubPublicRosterView<Reader: ClubReading & ObservableObject>: View {
    let clubID: Int
    @ObservedObject var reader: Reader
    let source: ClubPublicRosterReader?
    let profile: ClubEnrollmentProfileContext?
    let viewerRevision: UInt64
    let isLeaderboard: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.themeDomain) private var domain
    @State private var mode: ClubPublicRosterMode
    @State private var snapshot: ClubPublicRosterSnapshot?
    @State private var snapshotKey: ReadKey?
    @State private var generation: UInt64 = 0
    @State private var loading = false
    @State private var failed = false
    @State private var active = true
    @State private var profileTarget: ProfileTarget?
    private struct ReadKey: Equatable {
        let identity: ClubReadIdentity
        let clubID: Int
        let mode: ClubPublicRosterMode
        let revision: UInt64
        let approval: ClubPublicRosterApproval?
    }
    private struct ProfileTarget: Identifiable {
        let id = UUID()
        let memberID: Int
        let generation: UInt64
        let identity: ClubReadIdentity
        let profileRevision: UInt64
        let profileReader: ObjectIdentifier
        let squareReader: ObjectIdentifier
        let squareScope: UUID
    }
    init(clubID: Int, reader: Reader, source: ClubPublicRosterReader?, profile: ClubEnrollmentProfileContext?,
         viewerRevision: UInt64, leaderboard: Bool) {
        self.clubID = clubID; self.reader = reader; self.source = source; self.profile = profile
        self.viewerRevision = viewerRevision; isLeaderboard = leaderboard
        _mode = State(initialValue: leaderboard ? .composite : .members)
    }
    private var key: ReadKey { .init(identity: reader.clubIdentity, clubID: clubID, mode: mode, revision: viewerRevision, approval: source?.authorization) }
    private var accepted: ClubPublicRosterSnapshot? {
        guard active, scenePhase == .active, snapshotKey == key, let snapshot, snapshot.club.id == clubID,
              snapshot.identity == reader.clubIdentity, snapshot.mode == mode,
              source?.isCurrent(snapshot) == true else { return nil }
        return snapshot
    }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        Group {
            if !reader.clubIdentity.isSignedIn {
                ContentUnavailableView("club.signInRequired", systemImage: "person.crop.circle.badge.exclamationmark")
            } else if source?.authorization == nil {
                ContentUnavailableView { Label { Text("club.publicRoster.unavailable", tableName: "ClubPublicRoster") } icon: { Image(systemName: "lock") } }
            } else {
                List {
                    if isLeaderboard {
                        Picker("club.gov.sort", selection: $mode) {
                            ForEach([ClubPublicRosterMode.composite, .mileage, .pace, .duration], id: \.self) { value in
                                Text(LocalizedStringKey("club.gov.sort." + value.rawValue)).tag(value)
                            }
                        }.font(Theme.Font.label).frame(minHeight: 44)
                            .accessibilityIdentifier("club.publicRoster.sort")
                        Text("club.detail.leaderboard.reset").font(Theme.Font.label)
                            .foregroundColor(Theme.Generated.color("--cy-color-text-secondary", in: domain))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if loading { ProgressView("club.loading") }
                    if failed {
                        Text("club.publicRoster.revoked", tableName: "ClubPublicRoster")
                            .font(Theme.Font.body).foregroundColor(Theme.Generated.color("--cy-color-status-danger", in: domain))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("club.publicRoster.error")
                        Button("action.retry") { Task { await load() } }
                            .buttonStyle(.bordered).font(Theme.Font.button).frame(minHeight: 44)
                            .disabled(loading)
                    } else if let current = accepted {
                        Section {
                            Text(verbatim: current.club.name).font(Theme.Font.sectionTitle)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if current.memberIDs.isEmpty {
                            Group {
                                if isLeaderboard { Text("club.publicRoster.emptyRank", tableName: "ClubPublicRoster") }
                                else { Text(current.club.memberCount > 0 ? "club.membersUnavailable" : "club.emptyMembers") }
                            }
                                .font(Theme.Font.body).foregroundColor(Theme.Generated.color("--cy-color-text-secondary", in: domain))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("club.publicRoster.empty")
                        }
                        ForEach(current.members) { member in
                            memberLink(id: member.memberId, nickname: member.nickname) {
                                if let level = member.levelId, level > 0 { Text("club.memberLevel \(level)").font(Theme.Font.label) }
                                if let time = member.joinTime, !time.isEmpty { Text("club.memberJoined \(time)").font(Theme.Font.label).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                        ForEach(Array(current.ranks.enumerated()), id: \.element.memberId) { index, member in
                            memberLink(id: member.memberId, nickname: member.nickname) {
                                let rankLayout = dynamicTypeSize.isAccessibilitySize
                                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Generated.length("--cy-space-1", in: domain)))
                                    : AnyLayout(HStackLayout(spacing: Theme.Generated.length("--cy-space-2", in: domain)))
                                rankLayout {
                                    Text("#\(index + 1)").monospacedDigit()
                                    if let value = member.metric(mode) { Text(value, format: .number.precision(.fractionLength(0...1))).monospacedDigit() }
                                    Text(LocalizedStringKey("club.publicRoster.unit." + mode.rawValue), tableName: "ClubPublicRoster")
                                }.font(Theme.Font.label)
                            }
                        }
                        Text("club.publicRoster.readOnly", tableName: "ClubPublicRoster").font(Theme.Font.label)
                            .foregroundColor(Theme.Generated.color("--cy-color-text-secondary", in: domain))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .scrollContentBackground(Theme.Generated.color("--cy-color-bg-page", in: domain) != nil ? .hidden : .automatic)
                .background {
                    if let background = Theme.Generated.color("--cy-color-bg-page", in: domain) { background }
                }
            }
        }
        .font(Theme.Font.body)
        .tint(Theme.Generated.color("--cy-color-accent", in: domain))
        .appNavigationTitle(isLeaderboard ? "club.detail.leaderboard.title" : "club.members")
        .accessibilityIdentifier("club.publicRoster.root")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("club.refresh", systemImage: "arrow.clockwise") { Task { await load() } }.disabled(loading) } }
        .refreshable { await load() }
        .task(id: key) { active = true; await load() }
        .onChange(of: scenePhase) { _, phase in
            invalidate()
            if phase == .active { active = true; Task { await load() } }
        }
        .onAppear { active = true }
        .onDisappear { active = false; invalidate() }
        .sheet(item: $profileTarget) { target in
            if let profile, current(target) {
                NavigationStack {
                    SocialPublicProfileView(memberID: target.memberID, reader: profile.reader, squareReader: profile.squareReader,
                                            actions: nil, showsStartChat: false, isCurrent: { current(target) })
                }
            } else { Color.clear.onAppear { profileTarget = nil } }
        }
    }
    @ViewBuilder private func memberLink<Detail: View>(id: Int, nickname: String?, @ViewBuilder detail: () -> Detail) -> some View {
        Button { Task { await load(selecting: id) } } label: {
            HStack(alignment: .top, spacing: Theme.Space.s3) {
                Image(systemName: "person.crop.circle.fill").font(Theme.Font.sectionTitle)
                    .foregroundStyle(Theme.Color.textSecondary(in: domain)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.s1) {
                    Group {
                        if let nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(verbatim: nickname) }
                        else { Text("club.memberNumber \(id)") }
                    }.font(Theme.Font.cardTitle).foregroundStyle(Theme.Color.textPrimary(in: domain))
                    detail().foregroundStyle(Theme.Color.textSecondary(in: domain))
                }.fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .disabled(loading || !profileMatches || profileTarget != nil)
            .accessibilityIdentifier("club.publicRoster.member.\(id)")
    }
    private var profileMatches: Bool {
        guard let profile else { return false }
        return profile.reader.isConfigured && profile.reader.identity.accountID == reader.clubIdentity.accountID &&
            profile.reader.identity.epoch == reader.clubIdentity.epoch
    }
    private func current(_ target: ProfileTarget) -> Bool {
        guard let snapshot = accepted, let profile else { return false }
        return target.identity == reader.clubIdentity && target.generation == generation && snapshot.memberIDs.contains(target.memberID) &&
            profileMatches && profile.reader.presentationRevision == target.profileRevision &&
            ObjectIdentifier(profile.reader) == target.profileReader && ObjectIdentifier(profile.squareReader) == target.squareReader &&
            profile.squareReader.scope == target.squareScope
    }
    private func invalidate() {
        generation &+= 1; snapshot = nil; snapshotKey = nil; profileTarget = nil; loading = false; failed = false
    }
    private func load(selecting memberID: Int? = nil) async {
        invalidate()
        guard active, scenePhase == .active, let source, source.authorization != nil else { return }
        let operation = generation, expected = key
        loading = true
        defer { if generation == operation { loading = false } }
        do {
            let value = try await source.read(clubID: clubID, mode: mode, isCurrent: {
                active && scenePhase == .active && generation == operation && key == expected
            })
            guard active, scenePhase == .active, generation == operation, key == expected, !Task.isCancelled else { return }
            snapshot = value; snapshotKey = expected
            if let memberID, value.memberIDs.contains(memberID), profileMatches, let profile {
                profileTarget = .init(memberID: memberID, generation: operation, identity: reader.clubIdentity,
                    profileRevision: profile.reader.presentationRevision, profileReader: ObjectIdentifier(profile.reader),
                    squareReader: ObjectIdentifier(profile.squareReader), squareScope: profile.squareReader.scope)
            }
        } catch {
            guard active, generation == operation, key == expected, !Task.isCancelled else { return }
            snapshot = nil; profileTarget = nil; failed = true
        }
    }
}

#if DEBUG
// C44's actual club-name fixture only. No roster, reader, profile target or request.
#Preview("C44 · public-roster heading · offline") {
    Text(verbatim: "城瘾夜行俱乐部").font(Theme.Font.sectionTitle)
        .fixedSize(horizontal: false, vertical: true)
        .padding(Theme.Space.pageX).themeDomain(.player)
}
#endif

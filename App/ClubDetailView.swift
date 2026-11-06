import SwiftUI

@MainActor
struct ClubDetailView<Reader: ClubReading & ObservableObject>: View {
    let id: Int
    @ObservedObject var reader: Reader
    var onSignIn: (() -> Void)? = nil
    var actionCoordinator: ClubActionCoordinator? = nil
    var management:ClubManagementContext? = nil
    var community: ClubCommunityContext? = nil
    /// Dedicated read approval is never inferred from membership or governance.
    var publicRoster: ClubPublicRosterReader? = nil
    /// Deep-link intent (`tab=manage`); honored only after the detail read confirms access.
    var requestedTab: ClubDetailTab? = nil
    @State private var selectedTab: ClubDetailTab? = nil
    @State private var manageGrant: ClubDetailManageGrant? = nil
    @State private var actionDetail: ClubRecord? = nil
    @State private var actionIdentity: ClubReadIdentity? = nil
    @State private var managementNeedsRefresh = false
    @State private var managementRevision: UInt64 = 0
    @State private var detailGeneration: UInt64 = 0
    @Environment(\.clubBadgeHostFactory) private var badgeHost
    @Environment(\.locale) private var locale
    var body: some View {
        ClubReadScreen(reader: reader, accessibilityPrefix: "club.detail", refreshRevision: managementRevision, onSignIn: onSignIn,
                       load: {
                           detailGeneration &+= 1
                           let revision = detailGeneration, identity = reader.clubIdentity
                           let detail = try await reader.clubDetail(id: id)
                           // Neither an older refresh nor a pre-mutation read can
                           // replace a newer refresh or action readback.
                           guard !Task.isCancelled, revision == detailGeneration, identity == reader.clubIdentity else { throw CancellationError() }
                           // Clear on every accepted read, even if its value equals the
                           // older pre-action snapshot (for example after removal).
                           actionDetail = nil; actionIdentity = nil
                           return detail
                       }) { loadedClub in
            let club = actionIdentity == reader.clubIdentity && actionDetail?.id == id ? (actionDetail ?? loadedClub) : loadedClub
            let tabs = ClubDetailTabPolicy(club: club, grant: manageGrant)
            let tab = tabs.resolve(selectedTab ?? tabs.initialTab(requested: requestedTab))
            List {
                // Mini-program profile block: cover hero, name, then two meta lines —
                // 「类型 · N 名成员」 and the join policy (公开加入 / 需审核加入).
                Section {
                    VStack(alignment: .leading, spacing: Theme.Space.s2) {
                        ClubDetailCover(source: club.cover)
                        ClubName(value: club.name).font(Theme.Font.pageTitle)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("club.detail.name")
                        Label { Text(verbatim: headerMeta(club)) } icon: { Image(systemName: "person.3") }
                            .font(Theme.Font.label).foregroundStyle(.secondary)
                        if club.joinPolicySupported {
                            Label(club.needsApproval ? "club.detail.joinPolicy.review" : "club.detail.joinPolicy.open",
                                  systemImage: club.needsApproval ? "lock" : "checkmark")
                                .font(Theme.Font.label).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                // Viewer status only; the mini-program shows it through the join/quit controls.
                if club.isOwner || club.isJoined || club.joinPending || club.myJoinStatus == 2 || club.viewerIsAdmin {
                    Section {
                        if club.isOwner { Label("club.role.creator", systemImage: "person.crop.circle.badge.checkmark") }
                        else if club.isJoined { Label("club.membership.joined", systemImage: "checkmark.circle") }
                        else if club.joinPending { Label("club.membership.pending", systemImage: "clock") }
                        else if club.myJoinStatus == 2 { Label("club.membership.rejected", systemImage: "xmark.circle") }
                        if club.viewerIsAdmin { Label("club.viewerAdministrator", systemImage: "person.badge.shield.checkmark") }
                    }
                }
                if let actionCoordinator {
                    ClubActionPanel(club: club, identity: reader.clubIdentity, coordinator: actionCoordinator,
                                    onReadbackStarted: { detailGeneration &+= 1; return detailGeneration }) { detail, identity, generation in
                        guard identity == reader.clubIdentity, detail.id == id, generation == detailGeneration else { return }
                        actionDetail = detail; actionIdentity = identity
                    }
                }
                ClubDetailTabBar(tabs: tabs.tabs, selection: tab) { selectedTab = tabs.select($0, from: tab) }
                if tab == .posts, (club.isOwner || club.isJoined), reader.clubIdentity.isSignedIn, let session = reader as? AppSession {
                    Section {
                        NavigationLink { SessionClubChatView(clubID: id, session: session) } label: { Label("club.chat.title", systemImage: "person.3") }
                            .accessibilityIdentifier("club.chat.entry")
                        NativeChannelManagementClubEntry(club: club, session: session)
                    }
                }
                if tab == .manage, club.isOwner, let session = reader as? AppSession {
                    Section { NavigationLink("context.ai.title") { SessionClubAIDesignView(session: session, clubID: id) }.accessibilityIdentifier("club.context.openAI") }
                    Section { NavigationLink("club.projectLaunch.title") { SessionClubProjectLaunchView(session: session, club: club) }.accessibilityIdentifier("club.projectLaunch.entry") }
                }
                if tab == .manage, let session = reader as? AppSession {
                    // Keep the scope binder mounted for non-owners so owner loss fences old callbacks immediately;
                    // leaving the manage tab unmounts it with the rest of the tab.
                    SessionClubMerchantProfileHost(session: session) {
                        ClubMerchantDiscoveryView(club: club, clubReader: reader, reader: session.cooperationFlowReader)
                    }
                    if let governance = management?.governance {
                        ClubInvitationFeedbackEntry(club: club, clubReader: reader, reader: session.cooperationFlowReader, access: governance.access)
                        ClubLeadProgressEntry(club: club, clubReader: reader, reader: session.cooperationFlowReader, access: governance.access, projects: session.creatorContentReader, destinations: session.clubLeadPrimaryDestinations(club: club, governance: governance))
                    }
                }
                if tab == .posts, community == nil {
                    Section {
                        ContentUnavailableView("club.detail.posts.unavailable", systemImage: "text.bubble")
                            .accessibilityIdentifier("club.detail.posts.unavailable")
                    }
                }
                if tab == .posts, let community {
                    Section {
                        ClubCommunityEntry(clubID: id, identity: reader.clubIdentity, context: community)
                            .environment(\.clubEnrollmentProfile, management?.governance?.enrollmentProfile)
                            .environment(\.clubCustomerTopics, management?.governance?.customerTopics ?? .init())
                            .environment(\.clubPostPlayHost, ClubPostPlayHost.session(reader as? AppSession))
                    }
                }
                // Public topics use their own optional viewer grant, never access/me.
                if tab == .events, let session = reader as? AppSession {
                    Section {
                        NavigationLink {
                            SessionClubPublicActivityListView(clubID: id, session: session, onSignIn: onSignIn)
                        } label: {
                            Label { Text("publicTopics.title", tableName: "ClubPublicTopics") }
                                  icon: { Image(systemName: "list.bullet.rectangle") }
                        }
                        .accessibilityIdentifier("club.publicTopics.open")
                    }
                }
                // V2 governance has its own access/me model, including delegated event staff.
                if tab == .events, management?.governance == nil {
                    Section {
                        ContentUnavailableView("club.detail.events.unavailable", systemImage: "calendar")
                            .accessibilityIdentifier("club.detail.events.unavailable")
                    }
                }
                if tab == .events, let governance = management?.governance {
                    ClubDetailEventsSection(club: club, identity: reader.clubIdentity, governance: governance, reader: reader)
                    Section {
                        ClubSessionQuickStartEntry(club: club, reader: reader, governance: governance)
                    }
                }
                // Members without a manage tab still reach their own governance cases from the overview.
                if tab == .manage || (tab == .overview && !tabs.canUseManageTab), let governance = management?.governance {
                    Section {
                        if club.isOwner {
                            NavigationLink {
                                ClubStatsOverviewView(clubID: id, identity: reader.clubIdentity, governance: governance)
                            } label: { Label("club.statsOverview.title", systemImage: "chart.bar") }
                                .accessibilityIdentifier("club.statsOverview.open")
                        }
                        ClubGovernanceEntryButton(clubID: id, identity: reader.clubIdentity, access: governance.access, coordinator: governance.coordinator, enrollmentProfile: governance.enrollmentProfile, ownerRefund: governance.ownerRefund, opsTimeFactory: governance.opsTimeFactory, customerTopics: governance.customerTopics, storyTemplates: governance.storyTemplates, terminalSessions: governance.terminalSessions, ownerFunds: governance.ownerFunds)
                    }
                }
                if (club.isOwner || club.viewerIsAdmin), tab == .manage, let management {
                    Section {
                        if let operations = management.operations {
                            ClubOperationsEntryButton(target: .club(id), identity: reader.clubIdentity, access: operations.access, coordinator: operations.coordinator, onConfirmedReturn: { result in
                                guard result.identity == reader.clubIdentity, result.clubID == id else { return }
                                detailGeneration &+= 1; actionDetail = nil; actionIdentity = nil; manageGrant = nil
                                managementRevision &+= 1
                            }, onWelcomeConfirmedReturn: { result in
                                guard result.matches(target: .club(id), identity: reader.clubIdentity, access: operations.access) else { return }
                                // The saved text is historical evidence, not a current-detail substitute.
                                detailGeneration &+= 1; actionDetail = nil; actionIdentity = nil; manageGrant = nil
                                managementRevision &+= 1
                            })
                        }
                        NavigationLink {
                            ClubManagementView(clubID:id,identity:reader.clubIdentity,access:management.access,coordinator:management.coordinator, viewerRevision:management.viewerRevision, onMembershipChanged: {
                                // Do not reload a hidden NavigationLink source while its
                                // management destination is still showing the receipt.
                                managementNeedsRefresh = true
                            })
                        } label: { Label("club.management.title",systemImage:"person.2.badge.gearshape") }
                        .accessibilityIdentifier("club.openManagement")
                    }
                }
                if tab == .overview {
                    if let host = badgeHost(id) { ClubBadgeManagementEntry(host: host).id(host.id) }
                    // Mini-program overview: introduction, then the 主理人 / 俱乐部类型 / 所在城市 facts.
                    Section("club.introduction") {
                        if let description = club.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(verbatim: description).textSelection(.enabled)
                        } else { Text("club.noIntroduction").foregroundStyle(.secondary) }
                    }
                    Section {
                        LabeledContent("club.leader") { Text(verbatim: Self.dash(club.leaderName)) }
                        LabeledContent("club.type") { Text(verbatim: Self.dash(club.clubType ?? club.clubTypes)) }
                        LabeledContent("club.detail.cityFact") { Text(verbatim: Self.dash(club.city ?? club.address)) }
                        ClubOptionalRow(title: "club.preferences", value: club.activityPrefs.isEmpty ? nil : club.activityPrefs.joined(separator: ", "))
                        ClubOptionalRow(title: "club.keywords", value: club.keywords)
                        ClubOptionalRow(title: "club.style", value: club.style)
                    }
                    Section {
                        if club.canSeeMembers {
                            NavigationLink {
                                ClubMembersView(id: club.id, reader: reader, profile: management?.governance?.enrollmentProfile, governance: management?.governance, onSignIn: onSignIn)
                            } label: { Label("club.viewMembers", systemImage: "person.3") }
                                .accessibilityIdentifier("club.openMembers")
                        } else if publicRoster?.authorization?.identity == reader.clubIdentity,
                                  ClubPublicRosterEligibility.mayRequest(club, identity: reader.clubIdentity) {
                            NavigationLink {
                                ClubPublicRosterView(clubID: club.id, reader: reader, source: publicRoster,
                                    profile: nil, viewerRevision: managementRevision, leaderboard: false)
                            } label: { Label("club.viewMembers", systemImage: "person.3") }
                        } else {
                            Text(club.needsApproval ? "club.detail.members.lockedReview" : "club.detail.members.locked")
                                .foregroundStyle(.secondary).accessibilityIdentifier("club.members.gated")
                        }
                    } header: { Text("club.detail.membersCount \(club.memberCount)") }
                    // Mini-program overview: 本团贡献榜 · 本周, gated on member visibility like the source.
                    Section("club.detail.leaderboard.title") {
                        if club.canSeeMembers, let governance = management?.governance {
                            NavigationLink {
                                ClubGovernanceReadView(operation: .leaderboard, scope: .init(clubID: id), identity: reader.clubIdentity, access: governance.access, coordinator: governance.coordinator)
                                    .environment(\.clubEnrollmentProfile, governance.enrollmentProfile)
                            } label: { Label("club.detail.leaderboard.open", systemImage: "trophy") }
                                .accessibilityIdentifier("club.detail.leaderboard.open")
                        } else if club.canSeeMembers {
                            Text("club.detail.leaderboard.unavailable").foregroundStyle(.secondary).accessibilityIdentifier("club.detail.leaderboard.unavailable")
                        } else if publicRoster?.authorization?.identity == reader.clubIdentity,
                                  ClubPublicRosterEligibility.mayRequest(club, identity: reader.clubIdentity) {
                            NavigationLink {
                                ClubPublicRosterView(clubID: club.id, reader: reader, source: publicRoster,
                                    profile: nil, viewerRevision: managementRevision, leaderboard: true)
                            } label: { Label("club.detail.leaderboard.open", systemImage: "trophy") }
                        } else {
                            Text("club.detail.leaderboard.locked").foregroundStyle(.secondary).accessibilityIdentifier("club.detail.leaderboard.locked")
                        }
                    }
                }
            }
            .background {
                if let session = reader as? AppSession, let context = session.currentRuntimeDependencyContext,
                   reader.clubIdentity == ClubReadIdentity(accountID: context.session.accountID, epoch: context.session.epoch) {
                    ClubMemberWelcomeHost(club: club, identity: reader.clubIdentity,
                        namespace: context.baseURL.absoluteString + "|" + context.session.namespace,
                        role: context.role, active: !managementNeedsRefresh,
                        goEvents: { selectedTab = .events })
                }
            }
            .task(id: ClubDetailManageGrantKey(clubID: id, identity: reader.clubIdentity, hasGovernance: management?.governance != nil)) {
                await loadManageGrant()
            }
        }.safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.s2) {
                if let session = reader as? AppSession {
                    // Same-account history remains reachable after owner loss or failed detail reads.
                    ClubWelcomeNoteRecoveryEntry(clubID: id, identity: reader.clubIdentity,
                        access: session.clubOperationsAccess)
                }
            if let actionCoordinator, reader.clubIdentity.isSignedIn {
                // Outside the loaded-detail closure: failed current reads do not
                // hide an account-owned original request or open a private subtree.
                ClubActionOriginalRecoveryView(clubID: id, identity: reader.clubIdentity, coordinator: actionCoordinator)
                    .id(reader.clubIdentity)
            }
            }
        }.appNavigationTitle("club.detail")
            .id(id)
            .onAppear {
                guard managementNeedsRefresh else { return }
                managementNeedsRefresh = false
                detailGeneration &+= 1
                actionDetail = nil; actionIdentity = nil
                managementRevision &+= 1
            }
            .onChange(of: reader.clubIdentity) { _, _ in actionDetail = nil; actionIdentity = nil; manageGrant = nil; selectedTab = nil }
    }

    private static func dash(_ value: String?) -> String {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "—" : text
    }
    private func headerMeta(_ club: ClubRecord) -> String {
        let type = (club.clubType ?? club.clubTypes)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = ClubMemberCountLocalization.text(club.memberCount, locale: locale)
        guard let type, !type.isEmpty else { return count }
        return type + " · " + count
    }

    /// `/api/club/access/me` only widens the manage tab; a failed or foreign read revokes
    /// to the legacy owner/admin flags, as `revokeClubAccess` does in the mini-program.
    private func loadManageGrant() async {
        manageGrant = nil
        guard let governance = management?.governance, reader.clubIdentity.isSignedIn else { return }
        let identity = reader.clubIdentity
        let grant: ClubDetailManageGrant?
        do {
            let snapshot = try await governance.access.read(.access, scope: .init(clubID: id), options: [:])
            grant = snapshot.permissions.map { ClubDetailManageGrant($0) }
        } catch { grant = nil }
        guard !Task.isCancelled, identity == reader.clubIdentity else { return }
        manageGrant = grant?.clubID == id ? grant : nil
    }
}

private struct ClubDetailManageGrantKey: Hashable {
    let clubID: Int
    let identity: ClubReadIdentity
    let hasGovernance: Bool
}

/// Club cover hero: the real cover when there is one, a clean text-free placeholder otherwise.
private struct ClubDetailCover: View {
    let source: String?
    @QuestifyReduceMotion private var reduceMotion
    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "person.3").font(.largeTitle).foregroundStyle(.tertiary)
            if let url = QuestifyCardArtwork.safeURL(source) {
                AsyncImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : QuestifyMotion.content)) { phase in
                    if let image = phase.image { image.resizable().scaledToFill().transition(.opacity) }
                }
            }
        }
        .frame(maxWidth: .infinity).frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityHidden(true)
    }
}

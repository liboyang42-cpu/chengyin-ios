import SwiftUI

@MainActor
struct ClubDetailView<Reader: ClubReading & ObservableObject>: View {
    let id: Int
    @ObservedObject var reader: Reader
    var onSignIn: (() -> Void)? = nil
    var actionCoordinator: ClubActionCoordinator? = nil
    var management:ClubManagementContext? = nil
    var community: ClubCommunityContext? = nil
    /// Deep-link intent (`tab=manage`); honored only after the detail read confirms access.
    var requestedTab: ClubDetailTab? = nil
    @State private var selectedTab: ClubDetailTab? = nil
    @State private var manageGrant: ClubDetailManageGrant? = nil
    @State private var actionDetail: ClubRecord? = nil
    @State private var actionIdentity: ClubReadIdentity? = nil
    @State private var managementNeedsRefresh = false
    @State private var managementRevision: UInt64 = 0
    @State private var detailGeneration: UInt64 = 0
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
                Section {
                    ClubName(value: club.name).font(.title2.bold()).accessibilityIdentifier("club.detail.name")
                    ClubOptionalRow(title: "club.style", value: club.style)
                    LabeledContent("club.members") { Text(club.memberCount, format: .number) }
                    if club.isOwner { Label("club.role.creator", systemImage: "person.crop.circle.badge.checkmark") }
                    else if club.isJoined { Label("club.membership.joined", systemImage: "checkmark.circle") }
                    else if club.joinPending { Label("club.membership.pending", systemImage: "clock") }
                    else if club.myJoinStatus == 2 { Text("club.membership.rejected") }
                    if club.viewerIsAdmin { Text("club.viewerAdministrator") }
                    if (1...5).contains(club.level) { LabeledContent("club.level") { Text(verbatim: "L\(club.level)") } }
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
                    Section { Text("club.detail.posts.unavailable").foregroundStyle(.secondary).accessibilityIdentifier("club.detail.posts.unavailable") }
                }
                if tab == .posts, let community {
                    Section {
                        ClubCommunityEntry(clubID: id, identity: reader.clubIdentity, context: community)
                            .environment(\.clubEnrollmentProfile, management?.governance?.enrollmentProfile)
                            .environment(\.clubCustomerTopics, management?.governance?.customerTopics ?? .init())
                            .environment(\.clubPostPlayHost, ClubPostPlayHost.session(reader as? AppSession))
                    }
                }
                // V2 governance has its own access/me model, including delegated event staff.
                if tab == .events, management?.governance == nil {
                    Section { Text("club.detail.events.unavailable").foregroundStyle(.secondary).accessibilityIdentifier("club.detail.events.unavailable") }
                }
                if tab == .events, let governance = management?.governance {
                    Section {
                        NavigationLink {
                            ClubEventCalendarView(clubID: id, identity: reader.clubIdentity, governance: governance, reportClub: club, reportReader: reader)
                        } label: { Label("club.calendar.title", systemImage: "calendar") }
                            .accessibilityIdentifier("club.calendar.open")
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
                            ClubOperationsEntryButton(target: .club(id), identity: reader.clubIdentity, access: operations.access, coordinator: operations.coordinator)
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
                    Section("club.introduction") {
                        if let description = club.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(verbatim: description).textSelection(.enabled)
                        } else { Text("club.noIntroduction").foregroundStyle(.secondary) }
                        ClubOptionalRow(title: "club.leader", value: club.leaderName)
                        ClubOptionalRow(title: "club.city", value: club.city)
                        ClubOptionalRow(title: "club.address", value: club.address)
                        ClubOptionalRow(title: "club.type", value: club.clubType ?? club.clubTypes)
                        ClubOptionalRow(title: "club.preferences", value: club.activityPrefs.isEmpty ? nil : club.activityPrefs.joined(separator: ", "))
                        ClubOptionalRow(title: "club.keywords", value: club.keywords)
                    }
                    Section("club.members") {
                        if club.canSeeMembers {
                            NavigationLink {
                                ClubMembersView(id: club.id, reader: reader, profile: management?.governance?.enrollmentProfile, governance: management?.governance, onSignIn: onSignIn)
                            } label: { Label("club.viewMembers", systemImage: "person.3") }
                                .accessibilityIdentifier("club.openMembers")
                        } else { Text("club.joinToSeeMembers").foregroundStyle(.secondary).accessibilityIdentifier("club.members.gated") }
                    }
                }
            }
            .task(id: ClubDetailManageGrantKey(clubID: id, identity: reader.clubIdentity, hasGovernance: management?.governance != nil)) {
                await loadManageGrant()
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

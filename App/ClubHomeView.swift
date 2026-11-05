import SwiftUI

/// Place inside the root's existing NavigationStack. This view never uses entry role as access.
@MainActor
struct ClubHomeView<Reader: ClubReading & ObservableObject>: View {
    @ObservedObject var reader: Reader
    var onSignIn: (() -> Void)? = nil
    var actionCoordinator: ClubActionCoordinator? = nil
    var management:ClubManagementContext? = nil
    var community: ClubCommunityContext? = nil
    /// Home events carry topic IDs. The session host supplies its existing gated destination.
    var topicDestination: ((Int) -> AnyView)? = nil
    /// Retained callback for hosts that own a value-based navigation path.
    var onTopicDestination: ((Int) -> Void)? = nil
    @State private var locality = MerchantClubDiscoveryState()
    private var discoveryScope: ClubDiscoveryScope { reader.clubDiscoveryScope }
    /// Source talent/list top tabs 帖文 / 俱乐部; it opens on 俱乐部 and loads the feed only when chosen.
    @State private var topTab = ClubTabPresentation.TopTab.club
    var body: some View {
        VStack(spacing: 0) {
        if community != nil {
            Picker("club.title", selection: $topTab) {
                ForEach(ClubTabPresentation.TopTab.allCases, id: \.self) { Text(LocalizedStringKey($0.key)).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
                .accessibilityIdentifier("clubTab.topTabs")
        }
        if topTab == .feed, let community {
            ClubCommunityFeedView(context: community, identity: reader.clubIdentity)
        } else {
        ClubReadScreen(reader: reader, accessibilityPrefix: "club.home", onSignIn: onSignIn,
                       load: { try await reader.clubHome() }) { home in
            List {
                // Mini-program club tab: 「创建你自己的俱乐部」 stays pinned above the list; merchants never see it.
                if !discoveryScope.isMerchantViewer, let operations = management?.operations {
                    Section {
                        HStack(spacing: Theme.Space.s3) {
                            Text("club.tab.createPrompt").font(Theme.Font.body)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Theme.Space.s2)
                            ClubOperationsEntryButton(target: .create, identity: reader.clubIdentity, access: operations.access, coordinator: operations.coordinator, hostApplication: management?.governance)
                                .buttonStyle(.questifyPrimary)
                                .fixedSize()
                        }
                    }
                }
                // Mini-program club tab is one list: created → joined → nearby (merchants: nearby only), no group headers.
                let nearby = locality.nearby(home.nearby, in: discoveryScope)
                if discoveryScope.isMerchantViewer {
                    localityStatus
                    merchantNearbySection(nearby)
                } else if ClubTabPresentation.isEmpty(home, nearby: nearby, merchant: false) {
                    Section { ClubTabEmptyState(merchant: false) }
                } else {
                    Section {
                        clubRows(home.owned, identifier: "club.home.owned", section: .owned)
                        clubRows(home.joined, identifier: "club.home.joined", section: .joined)
                        clubRows(nearby, identifier: "club.home.nearby", section: .nearby)
                    }
                }
                Section {
                    if let governance = management?.governance {
                        ClubGovernanceHomeEntries(feedContext: .init(viewerRevision: management?.viewerRevision ?? governance.viewerRevision,
                            readerIdentity: ObjectIdentifier(reader), destination: { id in
                                AnyView(ClubDetailView(id: id, reader: reader, onSignIn: onSignIn))
                            }), identity: reader.clubIdentity, access: governance.access, coordinator: governance.coordinator)
                    }
                    NavigationLink {
                        ClubDirectoryView(reader: reader, onSignIn: onSignIn, actionCoordinator: actionCoordinator, management:management, community:community)
                    } label: { Label("club.directory", systemImage: "magnifyingglass") }
                        .accessibilityIdentifier("club.openDirectory")
                    if !discoveryScope.isMerchantViewer {
                        NavigationLink {
                            ClubOwnedView(reader: reader, onSignIn: onSignIn, actionCoordinator: actionCoordinator, management:management, community:community)
                        } label: { Label("club.owned", systemImage: "person.crop.circle") }
                            .accessibilityIdentifier("club.openOwned")
                    }
                }
                Section("club.events") {
                    if home.events.isEmpty {
                        Text("club.emptyEvents").foregroundStyle(.secondary).accessibilityIdentifier("club.home.events.empty")
                    }
                    ForEach(Array(home.events.enumerated()), id: \.offset) { _, event in
                        if let topicDestination, event.id > 0 {
                            NavigationLink { topicDestination(event.id) } label: { eventRow(event) }
                                .accessibilityIdentifier("club.event.\(event.id)")
                        } else if let onTopicDestination {
                            Button { onTopicDestination(event.id) } label: { eventRow(event) }
                                .accessibilityIdentifier("club.event.\(event.id)")
                        } else { eventRow(event) }
                    }
                }
            }
        }
        }
        }
        .appNavigationTitle(community == nil ? "club.title" : "club.tab.title")
        .environment(\.clubEnrollmentProfile, management?.governance?.enrollmentProfile)
        .environment(\.clubCustomerTopics, management?.governance?.customerTopics ?? .init())
        .environment(\.clubPostPlayHost, ClubPostPlayHost.session(reader as? AppSession))
        .task(id: discoveryScope) {
            if locality.phase(in: discoveryScope) != .ready { await loadLocality() }
        }
        .onDisappear { locality.leaveScreen() }
    }
    /// Merchant-only status above the list. Ready state becomes the list's section header instead.
    @ViewBuilder private var localityStatus: some View {
        switch locality.phase(in: discoveryScope) {
        case .idle, .loading:
            Section {
                ProgressView("club.locality.loading").frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("club.home.locality.loading")
            }
        case .unavailable:
            Section {
                Label("club.locality.unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("club.home.locality.unavailable")
                Button("action.retry") { Task { await loadLocality() } }
                    .accessibilityIdentifier("club.home.locality.retry")
            }
        case .ready:
            EmptyView()
        }
    }
    private func merchantNearbySection(_ rows: [ClubRecord]) -> some View {
        Section {
            if rows.isEmpty {
                Text(locality.phase(in: discoveryScope) == .ready ? "club.tab.empty.merchant" : "club.emptyNearby")
                    .foregroundStyle(.secondary).accessibilityIdentifier("club.home.nearby.empty")
            }
            clubRows(rows, identifier: "club.home.nearby", section: .nearby)
        } header: {
            if locality.phase(in: discoveryScope) == .ready {
                Text("club.locality.ready").accessibilityIdentifier("club.home.locality.ready")
            }
        }
    }
    private func loadLocality() async {
        guard let request = locality.begin(in: discoveryScope) else { return }
        do {
            let result = try await reader.clubMerchantLocality()
            guard !Task.isCancelled else { return }
            locality.receive(result, for: request, current: discoveryScope)
        } catch {
            guard !Task.isCancelled else { return }
            locality.fail(request, current: discoveryScope)
        }
    }
    @ViewBuilder private func clubRows(_ rows: [ClubRecord], identifier: String,
                                       section: ClubTabPresentation.Section) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, club in
            NavigationLink {
                ClubDetailView(id: club.id, reader: reader, onSignIn: onSignIn, actionCoordinator: actionCoordinator, management:management, community:community)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    ClubRow(club: club)
                    ClubTabTagLine(club: club, section: section)
                }
            }
                .buttonStyle(QuestifyCardButtonStyle()).questifyCardListRow()
                .accessibilityIdentifier(identifier + ".\(club.id)")
        }
    }
    private func eventRow(_ event: ClubHomeEvent) -> some View {
        Label {
            if event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text("club.untitledEvent") }
            else { Text(verbatim: event.title) }
        } icon: { Image(systemName: "flag.checkered") }
        .foregroundStyle(.primary)
    }
}

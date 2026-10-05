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
    var body: some View {
        ClubReadScreen(reader: reader, accessibilityPrefix: "club.home", onSignIn: onSignIn,
                       load: { try await reader.clubHome() }) { home in
            List {
                Section {
                    if let community {
                        NavigationLink { ClubCommunityFeedView(context: community, identity: reader.clubIdentity) } label: { Label("club.community.feed", systemImage: "text.bubble") }
                    }
                    if let governance = management?.governance {
                        ClubGovernanceHomeEntries(feedContext: .init(viewerRevision: management?.viewerRevision ?? governance.viewerRevision,
                            readerIdentity: ObjectIdentifier(reader), destination: { id in
                                AnyView(ClubDetailView(id: id, reader: reader, onSignIn: onSignIn))
                            }), identity: reader.clubIdentity, access: governance.access, coordinator: governance.coordinator)
                    }
                    if !discoveryScope.isMerchantViewer, let operations = management?.operations {
                        ClubOperationsEntryButton(target: .create, identity: reader.clubIdentity, access: operations.access, coordinator: operations.coordinator)
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
                if !discoveryScope.isMerchantViewer {
                    clubSection("club.owned", rows: home.owned, empty: "club.emptyOwned", identifier: "club.home.owned")
                    clubSection("club.joined", rows: home.joined, empty: "club.emptyJoined", identifier: "club.home.joined")
                } else { localityStatus }
                clubSection("club.nearby", rows: locality.nearby(home.nearby, in: discoveryScope),
                            empty: discoveryScope.isMerchantViewer && locality.phase(in: discoveryScope) == .ready
                                ? "club.locality.empty" : "club.emptyNearby", identifier: "club.home.nearby")
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
        .appNavigationTitle("club.title")
        .task(id: discoveryScope) {
            if locality.phase(in: discoveryScope) != .ready { await loadLocality() }
        }
        .onDisappear { locality.leaveScreen() }
    }
    @ViewBuilder private var localityStatus: some View {
        Section {
            switch locality.phase(in: discoveryScope) {
            case .idle, .loading:
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView("club.locality.loading")
                    Text("club.locality.loadingHint").font(.footnote).foregroundStyle(.secondary)
                }.accessibilityIdentifier("club.home.locality.loading")
            case .unavailable:
                VStack(alignment: .leading, spacing: 6) {
                    Label("club.locality.unavailable", systemImage: "exclamationmark.triangle")
                    Text("club.locality.unavailableHint").font(.footnote).foregroundStyle(.secondary)
                    Button("action.retry") { Task { await loadLocality() } }
                        .accessibilityIdentifier("club.home.locality.retry")
                }.accessibilityIdentifier("club.home.locality.unavailable")
            case .ready:
                Text("club.locality.ready").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("club.home.locality.ready")
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
    private func clubSection(_ title: LocalizedStringKey, rows: [ClubRecord], empty: LocalizedStringKey,
                             identifier: String) -> some View {
        Section(title) {
            if rows.isEmpty { Text(empty).foregroundStyle(.secondary).accessibilityIdentifier(identifier + ".empty") }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, club in
                NavigationLink {
                    ClubDetailView(id: club.id, reader: reader, onSignIn: onSignIn, actionCoordinator: actionCoordinator, management:management, community:community)
                } label: { ClubRow(club: club) }
                    .buttonStyle(QuestifyCardButtonStyle()).questifyCardListRow()
                    .accessibilityIdentifier(identifier + ".\(club.id)")
            }
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

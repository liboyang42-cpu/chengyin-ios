import SwiftUI

/// Normal project destination. Navigation IDs select a read, never establish authority.
@MainActor struct SessionPublisherLifecycleView: View {
    @ObservedObject var session: AppSession
    let resource: PublishedResource
    @State private var authority: PublisherAuthority?
    @State private var selectedClub: Int?
    @State private var failed = false
    @State private var generation = 0
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            NavigationLink { SessionCreatorProjectsView(session: session) } label: { Text("creatorContent.projects") }
                .accessibilityIdentifier("projectRemote.myProjects")
            if resource.kind == .topic {
                NavigationLink("contextPublish.result.preview") { SessionTopicDetailView(id: resource.value, session: session) }
                    .accessibilityIdentifier("contextPublish.result.preview")
            }
            if let context = session.publisherLifecycleContext {
                if let authority, authority.resource == resource {
                    if resource.kind == .topic, !authority.eligibleClubIDs.isEmpty {
                        Picker("publisher.host.club", selection: $selectedClub) {
                            Text("publisher.host.chooseClub").tag(Int?.none)
                            ForEach(authority.eligibleClubIDs.sorted(), id: \.self) { id in Text(verbatim: "#\(id)").tag(Optional(id)) }
                        }
                    }
                    PublisherLifecycleProjectLinks(resource: resource, context: context,
                        isOwner: authority.ownerAccountID == session.publishingSession?.accountID,
                        beta: authority.beta, selectedEligibleClubID: selectedClub)
                    if resource.kind == .topic { PublisherXPBudgetSection(topicID: resource.value, client: context.client) }
                } else if failed { Text("publisher.host.unavailable") }
                else { ProgressView() }
            } else { Text("publisher.host.unavailable") }
            Text("publisher.host.dormant").font(.footnote)
        }
        .navigationTitle("publisher.host.title")
        .task(id: session.publishingSession) { await load() }
        .refreshable { await load() }
        .onChange(of: selectedClub) { _, _ in session.publisherLifecycleContext?.invalidate() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { clear() }
            else { Task { await load() } }
        }
        .onDisappear { clear() }
    }
    private func clear() { generation += 1; authority = nil; selectedClub = nil; session.publisherLifecycleContext?.invalidate() }
    private func load() async {
        clear(); failed = false; let stamp = generation
        guard let captured = session.publishingSession else { failed = true; return }
        do {
            let value = try await session.freshPublisherAuthority(resource, session: captured)
            guard !Task.isCancelled, generation == stamp, session.publishingSession == captured else { return }
            authority = value
        } catch { guard generation == stamp else { return }; failed = true }
    }
}
@MainActor struct PublisherLifecycleNavigationLink: View {
    @ObservedObject var session: AppSession
    let resource: PublishedResource
    var body: some View {
        NavigationLink("publisher.host.title") { SessionPublisherLifecycleView(session: session, resource: resource).id(session.publishingSession?.epoch) }
    }
}

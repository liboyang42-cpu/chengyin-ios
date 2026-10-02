import SwiftUI

/// Real creator entry. Every destination is recreated at the account/role epoch boundary.
@MainActor struct SessionPublishingModesView: View {
    @EnvironmentObject private var session: AppSession
    @State private var seed: ProjectEditDraft?
    @State private var showEditor = false
    @State private var resource: PublishedResource?
    var body: some View {
        PublishingModesView(service: session.publishingService, account: session.publishingSession,
                            placeSearch: PublishingMapKitAdapter(), draftStore: session.publishingDraftStore, openProfessional: { seed = $0; showEditor = true },
                            openResource: { resource = $0 })
            .navigationDestination(isPresented: $showEditor) {
                if let seed {
                    ProjectEditView(coordinator: session.projectEditor(product: seed.product), sessionRevision: session.sessionRevision, seed: seed, publisherClient: session.publisherLifecycleContext?.client)
                        .id(session.publishingSession?.epoch)
                }
            }
            .navigationDestination(item: $resource) { destination in
                switch destination.kind {
                case .topic: SessionTopicDetailView(id: destination.value, session: session).id(session.topicReader.scope)
                case .activity: ActivityDetailView(id: destination.value, reader: session)
                    .toolbar { PublisherLifecycleNavigationLink(session: session, resource: destination) }
                case .template: DiscoveryTemplateDetailView(id: destination.value, reader: session,
                    authoringFactory: { session.templateAuthoringEditor(adopting: $0) }, authoringRevision: session.sessionRevision).id(session.templateAuthoringViewIdentity)
                }
            }
            .onChange(of: session.publishingSession) { _, _ in
                session.publishingService?.invalidateReviews(); seed = nil; showEditor = false; resource = nil
            }
    }
}

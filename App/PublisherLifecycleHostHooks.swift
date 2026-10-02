import SwiftUI

/// Composition seam for the existing publishing host. It never creates a live grant.
/// Keep one instance per account/region/role epoch and recreate at every session change.
@MainActor final class PublisherLifecycleHostContext {
    let client: PublisherLifecycleHTTP
    let coordinator: PublisherLifecycleCoordinator
    let application: CreatorApplicationCoordinator
    let creatorReader: any CreatorContentReading
    init(configuration: APIConfiguration, transport: any HTTPTransport,
         creatorReader: any CreatorContentReading, credentials: @escaping () -> PublishingCredentials?,
         freshAuthority: @escaping (PublishedResource, PublishingSession) async throws -> PublisherAuthority) {
        let client = PublisherLifecycleHTTP(configuration: configuration, transport: transport, grants: .dormant, credentials: credentials)
        self.client = client; self.creatorReader = creatorReader
        coordinator = PublisherLifecycleCoordinator(client: client, authority: freshAuthority)
        application = CreatorApplicationCoordinator(client: client, reader: creatorReader)
    }
    func invalidate() { coordinator.invalidate(); application.invalidate() }
}
/// Insert inside existing project detail/management List; never replaces generic editing.
@MainActor struct PublisherLifecycleProjectLinks: View {
    let resource: PublishedResource
    let context: PublisherLifecycleHostContext
    /// These are fresh host projections, not authorization. Coordinator rechecks on review.
    let isOwner: Bool
    let beta: Bool
    /// The existing club picker returns an eligible club ID; no freeform identity field.
    let selectedEligibleClubID: Int?
    @Environment(\.locale) private var locale
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        if isOwner {
            if resource.kind == .topic {
                NavigationLink(zh ? "定价与合作条款" : "Pricing and partner terms") { PublisherPricingView(topicID: resource.value, client: context.client, coordinator: context.coordinator) }
                if beta { NavigationLink(zh ? "Beta 转正" : "Graduate Beta") { PublisherOwnershipReviewView(action: .graduate(topicID: resource.value), coordinator: context.coordinator) } }
                if let clubID = selectedEligibleClubID {
                    NavigationLink(zh ? "移交俱乐部承接" : "Transfer to selected club") { PublisherOwnershipReviewView(action: .transfer(topicID: resource.value, clubID: clubID), coordinator: context.coordinator) }
                }
            }
            if resource.kind == .topic || resource.kind == .activity {
                NavigationLink(zh ? "取消并退款" : "Cancel and refund") { PublisherCancellationView(resource: resource, coordinator: context.coordinator) }
            }
        }
    }
}
/// Append to CreatorContentCenterView only for notApplied/rejected status. Existing
/// status/metrics stay in the original reader and receive its normal refresh callback.
@MainActor struct CreatorApplicationHostLink: View {
    let context: PublisherLifecycleHostContext
    let status: CreatorContentApplyStatus
    let refreshCenter: () -> Void
    @Environment(\.locale) private var locale
    var body: some View {
        if status == .notApplied || status == .rejected {
            NavigationLink(locale.language.languageCode?.identifier == "zh" ? "创作者申请" : "Creator application") {
                CreatorApplicationView(coordinator: context.application, reader: context.creatorReader, onCenterRefresh: refreshCenter)
                    .id(context.creatorReader.scope)
            }
        }
    }
}

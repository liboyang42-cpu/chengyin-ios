import Foundation

/// A single view-owned read. Unauthorized expiration is deferred until its loader
/// accepts the completion; callers never receive credentials or transport access.
@MainActor
struct DiscoveryReadRequest<Value> {
    let read: @MainActor () async throws -> Value
    let onUnauthorized: @MainActor () -> Void
}

/// The root session supplies configuration and captures its current verified credential per request.
/// Views receive only this read dependency, never a token, transport or default host.
@MainActor
protocol DiscoveryReading: AnyObject {
    var isConfigured: Bool { get }
    func discoveryBanners() async throws -> [DiscoveryBanner]
    func discoveryCategories(type: Int?) async throws -> [DiscoveryCategory]
    func discoveryTemplateHome() async throws -> DiscoveryTemplateHome
    func discoveryPlayTemplates(keyword: String, packType: DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate]
    func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate]
    func publicTopicTemplateCatalogRequest() -> DiscoveryReadRequest<[DiscoveryTopicTemplate]>
    func discoveryTopicTemplateDetail(id: Int) async throws -> PublicTopicTemplateDetail
    func publicTopicTemplateCoordinator(id: Int) -> PublicTopicTemplateCoordinator
    func discoveryPlayTemplate(id: Int) async throws -> DiscoveryPlayTemplate
}

extension DiscoveryReading {
    func publicTopicTemplateCatalogRequest() -> DiscoveryReadRequest<[DiscoveryTopicTemplate]> {
        DiscoveryReadRequest(read: { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.discoveryTopicTemplates()
        }, onUnauthorized: {})
    }
    func publicTopicTemplateCoordinator(id: Int) -> PublicTopicTemplateCoordinator {
        PublicTopicTemplateCoordinator(id: id) { [weak self] id in
            guard let self else { throw CancellationError() }
            return try await self.discoveryTopicTemplateDetail(id: id)
        }
    }
}

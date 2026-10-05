import Foundation
import Combine

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
    var discoveryPresentationIdentity: String { get }
    var discoveryPresentationChanges: AnyPublisher<Void, Never> { get }
    func discoveryBanners() async throws -> [DiscoveryBanner]
    func discoveryCategories(type: Int?) async throws -> [DiscoveryCategory]
    func templateMetadataDictionary(kind: TemplateMetadataKind) async throws -> [TemplateMetadataOption]
    func templateMetadataDictionaryRequest(kind: TemplateMetadataKind) -> DiscoveryReadRequest<[TemplateMetadataOption]>
    func templateMetadataCategoriesRequest() -> DiscoveryReadRequest<[DiscoveryCategory]>
    func discoveryTemplateHome() async throws -> DiscoveryTemplateHome
    func discoveryPlayTemplates(keyword: String, packType: DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate]
    func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate]
    func publicTopicTemplateCatalogRequest() -> DiscoveryReadRequest<[DiscoveryTopicTemplate]>
    func discoveryTopicTemplateDetail(id: Int) async throws -> PublicTopicTemplateDetail
    func publicTopicTemplateCoordinator(id: Int) -> PublicTopicTemplateCoordinator
    func discoveryPlayTemplate(id: Int) async throws -> DiscoveryPlayTemplate
}

extension DiscoveryReading {
    func templateMetadataDictionary(kind: TemplateMetadataKind) async throws -> [TemplateMetadataOption] {
        throw APIError.notConfigured
    }
    func templateMetadataDictionaryRequest(kind: TemplateMetadataKind) -> DiscoveryReadRequest<[TemplateMetadataOption]> {
        DiscoveryReadRequest(read: { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.templateMetadataDictionary(kind: kind)
        }, onUnauthorized: {})
    }
    func templateMetadataCategoriesRequest() -> DiscoveryReadRequest<[DiscoveryCategory]> {
        DiscoveryReadRequest(read: { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.discoveryCategories(type: 4)
        }, onUnauthorized: {})
    }
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

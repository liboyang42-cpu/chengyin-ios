import Foundation

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
    func discoveryPlayTemplate(id: Int) async throws -> DiscoveryPlayTemplate
}

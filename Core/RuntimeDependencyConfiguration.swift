import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Deployment approval, session authority and OS/user consent are separate inputs.
/// This value is never loaded from user defaults, a URL, or an API response.
public struct RuntimeDependencyConfiguration {
    public let market: RegionalMarket
    public let endpoints: OperationEndpointApproval
    public let play: Set<PlayExperienceCapability>
    public let journeyReads: Bool
    public let journeyChecks: Bool
    public let journeyAsks: Bool
    public let journeyCollect: Bool
    public let publisherReads: Bool
    public let nearbyLocation: Bool
    public let devices: Set<PlayDeviceKind>
    public let sensors: Set<PlayKitSensorKind>
    public let artworkHosts: Set<String>
    public let spatial: PlayKitSpatialApproval
    public let shopNPCWrites: Bool
    public init(market: RegionalMarket, endpoints: OperationEndpointApproval,
                play: Set<PlayExperienceCapability> = [], journeyReads: Bool = false,
                journeyChecks: Bool = false, journeyCollect: Bool = false, journeyAsks: Bool = false,
                publisherReads: Bool = false, nearbyLocation: Bool = false,
                devices: Set<PlayDeviceKind> = [], sensors: Set<PlayKitSensorKind> = [],
                artworkHosts: Set<String> = [], spatial: PlayKitSpatialApproval = .init(), shopNPCWrites: Bool = false) {
        self.market = market; self.endpoints = endpoints; self.play = play
        self.journeyAsks = journeyAsks
        self.journeyReads = journeyReads; self.journeyChecks = journeyChecks; self.journeyCollect = journeyCollect
        self.publisherReads = publisherReads; self.nearbyLocation = nearbyLocation
        self.devices = devices; self.sensors = sensors; self.artworkHosts = artworkHosts; self.spatial = spatial
        self.shopNPCWrites = shopNPCWrites
    }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        // These are audited CN contracts; US enablement requires its own contract acceptance.
        market == .china && context.market == market && endpoints.baseURL == context.baseURL &&
        endpoints.namespace == context.session.namespace && endpoints.accountID == context.session.accountID
    }
}

public struct RuntimeDependencyContext: Equatable {
    public let market: RegionalMarket
    public let baseURL: URL
    public let role: String
    public let session: PlayExperienceSession
    public init(market: RegionalMarket, baseURL: URL, role: String, session: PlayExperienceSession) {
        self.market = market; self.baseURL = baseURL; self.role = role; self.session = session
    }
}

/// Checks before dispatch and after completion. Account/role/epoch/token/realm changes
/// invalidate the captured service, including requests retained by a pushed screen.
@MainActor public final class RuntimeDependencyTransport: HTTPTransport {
    private let configuration: RuntimeDependencyConfiguration?
    private let captured: RuntimeDependencyContext?
    private let current: () -> RuntimeDependencyContext?
    private let transport: any HTTPTransport
    public init(configuration: RuntimeDependencyConfiguration?, captured: RuntimeDependencyContext?,
                transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?) {
        self.configuration = configuration; self.captured = captured; self.transport = transport; self.current = current
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard let configuration, let captured, configuration.matches(captured), current() == captured,
              request.value(forHTTPHeaderField: "Authorization") == captured.session.token,
              let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.fragment == nil else { throw PlayExperienceError.disabled }
        components.query = nil
        guard configuration.endpoints.paths.contains(where: {
            captured.baseURL.appendingPathComponent($0) == components.url
        }) else { throw PlayExperienceError.disabled }
        let result = try await transport.send(request)
        try Task.checkCancellation()
        guard current() == captured else { throw PlayExperienceError.staleSession }
        return result
    }
}

/// A real transport may be injected only after the existing regional/account gates.
/// Tests inject a recorder; the shipped AppSession supplies no configuration.
@MainActor public struct RuntimeDependencyFactory {
    public let accepted: RuntimeDependencyConfiguration?
    public let transport: RuntimeDependencyTransport
    private let api: APIConfiguration
    public init(api: APIConfiguration, configuration: RuntimeDependencyConfiguration? = nil,
                transport: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?) {
        self.api = api
        let captured = current()
        accepted = captured.flatMap { configuration?.matches($0) == true && $0.baseURL == api.baseURL ? configuration : nil }
        self.transport = RuntimeDependencyTransport(configuration: accepted, captured: captured, transport: transport, current: current)
    }
    public func playService() -> PlayExperienceService {
        PlayExperienceService(configuration: api, transport: transport, enabled: accepted?.play ?? [])
    }
    public func journeyService() -> JourneyContentService {
        JourneyContentService(configuration: api, transport: transport,
            readsEnabled: accepted?.journeyReads == true, checksEnabled: accepted?.journeyChecks == true,
            collectEnabled: accepted?.journeyCollect == true)
    }
    public func journeyNarrativeService() -> JourneyNarrativeService {
        .init(configuration: api, transport: transport,
              readsEnabled: accepted?.journeyReads == true, asksEnabled: accepted?.journeyAsks == true)
    }
    public var publisherGrants: PublisherLifecycleGrants {
        // Pricing mutations, refunds, ownership and applications remain independently off.
        PublisherLifecycleGrants(reads: accepted?.publisherReads == true ? accepted?.endpoints : nil)
    }
    public var allowsNearbyLocation: Bool {
        accepted?.nearbyLocation == true && accepted?.endpoints.paths.contains("api/merchant/nearby") == true
    }
}

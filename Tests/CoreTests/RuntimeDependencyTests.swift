import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class RuntimeDependencyTests: XCTestCase {
    private let url = URL(string: "https://example.com/runtime/")!
    private func context(account: Int = 7, epoch: UInt64 = 1, namespace: String = "fixture-cn", token: String = "synthetic", market: RegionalMarket = .china, role: String = "member") throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: url, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    private func approval(paths: Set<String> = ["api/play/nodes"], play: Set<PlayExperienceCapability> = [.reads], publisher: Bool = false, nearby: Bool = false) throws -> RuntimeDependencyConfiguration {
        .init(market: .china, endpoints: try .init(baseURL: url, namespace: "fixture-cn", accountID: 7, paths: paths),
              play: play, publisherReads: publisher, nearbyLocation: nearby)
    }
    private func request(_ path: String = "api/play/nodes", token: String = "synthetic") -> URLRequest {
        var request = URLRequest(url: url.appendingPathComponent(path)); request.setValue(token, forHTTPHeaderField: "Authorization"); return request
    }
    func testDefaultCompositionHasNoNetworkOrProviderCapabilities() async throws {
        let context = try context(), recorder = RuntimeTestTransport()
        let factory = RuntimeDependencyFactory(api: try .init(baseURL: url), transport: recorder, current: { context })
        XCTAssertTrue(factory.playService().enabled.isEmpty); XCTAssertNil(factory.publisherGrants.reads)
        XCTAssertFalse(factory.journeyService().readsEnabled); XCTAssertFalse(factory.allowsNearbyLocation)
        do { _ = try await factory.playService().nodes(scope: .topic(4), token: "synthetic"); XCTFail() } catch {}
        XCTAssertEqual(recorder.requests.count, 0)
    }
    func testApprovedReadUsesActualNodesContractAndOnlyInjectedTransport() async throws {
        let context = try context(), recorder = RuntimeTestTransport()
        recorder.response = PlayExperienceSyntheticFixtures.envelope(#"{"topicId":4,"nodes":[]}"#)
        let factory = RuntimeDependencyFactory(api: try .init(baseURL: url), configuration: try approval(), transport: recorder, current: { context })
        _ = try await factory.playService().nodes(scope: .topic(4), token: "synthetic")
        let sent = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(sent.httpMethod, "GET"); XCTAssertEqual(sent.url?.path, "/runtime/api/play/nodes")
        XCTAssertEqual(URLComponents(url: sent.url!, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "topicId", value: "4")])
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "synthetic"); XCTAssertEqual(recorder.requests.count, 1)
    }
    func testWrongAccountNamespaceMarketOriginAndMissingSessionAreOff() throws {
        let accepted = try approval(), recorder = RuntimeTestTransport()
        for current in [try context(account: 8), try context(namespace: "other"), try context(market: .unitedStates), nil] {
            let factory = RuntimeDependencyFactory(api: try .init(baseURL: url), configuration: accepted, transport: recorder, current: { current })
            XCTAssertNil(factory.accepted); XCTAssertTrue(factory.playService().enabled.isEmpty)
        }
        let current = try context()
        let factory = RuntimeDependencyFactory(api: try .init(baseURL: URL(string: "https://example.com/other/")!), configuration: accepted, transport: recorder, current: { current })
        XCTAssertNil(factory.accepted)
    }
    func testExactPathAndTokenFenceBeforeDispatch() async throws {
        let current = try context(), recorder = RuntimeTestTransport()
        let factory = RuntimeDependencyFactory(api: try .init(baseURL: url), configuration: try approval(), transport: recorder, current: { current })
        for input in [request("api/play/answer"), request(token: "wrong")] {
            do { _ = try await factory.transport.send(input); XCTFail() } catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }
    func testEpochRoleTokenAndLogoutInvalidateCapturedFactory() async throws {
        let recorder = RuntimeTestTransport()
        let initial = try context()
        for replacement in [try context(epoch: 2), try context(role: "creator"), try context(token: "rotated"), nil] {
            var current: RuntimeDependencyContext? = initial
            let factory = RuntimeDependencyFactory(api: try .init(baseURL: url), configuration: try approval(), transport: recorder, current: { current })
            current = replacement
            do { _ = try await factory.transport.send(request()); XCTFail() } catch {}
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }
    func testLateResponseAfterSessionChangeCannotProject() async throws {
        var current: RuntimeDependencyContext? = try context()
        let recorder = RuntimeTestTransport(); recorder.beforeReply = { current = nil }
        let factory = RuntimeDependencyFactory(api: try .init(baseURL: url), configuration: try approval(), transport: recorder, current: { current })
        do { _ = try await factory.transport.send(request()); XCTFail() } catch { XCTAssertEqual(error as? PlayExperienceError, .staleSession) }
        XCTAssertEqual(recorder.requests.count, 1)
    }
    func testPublisherReadGrantDoesNotGrantPricingRefundOrOwnershipWrites() async throws {
        let current = try context(), recorder = RuntimeTestTransport()
        recorder.response = Data(#"{"code":200,"data":{"priceMin":12,"lineup":[]}}"#.utf8)
        let factory = RuntimeDependencyFactory(api: try .init(baseURL: url), configuration: try approval(paths: ["api/topic/pricing/preview"], play: [], publisher: true), transport: recorder, current: { current })
        let grants = factory.publisherGrants
        XCTAssertNotNil(grants.reads); XCTAssertNil(grants.pricing); XCTAssertNil(grants.cancellationRefunds)
        XCTAssertNil(grants.ownership); XCTAssertNil(grants.graduation); XCTAssertNil(grants.creatorApplication)
        let credentials = try PublishingCredentials(session: .init(namespace: "fixture-cn", accountID: 7, epoch: UUID(), role: "member", region: .china), token: "synthetic")
        let client = PublisherLifecycleHTTP(configuration: try .init(baseURL: url), transport: factory.transport, grants: grants, credentials: { credentials })
        let preview = try await client.pricing(.init(topicID: 4, subtype: .selfPlay))
        XCTAssertEqual(preview.minimum, 12); XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests[0].url?.path, "/runtime/api/topic/pricing/preview")
        XCTAssertEqual(recorder.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    func testNearbyRequiresItsExactPathAndSeparateLocationAcceptance() throws {
        let current = try context(), recorder = RuntimeTestTransport()
        for accepted in [try approval(), try approval(nearby: true), try approval(paths: ["api/merchant/nearby"])] {
            let factory = RuntimeDependencyFactory(api: try .init(baseURL: url), configuration: accepted, transport: recorder, current: { current })
            XCTAssertFalse(factory.allowsNearbyLocation)
        }
        let factory = RuntimeDependencyFactory(api: try .init(baseURL: url), configuration: try approval(paths: ["api/merchant/nearby"], nearby: true), transport: recorder, current: { current })
        XCTAssertTrue(factory.allowsNearbyLocation)
    }
}

@MainActor private final class RuntimeTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var response = Data(#"{"code":200,"data":{}}"#.utf8)
    var beforeReply: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); beforeReply?(); return (response, 200) }
}

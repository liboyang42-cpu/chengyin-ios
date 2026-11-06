import Foundation
import XCTest
@testable import Questify

/// Synthetic transports only. These checks preserve the current closed boundary;
/// they do not claim native incremental/read-through endpoint authorization exists.
@MainActor final class NativeChannelHistoryFactoryClosedBoundaryTests: XCTestCase {
    func testActualOriginalAdapterKeepsCursorHistoryButCannotBorrowItForIncremental() async throws {
        let h = try Harness()
        let adapters = try h.adapters()
        let original = MessagingService(configuration: h.configuration, transport: adapters.historyTransport)
        let page = try await original.messages(conversationID: 9, cursor: 0, token: h.token)
        XCTAssertTrue(page.messages.isEmpty)
        XCTAssertEqual(h.wire.requests.count, 1)
        XCTAssertEqual(MessagingHistoryReadRoute(request: try XCTUnwrap(h.wire.requests.first), baseURL: h.base),
                       .messages(conversationID: 9, cursor: 0, size: 30))
        let inner = NativeChannelService(configuration: h.configuration, transport: adapters.historyTransport,
                                         allowsNewer: true)
        do { _ = try await inner.newer(conversationID: 9, after: 40, token: h.token); XCTFail("History lease must not grant incremental reads") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(h.wire.requests.count, 1)
    }

    func testActualOriginalAdapterDoesNotTurnHistoryLeaseIntoTypedReadAcknowledgement() async throws {
        let h = try Harness()
        let adapters = try h.adapters()
        let inner = NativeChannelService(configuration: h.configuration, transport: adapters.historyTransport,
                                         allowsReadReceipt: true)
        do { _ = try await inner.readThrough(conversationID: 9, readTo: 40, token: h.token); XCTFail("Service switch is not a write grant") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }

    func testOnlyIncrementalSwitchNeverEnablesReadThroughOrDispatchesIt() async throws {
        let h = try Harness()
        let service = NativeChannelService(configuration: h.configuration, transport: h.wire, allowsNewer: true)
        XCTAssertTrue(service.allowsNewer); XCTAssertFalse(service.allowsReadReceipt)
        do { _ = try await service.readThrough(conversationID: 9, readTo: 40, token: h.token); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }

    func testOnlyReadReceiptSwitchNeverEnablesIncrementalOrDispatchesIt() async throws {
        let h = try Harness()
        let service = NativeChannelService(configuration: h.configuration, transport: h.wire, allowsReadReceipt: true)
        XCTAssertFalse(service.allowsNewer); XCTAssertTrue(service.allowsReadReceipt)
        do { _ = try await service.newer(conversationID: 9, after: 40, token: h.token); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }

    func testZeroReadTargetIsRejectedBeforeEvenAnInjectedTransport() async throws {
        let h = try Harness()
        let service = NativeChannelService(configuration: h.configuration, transport: h.wire, allowsReadReceipt: true)
        do { _ = try await service.readThrough(conversationID: 9, readTo: 0, token: h.token); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }

    func testLegacyReadFeatureCannotRegisterEitherNativeHistoryOperation() throws {
        XCTAssertTrue(BusinessRuntimeFeature.imRead.accepts(try .post("api/im/read")))
        for path in ["api/im/messages", "api/native/channels/read-through"] {
            let route = try BusinessRuntimeRoute.post(path)
            XCTAssertFalse(BusinessRuntimeFeature.imRead.accepts(route))
            let h = try Harness()
            XCTAssertThrowsError(try BusinessRuntimeConfiguration(market: .china, baseURL: h.base,
                namespace: h.context.session.namespace, accountID: 7, routes: [.imRead: [route]]))
        }
    }

    @MainActor private final class Harness {
        let base = URL(string: "https://example.test/native")!
        let token = "synthetic-history-7"
        let configuration: APIConfiguration
        let context: RuntimeDependencyContext
        let binding: NativeChannelMessageBinding
        let historyGrant: MessagingHistoryReadApproval
        let wire: Wire
        let outer: CompositionHTTPTransport
        init() throws {
            let url = URL(string: "https://example.test/native")!
            configuration = try .init(baseURL: url)
            let deployment = try ReviewedAppDeployment(market: .china, baseURL: url.absoluteString,
                approvedBaseURLs: [.china: [url.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
                bundleIdentifier: "test.native-channel-history-boundary", realm: "synthetic")
            let captured = RuntimeDependencyContext(market: .china, baseURL: url, role: "player",
                session: try .init(accountID: 7, epoch: 1, namespace: deployment.storageScope.service,
                                   token: "synthetic-history-7"))
            context = captured
            binding = try .init(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!,
                                mappingRevision: "synthetic-read-binding-v1")
            let grant = try MessagingHistoryReadApproval(context: captured, expiresAt: Date().addingTimeInterval(300))
            historyGrant = grant
            let recorder = Wire(); wire = recorder
            outer = CompositionHTTPTransport(deployment: deployment, underlying: recorder,
                messagingHistoryReadApproval: { current in grant.matches(current) ? grant : nil })
            outer.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-history-7", viewerRevision: 1) }
        }
        func adapters() throws -> NativeChannelMessageOriginalAdapters {
            try outer.makeNativeChannelMessageOriginalAdapters(context: context, binding: binding,
                currentRuntime: { self.context }, stillCurrent: { true }, read: { nil }, write: { nil }, received401: {})
        }
    }

    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            guard request.url?.absoluteString == "https://example.test/native/api/im/messages",
                  let body = request.httpBody.flatMap({ String(data: $0, encoding: .utf8) }),
                  body.contains("name=\"cursor_id\""), !body.contains("name=\"after_id\"") else {
                XCTFail("Unexpected operation reached the synthetic original transport")
                throw APIError.invalidRequest
            }
            let response = #"{"code":200,"data":{"list":[],"nextCursor":null,"hasMore":false,"mutation_cursor":"0","sync_contract":"VISIBLE_ORDER_PLUS_MUTATIONS_V1","legacy_cache_action":"RELOAD_ON_RESUME"}}"#
            return (Data(response.utf8), 200)
        }
    }
}

import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelHostIndependentReadGateTests: XCTestCase {
    private let reads: [(BusinessRuntimeFeature, String)] = [
        (.imChannelMentionMemberRead, "api/channels/9/members"),
        (.imChannelMentionRoleRead, "api/im/roles"),
        (.imPollCreateReceipt, "api/im/poll/create-receipt")
    ]

    func testDefaultEmptyConfigurationCreatesNoReadOrSendGrant() async throws {
        let h = try IndependentHostReadHarness(routes: [:])
        let gate = try h.gate(features: Set(reads.map { $0.0 }))
        XCTAssertTrue(gate.isCurrent)
        for (_, path) in reads { await assertDenied(gate, request: try h.request(path)) }
        await assertDenied(gate, request: try h.request("api/im/send", method: "POST"))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }

    func testEachFeatureAcceptsOnlyItsExactOriginalGETCatalog() throws {
        for (feature, path) in reads {
            let get = try BusinessRuntimeRoute(method: "GET", path: path)
            let post = try BusinessRuntimeRoute(method: "POST", path: path)
            XCTAssertTrue(feature.accepts(get))
            XCTAssertFalse(feature.accepts(post))
            XCTAssertThrowsError(try IndependentHostReadHarness(routes: [feature: [post]]))
            XCTAssertFalse(feature.accepts(try .post("api/im/send")))
            for (_, otherPath) in reads where otherPath != path {
                XCTAssertFalse(feature.accepts(try .init(method: "GET", path: otherPath)))
            }
        }
        for path in ["api/channels/0/members", "api/channels/09/members", "api/channels/9/members/extra"] {
            XCTAssertFalse(BusinessRuntimeFeature.imChannelMentionMemberRead.accepts(try .init(method: "GET", path: path)))
        }
    }

    func testGenericSendCannotSupplyMentionOrPollReceiptReadPermission() async throws {
        let send = try BusinessRuntimeRoute.post("api/im/send")
        let h = try IndependentHostReadHarness(routes: [.imSend: [send]])
        let gate = try h.gate(features: Set(reads.map { $0.0 }))
        for (_, path) in reads {
            await assertDenied(gate, request: try h.request(path))
            XCTAssertThrowsError(try IndependentHostReadHarness(routes: [.imSend: [.init(method: "GET", path: path)]]))
        }
        await assertDenied(gate, request: try h.request("api/im/send", method: "POST"))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }

    func testEachReadUsesOnlyItsIssuedFeatureExactMethodAndChannel() async throws {
        for (feature, path) in reads {
            let route = try BusinessRuntimeRoute(method: "GET", path: path)
            let h = try IndependentHostReadHarness(routes: [feature: [route]])
            let gate = try h.gate(features: [feature])
            _ = try await gate.send(h.request(path))
            XCTAssertEqual(h.wire.requests.count, 1)
            XCTAssertEqual(h.wire.requests.first?.httpMethod, "GET")
            XCTAssertNil(h.wire.requests.first?.httpBody)
            XCTAssertEqual(h.wire.requests.first?.value(forHTTPHeaderField: "Authorization"), "fixture-token")
            await assertDenied(gate, request: try h.request(path, method: "POST"))
            for (_, otherPath) in reads where otherPath != path {
                await assertDenied(gate, request: try h.request(otherPath))
            }
            if feature == .imChannelMentionMemberRead {
                await assertDenied(gate, request: try h.request("api/channels/10/members"))
            }
            XCTAssertEqual(h.wire.requests.count, 1)
        }
    }

    func testObservedWithdrawalAndIdenticalRegrantNeverRevivesOldReadGate() async throws {
        for (feature, path) in reads {
            let route = try BusinessRuntimeRoute(method: "GET", path: path)
            let h = try IndependentHostReadHarness(routes: [feature: [route]])
            let gate = try h.gate(features: [feature])
            let issued = h.live
            h.live = try h.configuration(routes: [:])
            XCTAssertFalse(gate.isCurrent)
            h.live = issued
            XCTAssertFalse(gate.isCurrent)
            await assertDenied(gate, request: try h.request(path))
            XCTAssertTrue(h.wire.requests.isEmpty)
            let replacement = try h.gate(features: [feature])
            _ = try await replacement.send(h.request(path))
            XCTAssertEqual(h.wire.requests.count, 1)
        }
    }

    func testPollReceiptOnlyGETKeepsOriginalQueryAndCannotCreateVoteOrClose() async throws {
        let receipt = try BusinessRuntimeRoute(method: "GET", path: "api/im/poll/create-receipt")
        let h = try IndependentHostReadHarness(routes: [.imPollCreateReceipt: [receipt]])
        let gate = try h.gate(features: [.imPollCreateReceipt])
        var request = try h.request(receipt.path)
        var parts = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        parts.queryItems = [.init(name: "conversation_id", value: "9"),
                            .init(name: "client_message_id", value: "original-create-0001")]
        request.url = try XCTUnwrap(parts.url)
        _ = try await gate.send(request)
        XCTAssertEqual(h.wire.requests.first?.url, request.url)
        for path in [receipt.path, "api/im/poll/create", "api/im/poll/vote", "api/im/poll/close", "api/im/send"] {
            await assertDenied(gate, request: try h.request(path, method: "POST"))
        }
        XCTAssertEqual(h.wire.requests.count, 1)
    }

    func testPollCreatePermissionDoesNotSupplyReceiptOnlyGET() async throws {
        let h = try IndependentHostReadHarness(routes: [.imPollCreate: [.post("api/im/poll/create")]])
        let gate = try h.gate(features: [.imPollCreateReceipt])
        await assertDenied(gate, request: try h.request("api/im/poll/create-receipt"))
        await assertDenied(gate, request: try h.request("api/im/poll/create", method: "POST"))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }

    func testLateReadResponseAfterBackgroundRetirementCannotReturnOrRevive() async throws {
        for (feature, path) in reads {
            let h = try IndependentHostReadHarness(routes: [feature: [.init(method: "GET", path: path)]])
            let gate = try h.gate(features: [feature])
            h.wire.beforeReturn = { h.active = false }
            do {
                _ = try await gate.send(h.request(path))
                XCTFail("A retired response must not reach its consumer")
            } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertFalse(gate.isCurrent)
            h.active = true
            XCTAssertFalse(gate.isCurrent)
            await assertDenied(gate, request: try h.request(path))
            XCTAssertEqual(h.wire.requests.count, 1)
        }
    }

    private func assertDenied(_ gate: NativeChannelHostRuntimeTransport, request: URLRequest,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await gate.send(request)
            XCTFail("Unissued route must not reach the underlying transport", file: file, line: line)
        } catch { XCTAssertEqual(error as? APIError, .notConfigured, file: file, line: line) }
    }
}

@MainActor private final class IndependentHostReadHarness {
    let context: RuntimeDependencyContext
    let issued: BusinessRuntimeConfiguration
    var live: BusinessRuntimeConfiguration?
    var active = true
    let wire = IndependentHostReadTransport()

    init(routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>]) throws {
        let base = URL(string: "https://api.example.test")!
        context = .init(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "CN:host-read-test", token: "fixture-token"))
        issued = try .init(market: .china, baseURL: base, namespace: "CN:host-read-test", accountID: 7, routes: routes)
        live = issued
    }
    func configuration(routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>]) throws -> BusinessRuntimeConfiguration {
        try .init(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace,
                  accountID: context.session.accountID, routes: routes)
    }
    func gate(features: Set<BusinessRuntimeFeature>) throws -> NativeChannelHostRuntimeTransport {
        try XCTUnwrap(NativeChannelHostRuntimeTransport(context: context, issued: issued, features: features,
            underlying: wire, runtime: { self.context }, configuration: { self.live }, presentation: { self.active }))
    }
    func request(_ path: String, method: String = "GET") throws -> URLRequest {
        var request = URLRequest(url: context.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        return request
    }
}

@MainActor private final class IndependentHostReadTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var beforeReturn: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        beforeReturn?()
        return (Data(), 200)
    }
}

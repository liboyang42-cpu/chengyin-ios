import XCTest
@testable import Questify

/// Real assembly + final-forward descriptor gate. The underlying API and object
/// channels remain separately recorded; no requests are made by construction.
@MainActor final class NativeChannelAttachmentPreviewRetirementTests: XCTestCase {
    func testObservedRouteWithdrawalCannotReviveRetainedFlowAfterIdenticalRegrant() async throws {
        let h = try AttachmentPreviewRetirementHarness()
        let flow = try h.make()
        defer { flow.clear() }
        XCTAssertTrue(flow.isCurrent)
        let issued = h.configuration
        h.configuration = try h.configuration(routes: [], origins: h.origins)
        XCTAssertFalse(flow.isCurrent)
        h.configuration = issued
        XCTAssertFalse(flow.isCurrent)
        await flow.load()
        XCTAssertEqual(flow.visibleState, .unavailable)
        XCTAssertNil(flow.bytes)
        XCTAssertTrue(h.api.requests.isEmpty)
        XCTAssertTrue(h.media.requests.isEmpty)
        XCTAssertEqual(h.unauthorizedCount, 0)
        let replacement = try h.make()
        defer { replacement.clear() }
        XCTAssertTrue(replacement.isCurrent, "An explicit new owner may consume the restored exact grant")
    }

    func testObservedOriginWithdrawalCannotReviveRetainedFlowAfterIdenticalRegrant() async throws {
        let h = try AttachmentPreviewRetirementHarness()
        let flow = try h.make()
        defer { flow.clear() }
        let issued = h.configuration
        h.configuration = try h.configuration(routes: [h.route], origins: [])
        XCTAssertEqual(flow.visibleState, .unavailable)
        h.configuration = issued
        XCTAssertFalse(flow.isCurrent)
        await flow.load()
        XCTAssertNil(flow.bytes)
        XCTAssertTrue(h.api.requests.isEmpty)
        XCTAssertTrue(h.media.requests.isEmpty)
        XCTAssertEqual(h.unauthorizedCount, 0)
    }

    func testObservedPresentationRetirementCannotReviveOldFlow() async throws {
        let h = try AttachmentPreviewRetirementHarness()
        let flow = try h.make()
        defer { flow.clear() }
        h.hostCurrent = false
        XCTAssertFalse(flow.isCurrent)
        h.hostCurrent = true
        XCTAssertFalse(flow.isCurrent)
        await flow.load()
        XCTAssertTrue(h.api.requests.isEmpty)
        XCTAssertTrue(h.media.requests.isEmpty)
    }

    func testObservedRuntimeReplacementCannotReviveOldFlowWhenOriginalReturns() async throws {
        let h = try AttachmentPreviewRetirementHarness()
        let flow = try h.make()
        defer { flow.clear() }
        let original = h.context
        h.context = try h.context(epoch: 2)
        XCTAssertFalse(flow.isCurrent)
        h.context = original
        XCTAssertFalse(flow.isCurrent)
        await flow.load()
        XCTAssertTrue(h.api.requests.isEmpty)
        XCTAssertTrue(h.media.requests.isEmpty)
        XCTAssertEqual(h.unauthorizedCount, 0)
    }

    func testObservedWithdrawalDuringObjectTransferDiscardsLateBytesAfterRegrant() async throws {
        let h = try AttachmentPreviewRetirementHarness()
        let flow = try h.make()
        defer { flow.clear() }
        h.media.operation = { _ in
            let issued = h.configuration
            h.configuration = try h.configuration(routes: [], origins: h.origins)
            XCTAssertFalse(flow.isCurrent)
            h.configuration = issued
            XCTAssertFalse(flow.isCurrent)
            return h.media.result
        }
        await flow.load()
        XCTAssertEqual(flow.visibleState, .unavailable)
        XCTAssertNil(flow.bytes)
        XCTAssertEqual(h.api.requests.count, 1, "Retirement blocks the post-download descriptor reread")
        XCTAssertEqual(h.media.requests.count, 1)
        XCTAssertEqual(h.unauthorizedCount, 0)
        await flow.load()
        XCTAssertEqual(h.api.requests.count, 1)
        XCTAssertEqual(h.media.requests.count, 1)
    }

    func testCurrentFlowStillUsesIndependentAuthenticatedGETAndCredentialFreeObjectGET() async throws {
        let h = try AttachmentPreviewRetirementHarness()
        let flow = try h.make()
        defer { flow.clear() }
        XCTAssertTrue(h.api.requests.isEmpty)
        XCTAssertTrue(h.media.requests.isEmpty)
        await flow.load()
        XCTAssertEqual(flow.visibleState, .displayed)
        XCTAssertNotNil(flow.bytes)
        XCTAssertEqual(h.api.requests.count, 2)
        for request in h.api.requests {
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.test/prod-api/api/im/message/1/attachment")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        }
        let request = try XCTUnwrap(h.media.requests.first)
        XCTAssertEqual(h.media.requests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, "https://media.example.test/original?signature=synthetic")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.httpBodyStream)
        for header in ["Authorization", "Proxy-Authorization", "Cookie", "Cookie2"] {
            XCTAssertNil(request.value(forHTTPHeaderField: header))
        }
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(h.unauthorizedCount, 0)
    }
}

@MainActor private final class AttachmentPreviewRetirementHarness {
    let base = URL(string: "https://api.example.test/prod-api")!
    let origins: Set<String> = ["https://media.example.test"]
    let api = AttachmentPreviewRetirementTransport()
    let media = AttachmentPreviewRetirementTransport()
    let route: BusinessRuntimeRoute
    var context: RuntimeDependencyContext?
    var configuration: BusinessRuntimeConfiguration?
    var hostCurrent = true
    var unauthorizedCount = 0

    init() throws {
        route = try BusinessRuntimeRoute(method: "GET", path: "api/im/message/1/attachment")
        context = try context(epoch: 1)
        configuration = try configuration(routes: [route], origins: origins)
        api.result = (try JSONSerialization.data(withJSONObject: ["code": 200, "data": [
            "message_id": "1", "conversation_id": "9", "kind": "IMAGE", "source": "LEGACY_SINGLE_IMAGE",
            "state": "READY", "asset_id": "5", "asset_version": 0, "message_version": 1,
            "url": "https://media.example.test/original?signature=synthetic", "expires_in_seconds": 300
        ]]), 200)
        media.result = (Data([137, 80, 78, 71, 13, 10, 26, 10]), 200)
    }

    func context(epoch: UInt64) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: "player",
              session: try .init(accountID: 7, epoch: epoch, namespace: "preview-test", token: "synthetic-token"))
    }

    func configuration(routes: Set<BusinessRuntimeRoute>, origins: Set<String>) throws -> BusinessRuntimeConfiguration {
        try .init(market: .china, baseURL: base, namespace: "preview-test", accountID: 7,
                  routes: [.imChannelAttachmentPreview: routes], imMediaOrigins: origins)
    }

    func factory() -> BusinessRuntimeFactory? {
        guard let apiConfiguration = try? APIConfiguration(baseURL: base) else { return nil }
        return BusinessRuntimeFactory(configuration: configuration, api: apiConfiguration,
                                      transport: api, current: { self.context })
    }

    func make() throws -> NativeChannelAttachmentPreviewFlow {
        let issued = try XCTUnwrap(factory())
        let apiConfiguration = try APIConfiguration(baseURL: base)
        let descriptor = try XCTUnwrap(NativeChannelAttachmentDescriptorTransport(messageID: 1,
            context: issued.captured, issued: issued.configuration, underlying: api,
            runtime: { self.context }, configuration: { self.configuration },
            presentation: { self.hostCurrent }))
        // Match the AppSession binding: the descriptor latch is evaluated before
        // any outer gate can short-circuit a revoked retained page.
        let previewFactory = try XCTUnwrap(BusinessRuntimeFactory(configuration: issued.configuration,
            api: apiConfiguration, transport: descriptor,
            current: { descriptor.isCurrent ? self.context : nil }))
        let message = try JSONDecoder().decode(MessagingMessage.self,
            from: Data(#"{"id":1,"conversationId":9,"status":0,"msgType":2,"content":"https://media.example.test/old-link"}"#.utf8))
        return try XCTUnwrap(NativeChannelAttachmentPreviewAssembly.make(message: message,
            configuration: apiConfiguration, factory: previewFactory,
            currentFactory: {
                guard descriptor.isCurrent else { return nil }
                return self.factory()
            }, current: { descriptor.isCurrent && self.hostCurrent },
            unauthorized: { self.unauthorizedCount += 1 }, mediaTransport: media))
    }
}

@MainActor private final class AttachmentPreviewRetirementTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var result = (Data(), 200)
    var operation: ((URLRequest) async throws -> (Data, Int))?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return try await operation?(request) ?? result
    }
}

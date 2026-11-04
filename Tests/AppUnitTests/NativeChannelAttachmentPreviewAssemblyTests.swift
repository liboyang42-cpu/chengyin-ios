import XCTest
@testable import Questify

@MainActor final class NativeChannelAttachmentPreviewAssemblyTests: XCTestCase {
    func testNormalAssemblyUsesAuthenticatedDescriptorAndSeparateCredentiallessMedia() async throws {
        let h = try AttachmentPreviewAssemblyHarness()
        let flow = try h.make()
        defer { flow.clear() }
        XCTAssertEqual(flow.visibleState, .idle)
        XCTAssertTrue(h.api.requests.isEmpty);XCTAssertTrue(h.media.requests.isEmpty)
        await flow.load()
        XCTAssertEqual(flow.visibleState, .displayed);XCTAssertNotNil(flow.bytes)
        XCTAssertEqual(h.api.requests.count, 2, "Original descriptor is read before and after image bytes")
        for request in h.api.requests {
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.test/prod-api/api/im/message/1/attachment")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        }
        let request = try XCTUnwrap(h.media.requests.first)
        XCTAssertEqual(h.media.requests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, "https://media.example.test/original?signature=synthetic")
        XCTAssertEqual(request.httpMethod, "GET");XCTAssertNil(request.httpBody);XCTAssertNil(request.httpBodyStream)
        for header in ["Authorization", "Proxy-Authorization", "Cookie", "Cookie2"] {
            XCTAssertNil(request.value(forHTTPHeaderField: header))
        }
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/*")
        XCTAssertEqual(h.unauthorizedCount, 0)
    }

    func testDefaultDedicatedTransportHasTwelveMiBBoundAndRemainsDisabledWithoutGrant() {
        let enabled = NativeChannelAttachmentPreviewAssembly.boundedMediaTransport(enabled: true)
        XCTAssertTrue(enabled.enabled);XCTAssertEqual(enabled.maximumResponseBytes, 12 * 1024 * 1024)
        let disabled = NativeChannelAttachmentPreviewAssembly.boundedMediaTransport(enabled: false)
        XCTAssertFalse(disabled.enabled)
        // No send: the original ResponseLimitedHTTPTransport delegate suite owns
        // no-redirect/chunk-limit behavior; this test checks this exact assembly.
    }

    func testMissingExactRouteOrUnapprovedOriginCannotSend() async throws {
        let h = try AttachmentPreviewAssemblyHarness()
        let otherRoute = try BusinessRuntimeRoute(method: "GET", path: "api/im/message/2/attachment")
        for (routes, origins) in [(Set<BusinessRuntimeRoute>(), Set(["https://media.example.test"])),
                                  (Set([otherRoute]), Set(["https://media.example.test"])),
                                  (Set([h.route]), Set<String>()),
                                  (Set([h.route]), Set(["https://media.example.test/arbitrary-path"])),
                                  (Set([h.route]), Set(["https://localhost"]))] {
            h.configuration = try h.configuration(routes: routes, origins: origins)
            let flow = try h.make();await flow.load()
            XCTAssertFalse(flow.enabled);XCTAssertNil(flow.bytes)
            XCTAssertTrue(h.api.requests.isEmpty);XCTAssertTrue(h.media.requests.isEmpty)
            flow.clear()
        }
    }

    func testChangedOriginalIdentityOrForeignURLNeverPublishesImage() async throws {
        for (conversation, url) in [("99", "https://media.example.test/original?signature=synthetic"),
                                    ("9", "https://other.example.test/original"),
                                    ("9", "https://user:secret@media.example.test/original"),
                                    ("9", "https://media.example.test/original#fragment")] {
            let h = try AttachmentPreviewAssemblyHarness()
            h.api.result = (try h.descriptor(conversation: conversation, url: url), 200)
            let flow = try h.make();defer { flow.clear() }
            await flow.load()
            XCTAssertEqual(flow.visibleState, .unknown);XCTAssertNil(flow.bytes);XCTAssertTrue(h.media.requests.isEmpty)
        }
    }

    func testRevokedRouteOrOriginDuringMediaTransferDiscardsBytes() async throws {
        for removeOrigin in [false, true] {
            let h = try AttachmentPreviewAssemblyHarness()
            h.media.operation = { _ in
                h.configuration = try h.configuration(routes: removeOrigin ? [h.route] : [],
                    origins: removeOrigin ? [] : ["https://media.example.test"])
                return h.media.result
            }
            let flow = try h.make();defer { flow.clear() }
            await flow.load()
            XCTAssertEqual(flow.visibleState, .unavailable);XCTAssertNil(flow.bytes)
            XCTAssertEqual(h.api.requests.count, 1);XCTAssertEqual(h.media.requests.count, 1)
            XCTAssertEqual(h.unauthorizedCount, 0)
        }
    }

    func testSameAccountNewEpochOrLocalHostRevocationDiscardsBytes() async throws {
        for newEpoch in [false, true] {
            let h = try AttachmentPreviewAssemblyHarness()
            h.media.operation = { _ in
                if newEpoch { h.context = try h.context(epoch: 2) } else { h.hostCurrent = false }
                return h.media.result
            }
            let flow = try h.make();defer { flow.clear() }
            await flow.load()
            XCTAssertNil(flow.bytes);XCTAssertEqual(flow.visibleState, .unavailable)
            XCTAssertEqual(h.api.requests.count, 1);XCTAssertEqual(h.unauthorizedCount, 0)
        }
    }

    func testGrantWithdrawalBeforeLoadAndLateAPI401NeverExpiresReplacementSession() async throws {
        let h = try AttachmentPreviewAssemblyHarness()
        let flow = try h.make();defer { flow.clear() }
        h.configuration = try h.configuration(routes: [], origins: ["https://media.example.test"])
        await flow.load();XCTAssertTrue(h.api.requests.isEmpty);XCTAssertTrue(h.media.requests.isEmpty)
        h.configuration = try h.configuration(routes: [h.route], origins: ["https://media.example.test"])
        h.api.operation = { _ in h.context = try h.context(epoch: 2);return (Data(), 401) }
        await flow.load()
        XCTAssertNil(flow.bytes);XCTAssertEqual(h.unauthorizedCount, 0);XCTAssertTrue(h.media.requests.isEmpty)
    }

    func testStorageDenialRetainsDescriptorAuthorityAndDoesNotExpireLogin() async throws {
        let h = try AttachmentPreviewAssemblyHarness()
        h.media.result = (Data(), 403)
        h.api.operation = { _ in
            (try h.descriptor(state: h.api.requests.count == 1 ? "READY" : "REJECTED"), 200)
        }
        let flow = try h.make();defer { flow.clear() }
        await flow.load()
        XCTAssertEqual(flow.visibleState, .rejected);XCTAssertNil(flow.bytes)
        XCTAssertEqual(h.unauthorizedCount, 0);XCTAssertEqual(h.api.requests.count, 2)
    }
}

@MainActor private final class AttachmentPreviewAssemblyHarness {
    let base = URL(string: "https://api.example.test/prod-api")!
    let api = AttachmentPreviewAssemblyTransport(requiresCredential: true)
    let media = AttachmentPreviewAssemblyTransport(requiresCredential: false)
    let route: BusinessRuntimeRoute
    var context: RuntimeDependencyContext?
    var configuration: BusinessRuntimeConfiguration?
    var hostCurrent = true
    var unauthorizedCount = 0
    init() throws {
        route = try BusinessRuntimeRoute(method: "GET", path: "api/im/message/1/attachment")
        context = try context(epoch: 1)
        configuration = try configuration(routes: [route], origins: ["https://media.example.test"])
        api.result = (try descriptor(), 200)
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
        return BusinessRuntimeFactory(configuration: configuration, api: apiConfiguration, transport: api, current: { self.context })
    }
    func make() throws -> NativeChannelAttachmentPreviewFlow {
        let message = try JSONDecoder().decode(MessagingMessage.self,
            from: Data(#"{"id":1,"conversationId":9,"status":0,"msgType":2,"content":"https://media.example.test/old-link"}"#.utf8))
        return try XCTUnwrap(NativeChannelAttachmentPreviewAssembly.make(message: message,
            configuration: try APIConfiguration(baseURL: base), factory: try XCTUnwrap(factory()),
            currentFactory: { self.factory() }, current: { self.hostCurrent },
            unauthorized: { self.unauthorizedCount += 1 }, mediaTransport: media))
    }
    func descriptor(state: String = "READY", conversation: String = "9",
                    url: String = "https://media.example.test/original?signature=synthetic") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["message_id": "1", "conversation_id": conversation,
            "kind": "IMAGE", "source": "LEGACY_SINGLE_IMAGE", "state": state, "asset_id": "5", "asset_version": 0,
            "message_version": 1, "url": url, "expires_in_seconds": 300]])
    }
}
@MainActor private final class AttachmentPreviewAssemblyTransport: HTTPTransport {
    let requiresCredential: Bool
    var requests: [URLRequest] = []
    var result = (Data(), 200)
    var operation: ((URLRequest) async throws -> (Data, Int))?
    init(requiresCredential: Bool) { self.requiresCredential = requiresCredential }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if requiresCredential {
            guard request.url?.host == "api.example.test", request.value(forHTTPHeaderField: "Authorization") == "synthetic-token" else {
                throw APIError.invalidRequest
            }
        } else {
            guard request.url?.host == "media.example.test", request.value(forHTTPHeaderField: "Authorization") == nil else {
                throw APIError.invalidRequest
            }
        }
        return try await operation?(request) ?? result
    }
}

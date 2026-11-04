import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic local ports only. Configuring a fixture grant does not issue a production grant.
@MainActor final class NativeChannelHostMigrationContractTests: XCTestCase {
    private let base = URL(string: "https://api.example.test/prod-api")!
    private func context(epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: "member",
              session: try .init(accountID: 7, epoch: epoch, namespace: "fixture", token: "synthetic-token"))
    }
    private func config(_ routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>] = [:]) throws -> BusinessRuntimeConfiguration {
        try .init(market: .china, baseURL: base, namespace: "fixture", accountID: 7, routes: routes)
    }
    private func request(_ id: Int = 1, method: String = "GET", token: String = "synthetic-token") throws -> URLRequest {
        var request = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/im/message/\(id)/attachment"), fields: [:], token: token, includesBody: false)
        request.httpMethod = method;request.httpShouldHandleCookies = false;return request
    }
    func testAttachmentCatalogKeepsOriginalPositiveIDGETContract() throws {
        for id in [1, 42, 9001] {
            XCTAssertTrue(BusinessRuntimeFeature.imChannelAttachmentPreview.accepts(try .init(method: "GET", path: "api/im/message/\(id)/attachment")))
        }
        for path in ["api/im/message/0/attachment", "api/im/message/-1/attachment", "api/im/message/1/attachment/extra", "api/im/message/1/other", "api/im/message/one/attachment"] {
            XCTAssertFalse(BusinessRuntimeFeature.imChannelAttachmentPreview.accepts(try .init(method: "GET", path: path)), path)
        }
        XCTAssertFalse(BusinessRuntimeFeature.imChannelAttachmentPreview.accepts(try .post("api/im/message/1/attachment")))
        XCTAssertThrowsError(try BusinessRuntimeRoute(method: "GET", path: "api/im/message/*/attachment"))
        XCTAssertThrowsError(try BusinessRuntimeRoute(method: "GET", path: "api/im/message/1/attachment?other=1"))
    }
    func testEmptyConfigurationAndOrdinarySendNeverIssueAttachmentGrant() async throws {
        let context = try context(), wire = ChannelHostMigrationWire()
        for configuration in [try config(), try config([.imSend: [.post("api/im/send")]])] {
            let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: configuration, api: .init(baseURL: base), transport: wire, current: { context }))
            XCTAssertTrue(factory.routes([.imChannelAttachmentPreview]).isEmpty)
            do { _ = try await factory.client([.imChannelAttachmentPreview]).send(request());XCTFail("No attachment grant") } catch {}
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testIssuedAttachmentRouteCannotAuthorizeAnotherMessageMethodOrCredential() async throws {
        let context = try context(), wire = ChannelHostMigrationWire()
        let route = try BusinessRuntimeRoute(method: "GET", path: "api/im/message/1/attachment")
        let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: config([.imChannelAttachmentPreview: [route]]), api: .init(baseURL: base), transport: wire, current: { context }))
        let client = factory.client([.imChannelAttachmentPreview])
        for rejected in [try request(2), try request(method: "POST"), try request(token: "other-token")] {
            do { _ = try await client.send(rejected);XCTFail("Exact method/path/token required") } catch {}
        }
        XCTAssertTrue(wire.requests.isEmpty)
        _ = try await client.send(request())
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testLateAttachmentResponseCannotCrossRuntimeEpoch() async throws {
        let initial = try context(), replacement = try context(epoch: 2), wire = ChannelHostMigrationWire()
        var current: RuntimeDependencyContext? = initial
        let route = try BusinessRuntimeRoute(method: "GET", path: "api/im/message/1/attachment")
        let factory = try XCTUnwrap(BusinessRuntimeFactory(configuration: config([.imChannelAttachmentPreview: [route]]), api: .init(baseURL: base), transport: wire, current: { current }))
        wire.onSend = { current = replacement }
        do { _ = try await factory.client([.imChannelAttachmentPreview]).send(request());XCTFail("Late response") }
        catch { XCTAssertTrue(error is CancellationError) }
        do { _ = try await factory.client([.imChannelAttachmentPreview]).send(request());XCTFail("Old factory") } catch {}
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testLegacyExpandedJournalCannotRewriteCurrentReadCursor() throws {
        let storage = ChannelHostMigrationStorage(), context = try context()
        let scope = try NativeChannelTextScope(context: context, conversationID: 9)
        let journal = IMExpandedRecoveryJournal(storage: storage, scope: scope)
        let original = IMMutation.readCursor(conversationID: 9, lastMessageID: 10, requestID: UUID().uuidString.lowercased())
        XCTAssertThrowsError(try journal.saveBeforeDispatch(original))
        XCTAssertTrue(storage.rows.isEmpty);XCTAssertEqual(storage.writes, 0);XCTAssertEqual(storage.removes, 0)
    }
    func testCurrentOrdinaryReadSentCannotDropChannelReference() async throws {
        let wire = ChannelHostMigrationWire()
        let binding = try NativeChannelMessageBinding(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!, mappingRevision: "synthetic-original")
        let reference = try NativeChannelMessageTextReference(binding: binding, replyToID: .init(rawValue: "8")!)
        let intent = try MessageTextIntent(conversationID: 9, content: "same original text", clientMessageID: String(repeating: "a", count: 32), channelReference: reference)
        let service = MessageActionService(configuration: try .init(baseURL: base), transport: wire)
        do { _ = try await service.readSent(intent, token: "synthetic-token");XCTFail("Reference is not an ordinary receipt") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await service.send(intent, token: "synthetic-token");XCTFail("Reference is not an ordinary send") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testAddedCodableConformancePreservesAllCurrentPayloadValues() throws {
        let values: [IMOutgoingPayload] = [.image(URL(string: "https://media.example.test/a.png")!), .route(topicID: 1), .location(name: "selected", address: "address", latitude: 1.5, longitude: 2.5)]
        for value in values {
            XCTAssertEqual(try JSONDecoder().decode(IMOutgoingPayload.self, from: JSONEncoder().encode(value)), value)
        }
    }
    func testDescriptorFinalForwardCannotBeConstructedWithoutExactGrant() throws {
        let context = try context(), wire = ChannelHostMigrationWire(), empty = try config()
        XCTAssertNil(NativeChannelAttachmentDescriptorTransport(messageID: 1, context: context,
            issued: empty, underlying: wire, runtime: { context }, configuration: { empty }, presentation: { true }))
        let other = try config([.imChannelAttachmentPreview: [.init(method: "GET", path: "api/im/message/2/attachment")]])
        XCTAssertNil(NativeChannelAttachmentDescriptorTransport(messageID: 1, context: context,
            issued: other, underlying: wire, runtime: { context }, configuration: { other }, presentation: { true }))
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testDescriptorFinalForwardRejectsQueryBodyCookiesAndForeignTargets() async throws {
        let context = try context(), wire = ChannelHostMigrationWire()
        let issued = try config([.imChannelAttachmentPreview: [.init(method: "GET", path: "api/im/message/1/attachment")]])
        let transport = try XCTUnwrap(NativeChannelAttachmentDescriptorTransport(messageID: 1, context: context,
            issued: issued, underlying: wire, runtime: { context }, configuration: { issued }, presentation: { true }))
        var query = try request();query.url = URL(string: query.url!.absoluteString + "?other=1")
        var body = try request();body.httpBody = Data("unexpected".utf8)
        var cookie = try request();cookie.setValue("forbidden", forHTTPHeaderField: "Cookie")
        var proxy = try request();proxy.setValue("forbidden", forHTTPHeaderField: "Proxy-Authorization")
        var cookieHandling = try request();cookieHandling.httpShouldHandleCookies = true
        for value in [query, body, cookie, proxy, cookieHandling, try request(2), try request(method: "POST"), try request(token: "other-token")] {
            do { _ = try await transport.send(value);XCTFail("Exact descriptor request only") } catch {}
        }
        XCTAssertTrue(wire.requests.isEmpty)
        _ = try await transport.send(request());XCTAssertEqual(wire.requests.count, 1)
    }
    func testDescriptorFinalForwardRetiresObservedGrantWithdrawalAndCannotReopen() async throws {
        let context = try context(), wire = ChannelHostMigrationWire(), empty = try config()
        let issued = try config([.imChannelAttachmentPreview: [.init(method: "GET", path: "api/im/message/1/attachment")]])
        var live: BusinessRuntimeConfiguration? = issued
        let transport = try XCTUnwrap(NativeChannelAttachmentDescriptorTransport(messageID: 1, context: context,
            issued: issued, underlying: wire, runtime: { context }, configuration: { live }, presentation: { true }))
        wire.onSend = { live = empty }
        do { _ = try await transport.send(request());XCTFail("Revoked result") }
        catch { XCTAssertTrue(error is CancellationError) }
        live = issued;wire.onSend = nil
        do { _ = try await transport.send(request());XCTFail("Retired issuance cannot reopen") } catch {}
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testDescriptorFinalForwardDropsLate401AfterPresentationRetires() async throws {
        let context = try context(), wire = ChannelHostMigrationWire()
        let issued = try config([.imChannelAttachmentPreview: [.init(method: "GET", path: "api/im/message/1/attachment")]])
        var active = true
        let transport = try XCTUnwrap(NativeChannelAttachmentDescriptorTransport(messageID: 1, context: context,
            issued: issued, underlying: wire, runtime: { context }, configuration: { issued }, presentation: { active }))
        wire.status = 401;wire.onSend = { active = false }
        do { _ = try await transport.send(request());XCTFail("Stale API401 must not reach logout handling") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testDescriptorFinalForwardRejectsOversizedEnvelope() async throws {
        let context = try context(), wire = ChannelHostMigrationWire()
        let issued = try config([.imChannelAttachmentPreview: [.init(method: "GET", path: "api/im/message/1/attachment")]])
        let transport = try XCTUnwrap(NativeChannelAttachmentDescriptorTransport(messageID: 1, context: context,
            issued: issued, underlying: wire, runtime: { context }, configuration: { issued }, presentation: { true }))
        wire.bytes = Data(repeating: 0, count: 16_385)
        do { _ = try await transport.send(request());XCTFail("Oversized descriptor") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        XCTAssertEqual(wire.requests.count, 1)
    }
}
@MainActor private final class ChannelHostMigrationWire: HTTPTransport {
    var requests: [URLRequest] = []
    var onSend: (() -> Void)?
    var bytes = Data(#"{"code":200,"data":{}}"#.utf8)
    var status = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request);onSend?();return (bytes, status)
    }
}
@MainActor private final class ChannelHostMigrationStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    var writes = 0
    var removes = 0
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ value: Data, key: String) throws { writes += 1;rows[key] = value }
    func remove(_ key: String) throws { removes += 1;rows[key] = nil }
}

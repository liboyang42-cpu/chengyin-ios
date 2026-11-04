import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor private final class HostFixtureSource: NativeChannelMessageAuthorizing {
    var value: NativeChannelMessageCredentials
    var capabilities: Set<NativeChannelMessageCapability> = [.receipt, .mutations, .pins, .mutate(.edit)]
    var identity: MessagingReadIdentity? { value.identity }
    init(_ value: NativeChannelMessageCredentials) { self.value = value }
    func credentials(for capability: NativeChannelMessageCapability, binding: NativeChannelMessageBinding) throws -> NativeChannelMessageCredentials {
        guard capabilities.contains(capability), binding == value.binding else { throw APIError.notConfigured }; return value
    }
}
@MainActor private final class HostFixtureStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class HostFixtureWire: HTTPTransport {
    var requests: [URLRequest] = []
    var before: (() -> Void)?
    var status = 200
    var bytes = Data()
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); before?(); return (bytes, status) }
}
@MainActor private final class HostHarness {
    let context: RuntimeDependencyContext
    let binding: NativeChannelMessageBinding
    var source: HostFixtureSource
    var selected: HostFixtureSource?
    var live = true
    var viewer: UInt64 = 1
    let storage = HostFixtureStorage()
    let wire = HostFixtureWire()
    var unauthorized = 0
    init() throws {
        context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://fixture.invalid/native")!, role: "player",
            session: try .init(accountID: 3, epoch: 1, namespace: "fixture", token: "fixture-token"))
        binding = try .init(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!, mappingRevision: "actual-source:1")
        source = HostFixtureSource(try .init(identity: .init(accountID: 3, epoch: 1), namespace: context.session.namespace,
            baseURL: context.baseURL, binding: binding, authorityRevision: "source-issued-v1", token: context.session.token))
        selected = source
    }
    func authority() throws -> NativeChannelMessageHostAuthority {
        try .init(context: context, viewerRevision: viewer, binding: binding, source: source,
            current: { self.live ? self.context : nil }, viewer: { self.viewer }, selected: { self.selected })
    }
    func journal() -> NativeChannelMessageMutationJournal { .init(scope: .init(credentials: source.value), storage: storage) }
    func forward(_ authority: NativeChannelMessageHostAuthority) throws -> NativeChannelMessageFinalForward {
        try .init(authority: authority, journal: journal(), underlying: wire, current: { self.live }, onUnauthorized: { _ in self.unauthorized += 1 })
    }
    func pins() -> URLRequest {
        var request = URLRequest(url: URL(string: context.baseURL.absoluteString + "/api/im/pins?conversation_id=9")!)
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        return request
    }
    func command() throws -> NativeChannelMessageCommand {
        try .init(operation: .edit, requestID: "original_fixture_0001", binding: binding,
            messageID: .init(rawValue: "8")!, expectedVersion: 1, content: "original body")
    }
}
@MainActor final class NativeChannelMessageHostAuthorityTests: XCTestCase {
    func testSourceDisappearsAndReturnsNeverReopensObservedIssuance() throws {
        let h = try HostHarness(), a = try h.authority()
        XCTAssertNotNil(a.identity); h.selected = nil; XCTAssertNil(a.identity)
        h.selected = h.source; XCTAssertNil(a.identity)
    }
    func testAbsentCapabilityNeverAdoptedFromLaterSameSource() throws {
        let h = try HostHarness(); h.source.capabilities = [.receipt]
        let a = try h.authority(); h.source.capabilities.insert(.mutations)
        XCTAssertThrowsError(try a.credentials(for: .mutations, binding: h.binding))
        XCTAssertNoThrow(try a.credentials(for: .receipt, binding: h.binding))
    }
    func testActual401RetiresSameIssuanceAcrossNormalDispatcherRemountAndKeepsJournal() async throws {
        let h = try HostHarness(), a = try h.authority(); let original = try h.command(); try h.journal().saveBeforeDispatch(original)
        let bytes = h.storage.rows; h.wire.status = 401
        do { _ = try await h.forward(a).send(h.pins(), fence: .init { true }); XCTFail("401") } catch {}
        XCTAssertEqual(h.unauthorized, 1); XCTAssertNil(a.identity); XCTAssertEqual(h.storage.rows, bytes)
        XCTAssertThrowsError(try h.forward(a)); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testCancelled401RetiresButDoesNotCallCurrentSession() async throws {
        let h = try HostHarness(), a = try h.authority(); h.wire.status = 401
        var task: Task<Void, Never>?
        h.wire.before = { task?.cancel() }
        task = Task { do { _ = try await h.forward(a).send(h.pins(), fence: .init { true }) } catch {} }
        await task?.value
        XCTAssertNil(a.identity); XCTAssertEqual(h.unauthorized, 0)
    }
    func testCancelled200DoesNotRetireAuthority() async throws {
        let h = try HostHarness(), a = try h.authority()
        var task: Task<Void, Never>?
        h.wire.before = { task?.cancel() }
        task = Task { do { _ = try await h.forward(a).send(h.pins(), fence: .init { true }); XCTFail("late 200") } catch {} }
        await task?.value
        XCTAssertNotNil(a.identity); XCTAssertEqual(h.unauthorized, 0)
    }
    func testLate401DoesNotRetireReplacementOriginalSource() async throws {
        let h = try HostHarness(), a = try h.authority(); h.wire.status = 401
        let replacement = HostFixtureSource(try .init(identity: h.source.value.identity, namespace: h.context.session.namespace,
            baseURL: h.context.baseURL, binding: h.binding, authorityRevision: "new-explicit-source-v2", token: h.context.session.token))
        h.wire.before = { h.selected = replacement }
        do { _ = try await h.forward(a).send(h.pins(), fence: .init { true }) } catch {}
        XCTAssertEqual(h.unauthorized, 0); XCTAssertNil(a.identity)
        XCTAssertNoThrow(try replacement.credentials(for: .pins, binding: h.binding))
    }
    func testBoundedUnauthorizedHeaderMatchesOriginalWireWithoutRewritingStatus() {
        XCTAssertTrue(NativeChannelTextService.receivedUnauthorized(data: Data(), status: 401))
        XCTAssertTrue(NativeChannelTextService.receivedUnauthorized(data: Data(#"{"code":401}"#.utf8), status: 200))
        for raw in [#"{"code":200}"#, #"{"code":"401"}"#, #"{"code":true}"#,
                    #"{"code":401.5}"#, #"{"code":401,"errorCode":{}}"#, #"{"code":401"#] {
            XCTAssertFalse(NativeChannelTextService.receivedUnauthorized(data: Data(raw.utf8), status: 200))
        }
        var oversized = Data(#"{"code":401,"padding":""#.utf8)
        oversized.append(Data(repeating: 120, count: 2 * 1024 * 1024)); oversized.append(Data(#""}"#.utf8))
        XCTAssertFalse(NativeChannelTextService.receivedUnauthorized(data: oversized, status: 200))
    }
    func testCode401CurrentCallbackOnceAndSameIssuanceRemountDenied() async throws {
        let h = try HostHarness(), a = try h.authority(); h.wire.bytes = Data(#"{"code":401}"#.utf8)
        let original = try h.command(); try h.journal().saveBeforeDispatch(original); let bytes = h.storage.rows
        do { _ = try await h.forward(a).send(h.pins(), fence: .init { true }); XCTFail("header401") } catch {}
        XCTAssertEqual(h.unauthorized, 1); XCTAssertNil(a.identity); XCTAssertThrowsError(try h.forward(a))
        XCTAssertEqual(h.storage.rows, bytes); XCTAssertEqual(h.wire.status, 200)
    }
    func testCancelledCode401RetiresOriginalButCancelledCode200DoesNot() async throws {
        for rejected in [false, true] {
            let h = try HostHarness(), a = try h.authority()
            h.wire.bytes = Data((rejected ? #"{"code":401}"# : #"{"code":200}"#).utf8)
            var task: Task<Void, Never>?; h.wire.before = { task?.cancel() }
            task = Task { do { _ = try await h.forward(a).send(h.pins(), fence: .init { true }) } catch {} }
            await task?.value
            XCTAssertEqual(a.identity == nil, rejected); XCTAssertEqual(h.unauthorized, 0)
            if rejected { XCTAssertThrowsError(try h.forward(a)) }
        }
    }
    func testLateCode401CannotRetireReplacementOriginalSource() async throws {
        let h = try HostHarness(), a = try h.authority(); h.wire.bytes = Data(#"{"code":401}"#.utf8)
        let replacement = HostFixtureSource(try .init(identity: h.source.value.identity, namespace: h.context.session.namespace,
            baseURL: h.context.baseURL, binding: h.binding, authorityRevision: "new-explicit-source-v2", token: h.context.session.token))
        h.wire.before = { h.selected = replacement }
        do { _ = try await h.forward(a).send(h.pins(), fence: .init { true }) } catch {}
        XCTAssertNil(a.identity); XCTAssertEqual(h.unauthorized, 0)
        XCTAssertNoThrow(try replacement.credentials(for: .pins, binding: h.binding))
    }
    func testTextHeader401RetiresOnlyCapturedIssuanceWhenSameIdentityHasNewGrant() async throws {
        let h = try HostHarness(), c = h.context
        let oldRead = try NativeChannelTextApproval(context: c, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        let oldWrite = try NativeChannelTextApproval(context: c, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        let newRead = try NativeChannelTextApproval(context: c, operation: .receipt, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        let newWrite = try NativeChannelTextApproval(context: c, operation: .send, conversationIDs: [9], expiresAt: Date().addingTimeInterval(300))
        var selectedRead = oldRead, selectedWrite = oldWrite, callbacks = 0
        let transport = NativeChannelTextTransport(context: c, transport: h.wire, current: { c },
            read: { selectedRead }, write: { selectedWrite }, stillCurrent: { true })
        h.wire.bytes = Data(#"{"code":401}"#.utf8)
        h.wire.before = { selectedRead = newRead; selectedWrite = newWrite }
        var request = try AuthRequestBuilder.makeFormRequest(url: c.baseURL.appendingPathComponent("api/im/send"),
            fields: ["conversation_id":"9", "client_message_id":String(repeating: "a", count: 32), "msg_type":"1", "content":"original body"], token: c.session.token)
        request.httpShouldHandleCookies = false
        do { _ = try await transport.send(request, onCurrentUnauthorized: { callbacks += 1 }); XCTFail("header401") } catch {}
        XCTAssertTrue(oldRead.isRevoked); XCTAssertTrue(oldWrite.isRevoked)
        XCTAssertFalse(newRead.isRevoked); XCTAssertFalse(newWrite.isRevoked); XCTAssertEqual(callbacks, 0)
        let replacement = NativeChannelTextTransport(context: c, transport: h.wire, current: { c },
            read: { selectedRead }, write: { selectedWrite }, stillCurrent: { true })
        XCTAssertTrue(replacement.allows(.send, conversationID: 9)); XCTAssertTrue(replacement.allows(.receipt, conversationID: 9))
    }
    func testFinalForwardRejectsUnjournaledWriteAndForeignReceiptWithoutSending() async throws {
        let h = try HostHarness(), a = try h.authority(), f = try h.forward(a)
        var write = h.pins(); write.url = h.context.baseURL.appendingPathComponent("api/im/message/edit")
        write.httpMethod = "POST"; write.setValue("application/json", forHTTPHeaderField: "Content-Type")
        write.httpBody = try JSONSerialization.data(withJSONObject: h.command().body, options: [.sortedKeys])
        do { _ = try await f.send(write, fence: .init { true }); XCTFail("missing journal") } catch {}
        var read = h.pins(); read.url = URL(string: h.context.baseURL.absoluteString + "/api/im/message/request?request_id=foreign_fixture_0001")!
        do { _ = try await f.send(read, fence: .init { true }); XCTFail("foreign request") } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testOriginalWriteIsByteExactAndUnchangedAfterDispatch() async throws {
        let h = try HostHarness(), a = try h.authority(); let original = try h.command(); try h.journal().saveBeforeDispatch(original)
        let bytes = h.storage.rows
        var request = h.pins(); request.url = h.context.baseURL.appendingPathComponent("api/im/message/edit")
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: original.body, options: [.sortedKeys])
        _ = try await h.forward(a).send(request, fence: .init { true })
        XCTAssertEqual(h.wire.requests.first?.httpBody, request.httpBody); XCTAssertEqual(h.storage.rows, bytes)
    }
}

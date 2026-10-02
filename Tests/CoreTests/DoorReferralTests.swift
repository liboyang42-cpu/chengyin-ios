import XCTest
@testable import QuestifyCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class DoorReferralTests: XCTestCase {
    let hex = "abcdef0123456789abcdef0123456789"
    func session(_ id: Int? = 7, restored: Bool = true) -> DoorReferralSession {
        .init(accountID: id, epoch: UUID(), token: id == nil ? nil : "fixture-token", restored: restored)
    }
    func testDecodeExactlyOnceTrimAndLowercase() {
        XCTAssertEqual(DoorParsing.scene("%20ABCDEF0123456789ABCDEF0123456789%20"), hex)
        XCTAssertNil(DoorParsing.scene("%2561bcdef0123456789abcdef0123456789"))
        XCTAssertNil(DoorParsing.scene("%ZZ")); XCTAssertNil(DoorParsing.scene(hex + "0"))
        XCTAssertNil(DoorParsing.scene("ａｂｃｄｅｆ0123456789abcdef0123456789"))
    }
    func testURLSpoofingAndDuplicateQueriesFailClosed() {
        let policy = DoorLinkPolicy(verifiedHTTPSOrigins: ["https://example.test"])
        for raw in ["https://example.test.evil.test/door", "https://example.test@evil.test/door", "http://example.test/door", "https://example.test:443/door", "https://example.test/%64oor", "https://example.test/door?scene=a&scene=b", "https://example.test/door?redirect=https://evil.test", "https://example.test/door#x"] {
            XCTAssertNil(policy.parse(URL(string: raw)!), raw)
        }
        XCTAssertNil(DoorLinkPolicy().parse(URL(string: "https://example.test/door")!))
        let intent = policy.parse(URL(string: "https://example.test/door?scene=%2561bcdef0123456789abcdef0123456789&inviter=&id=4")!)
        XCTAssertEqual(intent?.inviter, ""); XCTAssertNil(DoorParsing.scene(intent?.scene))
    }
    func testTypedDestinationMatrix() throws {
        XCTAssertEqual(DoorScanResult(action: "play", topicID: 2, activityID: 3).destination, .activityPlay(activityID: 3, topicID: 2))
        XCTAssertEqual(DoorScanResult(action: "play", topicID: 2).destination, .topicSelfPlay(topicID: 2))
        XCTAssertEqual(DoorScanResult(action: "purchase", topicID: 2).destination, .topicDetail(topicID: 2))
        XCTAssertNil(DoorScanResult(action: "play", topicID: nil).destination)
        let result = try JSONDecoder().decode(DoorScanResult.self, from: Data(#"{"action":" play ","topicId":"2","activityId":"3","nodeId":true}"#.utf8))
        XCTAssertEqual(result.destination, .activityPlay(activityID: 3, topicID: 2)); XCTAssertNil(result.nodeID)
    }
    func testRestorationWaitThenResolveAndHomeFallback() async {
        let fake = FakeService(); let coordinator = DoorEntryCoordinator(session: session(nil, restored: false), service: fake)
        coordinator.receive(.init(scene: hex, inviter: nil)); await coordinator.resolve()
        XCTAssertEqual(fake.scanCalls, 0); XCTAssertNotNil(coordinator.pending)
        coordinator.updateSession(session()); await coordinator.resolve()
        XCTAssertEqual(coordinator.destination, .topicSelfPlay(topicID: 42))
        coordinator.receive(.init(scene: "bad", inviter: nil)); await coordinator.resolve()
        XCTAssertEqual(coordinator.destination, .home); XCTAssertEqual(fake.scanCalls, 1)
    }
    func testNewSceneSuppressesStaleResult() async {
        let fake = FakeService(); let coordinator = DoorEntryCoordinator(session: session(), service: fake)
        coordinator.receive(.init(scene: hex, inviter: nil))
        fake.scanHook = { coordinator.receive(.init(scene: "new-invalid", inviter: nil)) }
        await coordinator.resolve(); XCTAssertNil(coordinator.destination)
        await coordinator.resolve(); XCTAssertEqual(coordinator.destination, .home)
    }
    func testAccountChangeCancelsResolvedAccountIntent() async {
        let fake = FakeService(); let coordinator = DoorEntryCoordinator(session: session(), service: fake)
        coordinator.receive(.init(scene: hex, inviter: nil))
        fake.scanHook = { coordinator.updateSession(self.session(8)) }
        await coordinator.resolve(); XCTAssertNil(coordinator.destination); XCTAssertNil(coordinator.pending)
    }
    func testFailurePreservesServerTextWithHome() async {
        let fake = FakeService(); fake.scanError = .rejected("exact server failure")
        let coordinator = DoorEntryCoordinator(session: session(), service: fake)
        coordinator.receive(.init(scene: hex, inviter: nil)); await coordinator.resolve()
        XCTAssertEqual(coordinator.destination, .home); XCTAssertEqual(coordinator.failure, "exact server failure")
    }
    func testGuestClaimIsPersistedBeforeSend() async throws {
        var scope = session(nil); let store = MemoryStore(); let fake = FakeService()
        let queue = DoorReferralQueue(store: store, service: fake, currentSession: { scope })
        try queue.capture(" 0009 "); scope = session()
        fake.bindHook = { XCTAssertEqual(store.value.accounts["7"]?.owner, 7); XCTAssertEqual(store.value.accounts["7"]?.status, .attempting); XCTAssertNil(store.value.guest) }
        try await queue.replay(); XCTAssertEqual(store.value.accounts["7"]?.status, .bound)
    }
    func testInterruptedBindingCannotReplayForAnotherAccount() async throws {
        var scope = session(); let store = MemoryStore(); let fake = FakeService()
        let queue = DoorReferralQueue(store: store, service: fake, currentSession: { scope })
        try queue.capture("9"); fake.bindHook = { scope = self.session(8) }
        do { try await queue.replay(); XCTFail() } catch {}
        XCTAssertEqual(store.value.accounts["7"]?.status, .unknown)
        try await queue.replay(); XCTAssertEqual(fake.bindCalls, 1)
        scope = session(7)
        do { try await queue.replay(); XCTFail() } catch { XCTAssertEqual(error as? DoorReferralFailure, .alreadyAttempted) }
    }
    func testStorageFailurePreventsSend() async throws {
        let scope = session(); let store = MemoryStore(); let fake = FakeService()
        let queue = DoorReferralQueue(store: store, service: fake, currentSession: { scope })
        try queue.capture("9"); store.failSave = true
        do { try await queue.replay(); XCTFail() } catch {}
        XCTAssertEqual(fake.bindCalls, 0)
    }
    func testNoLegacyGlobalBoundFlagAndSelfRejected() async throws {
        let scope = session(); let store = MemoryStore(); let fake = FakeService()
        let queue = DoorReferralQueue(store: store, service: fake, currentSession: { scope })
        XCTAssertThrowsError(try queue.capture("0007")); XCTAssertThrowsError(try queue.capture("0"))
        try await queue.manualBind("9")
        XCTAssertThrowsError(try queue.capture("10")); XCTAssertEqual(fake.bindCalls, 1)
    }
    func testDefaultAdapterGatesPerformNoTransport() async throws {
        let scope = session(); let transport = RecordingTransport()
        let service = DoorReferralService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: transport, currentSession: { scope })
        do { _ = try await service.scan(code: hex, session: scope); XCTFail() } catch { XCTAssertEqual(error as? DoorReferralFailure, .disabled) }
        do { try await service.bind(inviter: 9, session: scope); XCTFail() } catch { XCTAssertEqual(error as? DoorReferralFailure, .disabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testExactMultipartScanAndInviterContracts() async throws {
        let scope = session(); let transport = RecordingTransport()
        let service = DoorReferralService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: transport, scanEnabled: true, bindingEnabled: true, currentSession: { scope })
        transport.body = #"{"code":200,"data":{"action":"play","topicId":42}}"#
        let result = try await service.scan(code: hex, session: scope); XCTAssertEqual(result.topicID, 42)
        transport.body = #"{"code":200}"#; try await service.bind(inviter: 9, session: scope)
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/play/scan-entry", "/api/user/setInviter"])
        for request in transport.requests { XCTAssertEqual(request.httpMethod, "POST"); XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary=")); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), scope.token) }
        XCTAssertTrue(String(data: transport.requests[0].httpBody!, encoding: .utf8)!.contains("name=\"code\"\r\n\r\n" + hex))
        XCTAssertTrue(String(data: transport.requests[1].httpBody!, encoding: .utf8)!.contains("name=\"inviter_id\"\r\n\r\n9"))
    }
    func testAdapterRejectsStaleEpochAndMalformedSuccess() async throws {
        var scope = session(); let transport = RecordingTransport(); let original = scope
        let service = DoorReferralService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: transport, scanEnabled: true, bindingEnabled: true, currentSession: { scope })
        scope = session()
        do { _ = try await service.scan(code: hex, session: original); XCTFail() } catch { XCTAssertEqual(error as? DoorReferralFailure, .stale) }
        XCTAssertTrue(transport.requests.isEmpty)
        transport.body = #"{"code":true}"#
        do { try await service.bind(inviter: 9, session: scope); XCTFail() } catch { XCTAssertEqual(error as? DoorReferralFailure, .unknown) }
    }
    func testAttemptingJournalSurvivesRestartWithoutRetry() async throws {
        let scope = session(); let store = MemoryStore(); let fake = FakeService()
        store.value.accounts["7"] = .init(inviter: 9, owner: 7, status: .attempting)
        let bytes = try JSONEncoder().encode(store.value)
        store.value = try JSONDecoder().decode(DoorReferralJournal.self, from: bytes)
        let queue = DoorReferralQueue(store: store, service: fake, currentSession: { scope })
        do { try await queue.replay(); XCTFail() } catch { XCTAssertEqual(error as? DoorReferralFailure, .alreadyAttempted) }
        XCTAssertEqual(fake.bindCalls, 0)
    }
    func testBusyCaptureCannotReplaceInFlightClaim() async throws {
        let scope = session(); let store = MemoryStore(); let fake = FakeService()
        let queue = DoorReferralQueue(store: store, service: fake, currentSession: { scope })
        try queue.capture("9")
        fake.bindHook = {
            XCTAssertThrowsError(try queue.capture("10")) { XCTAssertEqual($0 as? DoorReferralFailure, .busy) }
        }
        try await queue.replay(); XCTAssertEqual(store.value.accounts["7"]?.inviter, 9)
    }
    func testGuestCannotMovePastAlreadyBoundFirstAccount() async throws {
        var scope = session(nil); let store = MemoryStore(); let fake = FakeService()
        store.value.accounts["7"] = .init(inviter: 9, owner: 7, status: .bound)
        let queue = DoorReferralQueue(store: store, service: fake, currentSession: { scope })
        try queue.capture("10"); scope = session(7)
        do { try await queue.replay(); XCTFail() } catch {}
        XCTAssertNil(store.value.guest)
        scope = session(8); try await queue.replay(); XCTAssertEqual(fake.bindCalls, 0)
    }
    func testScanRejectionKeepsMessageDespiteUnrelatedErrorData() async throws {
        let scope = session(); let transport = RecordingTransport()
        transport.body = #"{"code":400,"msg":"server reason","data":"unrelated"}"#
        let service = DoorReferralService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: transport, scanEnabled: true, currentSession: { scope })
        do { _ = try await service.scan(code: hex, session: scope); XCTFail() }
        catch { XCTAssertEqual(error as? DoorReferralFailure, .rejected("server reason")) }
    }
    func testAdapterDiscardsResponseAfterSameAccountNewEpoch() async throws {
        var scope = session(); let original = scope; let transport = RecordingTransport()
        transport.body = #"{"code":200,"data":{"action":"play","topicId":42}}"#
        transport.hook = { scope = self.session(7) }
        let service = DoorReferralService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: transport, scanEnabled: true, currentSession: { scope })
        do { _ = try await service.scan(code: hex, session: original); XCTFail() }
        catch { XCTAssertEqual(error as? DoorReferralFailure, .stale) }
    }

}

@MainActor private final class MemoryStore: DoorReferralStoring {
    var value = DoorReferralJournal(); var failSave = false
    func load() throws -> DoorReferralJournal { value }
    func save(_ value: DoorReferralJournal) throws { if failSave { throw DoorReferralFailure.unknown }; self.value = value }
}
@MainActor private final class FakeService: DoorReferralServing {
    var scanEnabled = true; var bindingEnabled = true
    var scanCalls = 0; var bindCalls = 0
    var scanHook: (() -> Void)?; var bindHook: (() -> Void)?
    var scanError: DoorReferralFailure?
    func scan(code: String, session: DoorReferralSession) async throws -> DoorScanResult {
        scanCalls += 1; scanHook?(); if let scanError { throw scanError }; return .init(action: "play", topicID: 42)
    }
    func bind(inviter: Int, session: DoorReferralSession) async throws { bindCalls += 1; bindHook?() }
}
private final class RecordingTransport: HTTPTransport {
    var requests: [URLRequest] = []; var body = "{}"; var hook: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); hook?(); return (Data(body.utf8), 200) }
}

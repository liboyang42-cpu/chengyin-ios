import XCTest
import Foundation
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ClubOrdinaryAdmissionRecoveryTests: XCTestCase {
    private func marker(original: Bool = true) -> ClubOrdinaryAdmissionPending {
        .init(accountID: 1, clubID: 7, requestID: UUID(), action: .apply, hasOriginalReceipt: original, message: "reviewed")
    }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true) }
    func testJournalReopensExactMarkerAndDifferentInstanceCannotReplaceIt() throws {
        let root = root(), pending = marker()
        let a = ClubOrdinaryAdmissionFileJournal(root: root, namespace: "scope")
        let b = ClubOrdinaryAdmissionFileJournal(root: root, namespace: "scope")
        try a.reserve(pending)
        XCTAssertEqual(try b.pending(accountID: 1, clubID: 7), pending)
        XCTAssertThrowsError(try b.reserve(marker()))
        XCTAssertThrowsError(try b.retire(marker()))
        try b.retire(pending)
        XCTAssertNil(try a.pending(accountID: 1, clubID: 7))
    }
    func testJournalNamespaceAndAccountRemainSeparated() throws {
        let root = root(), pending = marker()
        let a = ClubOrdinaryAdmissionFileJournal(root: root, namespace: "one")
        try a.reserve(pending)
        XCTAssertNil(try a.pending(accountID: 2, clubID: 7))
        XCTAssertNil(try ClubOrdinaryAdmissionFileJournal(root: root, namespace: "two").pending(accountID: 1, clubID: 7))
    }
    func testFailureAfterRenameLeavesOriginalFenceOnReopen() throws {
        let root = root(), pending = marker()
        let interrupted = ClubOrdinaryAdmissionFileJournal(root: root, namespace: "scope", checkpoint: {
            if case .renamed = $0 { throw APIError.notConfigured }
        })
        XCTAssertThrowsError(try interrupted.reserve(pending))
        let reopened = ClubOrdinaryAdmissionFileJournal(root: root, namespace: "scope")
        XCTAssertEqual(try reopened.pending(accountID: 1, clubID: 7), pending)
        XCTAssertThrowsError(try reopened.reserve(marker()))
    }
    func testRestoredOriginalUnknownNeverResendsAndExactReceiptSettlesOnlyOriginal() async throws {
        let pending = marker(), journal = AdmissionMemoryJournal(), store = AdmissionRecoveryStore()
        try journal.reserve(pending)
        let coordinator = ClubActionCoordinator(writer: store, reader: store, journal: journal)
        XCTAssertTrue(coordinator.state(clubID: 7).preventsNewAction)
        store.fact = try fact(pending, state: "UNKNOWN")
        _ = await coordinator.readBack(clubID: 7)
        XCTAssertEqual(try journal.pending(accountID: 1, clubID: 7), pending)
        XCTAssertTrue(coordinator.state(clubID: 7).preventsNewAction)
        store.fact = try fact(pending, state: "APPLIED")
        _ = await coordinator.readBack(clubID: 7)
        XCTAssertNil(try journal.pending(accountID: 1, clubID: 7))
        if case .acknowledged(let value) = coordinator.state(clubID: 7) { XCTAssertEqual(value.state, "pending") } else { XCTFail() }
        XCTAssertEqual(store.writes, 0)
        if case .received(let club) = coordinator.readback(clubID: 7) { XCTAssertFalse(club.isJoined) } else { XCTFail() }
    }
    func testDispatchReservesExactIntentAndRestartNeverAutomaticallyReplays() async throws {
        let journal = AdmissionMemoryJournal(), store = AdmissionRecoveryStore()
        let first = ClubActionCoordinator(writer: store, reader: store, journal: journal)
        let confirmation = try await first.prepare(clubID: 7, action: .apply, expectedIdentity: store.clubIdentity, joinMessage: "reviewed")
        store.beforeWrite = { original in XCTAssertEqual(journal.value, original) }
        _ = await first.confirm(confirmation)
        let held = try XCTUnwrap(journal.value)
        XCTAssertEqual(held.requestID, confirmation.id)
        let restarted = ClubActionCoordinator(writer: store, reader: store, journal: journal)
        XCTAssertTrue(restarted.state(clubID: 7).preventsNewAction)
        do { _ = try await restarted.prepare(clubID: 7, action: .apply, expectedIdentity: store.clubIdentity, joinMessage: "again"); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionBlock, .pendingOperation) }
        XCTAssertEqual(store.writes, 1)
    }
    func testProtocolGrantDoesNotLiftExistingMerchantMembershipGate() async throws {
        let store = AdmissionRecoveryStore(); store.viewerIsMerchant = true
        let coordinator = ClubActionCoordinator(writer: store, reader: store, journal: AdmissionMemoryJournal())
        do { _ = try await coordinator.prepare(clubID: 7, action: .apply, expectedIdentity: store.clubIdentity, joinMessage: "reviewed"); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionBlock, .eligibilityChanged) }
        XCTAssertEqual(store.writes, 0)
    }
    func testLegacyMarkerCurrentMembershipNeverBecomesOriginalReceipt() async throws {
        let pending = marker(original: false), journal = AdmissionMemoryJournal(), store = AdmissionRecoveryStore()
        try journal.reserve(pending)
        let coordinator = ClubActionCoordinator(writer: store, reader: store, journal: journal)
        _ = await coordinator.readBack(clubID: 7)
        XCTAssertTrue(coordinator.state(clubID: 7).preventsNewAction)
        XCTAssertEqual(try journal.pending(accountID: 1, clubID: 7), pending)
        XCTAssertEqual(store.recoveries, 0); XCTAssertEqual(store.writes, 0)
    }
    func testRevokedGrantDisplaysFenceButMakesNoRecoveryOrDetailRequest() async throws {
        let journal = AdmissionMemoryJournal(), store = AdmissionRecoveryStore(); try journal.reserve(marker())
        store.ordinaryAdmissionApproved = false
        let coordinator = ClubActionCoordinator(writer: store, reader: store, journal: journal)
        XCTAssertTrue(coordinator.state(clubID: 7).preventsNewAction)
        let result = await coordinator.readBack(clubID: 7)
        XCTAssertEqual(result, .blocked(.unavailable))
        XCTAssertEqual(store.recoveries, 0); XCTAssertEqual(store.reads, 0); XCTAssertEqual(store.writes, 0)
    }
    func testAccountSwitchDuringRecoveryCannotRetireOldFence() async throws {
        let pending = marker(), journal = AdmissionMemoryJournal(), store = AdmissionRecoveryStore(); try journal.reserve(pending)
        let coordinator = ClubActionCoordinator(writer: store, reader: store, journal: journal)
        store.fact = try fact(pending, state: "APPLIED")
        store.onRecover = { store.clubIdentity = .init(accountID: 2, epoch: 2) }
        let result = await coordinator.readBack(clubID: 7)
        XCTAssertEqual(result, .ignoredStale)
        XCTAssertEqual(try journal.pending(accountID: 1, clubID: 7), pending)
        XCTAssertEqual(store.reads, 0)
    }
    func testOriginalTransportSendsExactHeadersAndOnlyExactAppliedReceiptAcknowledges() async throws {
        let pending = marker(), base = URL(string: "https://example.com/fixture/")!
        let transport = AdmissionClosureTransport { request in
            XCTAssertTrue(ClubOrdinaryAdmissionRoute.accepts(request, baseURL: base))
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Club-Admission-Request-Id"), pending.requestID.uuidString.lowercased())
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Club-Admission-Payload-SHA256"), pending.payloadSHA256)
            return (try self.envelope(pending, state: "APPLIED"), 200)
        }
        let service = ClubActionService(configuration: try APIConfiguration(baseURL: base), transport: transport)
        let result = try await service.perform(.apply, clubID: 7, token: "fixture-token", joinMessage: "reviewed", original: pending)
        XCTAssertEqual(result.state, "pending")
    }
    func testForeignReceiptCannotAcknowledgeOrRecoverOriginal() async throws {
        let pending = marker(), foreign = marker(), base = URL(string: "https://example.com/fixture/")!
        let service = ClubActionService(configuration: try APIConfiguration(baseURL: base), transport: AdmissionClosureTransport { _ in
            (try self.envelope(foreign, state: "APPLIED"), 200)
        })
        do { _ = try await service.perform(.apply, clubID: 7, token: "fixture-token", joinMessage: "reviewed", original: pending); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .outcomeUnknown(.malformedResponse)) }
        do { _ = try await service.recover(pending, token: "fixture-token"); XCTFail() } catch { }
    }
    private func envelope(_ p: ClubOrdinaryAdmissionPending, state: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 200, "data": fields(p, state: state)])
    }
    private func fields(_ p: ClubOrdinaryAdmissionPending, state: String) -> [String: Any] {
        var f: [String: Any] = ["actorMemberId": p.accountID, "clubId": p.clubID, "requestId": p.requestID.uuidString.lowercased(), "action": p.action.rawValue, "state": state, "payloadSHA256": p.payloadSHA256]
        if state == "APPLIED" { f["membershipState"] = "pending" }; return f
    }
    private func fact(_ p: ClubOrdinaryAdmissionPending, state: String) throws -> ClubOrdinaryAdmissionOriginalReceipt {
        try JSONDecoder().decode(ClubOrdinaryAdmissionOriginalReceipt.self, from: JSONSerialization.data(withJSONObject: fields(p, state: state)))
    }
}
@MainActor private final class AdmissionMemoryJournal: ClubOrdinaryAdmissionJournaling {
    var value: ClubOrdinaryAdmissionPending?
    func pending(accountID: Int, clubID: Int) throws -> ClubOrdinaryAdmissionPending? { value?.accountID == accountID && value?.clubID == clubID ? value : nil }
    func reserve(_ value: ClubOrdinaryAdmissionPending) throws { guard self.value == nil else { throw APIError.invalidRequest }; self.value = value }
    func retire(_ value: ClubOrdinaryAdmissionPending) throws { guard self.value == value else { throw APIError.invalidRequest }; self.value = nil }
}
@MainActor private final class AdmissionRecoveryStore: ClubReading, ClubActionWriting {
    var clubIdentity = ClubReadIdentity(accountID: 1, epoch: 1)
    var identity: ClubReadIdentity? { clubIdentity }
    var isConfigured = true, isClubConfigured = true, viewerIsMerchant = false, ordinaryAdmissionApproved = true
    var ordinaryAdmissionApprovalRevision: UUID? = UUID()
    var reads = 0, writes = 0, recoveries = 0
    var fact: ClubOrdinaryAdmissionOriginalReceipt?
    var beforeWrite: ((ClubOrdinaryAdmissionPending?) -> Void)?
    var onRecover: (() -> Void)?
    func clubDetail(id: Int) async throws -> ClubRecord { reads += 1; return try JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":7,\"joinPolicy\":1}".utf8)) }
    func recover(_ pending: ClubOrdinaryAdmissionPending, expectedIdentity: ClubReadIdentity) async throws -> ClubOrdinaryAdmissionOriginalReceipt { recoveries += 1; onRecover?(); return try XCTUnwrap(fact) }
    func perform(_ action: ClubAction, clubID: Int, expectedIdentity: ClubReadIdentity, joinMessage: String) async throws -> ClubActionReceipt { writes += 1; throw ClubActionWriteError.outcomeUnknown(.transport) }
    func perform(_ action: ClubAction, clubID: Int, expectedIdentity: ClubReadIdentity, joinMessage: String, original: ClubOrdinaryAdmissionPending?) async throws -> ClubActionReceipt {
        beforeWrite?(original); writes += 1; throw ClubActionWriteError.outcomeUnknown(.transport)
    }
    func clubHome() async throws -> ClubHome { throw APIError.notConfigured }
    func clubOwned() async throws -> [ClubRecord] { throw APIError.notConfigured }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw APIError.notConfigured }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw APIError.notConfigured }
}
@MainActor private final class AdmissionClosureTransport: HTTPTransport {
    let operation: (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}

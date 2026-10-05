import XCTest
@testable import QuestifyCore

@MainActor final class PublicMerchantReviewHostGateTests: XCTestCase {
    private func target(row: Int = 41, owner: Int = 73) -> PublicMerchantReviewTarget {
        .init(merchantRowID: PublicMerchantRowID(row)!, ownerMemberID: PublicMerchantOwnerID(owner)!)
    }
    private func session(token: String = "fake-session-token", scope: UUID = UUID()) throws -> PublicMerchantReviewSession {
        try .init(accountID: 8, scope: scope, realm: "https://api.example.com/", token: token)
    }
    private func page(registration: Int = 19, eligible: Bool = true) throws -> PublicMerchantReviewPage {
        let raw = """
        {"mode":"public","pageNum":1,"pageSize":20,"total":0,"hasMore":false,"averageRating":null,"eligibility":{"canCreate":\(eligible),"reasonCode":"\(eligible ? "ELIGIBLE" : "ALREADY_REVIEWED")","registrationId":\(registration)},"items":[]}
        """
        return try JSONDecoder().decode(PublicMerchantReviewPage.self, from: Data(raw.utf8))
    }
    func testDefaultWriterBlocksBothReadAndWriteBeforeBaseCalls() async throws {
        let s = try session(), base = Writer(session: nil, value: try page()); base.session = s
        let gate = PublicMerchantReviewGatedWriter(base: base)
        XCTAssertFalse(gate.isConfigured); XCTAssertEqual(gate.session, s)
        do { _ = try await gate.evidence(target(), page: 1, session: s); XCTFail() }
        catch { XCTAssertEqual(error as? PublicMerchantReviewWriteFailure, .notConfigured) }
        do { _ = try await gate.execute(.create(registrationID: 19, rating: 5, content: "Test"), target: target(), requestID: "test-1", session: s); XCTFail() }
        catch { XCTAssertEqual(error as? PublicMerchantReviewWriteFailure, .notConfigured) }
        XCTAssertEqual(base.reads, 0); XCTAssertEqual(base.writes, 0)
    }
    func testEvidenceRequiresExactRowOwnerRegistrationAndSession() throws {
        let store = PublicMerchantReviewImageEvidence(), s = try session()
        try store.record(page(), target: target(), session: s)
        XCTAssertNotNil(store.revision(target: target(), registrationID: 19, session: s))
        XCTAssertNil(store.revision(target: target(row: 8), registrationID: 19, session: s))
        XCTAssertNil(store.revision(target: target(owner: 41), registrationID: 19, session: s))
        XCTAssertNil(store.revision(target: target(), registrationID: 20, session: s))
        XCTAssertNil(store.revision(target: target(), registrationID: 19, session: try session()))
    }
    func testTokenRotationRevokesEligibilityEvenAtSameEpoch() throws {
        let store = PublicMerchantReviewImageEvidence(), s = try session()
        try store.record(page(), target: target(), session: s)
        let rotated = try session(token: "rotated-fake-token", scope: s.scope)
        XCTAssertNil(store.revision(target: target(), registrationID: 19, session: rotated))
    }
    func testRefreshSuspendsAndIdenticalEvidenceRestoresSameRevision() throws {
        let store = PublicMerchantReviewImageEvidence(), s = try session(), value = try page()
        try store.record(value, target: target(), session: s)
        let old = try XCTUnwrap(store.revision(target: target(), registrationID: 19, session: s))
        store.suspend(target()); XCTAssertNil(store.revision(target: target(), registrationID: 19, session: s))
        try store.record(value, target: target(), session: s)
        XCTAssertEqual(store.revision(target: target(), registrationID: 19, session: s), old)
    }
    func testChangedRegistrationOrPermissionRevokesOldSelection() throws {
        let store = PublicMerchantReviewImageEvidence(), s = try session()
        try store.record(page(), target: target(), session: s)
        let old = store.revision(target: target(), registrationID: 19, session: s)
        try store.record(page(registration: 20), target: target(), session: s)
        XCTAssertNil(store.revision(target: target(), registrationID: 19, session: s))
        XCTAssertNotEqual(store.revision(target: target(), registrationID: 20, session: s), old)
        try store.record(page(registration: 20, eligible: false), target: target(), session: s)
        XCTAssertNil(store.revision(target: target(), registrationID: 20, session: s))
    }
    func testInvalidatedEvidenceNeverReactivatesOldRevision() throws {
        let store = PublicMerchantReviewImageEvidence(), s = try session()
        try store.record(page(), target: target(), session: s)
        let old = store.revision(target: target(), registrationID: 19, session: s)
        store.invalidate(); XCTAssertNil(store.revision(target: target(), registrationID: 19, session: s))
        try store.record(page(), target: target(), session: s)
        XCTAssertNotEqual(store.revision(target: target(), registrationID: 19, session: s), old)
    }
    func testEnabledWrapperRejectsSessionChangingDuringEvidence() async throws {
        let s = try session(), base = Writer(session: nil, value: try page()); base.session = s
        base.rotateDuringRead = true
        var recorded = 0
        let gate = PublicMerchantReviewGatedWriter(base: base, enabled: true, record: { _, _, _ in recorded += 1 })
        do { _ = try await gate.evidence(target(), page: 1, session: s); XCTFail() }
        catch { XCTAssertEqual(error as? PublicMerchantReviewWriteFailure, .sessionChanged) }
        XCTAssertEqual(recorded, 0)
    }
    func testDispatchSuspendsEligibilityBeforeUnknownResult() async throws {
        let s = try session(), base = Writer(session: nil, value: try page()); base.session = s
        var discarded = false
        let gate = PublicMerchantReviewGatedWriter(base: base, enabled: true, discard: { _ in discarded = true })
        do { _ = try await gate.execute(.create(registrationID: 19, rating: 5, content: "Test"), target: target(), requestID: "test-2", session: s); XCTFail() }
        catch { XCTAssertEqual(error as? PublicMerchantReviewWriteFailure, .unknown) }
        XCTAssertTrue(discarded); XCTAssertEqual(base.writes, 1)
    }
    @MainActor private final class Writer: PublicMerchantReviewWriting {
        let isConfigured = true
        var session: PublicMerchantReviewSession?
        let value: PublicMerchantReviewPage
        var reads = 0, writes = 0
        var rotateDuringRead = false
        init(session: PublicMerchantReviewSession?, value: PublicMerchantReviewPage) { self.session = session; self.value = value }
        func evidence(_ target: PublicMerchantReviewTarget, page: Int, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewPage {
            reads += 1; if rotateDuringRead { self.session = nil }; return value
        }
        func execute(_ command: PublicMerchantReviewCommand, target: PublicMerchantReviewTarget, requestID: String, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewReceipt {
            writes += 1; throw PublicMerchantReviewWriteFailure.unknown
        }
    }
}

import Foundation
import XCTest
@testable import Questify

@MainActor private final class ReconciliationDisplayQuery: ClubCommunityPendingOutcomeQuerying {
    var allowsAuthoritativeQueries: Bool { true }
    var beforeReturn: (() throws -> Void)?
    func queryOutcome(for record: ClubCommunityPendingRecord, session: ClubCommunitySession,
                      check: () throws -> Void) async throws -> ClubCommunityPendingQueryResult {
        try check(); try beforeReturn?()
        return .resolved(.acknowledged(operationID: record.operationID))
    }
}
@MainActor private final class ReconciliationDisplayTransport: ClubCommunityOfflineTransport {
    var requests: [URLRequest] = []
    var beforeReturn: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeReturn?()
        return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
    }
}
@MainActor private final class ReconciliationDisplayHarness {
    var session: ClubCommunitySession
    let query = ReconciliationDisplayQuery()
    let transport = ReconciliationDisplayTransport()
    let journal = ClubCommunityInMemoryPendingJournal()
    let target: ClubCommunityPendingTarget
    let original: ClubCommunityPendingRecord
    var model: ClubCommunityViewModel!
    init() throws {
        session = try .init(identity: .init(accountID: 5, epoch: 1), token: "synthetic-token")
        let evidence = ClubCommunityEvidence(identity: session.identity, clubID: 10, joined: true, owner: false, administrator: false)
        target = try .init(evidence: evidence, namespace: "display-tests")
        original = try .init(target: target, operationID: UUID(), operationKind: "create", phase: .sending)
        try journal.recordBeforeSend(original)
        let service = ClubCommunityService(offlineBaseURL: URL(string: "https://display-tests.invalid")!, transport: transport)
        let coordinator = ClubCommunityCoordinator(service: service, currentSession: { [unowned self] in self.session }, refreshEvidence: { $0 }, journal: journal, namespace: { "display-tests" }, outcomeQuery: query)
        model = ClubCommunityViewModel(context: .init(service: service, currentSession: { [unowned self] in self.session }, coordinator: coordinator, evidence: { [unowned self] club, post, comment in
            .init(identity: self.session.identity, clubID: club, joined: true, owner: false, administrator: false, post: post, comment: comment)
        }))
    }
}
@MainActor final class ClubCommunityReconciliationLifetimeTests: XCTestCase {
    func testInvalidatedVisitCannotRestoreOldUnknownBannerOrRecord() async throws {
        let h = try ReconciliationDisplayHarness()
        h.query.beforeReturn = { [unowned h] in h.model.invalidate() }
        await h.model.reconcilePending(clubID: 10, refresh: .posts(clubID: 10, page: 1))
        XCTAssertNil(h.model.pendingRecord); XCTAssertNil(h.model.notice)
        XCTAssertTrue(h.transport.requests.isEmpty); XCTAssertFalse(h.model.busy)
        XCTAssertEqual(try h.journal.record(for: h.target)?.operationID, h.original.operationID)
    }
    func testAccountSwitchDoesNotLaunchOldRefreshOrOverwriteNewPresentation() async throws {
        let h = try ReconciliationDisplayHarness()
        h.query.beforeReturn = { [unowned h] in
            h.session = try .init(identity: .init(accountID: 8, epoch: 2), token: "new-synthetic-token")
            h.model.invalidate(); h.model.notice = "new-owner-message"
        }
        await h.model.reconcilePending(clubID: 10, refresh: .posts(clubID: 10, page: 1))
        XCTAssertEqual(h.model.notice, "new-owner-message"); XCTAssertNil(h.model.pendingRecord)
        XCTAssertTrue(h.transport.requests.isEmpty)
        XCTAssertEqual(try h.journal.record(for: h.target)?.operationID, h.original.operationID)
    }
    func testValidOriginalRefreshesAndShowsOriginalOutcome() async throws {
        let h = try ReconciliationDisplayHarness()
        await h.model.reconcilePending(clubID: 10, refresh: .posts(clubID: 10, page: 1))
        XCTAssertNil(try h.journal.record(for: h.target))
        XCTAssertEqual(h.transport.requests.count, 1)
        XCTAssertEqual(h.model.notice, "club.community.refreshRequired")
        XCTAssertNotNil(h.model.snapshot); XCTAssertFalse(h.model.busy)
    }
    func testInvalidationDuringRefreshDoesNotReintroduceSuccessBanner() async throws {
        let h = try ReconciliationDisplayHarness()
        h.transport.beforeReturn = { [unowned h] in h.model.invalidate() }
        await h.model.reconcilePending(clubID: 10, refresh: .posts(clubID: 10, page: 1))
        // The authoritative original was resolved before the later display invalidation.
        XCTAssertNil(try h.journal.record(for: h.target))
        XCTAssertNil(h.model.snapshot); XCTAssertNil(h.model.notice)
        XCTAssertEqual(h.transport.requests.count, 1)
    }
}

import XCTest
@testable import QuestifyCore

@MainActor private final class PublicReviewFakeWriter: PublicMerchantReviewWriting {
    var isConfigured = true
    var session: PublicMerchantReviewSession?
    var failUnknown = false
    var commands: [PublicMerchantReviewCommand] = []
    var requestIDs: [String] = []
    var canCreate = true
    var afterDispatch: (() -> Void)?
    init() throws { session = try .init(accountID: 8, scope: UUID(), realm: "fixture", token: "fixture-token") }
    func evidence(_ target: PublicMerchantReviewTarget, page: Int, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewPage {
        let text = "{\"mode\":\"public\",\"pageNum\":1,\"pageSize\":20,\"total\":0,\"hasMore\":false,\"eligibility\":{\"canCreate\":\(canCreate),\"reasonCode\":\"\(canCreate ? "ELIGIBLE" : "UNAVAILABLE")\",\"registrationId\":19},\"items\":[]}"
        return try JSONDecoder().decode(PublicMerchantReviewPage.self, from: Data(text.utf8))
    }
    func execute(_ command: PublicMerchantReviewCommand, target: PublicMerchantReviewTarget, requestID: String, session: PublicMerchantReviewSession) async throws -> PublicMerchantReviewReceipt {
        commands.append(command); requestIDs.append(requestID)
        afterDispatch?()
        if failUnknown { throw PublicMerchantReviewWriteFailure.unknown }
        return try JSONDecoder().decode(PublicMerchantReviewReceipt.self, from: Data(#"{"reviewId":7,"status":"PENDING_REVIEW","version":0,"replayed":false,"auditTaskId":9}"#.utf8))
    }
}
@MainActor final class PublicMerchantReviewWriteTests: XCTestCase {
    private let target = PublicMerchantReviewTarget(merchantRowID: PublicMerchantRowID(73)!, ownerMemberID: PublicMerchantOwnerID(41)!)
    private let command = PublicMerchantReviewCommand.create(registrationID: 19, rating: 5, content: "Fixture review")
    func testCreateExactBodyAndSourceLengthLimits() throws {
        let body = try command.body(target: target, requestID: "fixture-id")
        XCTAssertEqual(Set(body.keys), Set(["merchantRowId", "registrationId", "rating", "content", "imageUrls", "requestId"]))
        XCTAssertEqual(body["merchantRowId"] as? Int, 73); XCTAssertEqual(body["imageUrls"] as? [String], [])
        XCTAssertThrowsError(try PublicMerchantReviewCommand.create(registrationID: 19, rating: 5, content: "x").body(target: target, requestID: "id"))
        XCTAssertNoThrow(try PublicMerchantReviewCommand.create(registrationID: 19, rating: 5, content: String(repeating: "x", count: 1000)).body(target: target, requestID: "id"))
    }
    func testReportUsesOwnerNotRowAndRequiresVersion() throws {
        let body = try PublicMerchantReviewCommand.report(reviewID: 9, expectedVersion: 2, reason: "Fixture reason").body(target: target, requestID: "fixture-id")
        XCTAssertEqual(body["merchantMemberId"] as? Int, 41); XCTAssertNil(body["merchantRowId"])
        XCTAssertEqual(body["expectedVersion"] as? Int, 2)
    }
    func testPrepareNeverWritesAndConfirmUsesSameRequestID() async throws {
        let writer = try PublicReviewFakeWriter(); let journal = MerchantBusinessMemoryIntentStore()
        let coordinator = PublicMerchantReviewCoordinator(writer: writer, journal: journal)
        await coordinator.prepare(command, target: target, page: 1)
        let review = try XCTUnwrap(coordinator.confirmation)
        XCTAssertTrue(writer.commands.isEmpty)
        await coordinator.confirm(review)
        XCTAssertEqual(writer.requestIDs, [review.requestID]); XCTAssertEqual(coordinator.receipt?.status, "PENDING_REVIEW")
        XCTAssertTrue(try journal.intents().isEmpty)
    }
    func testChangedEligibilityStopsBeforeDispatch() async throws {
        let writer = try PublicReviewFakeWriter(); let coordinator = PublicMerchantReviewCoordinator(writer: writer, journal: MerchantBusinessMemoryIntentStore())
        await coordinator.prepare(command, target: target, page: 1); let review = try XCTUnwrap(coordinator.confirmation)
        writer.canCreate = false; await coordinator.confirm(review)
        XCTAssertTrue(writer.commands.isEmpty); XCTAssertEqual(coordinator.failure, .permissionChanged)
    }
    func testUnknownPersistsAcrossNewCoordinatorAndBlocksDuplicate() async throws {
        let writer = try PublicReviewFakeWriter(); writer.failUnknown = true
        let journal = MerchantBusinessMemoryIntentStore(); let first = PublicMerchantReviewCoordinator(writer: writer, journal: journal)
        await first.prepare(command, target: target, page: 1); await first.confirm(try XCTUnwrap(first.confirmation))
        XCTAssertTrue(first.locked); XCTAssertEqual(try journal.intents().count, 1)
        let second = PublicMerchantReviewCoordinator(writer: writer, journal: journal)
        await second.prepare(command, target: target, page: 1)
        XCTAssertNil(second.confirmation); XCTAssertTrue(second.locked); XCTAssertEqual(writer.commands.count, 1)
    }
    func testChangedSessionAndCancelledReviewNeverDispatch() async throws {
        let writer = try PublicReviewFakeWriter(); let coordinator = PublicMerchantReviewCoordinator(writer: writer, journal: MerchantBusinessMemoryIntentStore())
        await coordinator.prepare(command, target: target, page: 1); let review = try XCTUnwrap(coordinator.confirmation)
        coordinator.cancel(); await coordinator.confirm(review); XCTAssertTrue(writer.commands.isEmpty)
        await coordinator.prepare(command, target: target, page: 1); let next = try XCTUnwrap(coordinator.confirmation)
        writer.session = nil; await coordinator.confirm(next); XCTAssertTrue(writer.commands.isEmpty)
    }
    func testReportReceiptCannotBeShownAsDeletion() throws {
        let receipt = try JSONDecoder().decode(PublicMerchantReviewReceipt.self, from: Data(#"{"reviewId":9,"status":"PENDING_PLATFORM_REVIEW","replayed":false,"auditTaskId":4}"#.utf8))
        XCTAssertNoThrow(try receipt.validate(.report(reviewID: 9, expectedVersion: 2, reason: "Fixture reason")))
        XCTAssertThrowsError(try receipt.validate(.report(reviewID: 8, expectedVersion: 2, reason: "Fixture reason")))
        XCTAssertThrowsError(try receipt.validate(command))
    }
    func testUnknownSurvivesFileStoreReconstruction() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("intents.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = try PublicReviewFakeWriter(); writer.failUnknown = true
        let first = PublicMerchantReviewCoordinator(writer: writer, journal: MerchantBusinessFileIntentStore(url: url))
        await first.prepare(command, target: target, page: 1)
        await first.confirm(try XCTUnwrap(first.confirmation))
        let second = PublicMerchantReviewCoordinator(writer: writer, journal: MerchantBusinessFileIntentStore(url: url))
        await second.prepare(command, target: target, page: 1)
        XCTAssertTrue(second.locked); XCTAssertNil(second.confirmation); XCTAssertEqual(writer.commands.count, 1)
        let bytes = try String(contentsOf: url)
        XCTAssertFalse(bytes.contains("fixture-token")); XCTAssertFalse(bytes.contains("Fixture review"))
    }
    func testSessionChangeAfterDispatchDoesNotUnlockOrExposeReceipt() async throws {
        let writer = try PublicReviewFakeWriter(); let journal = MerchantBusinessMemoryIntentStore()
        let coordinator = PublicMerchantReviewCoordinator(writer: writer, journal: journal)
        await coordinator.prepare(command, target: target, page: 1)
        writer.afterDispatch = { writer.session = nil }
        await coordinator.confirm(try XCTUnwrap(coordinator.confirmation))
        XCTAssertNil(coordinator.receipt); XCTAssertTrue(coordinator.locked); XCTAssertEqual(try journal.intents().count, 1)
    }

}

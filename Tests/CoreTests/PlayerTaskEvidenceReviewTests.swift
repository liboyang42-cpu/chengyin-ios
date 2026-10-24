import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class PlayerTaskEvidenceReviewTests: XCTestCase {
    @MainActor private final class Owner {
        var value: PlayExperienceSession?
        init() throws { value = try .init(accountID: 1, epoch: 1, namespace: "evidence-review-tests", token: "synthetic-token") }
    }
    private func setup(enabled: Set<PlayExperienceCapability> = [.reads, .playerCommands]) async throws -> (Owner, EvidenceReviewTransport, PlayPlayerGameCoordinator, PlayerTaskEvidenceTarget) {
        let owner = try Owner(), transport = EvidenceReviewTransport()
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport, enabled: enabled)
        let model = PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { owner.value })
        await model.load(); return (owner, transport, model, try model.evidenceTarget(nodeID: 701))
    }
    func testPreparedScanFreezesExactExistingCommandWithoutSending() async throws {
        let (_, transport, model, target) = try await setup()
        let context = try model.captureEvidenceReview(target)
        let review = try model.prepareEvidenceReview(context, scan: "  A + / 中文  ")
        XCTAssertEqual(review.command.nodeID, 701); XCTAssertEqual(review.command.expectedRevision, 2)
        XCTAssertEqual(review.command.payload["evidenceUrls"]?.array?.first?.text, try PlayPlayerCommand.textEvidence("A + / 中文", scan: true))
        XCTAssertEqual(transport.posts, 0); XCTAssertEqual(transport.reads, 1)
    }
    func testSameRevisionDifferentTaskProjectionCannotBorrowReview() async throws {
        let (_, transport, model, target) = try await setup()
        let context = try model.captureEvidenceReview(target)
        let review = try model.prepareEvidenceReview(context, scan: "Synthetic")
        transport.projection = transport.projection.replacingOccurrences(of: "Write a synthetic observation", with: "Replacement prompt")
        await model.load(); XCTAssertFalse(model.acceptsEvidenceReview(context))
        await model.submitEvidenceReview(review); XCTAssertEqual(transport.posts, 0)
    }
    func testAccountEpochReplacementBeforeDispatchRejectsOldPreparedValue() async throws {
        let (owner, transport, model, target) = try await setup()
        let context = try model.captureEvidenceReview(target)
        let review = try model.prepareEvidenceReview(context, scan: "Synthetic")
        owner.value = try .init(accountID: 1, epoch: 2, namespace: "evidence-review-tests", token: "synthetic-token")
        XCTAssertFalse(model.ownsEvidenceReview(context)); await model.submitEvidenceReview(review)
        XCTAssertEqual(transport.posts, 0)
    }
    func testAppliedReceiptRequiresExistingFreshProjectionAndPreventsOldReviewReuse() async throws {
        let (_, transport, model, target) = try await setup()
        let review = try model.prepareEvidenceReview(model.captureEvidenceReview(target), scan: "Synthetic")
        await model.submitEvidenceReview(review)
        XCTAssertEqual(transport.posts, 1); XCTAssertEqual(transport.reads, 2)
        XCTAssertEqual(model.receipt?.requestID, review.command.requestID); XCTAssertEqual(model.phase, "ready")
        XCTAssertEqual(model.projection?.revision, 3); XCTAssertNil(model.pending)
        await model.submitEvidenceReview(review); XCTAssertEqual(transport.posts, 1)
    }
    func testUnknownKeepsOriginalPendingRequestAndDoesNotSendAgain() async throws {
        let (_, transport, model, target) = try await setup(); transport.fail = true
        let review = try model.prepareEvidenceReview(model.captureEvidenceReview(target), scan: "Synthetic")
        await model.submitEvidenceReview(review); await model.submitEvidenceReview(review)
        XCTAssertEqual(model.phase, "unknown"); XCTAssertEqual(model.pending?.requestID, review.command.requestID)
        XCTAssertEqual(transport.posts, 1); XCTAssertEqual(transport.reads, 1)
    }
    func testDisabledCommandCapabilityNeverExpandsTransport() async throws {
        let (_, transport, model, target) = try await setup(enabled: [.reads])
        let review = try model.prepareEvidenceReview(model.captureEvidenceReview(target), scan: "Synthetic")
        await model.submitEvidenceReview(review)
        XCTAssertEqual(transport.posts, 0); XCTAssertEqual(model.phase, "disabled")
    }
}

private final class EvidenceReviewTransport: HTTPTransport {
    var projection = PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "\"inputType\":\"TEXT\"", with: "\"inputType\":\"SCAN\"")
    var reads = 0, posts = 0
    var fail = false
    @MainActor func send(_ request: URLRequest) async throws -> (Data, Int) {
        if request.httpMethod == "POST" {
            posts += 1
            if fail { throw PlayExperienceError.unknownResult }
            let body = try JSONDecoder().decode(PlayWireValue.self, from: try XCTUnwrap(request.httpBody))
            projection = projection.replacingOccurrences(of: "\"revision\":2", with: "\"revision\":3")
            let receipt: PlayWireValue = .object(["activityId": .int(41), "requestId": body["requestId"], "action": body["action"], "outcome": .string("APPLIED"), "revision": .int(3), "receiptId": .int(1), "result": .object([:])])
            return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": receipt])), 200)
        }
        reads += 1; return (PlayExperienceSyntheticFixtures.envelope(projection), 200)
    }
}

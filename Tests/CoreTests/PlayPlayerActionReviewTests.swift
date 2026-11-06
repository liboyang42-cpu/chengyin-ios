import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class PlayPlayerActionReviewTests: XCTestCase {
    @MainActor private final class Owner {
        var session: PlayExperienceSession?
        init() throws { session = try .init(accountID: 1, epoch: 1, namespace: "five-action-tests", token: "synthetic-token") }
    }
    private func setup(raw: String = PlayExperienceSyntheticFixtures.player, capabilities: Set<PlayExperienceCapability> = [.reads, .playerCommands]) async throws -> (Owner, PlayerActionWire, PlayPlayerGameCoordinator) {
        let owner = try Owner(), wire = PlayerActionWire(raw: raw)
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire, enabled: capabilities)
        let model = PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { owner.session })
        await model.load(); return (owner, wire, model)
    }
    func testRoleConfirmationFreezesPublicRoleWithoutSending() async throws {
        let (_, wire, model) = try await setup(raw: PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "\"confirmed\":true", with: "\"confirmed\":false"))
        let value = try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .role)
        XCTAssertEqual(value.command.action, .confirmRole); XCTAssertNil(value.command.nodeID); XCTAssertTrue(value.command.payload.isEmpty)
        XCTAssertEqual(value.title, "Synthetic observer"); XCTAssertEqual(value.question, "Synthetic role brief"); XCTAssertEqual(wire.posts, 0)
    }
    func testTextReviewPreservesExactInputAndOriginalWireEncoding() async throws {
        let (_, wire, model) = try await setup(); let answer = " A + / 中文 "
        let value = try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .text(nodeID: 701, answer: answer))
        XCTAssertEqual(value.detail, answer); XCTAssertEqual(value.question, "Write a synthetic observation")
        XCTAssertEqual(value.command.payload["taskCode"]?.text, "OBSERVE")
        XCTAssertEqual(value.command.payload["evidenceUrls"]?.array?.first?.text, try PlayPlayerCommand.textEvidence(answer)); XCTAssertEqual(wire.posts, 0)
    }
    func testChoiceReviewPinsIDAndActualVisibleLabel() async throws {
        let (_, _, model) = try await setup()
        let value = try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .choice(nodeID: 701, choiceID: "LEFT"))
        XCTAssertEqual(value.detail, "Synthetic left path"); XCTAssertEqual(value.command.payload, ["choiceId": .string("LEFT")])
        XCTAssertThrowsError(try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .choice(nodeID: 701, choiceID: "OTHER")))
    }
    func testHintAndRevealKeepDifferentExactConsequencesAndPayloads() async throws {
        let (_, _, model) = try await setup(); let context = try model.capturePlayerActionReview()
        let hint = try model.preparePlayerActionReview(context, intent: .hint(nodeID: 701))
        let reveal = try model.preparePlayerActionReview(context, intent: .reveal(nodeID: 701))
        XCTAssertEqual(hint.hintLevel, 1); XCTAssertEqual(hint.command.payload, ["level": .int(1)])
        XCTAssertEqual(hint.consequence, "Synthetic score cap may change")
        XCTAssertEqual(reveal.consequence, "Synthetic assisted completion gives zero puzzle score"); XCTAssertTrue(reveal.command.payload.isEmpty)
        XCTAssertNil(reveal.hintLevel); XCTAssertNotEqual(hint.command.action, reveal.command.action)
    }
    func testTextPathCannotAdoptPhotoScanOrDifferentNodeTasks() async throws {
        for kind in ["PHOTO", "SCAN"] {
            let (_, wire, model) = try await setup(raw: PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "\"inputType\":\"TEXT\"", with: "\"inputType\":\"\(kind)\""))
            XCTAssertThrowsError(try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .text(nodeID: 701, answer: "Synthetic")))
            XCTAssertEqual(wire.posts, 0)
        }
        let (_, _, model) = try await setup(); XCTAssertThrowsError(try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .hint(nodeID: 999)))
    }
    func testPausedMissingActionsAndMissingImpactRejectWithoutDispatch() async throws {
        for raw in [PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "\"personalState\":\"ACTIVE\"", with: "\"personalState\":\"PAUSED\""),
                    PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "\"PLAYER_HINT\",", with: ""),
                    PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "Synthetic score cap may change", with: "")] {
            let (_, wire, model) = try await setup(raw: raw)
            XCTAssertThrowsError(try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .hint(nodeID: 701))); XCTAssertEqual(wire.posts, 0)
        }
    }
    func testFullSnapshotChangeBeforeDispatchRejectsStaleReview() async throws {
        let (_, wire, model) = try await setup(); let value = try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .choice(nodeID: 701, choiceID: "LEFT"))
        wire.raw = wire.raw.replacingOccurrences(of: "Synthetic left path", with: "Changed meaning"); await model.load()
        XCTAssertFalse(model.acceptsPlayerActionReview(value)); await model.submitPlayerActionReview(value); XCTAssertEqual(wire.posts, 0)
    }
    func testCanonicallyEqualButByteDifferentDisplayedLabelRejectsOldReview() async throws {
        let (_, wire, model) = try await setup(raw: PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "Synthetic left path", with: "Café"))
        let value = try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .choice(nodeID: 701, choiceID: "LEFT"))
        wire.raw = wire.raw.replacingOccurrences(of: "Café", with: "Cafe\u{301}"); await model.load()
        XCTAssertFalse(model.acceptsPlayerActionReview(value)); await model.submitPlayerActionReview(value); XCTAssertEqual(wire.posts, 0)
    }
    func testAccountEpochChangeNeverSendsOldPreparedCommand() async throws {
        let (owner, wire, model) = try await setup(); let value = try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .text(nodeID: 701, answer: "Synthetic"))
        owner.session = try .init(accountID: 1, epoch: 2, namespace: "five-action-tests", token: "synthetic-token")
        await model.submitPlayerActionReview(value); XCTAssertEqual(wire.posts, 0)
    }
    func testAppliedReceiptStillRequiresFreshReadBeforeNextAction() async throws {
        let (_, wire, model) = try await setup(); let value = try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .choice(nodeID: 701, choiceID: "LEFT"))
        await model.submitPlayerActionReview(value)
        XCTAssertEqual(wire.posts, 1); XCTAssertEqual(wire.reads, 2); XCTAssertEqual(model.receipt?.requestID, value.command.requestID)
        XCTAssertEqual(model.projection?.revision, 3); XCTAssertEqual(model.phase, "ready"); XCTAssertFalse(model.acceptsPlayerActionReview(value))
    }
    func testUnknownRetainsOriginalRequestAndPreventsNewSubmission() async throws {
        let (_, wire, model) = try await setup(); wire.fail = true
        let value = try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .hint(nodeID: 701))
        await model.submitPlayerActionReview(value); await model.submitPlayerActionReview(value)
        XCTAssertEqual(wire.posts, 1); XCTAssertEqual(model.phase, "unknown"); XCTAssertEqual(model.pending?.requestID, value.command.requestID)
        XCTAssertThrowsError(try model.capturePlayerActionReview())
    }
    func testReadOnlyCapabilityCannotBecomeCommandGrant() async throws {
        let (_, wire, model) = try await setup(capabilities: [.reads])
        let value = try model.preparePlayerActionReview(model.capturePlayerActionReview(), intent: .reveal(nodeID: 701))
        await model.submitPlayerActionReview(value); XCTAssertEqual(wire.posts, 0); XCTAssertEqual(model.phase, "disabled")
    }
}
private final class PlayerActionWire: HTTPTransport {
    var raw: String, posts = 0, reads = 0, fail = false
    init(raw: String) { self.raw = raw }
    @MainActor func send(_ request: URLRequest) async throws -> (Data, Int) {
        if request.httpMethod == "POST" {
            posts += 1; if fail { throw PlayExperienceError.unknownResult }
            let body = try JSONDecoder().decode(PlayWireValue.self, from: try XCTUnwrap(request.httpBody))
            raw = raw.replacingOccurrences(of: "\"revision\":2", with: "\"revision\":3")
            let receipt: PlayWireValue = .object(["activityId": .int(41), "requestId": body["requestId"], "action": body["action"], "outcome": .string("APPLIED"), "revision": .int(3), "receiptId": .int(1)])
            return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": receipt])), 200)
        }
        reads += 1; return (PlayExperienceSyntheticFixtures.envelope(raw), 200)
    }
}

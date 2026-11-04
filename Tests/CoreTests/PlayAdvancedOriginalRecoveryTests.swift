import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Scripted HTTP responses only. These tests do not start a server, authorize a
/// device, execute a real game action, or claim process-death persistence.
@available(macOS 14.0, *)
@MainActor final class PlayAdvancedOriginalRecoveryTests: XCTestCase {
    private let startPath = "/api/play/advanced/start"
    private let actionPath = "/api/play/advanced/action"
    private let statePath = "/api/play/advanced/state"
    private func owner(_ account: Int = 7, epoch: UInt64 = 1) throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: epoch, namespace: "synthetic-l5", token: "synthetic-token")
    }
    private func state(version: Int = 2, sessionID: Int = 601) -> Data {
        PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.advanced
            .replacingOccurrences(of: "\"version\":2", with: "\"version\":\(version)")
            .replacingOccurrences(of: "\"sessionId\":601", with: "\"sessionId\":\(sessionID)"))
    }
    private func rejected(_ code: Int) -> PlayRecoveryRecordingTransport.Response {
        .reply(Data("{\"code\":\(code),\"msg\":\"Synthetic rejected request\"}".utf8), 200)
    }
    private func model(_ wire: PlayRecoveryRecordingTransport, current: @escaping () -> PlayExperienceSession?) throws -> PlayAdvancedCoordinator {
        .init(activityID: 41, topicID: 71, nodeID: 701,
              service: .init(configuration: try .init(baseURL: URL(string: "https://example.test")!),
                             transport: wire, enabled: [.reads, .advanced]), currentSession: current)
    }
    private func opened() async throws -> (PlayAdvancedCoordinator, PlayRecoveryRecordingTransport, PlayExperienceSession) {
        let session = try owner(), wire = PlayRecoveryRecordingTransport()
        wire.responses[startPath] = .reply(state(), 200)
        wire.responses[actionPath] = .failure(.unknownResult)
        wire.responses[statePath] = .reply(state(version: 3), 200)
        let player = try model(wire, current: { session })
        await player.start()
        XCTAssertEqual(player.phase, "ready")
        return (player, wire, session)
    }
    private func makeUnknown(_ player: PlayAdvancedCoordinator, _ wire: PlayRecoveryRecordingTransport) async throws -> (PlayAdvancedPending, Data) {
        let review = try player.review(kind: "coinFlip", action: "FLIP_COIN")
        let accepted = await player.submit(review)
        XCTAssertFalse(accepted); XCTAssertEqual(player.phase, "unknown")
        let pending = try XCTUnwrap(player.pending)
        return (pending, try XCTUnwrap(wire.requests.last?.httpBody))
    }
    private func actions(_ wire: PlayRecoveryRecordingTransport) -> [URLRequest] {
        wire.requests.filter { $0.url?.path == actionPath }
    }

    func testStateReadBusinessErrorsCannotReleaseUnknownOriginal() async throws {
        for code in [403, 404, 409, 422, 500] {
            let (player, wire, _) = try await opened()
            let (original, bytes) = try await makeUnknown(player, wire)
            wire.responses[statePath] = rejected(code)
            await player.recover()
            XCTAssertEqual(player.pending, original); XCTAssertEqual(player.phase, "unknown")
            XCTAssertTrue(player.blocksReadRebinding); XCTAssertFalse(player.canInteract)
            XCTAssertThrowsError(try player.review(kind: "coinFlip", action: "FLIP_COIN"))
            await player.start(); await player.submit(kind: "coinFlip", action: "FLIP_COIN"); await player.completeUnit()
            XCTAssertEqual(actions(wire).count, 1); XCTAssertEqual(actions(wire).first?.httpBody, bytes)
            XCTAssertEqual(wire.requests.last?.httpMethod, "GET")
            XCTAssertEqual(wire.requests.last?.url?.path, statePath)
        }
    }
    func testDisabledStateReaderCannotTurnUnknownActionIntoFreshAttempt() async throws {
        let (player, wire, _) = try await opened(), (original, _) = try await makeUnknown(player, wire)
        wire.responses[statePath] = .failure(.disabled)
        await player.recover(); await player.retryExact()
        XCTAssertEqual(player.pending, original); XCTAssertEqual(player.phase, "unknown")
        XCTAssertTrue(player.blocksReadRebinding); XCTAssertEqual(actions(wire).count, 1)
    }
    func testMalformedMissingAndTransportFailuresPreserveExactPending() async throws {
        let failures: [PlayRecoveryRecordingTransport.Response] = [
            .reply(PlayExperienceSyntheticFixtures.envelope("null"), 200), .reply(Data("broken".utf8), 200),
            .reply(Data(), 503), .failure(.unknownResult)]
        for failure in failures {
            let (player, wire, _) = try await opened(), (original, _) = try await makeUnknown(player, wire)
            wire.responses[statePath] = failure
            await player.recover()
            XCTAssertEqual(player.pending, original); XCTAssertEqual(player.phase, "unknown")
            XCTAssertEqual(actions(wire).count, 1)
        }
    }
    func testForeignSessionOrOlderVersionReadCannotResolveOriginal() async throws {
        for raw in [state(version: 3, sessionID: 999), state(version: 1)] {
            let (player, wire, _) = try await opened(), (original, _) = try await makeUnknown(player, wire)
            wire.responses[statePath] = .reply(raw, 200)
            await player.recover()
            XCTAssertEqual(player.pending, original); XCTAssertEqual(player.phase, "unknown")
            XCTAssertEqual(actions(wire).count, 1)
        }
    }
    func testVersionAdvancementOnlyOffersExplicitOriginalReplay() async throws {
        let (player, wire, _) = try await opened(), (original, bytes) = try await makeUnknown(player, wire)
        await player.recover()
        XCTAssertEqual(player.pending, original); XCTAssertEqual(player.phase, "retryable")
        XCTAssertEqual(player.state?.version, 3); XCTAssertFalse(player.canInteract)
        XCTAssertEqual(actions(wire).count, 1); XCTAssertEqual(actions(wire).first?.httpBody, bytes)
        await player.refreshAuthoritative(); await player.start()
        XCTAssertEqual(actions(wire).count, 1)
    }
    func testReplayBusinessErrorCannotDiscardPriorPossiblyCommittedAction() async throws {
        for code in [403, 404, 409, 500] {
            let (player, wire, _) = try await opened(), (original, bytes) = try await makeUnknown(player, wire)
            await player.recover(); wire.responses[actionPath] = rejected(code)
            await player.retryExact()
            XCTAssertEqual(player.pending, original); XCTAssertEqual(player.phase, "unknown")
            XCTAssertEqual(actions(wire).count, 2)
            XCTAssertTrue(actions(wire).allSatisfy { $0.httpBody == bytes })
            XCTAssertFalse(player.canInteract); XCTAssertTrue(player.blocksReadRebinding)
            await player.retryExact()
            XCTAssertEqual(actions(wire).count, 2, "A failed replay requires a fresh state read before another explicit replay")
        }
    }
    func testReplayDisabledPreservesKeyAndNeverOpensNewSubmission() async throws {
        let (player, wire, _) = try await opened(), (original, bytes) = try await makeUnknown(player, wire)
        await player.recover(); wire.responses[actionPath] = .failure(.disabled)
        await player.retryExact()
        XCTAssertEqual(player.pending, original); XCTAssertEqual(player.phase, "unknown")
        XCTAssertEqual(actions(wire).count, 2); XCTAssertTrue(actions(wire).allSatisfy { $0.httpBody == bytes })
        await player.submit(kind: "coinFlip", action: "FLIP_COIN")
        XCTAssertEqual(actions(wire).count, 2)
    }
    func testHealthyReadAndSuccessfulOriginalReplayResolveAfterEarlierReadAndReplayFailures() async throws {
        let (player, wire, _) = try await opened(), (original, bytes) = try await makeUnknown(player, wire)
        wire.responses[statePath] = rejected(404); await player.recover()
        wire.responses[statePath] = .reply(state(version: 3), 200); await player.recover()
        wire.responses[actionPath] = rejected(409); await player.retryExact()
        XCTAssertEqual(player.pending, original)
        await player.recover()
        wire.responses[actionPath] = .reply(state(version: 3), 200); await player.retryExact()
        XCTAssertNil(player.pending); XCTAssertEqual(player.phase, "ready")
        XCTAssertEqual(player.state?.version, 3); XCTAssertTrue(player.canInteract)
        XCTAssertEqual(actions(wire).count, 3); XCTAssertTrue(actions(wire).allSatisfy { $0.httpBody == bytes })
        let body = try JSONDecoder().decode(PlayWireValue.self, from: bytes)
        XCTAssertEqual(body["idempotencyKey"].text, original.key)
        XCTAssertEqual(body["version"].integer, original.version)
        XCTAssertEqual(body["action"].text, original.action)
        XCTAssertEqual(body["payload"].object, original.payload)
    }
    func testUnauthorizedRecoveryRetainsPendingAndRetiresVisibleSurface() async throws {
        let responses: [PlayRecoveryRecordingTransport.Response] = [.reply(Data(), 401), rejected(401)]
        for response in responses {
            let (player, wire, _) = try await opened(), (original, _) = try await makeUnknown(player, wire)
            wire.responses[statePath] = response; await player.recover()
            XCTAssertEqual(player.pending, original); XCTAssertEqual(player.phase, "stale")
            XCTAssertFalse(player.canInteract); XCTAssertNil(player.objectCardReceipt)
            await player.start(); await player.retryExact()
            XCTAssertEqual(actions(wire).count, 1)
        }
    }
    func testFirstDefiniteBusinessRejectionRetainsExistingSemantics() async throws {
        let (player, wire, _) = try await opened()
        wire.responses[actionPath] = rejected(422)
        await player.submit(kind: "coinFlip", action: "FLIP_COIN")
        XCTAssertNil(player.pending); XCTAssertEqual(player.phase, "rejected")
        XCTAssertEqual(actions(wire).count, 1)
        await player.refreshAuthoritative()
        XCTAssertEqual(player.phase, "ready"); XCTAssertEqual(actions(wire).count, 1)
    }
    func testStateErrorWithNoPendingStillUsesOriginalRejectionPath() async throws {
        let (player, wire, _) = try await opened()
        wire.responses[statePath] = rejected(403)
        await player.refreshAuthoritative()
        XCTAssertNil(player.pending); XCTAssertEqual(player.phase, "rejected")
        XCTAssertTrue(actions(wire).isEmpty)
    }
    func testAccountOrEpochReplacementCannotRecoverOrReplayOriginal() async throws {
        var current: PlayExperienceSession? = try owner()
        let wire = PlayRecoveryRecordingTransport()
        wire.responses[startPath] = .reply(state(), 200); wire.responses[actionPath] = .failure(.unknownResult)
        wire.responses[statePath] = .reply(state(version: 3), 200)
        let player = try model(wire, current: { current }); await player.start()
        let (original, _) = try await makeUnknown(player, wire)
        for replacement in [try owner(8), try owner(epoch: 2)] {
            current = replacement
            await player.recover(); await player.retryExact(); await player.refreshAuthoritative(); await player.start()
            XCTAssertEqual(player.pending, original); XCTAssertFalse(player.isCurrent)
            XCTAssertEqual(wire.requests.count, 2)
        }
    }
    func testUnknownStartStillCannotBeRepeatedWithoutARealLookupContract() async throws {
        let session = try owner(), wire = PlayRecoveryRecordingTransport()
        wire.responses[startPath] = .failure(.unknownResult)
        let player = try model(wire, current: { session })
        await player.start(); await player.start(); await player.recover(); await player.retryExact()
        XCTAssertTrue(player.startOutcomeUnknown); XCTAssertTrue(player.blocksReadRebinding)
        XCTAssertNil(player.pending); XCTAssertEqual(wire.requests.count, 1)
    }
}

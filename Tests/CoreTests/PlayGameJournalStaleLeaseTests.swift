import XCTest
@testable import QuestifyCore

@available(macOS 14.0, *)
@MainActor final class PlayGameJournalStaleLeaseTests: XCTestCase {
    func testStaleReaderCannotClearOrOverwriteReplacementGameCommand() async throws {
        let anchors = PlayDurableRecoveryTests.Anchors(), blobs = PlayDurableRecoveryTests.Blobs()
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic-game-cas", token: "synthetic-token")
        let key = PlayRunStorageKey.make(session: session, scope: .activity(41))
        let first = try PlayDurableRecovery(owner: .init(session: session), key: key, anchors: anchors, ciphertexts: blobs, processID: UUID())
        let stale = try PlayDurableRecovery(owner: .init(session: session), key: key, anchors: anchors, ciphertexts: blobs, processID: UUID())
        func pending(_ id: String, choice: String) throws -> PlayPendingGameCommand {
            let command = try PlayPlayerCommand(activityID: 41, nodeID: 701, requestID: id, expectedRevision: 4,
                action: .choice, payload: ["choiceId": .string(choice)])
            return try PlayPendingGameCommand(command: command, session: session, sessionID: 501)
        }
        let a = try pending("original-a", choice: "LEFT"), b = try pending("replacement-b", choice: "RIGHT")
        let original = try await first.recordGameCommand(a, key: key)
        let loaded = try await stale.readGameCommand(key)
        let oldLease = try XCTUnwrap(loaded)
        XCTAssertEqual(oldLease, original)
        try await first.clearGameCommand(original, key: key)
        let replacement = try await first.recordGameCommand(b, key: key)
        do {
            try await stale.clearGameCommand(oldLease, key: key)
            XCTFail("A stale generation must not clear the replacement")
        } catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
        do {
            _ = try await stale.recordGameCommand(a, key: key)
            XCTFail("An occupied game slot must not be overwritten")
        } catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
        let kept = try await first.readGameCommand(key)
        XCTAssertEqual(kept, replacement); XCTAssertEqual(kept?.value, b)
    }
}

import XCTest
@testable import QuestifyCore

/// Synthetic durable metadata only. No location, account service, credentials or HTTP.
@MainActor final class PersonalLocationShareIdentityRecoveryTests: XCTestCase {
    private func scope(_ owner: Int64 = 1, realm: String = "synthetic.invalid/public-migration", epoch: UInt64 = 1) throws -> PersonalLocationShareScope {
        try .init(namespace: realm, accountId: owner, epoch: epoch)
    }
    private func record(_ scope: PersonalLocationShareScope) throws -> PersonalLocationSharePendingRecord {
        try .init(scope: scope, request: .init(
            requestKey: "10000000-0000-4000-8000-000000000021", recipientId: 2,
            policyId: "SYNTHETIC_NOT_APPROVAL", policyVersion: 1, policyDigest: String(repeating: "a", count: 64),
            modeChoiceId: "test-exact", durationChoiceId: "test-duration", foregroundOnly: true,
            acknowledgedDisclosures: PersonalLocationShareDisclosure.allCases))
    }
    func testUnknownOriginalIdentitySurvivesRestartAndNewEpoch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try record(scope())
        try PersonalLocationShareFileJournal(directory: directory).put(original, scope: scope())
        let restarted = PersonalLocationShareFileJournal(directory: directory)
        let recovered = try restarted.records(scope: scope(epoch: 9))
        XCTAssertEqual(recovered, [original])
        XCTAssertNil(recovered.first?.serverRequestHash)
        XCTAssertEqual(recovered.first?.request.requestKey, original.id)
    }
    func testReplacementAccountCannotReadOrRewriteOriginalUnknownRequest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = PersonalLocationShareFileJournal(directory: directory)
        let original = try record(scope())
        try journal.put(original, scope: scope())
        XCTAssertTrue(try journal.records(scope: scope(3, epoch: 2)).isEmpty)
        XCTAssertThrowsError(try journal.put(original, scope: scope(3, epoch: 2)))
        XCTAssertEqual(try journal.records(scope: scope(epoch: 3)), [original])
    }
    func testRealmSwitchCannotConsumeOriginalUnknownRequest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = PersonalLocationShareFileJournal(directory: directory)
        let original = try record(scope())
        try journal.put(original, scope: scope())
        let other = try scope(realm: "synthetic.invalid/other-realm", epoch: 2)
        XCTAssertTrue(try journal.records(scope: other).isEmpty)
        XCTAssertThrowsError(try journal.put(original, scope: other))
        XCTAssertEqual(try journal.records(scope: scope()), [original])
    }
    func testStickyStopAndOriginalHashPersistAcrossIdentityReturn() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = PersonalLocationShareFileJournal(directory: directory)
        var stopped = try record(scope())
        stopped.stopRequested = true; stopped.serverRequestHash = "original-request-hash"
        try journal.put(stopped, scope: scope())
        XCTAssertTrue(try journal.records(scope: scope(3)).isEmpty)
        let restored = try journal.records(scope: scope(epoch: 4))
        XCTAssertEqual(restored, [stopped])
        var replay = stopped; replay.stopRequested = false
        XCTAssertThrowsError(try journal.put(replay, scope: scope(epoch: 4)))
        XCTAssertEqual(try journal.records(scope: scope(epoch: 5)), [stopped])
    }
}

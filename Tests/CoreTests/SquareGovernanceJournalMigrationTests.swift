import XCTest
@testable import QuestifyCore

@MainActor final class SquareGovernanceJournalMigrationTests: XCTestCase {
    private func key(_ identity: SquareGovernanceIdentity) -> String {
        "square.governance.dispatch.\(identity.namespace.utf8.count):\(identity.namespace):\(identity.accountID)"
    }
    func testPersistedOldDeleteLockBlocksLegacyPrepareAndConfirmAfterRelogin() async throws {
        let suite = "square-journal-old-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let access = SquareGovernanceSyntheticAccess(), transport = SquareGovernanceSyntheticTransport()
        let identity = try XCTUnwrap(access.identity)
        defaults.set(["delete:62"], forKey: key(identity))
        let journal = SquareGovernanceJournal(defaults: defaults)
        let service = SquareGovernanceService(offlineBaseURL: URL(string: "https://example.com")!, transport: transport)
        let coordinator = SquareGovernanceCoordinator(service: service, journal: journal)
        let snapshot = try await coordinator.load(access: access)
        XCTAssertThrowsError(try coordinator.prepare(.deleteOwnComment(commentID: 62), snapshot: snapshot, access: access)) { XCTAssertEqual($0 as? SquareGovernanceFailure, .outcomeLocked) }
        let oldReview = SquareGovernanceReview(snapshot: snapshot, action: .deleteOwnComment(commentID: 62), now: Date())
        do { _ = try await coordinator.confirm(oldReview, access: access); XCTFail() } catch { XCTAssertEqual(error as? SquareGovernanceFailure, .outcomeLocked) }
        XCTAssertFalse(transport.requests.contains { $0.httpMethod != "GET" })
        XCTAssertEqual(Set(defaults.stringArray(forKey: key(identity)) ?? []), ["delete:62", "delete:legacySquare:62"])
        let replacement = SquareGovernanceJournal(defaults: defaults)
        let relogin = SquareGovernanceIdentity(accountID: identity.accountID, epoch: identity.epoch + 1, namespace: identity.namespace)
        XCTAssertTrue(replacement.contains("delete:legacySquare:62", identity: relogin))
        XCTAssertFalse(replacement.claim("delete:legacySquare:62", identity: relogin))
    }
    func testOldDeleteKeyDoesNotBlockEqualCommunityIDOrOtherAccountNamespace() throws {
        let suite = "square-journal-scope-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let identity = SquareGovernanceIdentity(accountID: 11, epoch: 1, namespace: "test")
        defaults.set(["delete:62"], forKey: key(identity))
        let journal = SquareGovernanceJournal(defaults: defaults)
        XCTAssertFalse(journal.contains("delete:communityV1:62", identity: identity))
        XCTAssertTrue(journal.claim("delete:communityV1:62", identity: identity))
        XCTAssertFalse(journal.contains("delete:legacySquare:62", identity: .init(accountID: 12, epoch: 1, namespace: "test")))
        XCTAssertFalse(journal.contains("delete:legacySquare:62", identity: .init(accountID: 11, epoch: 1, namespace: "other")))
        XCTAssertTrue(journal.contains("delete:legacySquare:62", identity: identity))
    }
}

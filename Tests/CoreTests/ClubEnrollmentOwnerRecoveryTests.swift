import XCTest
@testable import QuestifyCore

@MainActor final class ClubEnrollmentOwnerRecoveryTests: XCTestCase {
    func testChangedIdentityDuringRefreshClearsPreviouslyAcceptedRosterAndBusyState() async {
        let access = ClubGovernanceFixtureAccess()
        let reader = ClubEnrollmentReader(clubID: 81, focusTopicID: 91, access: access)
        await reader.activate(identity: access.identity)
        XCTAssertNotNil(reader.rosters[91])
        access.onRead = { access.identity = .init(accountID: 702, epoch: 2) }
        await reader.refresh()
        XCTAssertTrue(reader.teams.isEmpty); XCTAssertTrue(reader.rosters.isEmpty)
        XCTAssertFalse(reader.loading); XCTAssertFalse(reader.hasLoaded)
        XCTAssertEqual(reader.failure, .staleReview); XCTAssertTrue(access.sent.isEmpty)
    }

    func testExplicitReadDenialClearsButServerFailurePreservesStaleSnapshot() async {
        for code in [401, 403, 503] {
            let access = ClubGovernanceFixtureAccess()
            let reader = ClubEnrollmentReader(clubID: 81, focusTopicID: 91, access: access)
            await reader.activate(identity: access.identity)
            access.readFailure = .rejected(code: code, message: nil)
            await reader.refresh()
            XCTAssertEqual(reader.hasLoaded, code == 503)
            XCTAssertEqual(reader.rosters.isEmpty, code != 503)
            XCTAssertFalse(reader.loading); XCTAssertTrue(access.sent.isEmpty)
        }
    }

    func testPresentationInvalidationRequiresFreshReadButTemporaryPushSuspensionDoesNot() async {
        let access = ClubGovernanceFixtureAccess()
        var reads = 0; access.onRead = { reads += 1 }
        let reader = ClubEnrollmentReader(clubID: 81, focusTopicID: 91, access: access)
        await reader.activate(identity: access.identity)
        let acceptedReads = reads
        reader.suspend(); await reader.activate(identity: access.identity)
        XCTAssertEqual(reads, acceptedReads); XCTAssertNotNil(reader.rosters[91])
        reader.invalidatePresentation()
        XCTAssertTrue(reader.teams.isEmpty); XCTAssertTrue(reader.rosters.isEmpty)
        XCTAssertTrue(reader.expanded.isEmpty); XCTAssertFalse(reader.hasLoaded)
        await reader.activate(identity: access.identity)
        XCTAssertGreaterThan(reads, acceptedReads); XCTAssertNotNil(reader.rosters[91])
        XCTAssertTrue(access.sent.isEmpty)
    }

    func testChangedNamespaceBeforeDetailActionRetiresWithoutAnotherRead() async {
        let access = ClubGovernanceFixtureAccess()
        var reads = 0; access.onRead = { reads += 1 }
        let reader = ClubEnrollmentReader(clubID: 81, focusTopicID: 91, access: access)
        await reader.activate(identity: access.identity)
        let acceptedReads = reads
        access.storageNamespace = "different-deployment"
        await reader.toggle(topicID: 91); await reader.loadDetail(topicID: 91)
        XCTAssertEqual(reads, acceptedReads); XCTAssertTrue(reader.rosters.isEmpty)
        XCTAssertTrue(reader.teams.isEmpty); XCTAssertFalse(reader.hasLoaded)
        XCTAssertEqual(reader.failure, .staleReview); XCTAssertTrue(access.sent.isEmpty)
    }
}

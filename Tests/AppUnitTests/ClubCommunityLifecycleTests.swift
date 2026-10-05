import XCTest
import Combine
@testable import Questify

@MainActor final class ClubCommunityLifecycleTests: XCTestCase {
    func testSuspendingNavigationKeepsThePostThatOwnsTheDestination() async throws {
        let model = try ClubCommunityViewModel(context: ClubCommunityFixture.context())
        await model.load(.posts(clubID: 10, page: 1))
        XCTAssertEqual(model.snapshot?.posts.map(\.id), [20, 21])
        model.suspend()
        XCTAssertEqual(model.snapshot?.posts.map(\.id), [20, 21])
        XCTAssertFalse(model.loading)
    }

    func testIdentityInvalidationStillRemovesPrivatePosts() async throws {
        let model = try ClubCommunityViewModel(context: ClubCommunityFixture.context())
        await model.load(.posts(clubID: 10, page: 1))
        model.suspend()
        model.invalidate()
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.review)
        XCTAssertNil(model.notice)
    }

    func testSuspendingDiscardsUnreviewedDraftAndAllowsFreshRead() async throws {
        let model = try ClubCommunityViewModel(context: ClubCommunityFixture.context())
        await model.load(.posts(clubID: 10, page: 1))
        model.stageDraft(.create(content: "Discarded local draft", images: []), clubID: 10, post: nil)
        model.suspend()
        await model.reviewPendingDraft()
        XCTAssertNil(model.review)
        await model.load(.posts(clubID: 10, page: 1))
        XCTAssertEqual(model.snapshot?.posts.map(\.id), [20, 21])
    }
}

#if DEBUG
@MainActor final class ClubFixtureIdentityLifecycleTests: XCTestCase {
    func testCompanionIdentityIsReadyBeforeTheFirstRenderForEveryScenario() {
        let scenarios: [ClubFixtureScenario] = [.owner, .member, .visitor, .administrator, .empty, .retry,
            .forbidden, .guest, .missingMembers, .customerOwner, .customerAdministrator, .customerDenied]
        for scenario in scenarios {
            let reader = ClubFixtureReader(scenario: scenario)
            XCTAssertEqual(reader.profileReader.identity.accountID, reader.clubIdentity.accountID)
            XCTAssertEqual(reader.profileReader.identity.epoch, reader.clubIdentity.epoch)
            XCTAssertEqual(reader.governanceAccess.identity, reader.clubIdentity)
            XCTAssertFalse(reader.governanceAccess.allowsOfflineWrites)
            XCTAssertEqual(reader.governanceAccess.readFailure, scenario == .customerDenied ? .forbidden : nil)
        }
    }

    func testCompanionsAreSynchronizedBeforeIdentityPublicationAndRemainStableAcrossABA() {
        let reader = ClubFixtureReader(scenario: .customerOwner)
        let profile = reader.profileReader
        let governance = reader.governanceAccess
        var revisions: [UInt64] = []
        let observation = reader.$clubIdentity.sink { identity in
            XCTAssertEqual(profile.identity.accountID, identity.accountID)
            XCTAssertEqual(profile.identity.epoch, identity.epoch)
            XCTAssertEqual(governance.identity, identity)
            XCTAssertFalse(governance.allowsOfflineWrites)
            revisions.append(identity.epoch)
        }
        reader.switchAccount()
        XCTAssertEqual(reader.clubIdentity.accountID, 702)
        reader.switchAccount()
        XCTAssertEqual(reader.clubIdentity.accountID, 701)
        reader.signOut()
        XCTAssertNil(reader.profileReader.identity.accountID)
        reader.signIn()
        XCTAssertTrue(reader.profileReader === profile)
        XCTAssertTrue(reader.governanceAccess === governance)
        XCTAssertEqual(revisions, [0, 1, 2, 3, 4])
        withExtendedLifetime(observation) {}
    }

    func testDeniedFixtureStaysDeniedAfterAccountChanges() {
        let reader = ClubFixtureReader(scenario: .customerDenied)
        reader.switchAccount()
        reader.signOut()
        reader.signIn()
        XCTAssertEqual(reader.governanceAccess.readFailure, .forbidden)
        XCTAssertFalse(reader.governanceAccess.allowsOfflineWrites)
    }
}
#endif

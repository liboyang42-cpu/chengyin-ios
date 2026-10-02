import XCTest
@testable import Questify

@MainActor final class TeamNoticePresentationTests: XCTestCase {
    func testNoticeSnapshotsReflectCompletedSimulation() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .content)
        let coordinator = environment.makeCoordinator()
        let initial = TeamNotice(coordinator: coordinator)
        await coordinator.loadDetail(.id(4101))
        coordinator.prepare(.leave(teamID: 4101))
        await coordinator.confirm(try XCTUnwrap(coordinator.review))
        XCTAssertEqual(coordinator.writeState, .simulated)
        let completed = TeamNotice(coordinator: coordinator)
        XCTAssertNil(initial.messageKey)
        XCTAssertEqual(completed.messageKey, "team.simulated")
        XCTAssertFalse(completed.hasPending)
    }

    func testUnknownNoticeStaysDistinctFromSimulation() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .unknownOutcome)
        let coordinator = environment.makeCoordinator()
        await coordinator.loadDetail(.id(4101))
        coordinator.prepare(.leave(teamID: 4101))
        await coordinator.confirm(try XCTUnwrap(coordinator.review))
        let notice = TeamNotice(coordinator: coordinator)
        XCTAssertEqual(notice.messageKey, "team.unknown")
        XCTAssertTrue(notice.hasPending)
        XCTAssertEqual(environment.service.submissions.count, 1)
    }

    func testInvalidLinkAndSignOutProduceFreshNoticeValues() async throws {
        let environment = try TeamFixtureEnvironment(scenario: .content)
        let coordinator = environment.makeCoordinator()
        let initial = TeamNotice(coordinator: coordinator)
        await coordinator.loadDetail(.invitation(""))
        XCTAssertNil(initial.messageKey)
        XCTAssertEqual(TeamNotice(coordinator: coordinator).messageKey, "team.invalidLink")
        environment.becomeGuest()
        await coordinator.loadDetail(.id(4101))
        XCTAssertEqual(TeamNotice(coordinator: coordinator).messageKey, "team.signIn")
        XCTAssertNil(coordinator.detail)
    }
}

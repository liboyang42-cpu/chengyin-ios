import XCTest
import SwiftUI
@testable import Questify

@MainActor final class PrivateHomeAppTests: XCTestCase {
    func testAccountEntryHasNoImplicitProductionCoordinator() {
        let link = PrivateHomeAccountLink(coordinator: nil)
        XCTAssertNil(link.coordinator)
        _ = link.body // Unconfigured entry builds unavailable content; no service or location provider.
    }
    func testSyntheticFixtureUnknownOutcomeCanBeRecoveredWithoutNewRequest() async throws {
        let owner = try PlayExperienceSession(accountID: 12, epoch: 1, namespace: "fixture-private", token: "fixture-token")
        let journal = PrivateHomeFixtureJournal(owner: owner), service = PrivateHomeFixtureService()
        service.lost = true
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: { owner })
        await model.load()
        model.prepareSet(label: "Synthetic", point: try PrivateHomePoint(latitude: 12.345, longitude: 45.678))
        await model.confirm(); XCTAssertTrue(model.canRetry); XCTAssertFalse(model.canEdit)
        let request = try XCTUnwrap(journal.value)
        _ = PrivateHomeView(model: model).body
        await model.retryExact()
        XCTAssertEqual(service.version, 1); XCTAssertEqual(service.receipts.count, 1)
        XCTAssertEqual(service.receipts[request.requestId]?.decision, .saved); XCTAssertNil(journal.value)
    }
    func testDeleteReviewCancellationKeepsPrivateHome() async throws {
        let owner = try PlayExperienceSession(accountID: 12, epoch: 1, namespace: "fixture-private", token: "fixture-token")
        let journal = PrivateHomeFixtureJournal(owner: owner), service = PrivateHomeFixtureService()
        service.active = true; service.version = 2
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: { owner })
        await model.load(); model.prepareDelete(); XCTAssertEqual(model.review?.method, "DELETE")
        model.cancelReview(); await model.confirm()
        XCTAssertTrue(service.active); XCTAssertEqual(service.version, 2); XCTAssertNil(journal.value)
    }
}

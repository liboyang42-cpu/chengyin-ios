import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ClubBadgeHostDefaultTests: XCTestCase {
    func testEnvironmentDefaultHasNoBadgeEntryOrFactory() {
        let environment = EnvironmentValues()
        XCTAssertNil(environment.clubBadgeHostFactory(7))
    }
    func testUnconfiguredCompositionDoesNotConstructService() throws {
        let c = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://badge.example")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic"))
        let endpoints = try OperationEndpointApproval(baseURL: c.baseURL, namespace: c.session.namespace,
            accountID: 7, paths: ClubBadgeManagementRoute.paths)
        let approval = try ClubBadgeManagementApproval(endpoints: endpoints, clubIDs: [7], reviewedPolicyVersion: "synthetic", reads: true)
        let root = AppCompositionRoot()
        XCTAssertNil(root.clubBadgeManagementApproval(c))
        XCTAssertNil(root.makeClubBadgeService(context: c, clubID: 7, approval: approval, current: { c }, unauthorized: {}))
    }
}

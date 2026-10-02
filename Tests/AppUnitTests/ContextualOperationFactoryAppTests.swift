import XCTest
@testable import Questify

@MainActor final class ContextualOperationFactoryAppTests: XCTestCase {
    func testShippedContextualFactoriesHaveNoApproval() {
        let dependencies = NativeRuntimeDependencies.dormant
        XCTAssertNil(dependencies.clubOpsTimeApproval)
        XCTAssertNil(dependencies.contextualReviewApproval)
    }
    func testIndependentFactoryInputsAreRetained() throws {
        let endpoints = try OperationEndpointApproval(baseURL: URL(string: "https://example.com")!, namespace: "fixture-cn", accountID: 7,
            paths: ["api/activity/info", "api/club/lead/team-progress", "api/club/lead/edit-ops", "api/comment/add"])
        let time = try ClubOpsTimeApproval(market: .china, endpoints: endpoints, targets: [.init(activityID: 8, clubID: 4)])
        let reviews = try ContextualReviewApproval(market: .china, endpoints: endpoints, targets: [.activity(8)])
        let dependencies = NativeRuntimeDependencies(clubOpsTimeApproval: time, contextualReviewApproval: reviews)
        XCTAssertEqual(dependencies.clubOpsTimeApproval?.targets, time.targets)
        XCTAssertEqual(dependencies.contextualReviewApproval?.targets, reviews.targets)
        XCTAssertNil(dependencies.clubGovernanceApproval)
    }
}

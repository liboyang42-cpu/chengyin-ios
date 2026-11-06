import XCTest
@testable import QuestifyCore

final class NetworkReachabilityAndRetryBackoffAuditTests: XCTestCase {

    func testCanonicalPoliciesPassNetworkRetrySafetyAudit() {
        let policies = NetworkReachabilityAndRetryBackoffAudit.canonicalPolicies
        XCTAssertEqual(policies.count, 4)
        XCTAssertEqual(
            policies.map(\.routeGroup),
            [
                "roam-and-map-reads",
                "commerce-order-mutations",
                "im-message-delivery",
                "club-and-merchant-writes"
            ]
        )

        let result = NetworkReachabilityAndRetryBackoffAudit.evaluate()
        XCTAssertEqual(result.totalPolicies, 4)
        XCTAssertEqual(result.compliantPolicies, 4)
        XCTAssertTrue(result.isNetworkRetrySafe)
        XCTAssertTrue(NetworkReachabilityAndRetryBackoffAudit.ReachabilityState.satisfied.allowsImmediateAutoRetry)
        XCTAssertFalse(NetworkReachabilityAndRetryBackoffAudit.ReachabilityState.unsatisfied.allowsImmediateAutoRetry)
    }

    func testUnkeyedNonIdempotentAutoRetryIsRejected() {
        let unsafeMutationPolicy = NetworkRetryPolicyCheck(
            routeGroup: "commerce-order-mutations",
            isIdempotentOrKeyed: false,
            maxAutoRetries: 1,
            baseDelayMs: 500,
            respectsRetryAfterHeader: true
        )
        XCTAssertFalse(unsafeMutationPolicy.isCompliant)

        let evaluation = NetworkReachabilityAndRetryBackoffAudit.evaluate(
            policies: [unsafeMutationPolicy]
        )
        XCTAssertEqual(evaluation.totalPolicies, 1)
        XCTAssertEqual(evaluation.compliantPolicies, 0)
        XCTAssertFalse(evaluation.isNetworkRetrySafe)
    }

    func testExcessiveMaxAutoRetriesOrOutOfBoundsBackoffDelayIsRejected() {
        let excessiveRetries = NetworkRetryPolicyCheck(
            routeGroup: "roam-and-map-reads",
            isIdempotentOrKeyed: true,
            maxAutoRetries: 4,
            baseDelayMs: 500,
            respectsRetryAfterHeader: true
        )
        XCTAssertFalse(excessiveRetries.isCompliant)

        let negativeRetries = NetworkRetryPolicyCheck(
            routeGroup: "roam-and-map-reads",
            isIdempotentOrKeyed: true,
            maxAutoRetries: -1,
            baseDelayMs: 500,
            respectsRetryAfterHeader: true
        )
        XCTAssertFalse(negativeRetries.isCompliant)

        let tooFastBackoff = NetworkRetryPolicyCheck(
            routeGroup: "roam-and-map-reads",
            isIdempotentOrKeyed: true,
            maxAutoRetries: 2,
            baseDelayMs: 50,
            respectsRetryAfterHeader: true
        )
        XCTAssertFalse(tooFastBackoff.isCompliant)

        let evaluation = NetworkReachabilityAndRetryBackoffAudit.evaluate(
            policies: [excessiveRetries, negativeRetries, tooFastBackoff]
        )
        XCTAssertEqual(evaluation.compliantPolicies, 0)
        XCTAssertFalse(evaluation.isNetworkRetrySafe)
    }

    func testRetryAfterHeaderComplianceAnd429Or503DelayFloor() {
        let ignoresRetryAfter = NetworkRetryPolicyCheck(
            routeGroup: "im-message-delivery",
            isIdempotentOrKeyed: true,
            maxAutoRetries: 2,
            baseDelayMs: 500,
            respectsRetryAfterHeader: false
        )
        XCTAssertFalse(ignoresRetryAfter.isCompliant)

        let delay429 = NetworkReachabilityAndRetryBackoffAudit.effectiveRetryDelaySeconds(
            httpStatusCode: 429,
            retryAfterSecondsHeader: 15,
            attemptIndex: 0,
            baseDelayMs: 500
        )
        XCTAssertEqual(delay429, 15.0)

        let delay503 = NetworkReachabilityAndRetryBackoffAudit.effectiveRetryDelaySeconds(
            httpStatusCode: 503,
            retryAfterSecondsHeader: 1,
            attemptIndex: 2,
            baseDelayMs: 1000
        )
        XCTAssertEqual(delay503, 4.0)
    }
}

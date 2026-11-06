import Foundation

/// Audit descriptor for a route group's retry discipline, idempotency requirement,
/// exponential backoff base delay bounds (`200...2000` ms), and HTTP `429`/`503` `Retry-After` compliance.
public struct NetworkRetryPolicyCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let routeGroup: String
    public let isIdempotentOrKeyed: Bool
    public let maxAutoRetries: Int
    public let baseDelayMs: Int
    public let respectsRetryAfterHeader: Bool

    public init(
        id: String? = nil,
        routeGroup: String,
        isIdempotentOrKeyed: Bool,
        maxAutoRetries: Int,
        baseDelayMs: Int = 500,
        respectsRetryAfterHeader: Bool
    ) {
        self.id = id ?? routeGroup
        self.routeGroup = routeGroup
        self.isIdempotentOrKeyed = isIdempotentOrKeyed
        self.maxAutoRetries = maxAutoRetries
        self.baseDelayMs = baseDelayMs
        self.respectsRetryAfterHeader = respectsRetryAfterHeader
    }

    public var isCompliant: Bool {
        maxAutoRetries >= 0
            && maxAutoRetries <= 3
            && (200...2000).contains(baseDelayMs)
            && respectsRetryAfterHeader
            && (isIdempotentOrKeyed || maxAutoRetries == 0)
    }
}

/// Pure, self-contained audit of `NWPathMonitor` reachability state transitions,
/// idempotent `GET` vs non-idempotent `POST` retry discipline, exponential backoff bounds,
/// and HTTP `429` / `503` `Retry-After` header compliance.
public struct NetworkReachabilityAndRetryBackoffAudit: Sendable, Equatable {
    public enum ReachabilityState: String, CaseIterable, Sendable, Equatable {
        case satisfied
        case unsatisfied
        case requiresConnection

        public var allowsImmediateAutoRetry: Bool {
            self == .satisfied
        }
    }

    public static let canonicalPolicies: [NetworkRetryPolicyCheck] = [
        NetworkRetryPolicyCheck(
            id: "roam-and-map-reads",
            routeGroup: "roam-and-map-reads",
            isIdempotentOrKeyed: true,
            maxAutoRetries: 2,
            baseDelayMs: 400,
            respectsRetryAfterHeader: true
        ),
        NetworkRetryPolicyCheck(
            id: "commerce-order-mutations",
            routeGroup: "commerce-order-mutations",
            isIdempotentOrKeyed: false,
            maxAutoRetries: 0,
            baseDelayMs: 500,
            respectsRetryAfterHeader: true
        ),
        NetworkRetryPolicyCheck(
            id: "im-message-delivery",
            routeGroup: "im-message-delivery",
            isIdempotentOrKeyed: true,
            maxAutoRetries: 2,
            baseDelayMs: 500,
            respectsRetryAfterHeader: true
        ),
        NetworkRetryPolicyCheck(
            id: "club-and-merchant-writes",
            routeGroup: "club-and-merchant-writes",
            isIdempotentOrKeyed: false,
            maxAutoRetries: 0,
            baseDelayMs: 500,
            respectsRetryAfterHeader: true
        )
    ]

    public static func evaluate(
        policies: [NetworkRetryPolicyCheck] = canonicalPolicies
    ) -> (totalPolicies: Int, compliantPolicies: Int, isNetworkRetrySafe: Bool) {
        let total = policies.count
        let compliant = policies.filter(\.isCompliant).count
        let isSafe = total > 0 && compliant == total
        return (totalPolicies: total, compliantPolicies: compliant, isNetworkRetrySafe: isSafe)
    }

    public static func isValidBackoffBaseDelay(ms: Int) -> Bool {
        (200...2000).contains(ms)
    }

    public static func effectiveRetryDelaySeconds(
        httpStatusCode: Int,
        retryAfterSecondsHeader: Int?,
        attemptIndex: Int,
        baseDelayMs: Int = 500
    ) -> Double? {
        guard isValidBackoffBaseDelay(ms: baseDelayMs), attemptIndex >= 0, attemptIndex < 3 else {
            return nil
        }
        let exponentialSeconds = (Double(baseDelayMs) / 1000.0) * pow(2.0, Double(attemptIndex))
        if httpStatusCode == 429 || httpStatusCode == 503 {
            guard let retryAfter = retryAfterSecondsHeader, retryAfter > 0 else {
                return exponentialSeconds
            }
            return max(Double(retryAfter), exponentialSeconds)
        }
        return exponentialSeconds
    }
}

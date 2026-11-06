import Foundation

/// Bidirectional like transition audited for `I05` (`POST /api/topic/like`).
public enum AuditedTopicLikeDirection: String, CaseIterable, Equatable, Sendable {
    case like = "LIKE"
    case unlike = "UNLIKE"

    public var signedDelta: Int {
        switch self {
        case .like:
            return 1
        case .unlike:
            return -1
        }
    }

    public func optimisticCount(from initialCount: Int) -> Int {
        max(0, initialCount + signedDelta)
    }
}

/// Probe representing a square post's HTTP/status state and its cached media URLs (`I05`).
public struct SquarePostMediaEvictionSample: Equatable, Sendable {
    public let postID: String
    public let httpStatusCode: Int
    public let lifecycleStatus: String
    public let attachedMediaURLs: [String]
    public let evictedFromURLCacheURLs: [String]

    public init(
        postID: String,
        httpStatusCode: Int = 200,
        lifecycleStatus: String = "PUBLISHED",
        attachedMediaURLs: [String],
        evictedFromURLCacheURLs: [String]
    ) {
        self.postID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.httpStatusCode = httpStatusCode
        self.lifecycleStatus = lifecycleStatus.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.attachedMediaURLs = attachedMediaURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.evictedFromURLCacheURLs = evictedFromURLCacheURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// True when the post returned HTTP 404 or a deleted/takedown status requiring immediate media eviction.
    public var requiresImmediateMediaEviction: Bool {
        httpStatusCode == 404 ||
            lifecycleStatus == "DELETED" ||
            lifecycleStatus == "REMOVED" ||
            lifecycleStatus == "TAKEDOWN"
    }

    /// Media URLs that remained in `URLCache` despite the post being `404` or `DELETED`.
    public var unevictedMediaURLs: [String] {
        guard requiresImmediateMediaEviction else { return [] }
        let evictedSet = Set(evictedFromURLCacheURLs)
        return attachedMediaURLs.filter { !evictedSet.contains($0) }.sorted()
    }
}

/// Sample of a topic like interaction and server settle revalidation (`I05`).
public struct TopicLikeInteractionAuditSample: Equatable, Sendable {
    public let topicID: String
    public let direction: AuditedTopicLikeDirection
    public let initialCount: Int
    public let recordedDelta: Int
    public let settledCount: Int
    public let authoritativeServerCount: Int
    public let revalidatedOnSettle: Bool

    public init(
        topicID: String,
        direction: AuditedTopicLikeDirection,
        initialCount: Int,
        recordedDelta: Int,
        settledCount: Int,
        authoritativeServerCount: Int,
        revalidatedOnSettle: Bool
    ) {
        self.topicID = topicID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.direction = direction
        self.initialCount = max(0, initialCount)
        self.recordedDelta = recordedDelta
        self.settledCount = settledCount
        self.authoritativeServerCount = max(0, authoritativeServerCount)
        self.revalidatedOnSettle = revalidatedOnSettle
    }

    public var isBidirectionalDeltaValid: Bool {
        recordedDelta == direction.signedDelta
    }

    public var isServerRevalidationConsistent: Bool {
        revalidatedOnSettle && settledCount == authoritativeServerCount && settledCount >= 0
    }
}

/// Deterministic `I05` audit report for square media eviction and topic like host control.
public struct TopicLikeAndSquareEvictionAuditReport: Equatable, Sendable {
    public enum Violation: Equatable, Sendable {
        case unapprovedTopicLikeGrantEnabled
        case topicLikeWriteDispatchedWhileGateDisabled
        case unevictedMediaOnDeletedOrNotFoundPost(postID: String, urls: [String])
        case invalidBidirectionalLikeDelta(topicID: String, expected: Int, actual: Int)
        case missingOrMismatchedServerRevalidationOnSettle(topicID: String)
    }

    public let likeGrantEnabled: Bool
    public let likeGrantApproved: Bool
    public let evictedMediaURLCount: Int
    public let unevictedMediaByPostID: [String: [String]]
    public let violations: [Violation]

    public init(
        likeGrantEnabled: Bool,
        likeGrantApproved: Bool,
        evictedMediaURLCount: Int,
        unevictedMediaByPostID: [String: [String]],
        violations: [Violation]
    ) {
        self.likeGrantEnabled = likeGrantEnabled
        self.likeGrantApproved = likeGrantApproved
        self.evictedMediaURLCount = evictedMediaURLCount
        self.unevictedMediaByPostID = unevictedMediaByPostID
        self.violations = violations
    }

    public var isCompliant: Bool {
        violations.isEmpty
    }
}

/// Pure auditor for `I05` (`SquareWorkspacePrivacy` immediate `URLCache` media eviction on `404`/`DELETED`,
/// `TopicLikeDirection` bidirectional `+1`/`-1` delta with server revalidation on settle, and
/// `TopicLikeHostController.likeGrantEnabled == false` default fail-closed write gate).
public enum TopicLikeAndSquareEvictionAudit {
    public static let topicLikeRoute = "/api/topic/like"

    public static func audit(
        likeGrantEnabled: Bool = false,
        likeGrantApproved: Bool = false,
        dispatchedWriteCount: Int = 0,
        mediaEvictionSamples: [SquarePostMediaEvictionSample] = [],
        likeInteractionSamples: [TopicLikeInteractionAuditSample] = []
    ) -> TopicLikeAndSquareEvictionAuditReport {
        var violations: [TopicLikeAndSquareEvictionAuditReport.Violation] = []

        if likeGrantEnabled && !likeGrantApproved {
            violations.append(.unapprovedTopicLikeGrantEnabled)
        }
        if !likeGrantEnabled && dispatchedWriteCount > 0 {
            violations.append(.topicLikeWriteDispatchedWhileGateDisabled)
        }

        var totalEvicted = 0
        var unevictedMap: [String: [String]] = [:]
        for sample in mediaEvictionSamples {
            totalEvicted += Set(sample.evictedFromURLCacheURLs).count
            let missing = sample.unevictedMediaURLs
            if !missing.isEmpty {
                unevictedMap[sample.postID] = missing
                violations.append(
                    .unevictedMediaOnDeletedOrNotFoundPost(postID: sample.postID, urls: missing)
                )
            }
        }

        for sample in likeInteractionSamples {
            if !sample.isBidirectionalDeltaValid {
                violations.append(
                    .invalidBidirectionalLikeDelta(
                        topicID: sample.topicID,
                        expected: sample.direction.signedDelta,
                        actual: sample.recordedDelta
                    )
                )
            }
            if !sample.isServerRevalidationConsistent {
                violations.append(
                    .missingOrMismatchedServerRevalidationOnSettle(topicID: sample.topicID)
                )
            }
        }

        return TopicLikeAndSquareEvictionAuditReport(
            likeGrantEnabled: likeGrantEnabled,
            likeGrantApproved: likeGrantApproved,
            evictedMediaURLCount: totalEvicted,
            unevictedMediaByPostID: unevictedMap,
            violations: violations
        )
    }
}

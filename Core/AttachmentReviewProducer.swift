import Foundation

/// C09 exclusive 16-type attachment review → original receipt.
/// Visible / APPLIED current projection is not approval.
public enum AttachmentType: String, Equatable, Sendable, CaseIterable {
    case image = "IMAGE"
    case video = "VIDEO"
    case audio = "AUDIO"
    case file = "FILE"
    case location = "LOCATION"
    case sticker = "STICKER"
    case link = "LINK"
    case card = "CARD"
    case poll = "POLL"
    case contact = "CONTACT"
    case voiceNote = "VOICE_NOTE"
    case live = "LIVE"
    case music = "MUSIC"
    case gif = "GIF"
    case album = "ALBUM"
    case miniProgram = "MINI_PROGRAM"
}

public struct AttachmentReviewProducer: Equatable {
    public static let statusPending = "PENDING_REVIEW"
    public static let statusApproved = "APPROVED"
    public static let statusRejected = "REJECTED"
    public static let statusUnknown = "UNKNOWN"

    public struct ReviewReceipt: Equatable, Sendable {
        public var requestId: String?
        public var type: AttachmentType?
        public var originalDigest: String?
        public var status: String?
        public var currentProjectionClaimsVisible: Bool
        public var mintedNewRequest: Bool
        public func originalIsNotVisibleProjection() -> Bool {
            status != "VISIBLE" && status != ImmutableReceiptProducer.projectionApplied
        }
        public func jsonObject() -> [String: Any] {
            [
                "requestId": requestId.map { $0 as Any } ?? NSNull(),
                "type": type.map { $0.rawValue as Any } ?? NSNull(),
                "originalDigest": originalDigest.map { $0 as Any } ?? NSNull(),
                "status": status.map { $0 as Any } ?? NSNull(),
                "usedVisibleProjectionAsApproval": false
            ]
        }
        public func withStatus(_ next: String?) -> ReviewReceipt {
            var copy = self
            copy.status = ImmutableReceiptProducer.parse(next)
            return copy
        }
        public func withProjectionClaim(_ claimed: Bool) -> ReviewReceipt {
            var copy = self
            copy.currentProjectionClaimsVisible = claimed
            return copy
        }
    }

    public private(set) var originalByRequestID: [String: ReviewReceipt] = [:]
    public init() {}

    public static func typeCount() -> Int { AttachmentType.allCases.count }

    public mutating func submit(originalRequestID: String?, type: AttachmentType?, originalDigest: String?) throws -> ReviewReceipt {
        let id = try ImmutableReceiptProducer.requireRequestID(originalRequestID)
        guard let type else { throw NotifyFailure.missingOriginalRequestID }
        guard let digest = ImmutableReceiptProducer.parse(originalDigest, limit: 256) else {
            throw NotifyFailure.missingOriginalRequestID
        }
        if let existing = originalByRequestID[id] {
            if existing.type != type || existing.originalDigest != digest {
                throw NotifyFailure.attachmentConflict(requestId: id)
            }
            return existing
        }
        let receipt = ReviewReceipt(
            requestId: id, type: type, originalDigest: digest, status: Self.statusPending,
            currentProjectionClaimsVisible: false, mintedNewRequest: false)
        originalByRequestID[id] = receipt
        return receipt
    }

    public mutating func decide(originalRequestID: String?, decision: String?) throws -> ReviewReceipt {
        var original = try require(originalRequestID)
        if original.status != Self.statusPending && original.status != Self.statusUnknown {
            return original
        }
        guard let decision = ImmutableReceiptProducer.parse(decision),
              decision == Self.statusApproved || decision == Self.statusRejected || decision == Self.statusUnknown else {
            throw NotifyFailure.invalidReviewDecision
        }
        original = original.withStatus(decision)
        if let id = original.requestId {
            originalByRequestID[id] = original
        }
        return original
    }

    public mutating func recover(originalRequestID: String?, appliedProjectionStatus: String?) throws -> ReviewReceipt {
        let original = try require(originalRequestID)
        let claimed = appliedProjectionStatus == ImmutableReceiptProducer.projectionApplied
            || appliedProjectionStatus == "VISIBLE"
            || appliedProjectionStatus == "APPLIED"
        return original.withProjectionClaim(claimed)
    }

    public mutating func recoverOriginal(originalRequestID: String, appliedProjectionStatus: String?) -> ReviewReceipt {
        recoverUnknown(originalRequestID: originalRequestID, appliedProjectionStatus: appliedProjectionStatus)
    }

    public mutating func recoverUnknown(originalRequestID: String, appliedProjectionStatus: String?) -> ReviewReceipt {
        guard let id = ImmutableReceiptProducer.parse(originalRequestID) else {
            return Self.unknownReceipt(requestId: nil)
        }
        if let original = originalByRequestID[id] {
            let claimed = appliedProjectionStatus == ImmutableReceiptProducer.projectionApplied
                || appliedProjectionStatus == "VISIBLE"
                || appliedProjectionStatus == "APPLIED"
            return original.withProjectionClaim(claimed)
        }
        return Self.unknownReceipt(requestId: id)
    }

    public func treatsVisibleProjectionAsApproval(_ appliedProjectionStatus: String?) -> Bool {
        false
    }

    private func require(_ originalRequestID: String?) throws -> ReviewReceipt {
        let id = try ImmutableReceiptProducer.requireRequestID(originalRequestID)
        guard let original = originalByRequestID[id] else { throw NotifyFailure.originalMissing(id) }
        return original
    }

    private static func unknownReceipt(requestId: String?) -> ReviewReceipt {
        ReviewReceipt(
            requestId: requestId, type: nil, originalDigest: nil, status: statusUnknown,
            currentProjectionClaimsVisible: false, mintedNewRequest: false)
    }
}

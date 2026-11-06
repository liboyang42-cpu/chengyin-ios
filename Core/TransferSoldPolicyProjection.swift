import Foundation

/// Exclusive C07 projection: transfer of an already-sold entitlement.
/// Sold-policy + designated recipient + irrevocable-once-effective originals are
/// not on this public tree. Missing designated recipient or missing sold-policy
/// source is typed WAITING_SOURCE, not a successful transfer.
/// D4 17 SMS / phone-identity is not this chain.
public enum TransferSoldPolicyOutcome: String, Equatable, Sendable {
    case allow = "ALLOW"
    case deny = "DENY"
    case waitingSource = "WAITING_SOURCE"
}

public struct TransferSoldPolicyFact: Equatable, Sendable {
    public let originalRequestID: String?
    public let soldPolicySourceHash: String?
    public let designatedRecipientMemberID: Int64?
    public let irrevocableEffectRecorded: Bool
    public let smsIdentityVerified: Bool
    public init(originalRequestID: String?, soldPolicySourceHash: String?,
                designatedRecipientMemberID: Int64?, irrevocableEffectRecorded: Bool,
                smsIdentityVerified: Bool) {
        self.originalRequestID = TransferSoldPolicyProjection.parse(originalRequestID)
        self.soldPolicySourceHash = TransferSoldPolicyProjection.parse(soldPolicySourceHash)
        self.designatedRecipientMemberID = designatedRecipientMemberID
        self.irrevocableEffectRecorded = irrevocableEffectRecorded
        self.smsIdentityVerified = smsIdentityVerified
    }
}

public struct TransferSoldPolicyDecision: Equatable, Sendable {
    public let outcome: TransferSoldPolicyOutcome
    public let originalRequestID: String?
    public let usedSmsIdentityAsPolicy: Bool
    public let reason: String?
    public var grantsTransfer: Bool { outcome == .allow }
    public func jsonObject() -> [String: Any] {
        [
            "outcome": outcome.rawValue,
            "originalRequestID": originalRequestID.map { $0 as Any } ?? NSNull(),
            "usedSmsIdentityAsPolicy": usedSmsIdentityAsPolicy,
            "reason": reason.map { $0 as Any } ?? NSNull()
        ]
    }
}

public struct TransferSoldPolicyProjection: Equatable {
    public static let waitingSource = "WAITING_SOURCE"
    /// Remote originals for transfer-sold policy were not pushed.
    public static let remoteSoldPolicyOriginalPresent = false
    public private(set) var originalByRequestID: [String: TransferSoldPolicyDecision] = [:]
    public init() {}
    public static func parse(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return nil }
        return trimmed
    }
    /// SMS identity never satisfies sold-policy even when verified.
    public mutating func evaluate(_ fact: TransferSoldPolicyFact?) -> TransferSoldPolicyDecision {
        let decision = compute(fact)
        if let requestID = decision.originalRequestID, originalByRequestID[requestID] == nil {
            originalByRequestID[requestID] = decision
        }
        return decision
    }
    public mutating func requery(_ fact: TransferSoldPolicyFact?) -> TransferSoldPolicyDecision {
        evaluate(fact)
    }
    public func recoverOriginal(originalRequestID: String) -> TransferSoldPolicyDecision {
        let requestID = Self.parse(originalRequestID)
        if let requestID, let original = originalByRequestID[requestID] {
            return original
        }
        return waiting(requestID, "original intent unknown")
    }
    private func compute(_ fact: TransferSoldPolicyFact?) -> TransferSoldPolicyDecision {
        guard let fact else {
            return waiting(nil, "transfer fact missing")
        }
        // Consume the SMS bit so callers cannot skip it; it still does not authorize transfer.
        _ = fact.smsIdentityVerified
        let requestID = fact.originalRequestID
        guard let requestID else {
            return waiting(nil, "originalRequestID missing")
        }
        if fact.smsIdentityVerified {
            if !Self.remoteSoldPolicyOriginalPresent || fact.soldPolicySourceHash == nil {
                return waiting(requestID,
                               "SMS identity is not transfer-sold policy; originals WAITING_SOURCE")
            }
        }
        if !Self.remoteSoldPolicyOriginalPresent || fact.soldPolicySourceHash == nil {
            return waiting(requestID, Self.waitingSource + ": sold-policy original not on remote")
        }
        if fact.designatedRecipientMemberID == nil || fact.designatedRecipientMemberID! <= 0 {
            return waiting(requestID, Self.waitingSource + ": designated recipient missing")
        }
        if !fact.irrevocableEffectRecorded {
            return waiting(requestID, Self.waitingSource + ": irrevocable-effect original missing")
        }
        // Unreachable while remote originals are absent. Do not invent policy numbers.
        return TransferSoldPolicyDecision(outcome: .allow, originalRequestID: requestID,
                                          usedSmsIdentityAsPolicy: false,
                                          reason: "sold-policy + recipient + irrevocable")
    }
    private func waiting(_ requestID: String?, _ reason: String) -> TransferSoldPolicyDecision {
        TransferSoldPolicyDecision(outcome: .waitingSource, originalRequestID: requestID,
                                   usedSmsIdentityAsPolicy: false, reason: reason)
    }
}

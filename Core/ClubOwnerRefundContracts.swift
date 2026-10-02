import Foundation

public struct ClubOwnerRefundTarget: Hashable {
    public let clubID: Int
    public let registrationID: Int
    public init(clubID: Int, registrationID: Int) throws {
        guard clubID > 0, registrationID > 0 else { throw ClubOwnerRefundFailure.invalid }
        self.clubID = clubID; self.registrationID = registrationID
    }
    public var scope: ClubGovernanceScope { .init(clubID: clubID, registrationID: registrationID) }
}
public enum ClubOwnerRefundFailure: Error, Equatable {
    case disabled, signedOut, invalid, ineligible, stale, busy, locked, storage, malformed, unknown
    case unconfirmed(message: String?)
    public var message: String? { if case .unconfirmed(let value) = self { return value }; return nil }
    public var localizationKey: String {
        switch self {
        case .unconfirmed: return "club.refund.error.unknown"
        default: return "club.refund.error." + String(describing: self)
        }
    }
}
public struct ClubOwnerRefundEvidence: Equatable {
    public let target: ClubOwnerRefundTarget
    public let canRefund: Bool
    public let status: String
    public let displayName: String?
    public let topicName: String?
    public let ticketText: String?
    public let orderNo: String?
    public let paidAmountText: String?
    public var eligible: Bool { canRefund && ["PENDING", "CONTACTED"].contains(status) }
    public init(snapshot: ClubGovernanceSnapshot, target: ClubOwnerRefundTarget) throws {
        guard snapshot.operation == .checkin, snapshot.scope == target.scope,
              snapshot.value["registrationId"].int == target.registrationID else { throw ClubOwnerRefundFailure.stale }
        let value = snapshot.value
        guard let canRefund = value["canRefund"].bool, let status = value["statusCode"].string,
              ["PENDING", "CONTACTED", "VERIFIED", "REVIEWED", "REFUNDED"].contains(status) else { throw ClubOwnerRefundFailure.malformed }
        if canRefund {
            guard snapshot.permissions?.allows("OWNER", scope: target.scope) == true,
                  ["PENDING", "CONTACTED"].contains(status) else { throw ClubOwnerRefundFailure.ineligible }
        }
        self.target = target; self.canRefund = canRefund; self.status = status
        func text(_ key: String) throws -> String? {
            if value[key] == .null { return nil }
            guard let string = value[key].string else { throw ClubOwnerRefundFailure.malformed }
            return string.isEmpty ? nil : string
        }
        displayName = try text("displayName"); topicName = try text("topicName")
        ticketText = try text("ticketText"); orderNo = try text("orderNo"); paidAmountText = try text("paidAmountText")
    }
}
public struct ClubOwnerRefundReceipt: Equatable {
    public enum Cancellation: String { case cancelled = "CANCELLED", manualReview = "MANUAL_REVIEW", unconfirmed = "UNCONFIRMED" }
    public enum Cash: String {
        case notNeeded = "NOT_NEEDED", dispatchPending = "DISPATCH_PENDING", dispatching = "DISPATCHING", processing = "PROCESSING", success = "SUCCESS", pendingManual = "PENDING_MANUAL", manualHandled = "MANUAL_HANDLED", manualVerified = "MANUAL_VERIFIED", manualReview = "MANUAL_REVIEW", unconfirmed = "UNCONFIRMED"
    }
    public enum Points: String { case notNeeded = "NOT_NEEDED", returned = "RETURNED", partial = "PARTIAL", unconfirmed = "UNCONFIRMED" }
    public let registrationID: Int
    public let cancellation: Cancellation
    public let cash: Cash
    public let points: Points
    public let scope: String?
    public let message: String?
    public var manualReview: Bool { cancellation == .manualReview || cash == .manualReview || cash == .pendingManual || cash == .manualHandled }
    public init(value: ClubGovernanceValue, message: String?, registrationID: Int) throws {
        guard value["registrationId"].int == registrationID,
              let cancellation = Cancellation(rawValue: value["cancellationStatus"].string ?? ""),
              let cash = Cash(rawValue: value["cashRefundStatus"].string ?? "") else { throw ClubOwnerRefundFailure.unknown }
        guard cancellation != .manualReview || cash == .manualReview else { throw ClubOwnerRefundFailure.unknown }
        let points: Points
        if value["pointsRefundStatus"] == .null, cancellation == .manualReview { points = .unconfirmed }
        else { guard let accepted = Points(rawValue: value["pointsRefundStatus"].string ?? "") else { throw ClubOwnerRefundFailure.unknown }; points = accepted }
        let scope = value["scope"].string
        guard value["scope"] == .null || ["REGISTRATION", "PARENT_ORDER"].contains(scope ?? "") else { throw ClubOwnerRefundFailure.unknown }
        self.registrationID = registrationID; self.cancellation = cancellation; self.cash = cash; self.points = points; self.scope = scope; self.message = message
    }
}
public struct ClubOwnerRefundReview: Identifiable, Equatable {
    public let id: UUID
    public let identity: ClubReadIdentity
    public let namespace: String
    public let evidence: ClubOwnerRefundEvidence
    public let createdAt: Date
    public let ownerID: UUID
    init(identity: ClubReadIdentity, namespace: String, evidence: ClubOwnerRefundEvidence, createdAt: Date, ownerID: UUID) {
        id = UUID(); self.identity = identity; self.namespace = namespace; self.evidence = evidence; self.createdAt = createdAt; self.ownerID = ownerID
    }
}
public struct ClubOwnerRefundStatus: Equatable {
    public enum Phase: String { case idle, preparing, reviewing, preflighting, submitting, notSent, acknowledged, manualReview, outcomeUnknown, refundRecorded }
    public var phase: Phase = .idle
    public var receipt: ClubOwnerRefundReceipt?
    public var failure: ClubOwnerRefundFailure?
    public var readback: ClubOwnerRefundEvidence?
    public var readbackLoading = false
    public var readbackUnavailable = false
    public var inFlight: Bool { [.preparing, .preflighting, .submitting].contains(phase) || readbackLoading }
}

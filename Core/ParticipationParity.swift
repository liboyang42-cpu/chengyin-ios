import Foundation

/// Source utils/order-status.js facts that the shared lifecycle summary does not read.
/// Display only: no request, cancellation, refund or verification is derived from these.
public struct ParticipationParityFacts: Equatable {
    public let activityCancelTime: String?
    public let firstSuccessfulScanAt: String?
    /// isFreeOrder: explicit zero totalAmount and payableAmount, and no non-zero point/WeChat payment.
    public let isFree: Bool
    public init(raw: PlayWireValue) {
        func moment(_ value: PlayWireValue) -> String? {
            if let text = ParticipationRecord.text(value) { return text }
            if let number = value.integer, number > 0 { return String(number) }
            return nil
        }
        let activity = raw["cmsActivity"]
        activityCancelTime = activity.object == nil ? nil : moment(activity["cancelTime"])
        firstSuccessfulScanAt = moment(raw["firstSuccessfulScanAt"])
        func zero(_ value: PlayWireValue) -> Bool {
            switch value {
            case .integer(let number): return number == 0
            case .number(let number): return number == 0
            case .string(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && Double(trimmed) == 0
            default: return false
            }
        }
        func absentOrZero(_ value: PlayWireValue) -> Bool { value == .null || zero(value) }
        isFree = zero(raw["totalAmount"]) && zero(raw["payableAmount"])
            && absentOrZero(raw["pointPaymentAmount"]) && absentOrZero(raw["wechatPaymentAmount"])
    }
}

/// Source mycanyu/mycanyuinfo status: summarizeOrderState with its activity-cancel,
/// paid-first-scan and free-order rules. The shared order summary stays unchanged.
public struct ParticipationStatus: Equatable {
    public let state: OrderLifecycleState
    public let activityCancelled: Bool
    public var labelKey: String {
        activityCancelled ? "playerJourney.parity.state.activityCancelled" : "orderLifecycle.state." + state.rawValue
    }
    public enum Tone: Equatable { case info, success, warning, neutral }
    /// List: not started info, in progress success, else neutral. Detail also marks pending/refunding.
    public func tone(detail: Bool) -> Tone {
        switch state {
        case .notStarted: return .info
        case .inProgress: return .success
        case .pendingPayment, .refunding: return detail && !activityCancelled ? .warning : .neutral
        default: return .neutral
        }
    }
}

public extension ParticipationRecord {
    func participationStatus(now: Date = Date()) -> ParticipationStatus {
        let base = order.summary(now: now).state
        switch base {
        case .manualRefund, .refunding, .refunded: return .init(state: base, activityCancelled: false)
        default: break
        }
        if OrderLifecycleTime.date(parity.activityCancelTime) != nil { return .init(state: .cancelled, activityCancelled: true) }
        guard order.registrationStatus == 2 else { return .init(state: base, activityCancelled: false) }
        func plain(_ state: OrderLifecycleState) -> ParticipationStatus { .init(state: state, activityCancelled: false) }
        if order.verificationStatus == 1 { return plain(.completed) }
        if order.paymentStatus == 2, OrderLifecycleTime.date(parity.firstSuccessfulScanAt) != nil { return plain(.completed) }
        if !parity.isFree, order.refundable == false { return plain(.nonRefundable) }
        let start = OrderLifecycleTime.date(order.ownerStartDate)
        let end = OrderLifecycleTime.date(order.ownerEndDate) ?? start
        if let end, now > end { return plain(.completed) }
        if let start, now < start { return plain(.notStarted) }
        return plain(.inProgress)
    }
    /// 自由探索 / 城市定向 / 线下活动, the same rule as the source modeText.
    var modeKey: String { isFreeExplore ? "playerJourney.freeExplore" : isTopic ? "playerJourney.route" : "playerJourney.activity" }
}

public extension ParticipationFilter {
    /// Client-side tab filtering over one read, using the source participation status.
    func matches(_ value: ParticipationRecord, now: Date = Date()) -> Bool {
        self == .all || value.participationStatus(now: now).state.rawValue == rawValue
    }
    var emptyTitleKey: String { self == .all ? "playerJourney.empty" : "playerJourney.parity.filteredEmpty" }
    var emptyDetailKey: String { self == .all ? "playerJourney.parity.emptyDetail" : "playerJourney.parity.filteredEmptyDetail" }
}

public extension ParticipationDetail {
    /// Source canCancel: pending payment, or canRequestOrderRefund. Visibility only; the action
    /// still opens the existing reviewed order lifecycle screen and never dispatches here.
    func sourceCanCancel(now: Date = Date()) -> Bool {
        guard !needsModification else { return false }
        let status = record.participationStatus(now: now)
        if status.state == .pendingPayment, !status.activityCancelled { return true }
        let order = record.order
        let base = order.summary(now: now).state
        return base != .manualRefund && base != .refunding && base != .refunded
            && order.manualRefundCaseStatus?.isEmpty != false
            && order.registrationStatus == 2 && order.paymentStatus == 2
            && order.verificationStatus != 1 && order.refundable == true
    }
    /// 联系客服 falls back whenever self-service cancellation is unavailable (except 需修改).
    func showsContactService(now: Date = Date()) -> Bool { !sourceCanCancel(now: now) && !needsModification }
    /// Two source cells; unknown statistics display 0, never a placeholder dash.
    var pendingText: String { String(pending ?? 0) }
    var verifiedText: String { String(verified ?? 0) }
    var totalText: String { String(total ?? 0) }
}

/// Source list/detail load-failure copy. Server prose stays verbatim; local fallbacks are keys.
public struct ParticipationLoadIssue: Equatable {
    public enum Kind: Equatable { case signIn, notConfigured, failed }
    public let kind: Kind
    public let serverMessage: String?
    public let fallbackKey: String
    public let isDetail: Bool
    public init(_ error: Error, detail: Bool) {
        isDetail = detail
        let prefix = detail ? "playerJourney.parity.detail." : "playerJourney.parity.list."
        if error as? APIError == .unauthorized { kind = .signIn; serverMessage = nil; fallbackKey = "playerJourney.login"; return }
        if error as? APIError == .notConfigured { kind = .notConfigured; serverMessage = nil; fallbackKey = "playerJourney.notConfigured"; return }
        kind = .failed
        if let failure = error as? PlayerJourneyFailure {
            serverMessage = failure.message; fallbackKey = prefix + "rejected"
        } else if error as? APIError == .malformedResponse {
            serverMessage = nil; fallbackKey = prefix + (detail ? "malformed" : "rejected")
        } else if case .httpStatus(_)? = error as? APIError {
            serverMessage = nil; fallbackKey = prefix + (detail ? "rejected" : "unavailable")
        } else {
            serverMessage = nil; fallbackKey = "playerJourney.parity.network"
        }
    }
    public var titleKey: String {
        switch kind {
        case .signIn: return "playerJourney.login"
        case .notConfigured: return "playerJourney.notConfigured"
        case .failed: return isDetail ? "playerJourney.parity.detailFailed" : "playerJourney.parity.listFailed"
        }
    }
}

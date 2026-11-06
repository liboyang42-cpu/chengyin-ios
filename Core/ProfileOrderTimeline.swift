import Foundation

/// Supplemental read-only detail facts for the Mini order detail (scene-member-order-detail).
/// Decoded leniently: a missing or malformed field is absent and never changes how the
/// existing ProfileOrder fields decode. Nothing here permits any request or mutation.
public struct ProfileOrderDetailFacts: Decodable, Equatable {
    /// Source `info.transactionId` (微信交易单号), shown as literal text only.
    public let transactionID: String?
    /// Source refund timeline time: `refundApplication.payoutTime || refundApplication.updateTime`.
    public let refundTime: String?
    /// Source `refundInfo.reason`, used for the manual after-sales timeline label.
    public let refundReason: String?

    private enum CodingKeys: String, CodingKey { case transactionId, refundApplication, refundInfo }
    private enum RefundApplicationKeys: String, CodingKey { case payoutTime, updateTime }
    private enum RefundInfoKeys: String, CodingKey { case reason }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transactionID = Self.present(try? c.decode(String.self, forKey: .transactionId))
        if let refund = try? c.nestedContainer(keyedBy: RefundApplicationKeys.self, forKey: .refundApplication) {
            refundTime = Self.present(try? refund.decode(String.self, forKey: .payoutTime))
                ?? Self.present(try? refund.decode(String.self, forKey: .updateTime))
        } else { refundTime = nil }
        if let info = try? c.nestedContainer(keyedBy: RefundInfoKeys.self, forKey: .refundInfo) {
            refundReason = Self.present(try? info.decode(String.self, forKey: .reason))
        } else { refundReason = nil }
    }

    private static func present(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

/// One step of the source buildOrderTimeline. Exactly one of `labelKey`/`label` is set:
/// the manual after-sales step shows the server reason as literal text.
public struct ProfileOrderTimelineStep: Equatable, Identifiable {
    public enum State: String, Equatable { case done, current }
    public let id: String
    public let labelKey: String?
    public let label: String?
    public let time: String?
    public let timeKey: String?
    public let state: State
}

public extension ProfileOrder {
    /// Source buildOrderTimeline (scene-member-order-detail/index.js), read-only.
    /// Times use OrderLifecycleTime.display, the same China-time `yyyy-MM-dd HH:mm`
    /// as the source formatRefundDeadline; an unparseable time is omitted.
    func sourceTimeline(now: Date = Date()) -> [ProfileOrderTimelineStep] {
        let state = historyState(now: now)
        func step(_ id: String, _ key: String, time: String? = nil, timeKey: String? = nil, _ status: ProfileOrderTimelineStep.State) -> ProfileOrderTimelineStep {
            ProfileOrderTimelineStep(id: id, labelKey: key, label: nil, time: time, timeKey: timeKey, state: status)
        }
        var rows = [step("created", "orderLifecycle.timeline.created", time: OrderLifecycleTime.display(createTime), .done)]
        if paymentStatus == 2 {
            rows.append(step("paid", isSourceFreeOrder ? "profile.orderParity.timeline.free" : "orderLifecycle.timeline.paid",
                             time: OrderLifecycleTime.display(paymentTime), .done))
        } else if state == .cancelled {
            rows.append(step("cancelled", "orderLifecycle.timeline.cancelled", .done))
            return rows
        } else {
            rows.append(step("payment", "orderLifecycle.timeline.awaitingPayment", timeKey: "profile.orderParity.timeline.updatesLater", .current))
            return rows
        }
        if let scan = OrderLifecycleTime.display(historyFacts.firstSuccessfulScanAt) {
            rows.append(step("first_scan", "profile.orderParity.timeline.firstScan", time: scan, .done))
        }
        if state == .refunding || state == .refunded {
            let refunded = state == .refunded
            rows.append(step("refund", refunded ? "profile.orderParity.timeline.refunded" : "orderLifecycle.timeline.refunding",
                             time: OrderLifecycleTime.display(detailFacts.refundTime), refunded ? .done : .current))
            return rows
        }
        let verified = verificationStatus == 1
        let manual = state == .manualRefund
        if verified {
            rows.append(step("verification", "orderLifecycle.timeline.verified", time: OrderLifecycleTime.display(verificationTime), .done))
        } else if manual {
            rows.append(step("verification", "profile.orderParity.timeline.notVerified", .current))
        } else {
            rows.append(step("verification", "profile.orderParity.timeline.awaitingStore", timeKey: "profile.orderParity.timeline.updatesLater", .current))
        }
        if manual {
            let settled = manualRefundCaseStatus == "NO_REFUND" || manualRefundCaseStatus == "MANUAL_REFUND_EVIDENCE_VERIFIED"
            let reason = detailFacts.refundReason
            rows.append(ProfileOrderTimelineStep(id: "manual_refund", labelKey: reason == nil ? "profile.orderParity.timeline.manualDefault" : nil,
                                                 label: reason, time: nil, timeKey: nil, state: settled ? .done : .current))
        }
        return rows
    }

    /// Source 支付信息/报名信息 card is shown only for paid orders (`paymentStatus == 2`).
    var showsSourcePaymentInfo: Bool { paymentStatus == 2 }
    /// Source showWechatPay / showPointPay: present and greater than zero.
    var showsSourceWechatPay: Bool { (wechatPaymentAmount ?? .zero) > .zero }
    var showsSourcePointPay: Bool { (pointPaymentAmount ?? .zero) > .zero }
    /// Source paymentTimeText / verificationTimeText (verified orders only) / expiresAtText.
    var sourcePaymentTimeText: String? { OrderLifecycleTime.display(paymentTime) }
    var sourceVerificationTimeText: String? { verificationStatus == 1 ? OrderLifecycleTime.display(verificationTime) : nil }
    var sourceExpiresAtText: String? { OrderLifecycleTime.display(expiresAt) }
    /// Source participateDateText: formatted time, else the literal value.
    var sourceParticipateDateText: String? {
        guard let raw = participateDate, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return OrderLifecycleTime.display(raw) ?? raw
    }
}

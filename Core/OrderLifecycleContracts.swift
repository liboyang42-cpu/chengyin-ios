import Foundation

/// Detailed registration read projection. Source: RegistrationDetail.fromJson.
/// No payment parameters, signed codes, personal contact fields or transaction identifiers.
public struct OrderLifecycleDetail: Decodable, Equatable, Identifiable {
    public let id: Int
    public let ownerType: Int?
    public let ownerID: Int?
    public let registrationNumber: String?
    public let registrationStatus: Int?
    public let paymentStatus: Int?
    public let verificationStatus: Int?
    public let payableAmount: Decimal?
    public let title: String?
    public let ticketName: String?
    public let purchaseKind: String?
    public let createTime: String?
    public let paymentTime: String?
    public let verificationTime: String?
    public let payExpireTime: String?
    public let ownerStartDate: String?
    public let ownerEndDate: String?
    public let ownerMemberID: Int?
    public let teamMode: Int?
    public let teamMaxMembers: Int?
    public let refundable: Bool?
    public let refundReason: String?
    public let refundDeadline: String?
    public let refundApplication: OrderLifecycleRefund?
    public let manualRefundCaseStatus: String?
    public let entitlements: [TicketWalletEntitlement]

    enum CodingKeys: String, CodingKey {
        case id, ownerType, ownerId, registrationNo, registrationStatus, paymentStatus, verificationStatus
        case payableAmount, ticketName, purchaseKind, createTime, paymentTime, verificationTime, payExpireTime
        case cmsActivity, cmsTopic, refundInfo, refundApplication, manualRefundCaseStatus, entitlements
    }
    private struct Owner: Decodable {
        let name: String?
        let memberId: OrderLifecycleInteger?
        let teamMode: OrderLifecycleInteger?
        let teamMaxMembers: OrderLifecycleInteger?
        let startDate: String?
        let startTime: String?
        let endDate: String?
        let endTime: String?
    }
    private struct RefundInfo: Decodable { let refundable: Bool?; let reason: String?; let deadline: String? }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        guard id > 0 else { throw APIError.malformedResponse }
        ownerType = try c.decodeIfPresent(Int.self, forKey: .ownerType)
        ownerID = try c.decodeIfPresent(Int.self, forKey: .ownerId)
        registrationNumber = try c.decodeIfPresent(String.self, forKey: .registrationNo)
        registrationStatus = try c.decodeIfPresent(Int.self, forKey: .registrationStatus)
        paymentStatus = try c.decodeIfPresent(Int.self, forKey: .paymentStatus)
        verificationStatus = try c.decodeIfPresent(Int.self, forKey: .verificationStatus)
        payableAmount = try c.lifecycleMoney(.payableAmount)
        ticketName = try c.decodeIfPresent(String.self, forKey: .ticketName)
        if let raw = try? c.decode(Int.self, forKey: .purchaseKind) {
            purchaseKind = [1: "GUIDED_TICKET", 2: "SELF_PASS", 3: "EXPLORE_PASS"][raw]
        } else { purchaseKind = try c.decodeIfPresent(String.self, forKey: .purchaseKind) }
        createTime = try c.decodeIfPresent(String.self, forKey: .createTime)
        paymentTime = try c.decodeIfPresent(String.self, forKey: .paymentTime)
        verificationTime = try c.decodeIfPresent(String.self, forKey: .verificationTime)
        payExpireTime = try c.decodeIfPresent(String.self, forKey: .payExpireTime)
        let owner = try c.decodeIfPresent(Owner.self, forKey: .cmsActivity) ?? c.decodeIfPresent(Owner.self, forKey: .cmsTopic)
        title = owner?.name; ownerMemberID = owner?.memberId?.value
        teamMode = owner?.teamMode?.value; teamMaxMembers = owner?.teamMaxMembers?.value
        ownerStartDate = owner?.startDate ?? owner?.startTime
        ownerEndDate = owner?.endDate ?? owner?.endTime
        let policy = try c.decodeIfPresent(RefundInfo.self, forKey: .refundInfo)
        refundable = policy?.refundable; refundReason = policy?.reason; refundDeadline = policy?.deadline
        refundApplication = try c.decodeIfPresent(OrderLifecycleRefund.self, forKey: .refundApplication)
        manualRefundCaseStatus = try c.decodeIfPresent(String.self, forKey: .manualRefundCaseStatus)
        entitlements = try c.decodeIfPresent([TicketWalletEntitlement].self, forKey: .entitlements) ?? []
    }
}

public struct OrderLifecycleRefund: Decodable, Equatable {
    public let payoutStatus: Int?
    public let applicationStatus: Int?
    public let amount: Decimal?
    public let payoutTime: String?
    public let updateTime: String?
    enum CodingKeys: String, CodingKey { case payoutStatus, status, refundAmount, payoutTime, updateTime }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        payoutStatus = try c.decodeIfPresent(OrderLifecycleInteger.self, forKey: .payoutStatus)?.value
        applicationStatus = try c.decodeIfPresent(OrderLifecycleInteger.self, forKey: .status)?.value
        amount = try c.lifecycleMoney(.refundAmount)
        payoutTime = try c.decodeIfPresent(String.self, forKey: .payoutTime)
        updateTime = try c.decodeIfPresent(String.self, forKey: .updateTime)
    }
}

public enum OrderLifecycleState: String, Equatable {
    case manualRefund, refunding, refunded, pendingPayment, cancelled, expired
    case completed, nonRefundable, notStarted, inProgress, unknown
}
public struct OrderLifecycleSummary: Equatable {
    public let state: OrderLifecycleState
    /// Local key only; backend prose remains separate and is displayed verbatim.
    public let explanationKey: String
    public let serverReason: String?
}
public struct OrderLifecycleTimelineRow: Equatable, Identifiable {
    public let id: String
    public let labelKey: String
    public let time: String?
    public let done: Bool
}

/// Exact precedence of orders/order_timeline.dart. Never infer payout from cancellation.
public extension OrderLifecycleDetail {
    func summary(now: Date = Date()) -> OrderLifecycleSummary {
        func result(_ state: OrderLifecycleState, _ explanation: String, reason: String? = nil) -> OrderLifecycleSummary {
            OrderLifecycleSummary(state: state, explanationKey: "orderLifecycle.explanation." + explanation, serverReason: reason?.isEmpty == false ? reason : nil)
        }
        if manualRefundCaseStatus?.isEmpty == false { return result(.manualRefund, "manualRefund", reason: refundReason) }
        if let refund = refundApplication {
            switch refund.payoutStatus {
            case 1, 4: return result(.refunded, "refunded")
            case 2: return result(.refunding, "manualProcessing")
            case 3: return result(.refunding, "manualReview")
            default: break
            }
            if (refund.amount.map { $0 > 0 } ?? true), refund.applicationStatus != 2 {
                if refund.applicationStatus == 0 { return result(.refunding, "refundReview") }
                if refund.payoutStatus == 0 { return result(.refunding, "refundAccepted") }
                if refund.applicationStatus == 1 { return result(.refunding, "refundApproved") }
                return result(.refunding, "refundUpdating")
            }
        }
        switch registrationStatus {
        case 1: return result(.pendingPayment, "pendingPayment")
        case 3: return result(.cancelled, "cancelled")
        case 4: return result(.expired, "expired")
        case 2: break
        default: return result(.unknown, "unknown")
        }
        if verificationStatus == 1 { return result(.completed, "verified") }
        if refundable == false { return result(.nonRefundable, "nonRefundable", reason: refundReason) }
        let start = OrderLifecycleTime.date(ownerStartDate)
        let end = OrderLifecycleTime.date(ownerEndDate) ?? start
        if let end, now > end { return result(.completed, "ended") }
        if let start, now < start { return result(.notStarted, "refundPolicy", reason: refundReason) }
        return result(.inProgress, "refundPolicy", reason: refundReason)
    }
    func timeline(now: Date = Date()) -> [OrderLifecycleTimelineRow] {
        let state = summary(now: now).state
        func row(_ id: String, _ label: String, _ time: String?, _ done: Bool) -> OrderLifecycleTimelineRow {
            OrderLifecycleTimelineRow(id: id, labelKey: "orderLifecycle.timeline." + label, time: OrderLifecycleTime.display(time), done: done)
        }
        var rows = [row("created", "created", createTime, true)]
        guard paymentStatus == 2 else {
            rows.append(row(state == .cancelled ? "cancelled" : "payment", state == .cancelled ? "cancelled" : "awaitingPayment", nil, state == .cancelled))
            return rows
        }
        rows.append(row("paid", "paid", paymentTime, true))
        if state == .refunding || state == .refunded {
            let refundTime = refundApplication?.payoutTime?.isEmpty == false ? refundApplication?.payoutTime : refundApplication?.updateTime
            rows.append(row("refund", state == .refunded ? "refunded" : "refunding", refundTime, state == .refunded))
            return rows
        }
        rows.append(row("verification", verificationStatus == 1 ? "verified" : "awaitingVerification", verificationStatus == 1 ? verificationTime : nil, verificationStatus == 1))
        if state == .manualRefund {
            rows.append(row("manualRefund", "manualRefund", nil, ["NO_REFUND", "MANUAL_REFUND_EVIDENCE_VERIFIED"].contains(manualRefundCaseStatus ?? "")))
        }
        return rows
    }
}

/// Source wall-clock dates are Asia/Shanghai, never the device's local time zone.
/// Explicit ISO offsets are respected. No fabricated time for missing/malformed values.
public enum OrderLifecycleTime {
    public static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.allSatisfy(\.isNumber), let value = Double(text), value > 0 {
            if text.count == 10 { return Date(timeIntervalSince1970: value) }
            if text.count == 13 { return Date(timeIntervalSince1970: value / 1000) }
            return nil
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: text) { return date }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
            formatter.dateFormat = format; formatter.isLenient = false
            if let date = formatter.date(from: text), formatter.string(from: date) == text { return date }
        }
        return nil
    }
    public static func display(_ raw: String?) -> String? {
        guard let date = date(raw) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// Registration acceptance and cash settlement stay independent. In Flutter the verifier
/// treats registrationStatus==2 OR paymentStatus==2 as success; we expose both dimensions
/// so the UI never relabels acceptance alone as money paid.
public enum OrderPaymentObservation: String, Equatable {
    case paid, registrationAccepted, failed, pending, unknown
    public init(payment: Int?, registration: Int?) {
        if payment == 2 { self = .paid }
        else if registration == 2 { self = .registrationAccepted }
        else if payment == 3 || payment == 4 || registration == 3 { self = .failed }
        else if payment == nil && registration == nil { self = .unknown }
        else { self = .pending }
    }
}

private struct OrderLifecycleInteger: Decodable { let value: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Int.self) { self.value = value }
        else if let text = try? c.decode(String.self), let value = Int(text) { self.value = value }
        else { throw APIError.malformedResponse }
    }
}
private extension KeyedDecodingContainer {
    func lifecycleMoney(_ key: Key) throws -> Decimal? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        guard (try? decode(String.self, forKey: key)) == nil else { throw APIError.malformedResponse }
        let value = try decode(Decimal.self, forKey: key)
        guard !value.isNaN, value >= 0 else { throw APIError.malformedResponse }
        return value
    }
}

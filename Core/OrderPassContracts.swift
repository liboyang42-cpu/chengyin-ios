import Foundation

/// Metadata only. Intentionally cannot decode, expose, cache, log or copy code/token/QR URL.
/// Real code issuance remains unavailable until an independently approved adapter exists.
public struct OrderPassMetadata: Decodable, Equatable {
    public let expiresAtMilliseconds: Int64?
    public let ttlMilliseconds: Int64?
    public let type: String?
    enum CodingKeys: String, CodingKey { case expiresAt, ttlMs, type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expiresAtMilliseconds = try c.decodeIfPresent(Int64.self, forKey: .expiresAt)
        ttlMilliseconds = try c.decodeIfPresent(Int64.self, forKey: .ttlMs)
        type = try c.decodeIfPresent(String.self, forKey: .type)
    }
    /// Absolute expiry is authoritative. ttlMs is never substituted for missing expiresAt.
    public func remainingSeconds(now: Date) -> Int? {
        guard let expiry = expiresAtMilliseconds, expiry > 0 else { return nil }
        let remaining = max(0, (Double(expiry) / 1000) - now.timeIntervalSince1970)
        guard remaining.isFinite, remaining < Double(Int.max) else { return nil }
        return Int(remaining.rounded(.down))
    }
}
public struct OrderCouponStatus: Decodable, Equatable {
    public let useStatus: Int?
    public let useTime: String?
    public var stateKey: String {
        switch useStatus {
        case 0: return "available"
        case 1: return "used"
        case 2: return "expired"
        case 3: return "invalid"
        default: return "unknown"
        }
    }
}
public enum OrderPassAvailability: String, Equatable {
    case unpaid, cancelled, expired, complete, unknown, previewOnly
    public init(detail: OrderLifecycleDetail) {
        switch detail.registrationStatus {
        case 1: self = .unpaid
        case 3: self = .cancelled
        case 4: self = .expired
        case 2:
            if detail.entitlements.isEmpty { self = detail.verificationStatus == 1 ? .complete : .previewOnly }
            else if detail.entitlements.contains(where: { $0.status == 0 }) { self = .previewOnly }
            else if detail.entitlements.contains(where: { ![1, 2].contains($0.status ?? -1) }) { self = .unknown }
            else { self = .complete }
        default: self = .unknown
        }
    }
}

/// Inert documentation contract; not URLRequest and not accepted by any transport.
/// No client role, location or QR shape can authorize a redemption.
public enum OrderPassSourceOperation: String, CaseIterable {
    case issueTicket, issueCoupon, verifyDynamicTicket, verifyCoupon, chooseChapter, chooseStation
    public var path: String {
        switch self {
        case .issueTicket: return "api/verify/dyncode/issue"
        case .issueCoupon: return "api/coupon/qr-token"
        case .verifyDynamicTicket: return "api/registration/scan_dynamic_code"
        case .verifyCoupon: return "api/coupon/verification"
        case .chooseChapter: return "api/registration/scan_qr_code_chapter"
        case .chooseStation: return "api/registration/scan_qr_code_station"
        }
    }
    public var fieldNames: [String] {
        switch self {
        case .issueTicket: return ["registrationId"]
        case .issueCoupon: return ["couponHistoryId"]
        case .verifyDynamicTicket, .verifyCoupon: return ["code"]
        case .chooseChapter: return ["code", "chapterId"]
        case .chooseStation: return ["code", "registrationMerchantId"]
        }
    }
    public var isDispatchEnabled: Bool { false }
}

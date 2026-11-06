import Foundation
import CryptoKit

/// Correlation only: the v1 payload is NOT authenticated here. The original server
/// still owns HMAC, expiry, VERIFY permission, merchant ownership and the transaction.
/// Neither this transient target nor the presented code is Codable or journaled.
public struct CityNodeRedemptionTarget: Equatable {
    public let poiID: Int
    public let memberID: Int
    /// Wrong-entry guidance only. This recognizes the original type prefix even when
    /// the rest needs server validation, and never retains or forwards the scanned code.
    public static func requiresDedicatedEntry(_ raw: String) -> Bool {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.utf8.count <= 16_384 else { return false }
        let parts = code.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 3 && parts[0] == "v1" && parts[2].hasPrefix("citynode_")
    }
    public init?(code: String) {
        let parts = code.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 6, parts[0] == "v1", parts[2].hasPrefix("citynode_"),
              let poi = Self.safeInteger(.string(String(parts[1])), minimum: 1),
              let member = Self.safeInteger(.string(String(parts[2].dropFirst("citynode_".count))), minimum: 1) else { return nil }
        poiID = poi; memberID = member
    }
    static let journalPrefix = "citynode-redemption:v1:"
    var journalTarget: String {
        // Expiry, nonce and signature must NOT change the target lock when a player refreshes a code.
        let bytes = Data("verification-target:citynode:\(poiID):\(memberID)".utf8)
        return Self.journalPrefix + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    static func safeInteger(_ value: MerchantBusinessValue?, minimum: Int, allowsString: Bool = true) -> Int? {
        guard let value else { return nil }
        switch value {
        case .string(let text):
            guard allowsString, !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
                  text == "0" || text.first != "0" else { return nil }
        case .number: break
        default: return nil
        }
        guard let number = value.integer, number >= minimum, number <= 9_007_199_254_740_991 else { return nil }
        return number
    }
    /// Existing unscoped redemption records never become scoped records and are never deleted.
    /// A changed merchant or login epoch is not proof that an earlier account request did not run.
    static func blocks(_ existing: MerchantBusinessIntent, candidate: MerchantBusinessIntent) -> Bool {
        guard existing.realm == candidate.realm, existing.accountID == candidate.accountID else { return false }
        if existing.target == "redemption" { return true }
        if candidate.target == "redemption" { return existing.target.hasPrefix(journalPrefix) }
        return existing.target == candidate.target
    }
}

public enum CityNodeRedemptionOutcome: Equatable {
    case redeemed(couponGranted: Bool)
    case failed
    case unknown
}

/// Only an exact original outcome can settle a pending intent. A local UUID is not
/// a server receipt; current coupons, ledger rows and later scans cannot settle it.
public struct CityNodeRedemptionResult: Equatable {
    public let outcome: CityNodeRedemptionOutcome
    public let message: String
    /// Preserved separately on UNKNOWN so an unverified success message is never a success heading.
    public let unverifiedServerMessage: String?
    public var redeemed: Bool { if case .redeemed = outcome { return true }; return false }
    public var isUnknown: Bool { outcome == .unknown }
    public static let unknownMessage = "核销结果待确认，请勿重复核销"
    public static let unknownGuidance = "核销可能已经完成。请让玩家在「我的券」自行核对是否到账，不要重复扫码；无法确认时请联系平台处理。当前券或核销记录不能证明本次请求的结果，本机不会据此解锁或重新提交。"
    public static let legacyGuidance = "本账号存在无法确认具体目标的未决核销记录。为避免重复核销，本机不会继续提交，也不会把旧记录迁移或清除。请联系平台处理。"

    public init(body: MerchantBusinessObject, target: CityNodeRedemptionTarget? = nil) throws {
        let message = body["msg"]?.string
        guard let code = CityNodeRedemptionTarget.safeInteger(body["code"], minimum: 0) else {
            self = Self.unknown(serverMessage: message); return
        }
        if code == 200 {
            guard let target, let message, let data = body["data"]?.object,
                  CityNodeRedemptionTarget.safeInteger(data["poiId"], minimum: 1) == target.poiID,
                  CityNodeRedemptionTarget.safeInteger(data["memberId"], minimum: 1) == target.memberID,
                  let couponID = CityNodeRedemptionTarget.safeInteger(data["couponId"], minimum: 0, allowsString: false),
                  let granted = data["couponGranted"]?.bool,
                  message == (granted ? "核销成功,券已发放玩家" : "核销成功,该券已失效或停发,未发放"),
                  granted || couponID > 0 else {
                self = Self.unknown(serverMessage: message); return
            }
            // The original endpoint permits couponId == 0 and reports !couponSkipped.
            // Do not invent a coupon/history ID or stronger issuance claim than its exact message.
            self.init(outcome: .redeemed(couponGranted: granted), message: message, unverifiedServerMessage: nil)
        } else if code == 500, let message, Self.notRedeemed.contains(message),
                  body["data"] == nil || body["data"] == .null {
            self.init(outcome: .failed, message: message, unverifiedServerMessage: nil)
        } else {
            // Even a decodable 400/401/403/500 business envelope is NOT a generic rollback receipt.
            self = Self.unknown(serverMessage: message)
        }
    }
    private init(outcome: CityNodeRedemptionOutcome, message: String, unverifiedServerMessage: String?) {
        self.outcome = outcome; self.message = message; self.unverifiedServerMessage = unverifiedServerMessage
    }
    static func unknown(serverMessage: String? = nil) -> Self {
        .init(outcome: .unknown, message: unknownMessage, unverifiedServerMessage: serverMessage)
    }
    /// Exact fixed58 pre-write/verification refusals and the explicitly transactional stock rollback.
    /// Preserve the original text; a new or slightly different message stays UNKNOWN.
    private static let notRedeemed: Set<String> = [
        "请先登录", "据点不存在", "无权核销该据点", "玩家未到店打卡,或该券已核销", "券库存不足,核销失败",
        "核销码无效", "空码", "格式错误", "签名不匹配", "参数错误", "已过期", "非据点核销码", "核销码格式错误"
    ]
    /// These are transport HTTP rejections from the existing service, not business body codes.
    /// The exact mini-app classifier treats only this finite set as a pre-dispatch refusal.
    static func transportRejection(_ error: Error) -> Self? {
        let status: Int
        if error as? APIError == .unauthorized { status = 401 }
        else if error as? MerchantBusinessFailure == .denied { status = 403 }
        else if case .httpStatus(let value)? = error as? APIError { status = value }
        else { return nil }
        guard [400, 401, 403, 404, 405, 413, 415, 426, 429].contains(status) else { return nil }
        return .init(outcome: .failed, message: "请求被拒绝，未执行核销", unverifiedServerMessage: nil)
    }
}

import Foundation
import CryptoKit

/// Ephemeral presentation of one acknowledged create response. It cannot mint an
/// invitation, restore a token from a list, accept membership or authorize a request.
@MainActor public final class MerchantOperatorInvitationPresentation {
    public let id = UUID()
    public let scope: MerchantBusinessScope
    public let authorizationGeneration: UUID?
    public let merchantID: Int
    public let merchantName: String?
    public let roleCode: String
    public let roleName: String?
    public let inviteID: Int?
    public let expiresAt: Date?
    public let expiresAtText: String?
    public let hasValidReceipt: Bool
    private let receivedAt: Date
    private let access: MerchantBusinessAccess
    private let receivedUptime: TimeInterval
    private let receiptFingerprint: Data?
    private var token: String?
    private var retired = false
    // A local privacy lifetime, never an extension of the server's absolute expiry.
    public static let maximumPresentationSeconds: TimeInterval = 600

    init(receipt: MerchantBusinessReceipt, review: MerchantBusinessConfirmation,
         now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        scope = review.scope; authorizationGeneration = review.authorizationGeneration
        access = review.baseline.access
        merchantID = review.baseline.access.merchantID; merchantName = review.baseline.access.name
        let requestedRole: String
        if case .inviteOperator(let value) = review.mutation { requestedRole = value } else { requestedRole = "" }
        roleCode = requestedRole
        roleName = review.baseline.roles?.rows.first { $0.id == requestedRole }?.fields["name"]?.string
        receivedAt = now; receivedUptime = uptime; receiptFingerprint = Self.fingerprint(receipt)
        let parsed = Self.extract(receipt, review: review, role: requestedRole, now: now, uptime: uptime)
        inviteID = parsed?.inviteID; expiresAt = parsed?.expiry; expiresAtText = parsed?.expiryText
        token = parsed?.token; hasValidReceipt = parsed != nil
    }
    private struct Fields { let inviteID: Int; let expiry: Date; let expiryText: String; let token: String }
    private static func extract(_ receipt: MerchantBusinessReceipt, review: MerchantBusinessConfirmation,
                                role: String, now: Date, uptime: TimeInterval) -> Fields? {
        guard review.baseline.document.query == .operators, review.baseline.access.canManageOperators, review.baseline.access.role == "MERCHANT_OWNER",
              MerchantBusinessAccess.employeeRoles.contains(role), uptime.isFinite, uptime >= 0,
              now.timeIntervalSince1970.isFinite, let object = receipt.data.object,
              let invite = object["invite"]?.object, let identifier = invite["id"], case .number = identifier,
              let inviteID = invite["id"]?.integer, inviteID > 0,
              invite["roleCode"]?.string == role, invite["status"]?.string == "PENDING",
              invite["version"] == .int(0),
              let expiryText = invite["expiresAt"]?.string, let expiry = parseExpiry(expiryText),
              expiry > now, expiry.timeIntervalSince(now) <= 24 * 60 * 60,
              let token = object["token"]?.string, validToken(token) else { return nil }
        return .init(inviteID: inviteID, expiry: expiry, expiryText: expiryText, token: token)
    }
    static func validToken(_ value: String) -> Bool {
        guard value.utf8.count == 43,
              value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
              let bytes = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="), bytes.count == 32 else { return false }
        return bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == value
    }
    /// Exact current feature-branch Jackson wire form, verified using its real VO,
    /// ApplicationConfig and Spring Boot auto-configuration. No local-time fallback.
    static func parseExpiry(_ value: String) -> Date? {
        guard value.utf8.count == 29,
              value.range(of: #"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.000\+08:00\z"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSxxx"; formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
    private static func fingerprint(_ receipt: MerchantBusinessReceipt) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(receipt.data) else { return nil }
        return Data(SHA256.hash(data: bytes))
    }
    func matchesAccess(_ current: MerchantBusinessAccess) -> Bool {
        current == access && current.role == "MERCHANT_OWNER" && current.canManageOperators &&
            (current.name ?? "").utf8.elementsEqual((access.name ?? "").utf8)
    }
    func matches(_ receipt: MerchantBusinessReceipt?) -> Bool {
        guard let receipt, let receiptFingerprint else { return false }
        return Self.fingerprint(receipt) == receiptFingerprint
    }
    public func privacyLifetimeIsActive(now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        !retired && now.timeIntervalSince1970.isFinite && now >= receivedAt && uptime.isFinite &&
            uptime >= receivedUptime && uptime - receivedUptime < Self.maximumPresentationSeconds
    }
    public func remainingSeconds(now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int {
        guard !retired, hasValidReceipt, token != nil, let expiresAt,
              now.timeIntervalSince1970.isFinite, now >= receivedAt,
              uptime.isFinite, uptime >= receivedUptime else { return 0 }
        let remaining = min(expiresAt.timeIntervalSince(now), Self.maximumPresentationSeconds - (uptime - receivedUptime))
        return remaining > 0 ? Int(ceil(remaining)) : 0
    }
    func isCurrent(reader: any MerchantBusinessReading, receipt: MerchantBusinessReceipt?, now: Date, uptime: TimeInterval) -> Bool {
        remainingSeconds(now: now, uptime: uptime) > 0 && matches(receipt) && reader.isConfigured &&
            reader.scope == scope && reader.authorizationGeneration == authorizationGeneration &&
            reader.canExecute(.inviteOperator(role: roleCode), merchantID: merchantID)
    }
    func revealedCode(reader: any MerchantBusinessReading, receipt: MerchantBusinessReceipt?, now: Date, uptime: TimeInterval) -> String? {
        isCurrent(reader: reader, receipt: receipt, now: now, uptime: uptime) ? token : nil
    }
    func retire() { retired = true; token = nil }
}

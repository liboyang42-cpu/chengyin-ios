import Foundation

public enum BankWithdrawalFailure: Error, Equatable {
    case unavailable, consentRequired, invalidInput, staleSession, reviewRequired
    case expired, serverBlocked, malformed, unresolved, busy
    case rejected(String) // Machine code only; never stores raw server messages or account details.
}

/// Memory-only input. Never Codable, logged, put in defaults, or copied into a pending journal.
public struct BankWithdrawalDraft: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var amount = ""
    public var realname = ""
    public var bankName = ""
    public var bankAccount = ""
    public var mobilephone = ""
    public init() {}
    public var description: String { "BankWithdrawalDraft(redacted)" }
    public var debugDescription: String { description }
    public func validatedAmount() throws -> Decimal {
        let text = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^[0-9]{1,12}(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0,
              [(realname, 64), (bankName, 128), (bankAccount, 64), (mobilephone, 32)].allSatisfy({
                  !$0.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.0.utf16.count <= $0.1
              }) else { throw BankWithdrawalFailure.invalidInput }
        return value
    }
    var accountMask: String { Self.mask(bankAccount) }
    var phoneMask: String { Self.mask(mobilephone) }
    static func mask(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count > 4 ? "•••• " + String(value.suffix(4)) : "••••"
    }
    func fields(requestID: String, challengeID: Int? = nil) throws -> [String: Any] {
        let value = try validatedAmount()
        var body: [String: Any] = ["requestId": requestID, "realname": realname, "bankName": bankName,
                                  "bankAccount": bankAccount, "mobilephone": mobilephone]
        body[challengeID == nil ? "amount" : "withdrawalAmount"] = NSDecimalNumber(decimal: value)
        if let challengeID { body["challengeId"] = challengeID }
        return body
    }
}

public struct BankWithdrawalSession: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let scope: WalletCommerceScope
    let token: String
    public init(scope: WalletCommerceScope, token: String) { self.scope = scope; self.token = token }
    public var description: String { "BankWithdrawalSession(redacted)" }
    public var debugDescription: String { description }
}

/// Supplied only after independently verified current consent. A local checkbox is not evidence.
/// The future composition root must read the current server document/version and matching AGREE.
public struct BankWithdrawalConsentEvidence: Equatable {
    public let scope: WalletCommerceScope
    public let currentDocumentVersion: String
    public let consentDocumentVersion: String
    public let documentType: String
    public let scene: String
    public let eventType: String
    private let unscoped: Bool
    public init(scope: WalletCommerceScope, currentDocumentVersion: String, consent: ComplianceConsent) {
        self.scope = scope; self.currentDocumentVersion = currentDocumentVersion
        consentDocumentVersion = consent.docVersion ?? ""; documentType = consent.docType
        scene = consent.scene ?? ""; eventType = consent.eventType ?? ""
        unscoped = consent.scopeId == nil && consent.scopeType == nil
    }
    var valid: Bool {
        !currentDocumentVersion.isEmpty && currentDocumentVersion == consentDocumentVersion &&
        documentType == "bank_account_collection" && scene == "withdrawal" && eventType == "AGREE" && unscoped
    }
}

/// Immutable review includes all submitted fields, deployment, account, and authentication epoch.
public struct BankWithdrawalReview: Equatable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: UUID
    public let scope: WalletCommerceScope
    let draft: BankWithdrawalDraft
    let created: Date
    public var amount: Decimal { (try? draft.validatedAmount()) ?? .nan }
    public var bankName: String { draft.bankName }
    public var maskedAccount: String { draft.accountMask }
    public var maskedPhone: String { draft.phoneMask }
    public var description: String { "BankWithdrawalReview(redacted)" }
    public var debugDescription: String { description }
}

/// Only a server response can supply this challenge; private construction prevents UI fabrication.
public struct BankWithdrawalProof: Identifiable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: UUID
    public let challengeID: Int
    public let amount: Decimal
    public let currency: String
    public let maskedAccount: String
    public let maskedPhone: String
    public let question: String
    public let consequence: String
    public let safetyMessages: [String]
    public let riskLevel: String
    public let expiresAt: Date
    let token: String
    let review: BankWithdrawalReview
    init(response: BankWithdrawalChallenge, review: BankWithdrawalReview, expiresAt: Date) throws {
        guard response.state == "PENDING", response.canProceed, response.riskLevel != "BLOCKED",
              let token = response.challengeToken, !token.isEmpty else { throw BankWithdrawalFailure.serverBlocked }
        id = UUID(); challengeID = response.challengeId; amount = response.amount.value
        currency = response.currency; maskedAccount = BankWithdrawalDraft.mask(response.accountMask)
        maskedPhone = BankWithdrawalDraft.mask(response.phoneMask); question = response.question
        consequence = response.consequence; safetyMessages = response.safetyMessages
        riskLevel = response.riskLevel; self.expiresAt = expiresAt; self.token = token; self.review = review
    }
    public var description: String { "BankWithdrawalProof(redacted)" }
    public var debugDescription: String { description }
}

struct BankWithdrawalChallenge: Decodable {
    let challengeId: Int
    let challengeToken: String?
    let state: String
    let serverTime: String
    let expiresAt: String
    let expiresInSeconds: Int
    let question: String
    let consequence: String
    let riskLevel: String
    let canProceed: Bool
    let amount: WalletAmount
    let currency: String
    let accountMask: String
    let phoneMask: String
    let safetyMessages: [String]
    func validate(review: BankWithdrawalReview) throws {
        guard challengeId > 0, amount.value == review.amount, currency == "CNY",
              !accountMask.isEmpty, !phoneMask.isEmpty, !question.isEmpty, !consequence.isEmpty,
              ["STATIC", "WARNING", "BLOCKED"].contains(riskLevel), expiresInSeconds >= 0 else {
            throw BankWithdrawalFailure.malformed
        }
    }
    func expiry(receivedAt: Date) throws -> Date {
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian); format.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        format.dateFormat = "yyyy-MM-dd HH:mm:ss"; format.isLenient = false
        guard let server = format.date(from: serverTime), let expiry = format.date(from: expiresAt),
              format.string(from: server) == serverTime, format.string(from: expiry) == expiresAt,
              expiry > server, expiresInSeconds > 0 else { throw BankWithdrawalFailure.expired }
        // Server TTL and server timestamp delta are both honored. Never trust device wall-clock skew.
        return receivedAt.addingTimeInterval(min(Double(expiresInSeconds), expiry.timeIntervalSince(server)))
    }
}

/// Means application accepted for review only. It is never evidence of payout or arrival.
public struct BankWithdrawalReceipt: Equatable { public let applicationID: Int }

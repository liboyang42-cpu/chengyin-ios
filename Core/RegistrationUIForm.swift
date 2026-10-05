import Foundation

/// The activity sheet, unlike other registration products, collects only these two fields.
/// Saved participants are autofill suggestions; edited values are what gets confirmed.
public struct RegistrationUIFormDraft: Equatable {
    public var realName: String
    public var phone: String
    public init(realName: String = "", phone: String = "") {
        self.realName = realName; self.phone = phone
    }
    public var trimmedName: String { realName.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedPhone: String { phone.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var validation: RegistrationUIValidation? {
        if trimmedName.isEmpty { return .nameRequired }
        if trimmedPhone.isEmpty { return .phoneRequired }
        // Source activity checkout uses ^1\d{10}$. Accept ASCII wire digits only.
        let bytes = Array(trimmedPhone.utf8)
        if bytes.count != 11 || bytes.first != 49 || !bytes.allSatisfy({ (48...57).contains($0) }) {
            return .invalidPhone
        }
        return nil
    }
    public var participantDetails: RegistrationParticipantDetails { details(waitlistOffer: nil) }
    public func details(waitlistOffer: RegistrationWaitlistOffer?) -> RegistrationParticipantDetails {
        RegistrationParticipantDetails(realName: trimmedName, phone: trimmedPhone, waitlistOffer: waitlistOffer)
    }
}

public enum RegistrationUIValidation: Equatable { case nameRequired, phoneRequired, invalidPhone }

/// UI confirmation is separate from the current server consent receipt. The production
/// service independently checks the scoped grant and maintains a durable replay lock.
public enum RegistrationUICreationPolicy: Equatable {
    case disabled
    case approved(RegistrationProductionApproval)
    #if DEBUG
    case offlineFixture
    #endif
    public var permitsCreation: Bool {
        switch self {
        case .disabled: return false
        case .approved(let grant): return Date() < grant.expiresAt
        #if DEBUG
        case .offlineFixture: return true
        #endif
        }
    }
    public var isOfflineFixture: Bool {
        #if DEBUG
        return self == .offlineFixture
        #else
        return false
        #endif
    }
    public func permits(identity: ProfileReadIdentity?, activityID: Int, ticketID: Int?, now: Date) -> Bool {
        if case .approved(let grant) = self { return grant.permits(identity: identity, activityID: activityID, ticketID: ticketID, now: now) }
        return isOfflineFixture
    }
}

/// The quote/create wire contract has no currency field. Only the explicitly Yuan-named
/// deduction fields have a verified unit. A device locale never determines currency.
public enum RegistrationUIMoney {
    public static let yuanCurrencyCode = "CNY"
    public static func display(_ amount: Decimal?, locale: Locale, currencyCode: String? = nil) -> String? {
        guard let amount, !amount.isNaN, amount >= .zero else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        if let currencyCode {
            formatter.numberStyle = .currency
            formatter.currencyCode = currencyCode
            formatter.currencySymbol = currencyCode
        } else { formatter.numberStyle = .decimal }
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount))
    }
}

/// Known registration labels are verified in the source order model. Keep payment and
/// verification codes separate; do not combine conflicting fields into a success verdict.
public enum RegistrationUIStatus {
    public static func registrationKey(_ code: Int?) -> String {
        switch code {
        case 1: return "registration.form.awaitingPayment"
        case 2: return "registration.form.registered"
        case 3: return "registration.form.cancelled"
        case 4: return "registration.form.expired"
        default: return "registration.form.unknownStatus"
        }
    }
}

/// Presentation only: capability and current status do not grant access or permit purchase.
public enum RegistrationUIWaitlistGuidance {
    public static func soldOutKey(available: Bool, status: RegistrationWaitlistStatus?,
                                  outcomeUnknown: Bool, now: Date) -> String {
        guard available else { return "registration.form.soldOutHint" }
        guard !outcomeUnknown else { return "registration.waitlist.unknown" }
        if status?.state == .waiting { return "registration.form.soldOutWaiting" }
        if status?.offer(at: now) != nil { return "registration.form.soldOutOffer" }
        return "registration.form.soldOutAvailable"
    }
}

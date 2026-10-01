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
    public var participantDetails: RegistrationParticipantDetails {
        RegistrationParticipantDetails(realName: trimmedName, phone: trimmedPhone)
    }
}

public enum RegistrationUIValidation: Equatable { case nameRequired, phoneRequired, invalidPhone }

/// No production-enabled case exists. A UI checkbox is not a server consent receipt,
/// and in-memory intent retention is not adequate for live checkout after a restart.
public enum RegistrationUICreationPolicy: Equatable {
    case disabled
    #if DEBUG
    case offlineFixture
    #endif
    public var permitsCreation: Bool {
        #if DEBUG
        return self == .offlineFixture
        #else
        return false
        #endif
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

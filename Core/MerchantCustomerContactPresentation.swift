import Foundation

/// Ephemeral display of an already-authorized CRM list row. Never fetches cleartext,
/// remasks a number, or grants permission from the presence of response fields.
public enum MerchantCustomerContactPresentation: Equatable {
    case maskedPhone(String)
    case reason(String)
    case unavailable

    public init?(record: MerchantBusinessRecord, access: MerchantBusinessAccess) {
        guard record.kind == .customer, access.allows("merchant:crm:read") else { return nil }
        if access.allows("merchant:crm:sensitive:read"),
           let phone = Self.text(record.fields["phone"]), Self.isSourceMask(phone) {
            self = .maskedPhone(phone)
        } else if let reason = Self.text(record.fields["contactHint"]) {
            self = .reason(reason)
        } else {
            // Missing, malformed, or unexpectedly cleartext is not proof of a missing phone.
            self = .unavailable
        }
    }

    private static func text(_ value: MerchantBusinessValue?) -> String? {
        guard let text = value?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// PiiCryptoService.maskPhone returns 3 + four stars + 4 for 11-unit values;
    /// maskMiddle returns one star, or 1/2 units on each side of four stars.
    /// Match its Java UTF-16 framing; unknown/plaintext formats stay unavailable.
    private static func isSourceMask(_ value: String) -> Bool {
        let units = Array(value.utf16)
        if units == [42] { return true }
        let prefix: Int
        switch units.count {
        case 6: prefix = 1
        case 8: prefix = 2
        case 11: prefix = 3
        default: return false
        }
        return units[prefix..<(prefix + 4)].allSatisfy { $0 == 42 }
    }
}

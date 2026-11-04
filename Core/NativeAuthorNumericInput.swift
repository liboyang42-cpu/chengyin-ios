import Foundation

/// Pure input/display helpers extracted unchanged from the original author draft.
/// This type owns no module, permission, network request or persistence.
public enum NativeAuthorNumericInput {
    private static func matchesEntire(_ text: String, _ pattern: String) -> Bool {
        guard let match = text.range(of: pattern, options: .regularExpression) else { return false }
        return match == text.startIndex..<text.endIndex
    }
    public static func numberInput(_ text: String) -> ProjectEditJSON {
        guard !text.isEmpty, Self.matchesEntire(text, #"^-?(0|[1-9][0-9]*)$"#),
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return .string(text) }
        return .number(value)
    }
    public static func display(_ value: ProjectEditJSON?) -> String {
        switch value { case .string(let text)?: return text
        case .number(let number)?: return NSDecimalNumber(decimal: number).stringValue
        default: return "" }
    }
}

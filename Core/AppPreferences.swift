import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", simplifiedChinese = "zh-Hans"
    public var id: String { rawValue }
    public init(storedValue: String) { self = Self(rawValue: storedValue) ?? .system }
    public var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }
}

/// An onboarding intention, never evidence of authorization or a server-owned role.
public enum RegistrationIntent: String, CaseIterable, Identifiable {
    case player, merchant
    public var id: String { rawValue }
}

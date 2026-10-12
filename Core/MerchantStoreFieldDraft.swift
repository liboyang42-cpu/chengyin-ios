import Foundation

/// The six fields in P079's actual FIELDS table. Legacy merchandise/website are not included.
public enum MerchantStoreTextField: String, CaseIterable {
    case name, preference, description, derivativeBenefits, slogan, cityRole
    public var titleKey: String { "merchant.storeField." + rawValue }
    public var limit: Int { self == .description ? 300 : 100 }
    public func value(in draft: MerchantOperationsDraft) -> String? {
        switch draft {
        case .profile(let p):
            switch self {
            case .name: return p.name
            case .preference: return p.preference
            case .description: return p.description
            case .derivativeBenefits: return p.derivativeBenefits ?? ""
            default: return nil
            }
        case .decor(let d):
            switch self { case .slogan: return d.slogan; case .cityRole: return d.cityRole; default: return nil }
        case .story(let s): return self == .description ? s.profile.description : nil
        default: return nil
        }
    }
}

public struct MerchantStoreFieldDraft: Equatable {
    public let field: MerchantStoreTextField
    public let original: String
    public var value: String
    public init?(field: MerchantStoreTextField, source: MerchantOperationsDraft) {
        guard let original = field.value(in: source) else { return nil }
        self.field = field; self.original = original; value = original
    }
    public var isDirty: Bool { !value.utf8.elementsEqual(original.utf8) }
    public var issueKey: String? {
        // Opening or closing an unchanged historical value never rewrites it.
        guard isDirty else { return nil }
        if value.utf16.count > field.limit { return field == .description ? "merchant.storeField.limit300" : "merchant.storeField.limit100" }
        if field == .name, value.unicodeScalars.allSatisfy({ Self.nameWhitespace.contains($0) }) { return "merchant.storeField.nameRequired" }
        return nil
    }
    // Match JavaScript String.trim() for validation; never trim the stored input.
    private static let nameWhitespace = CharacterSet(charactersIn:
        "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
    public func applying(to source: MerchantOperationsDraft) throws -> MerchantOperationsDraft {
        guard let current = field.value(in: source), current.utf8.elementsEqual(original.utf8), issueKey == nil else { throw APIError.invalidRequest }
        guard isDirty else { return source }
        switch source {
        case .profile(var p):
            switch field {
            case .name: p.name = value
            case .preference: p.preference = value
            case .description: p.description = value
            case .derivativeBenefits: p.derivativeBenefits = value
            default: throw APIError.invalidRequest
            }
            return .profile(p)
        case .decor(var d):
            switch field { case .slogan: d.slogan = value; case .cityRole: d.cityRole = value; default: throw APIError.invalidRequest }
            return .decor(d)
        case .story(var s):
            guard field == .description else { throw APIError.invalidRequest }
            s.profile.description = value; return .story(s)
        default: throw APIError.invalidRequest
        }
    }
    /// Equatable alone treats canonically equivalent Unicode strings as equal.
    /// Supplement every text field with UTF8 identity, including optional/hidden siblings.
    public static func sameDraft(_ a: MerchantOperationsDraft, _ b: MerchantOperationsDraft) -> Bool {
        func bytes(_ values: [String]) -> [Data] { values.map { Data($0.utf8) } }
        func optionalBytes(_ values: [String?]) -> [Data?] { values.map { $0.map { Data($0.utf8) } } }
        func profile(_ x: MerchantStoreProfile, _ y: MerchantStoreProfile) -> Bool {
            x == y && bytes([x.logo, x.name, x.description, x.derivatives, x.website, x.preference]) == bytes([y.logo, y.name, y.description, y.derivatives, y.website, y.preference]) &&
                optionalBytes([x.derivativeBenefits, x.businessTime, x.businessTimeReplacement]) == optionalBytes([y.derivativeBenefits, y.businessTime, y.businessTimeReplacement])
        }
        func decor(_ x: MerchantStoreDecor, _ y: MerchantStoreDecor) -> Bool {
            x == y && bytes([x.slogan, x.cityRole, x.storyTitle] + x.gallery + x.tags) == bytes([y.slogan, y.cityRole, y.storyTitle] + y.gallery + y.tags) &&
                optionalBytes([x.coverImage, x.serviceTag, x.serviceText]) == optionalBytes([y.coverImage, y.serviceTag, y.serviceText])
        }
        switch (a, b) {
        case (.profile(let x), .profile(let y)): return profile(x, y)
        case (.decor(let x), .decor(let y)): return decor(x, y)
        case (.story(let x), .story(let y)):
            return profile(x.profile, y.profile) && decor(x.decor, y.decor) && x.cooperation == y.cooperation &&
                bytes([x.cooperation.capacity, x.cooperation.availableTime, x.cooperation.demand]) == bytes([y.cooperation.capacity, y.cooperation.availableTime, y.cooperation.demand]) &&
                optionalBytes([x.cooperation.suitActivityTypes]) == optionalBytes([y.cooperation.suitActivityTypes]) && x.cooperation.clearsCapacity == y.cooperation.clearsCapacity
        default: return false
        }
    }
}

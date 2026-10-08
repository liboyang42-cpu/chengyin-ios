import Foundation

/// Existing chapter data, not an app theme or a free-form color. The five values
/// and legacy aliases match ce61's chapter-atmosphere.js / ChapterAtmospherePreset.
public enum ProjectChapterAtmosphere: String, CaseIterable, Identifiable {
    case black = "DEFAULT", blue = "BLUE", red = "RED", yellow = "YELLOW", white = "WHITE"
    public var id: String { rawValue }

    /// Pure projection. Opening a chapter never migrates its stored value. Unknown
    /// local data has no selected swatch rather than being displayed as a default.
    public static func selected(in chapter: ProjectEditChapter) -> Self? {
        switch chapter.preserved["atmospherePreset"] {
        case nil, .null?: return .black
        case .string(let raw)?:
            // JavaScript String.trim(), including BOM but excluding U+0085.
            let whitespace = CharacterSet(charactersIn:
                "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}"
                + "\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}"
                + "\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
            let value = raw.trimmingCharacters(in: whitespace).uppercased()
            if value.isEmpty { return .black }
            return matching(value)
        default: return nil
        }
    }

    /// Only a deliberate choice of this closed enum replaces unsupported data.
    public func applying(to chapter: ProjectEditChapter) -> ProjectEditChapter {
        var next = chapter
        next.preserved["atmospherePreset"] = .string(rawValue)
        return next
    }

    /// Mirrors Java requireValid: null/missing defaults, String.trim() removes only
    /// codepoints <= U+0020, and empty or unknown values fail. No other chapter
    /// metadata is inspected or changed. The existing wire payload is left intact.
    public static func canSubmit(_ chapter: ProjectEditChapter) -> Bool {
        switch chapter.preserved["atmospherePreset"] {
        case nil, .null?: return true
        case .string(let raw)?:
            var value = raw
            while let first = value.unicodeScalars.first, first.value <= 0x20 { value.unicodeScalars.removeFirst() }
            while let last = value.unicodeScalars.last, last.value <= 0x20 { value.unicodeScalars.removeLast() }
            return matching(value.uppercased()) != nil
        default: return false
        }
    }
    private static func matching(_ value: String) -> Self? {
        if let preset = Self(rawValue: value) { return preset }
        switch value {
        case "NIGHT": return .blue
        case "ARCHIVE": return .yellow
        case "NEON": return .red
        case "MOSS": return .black
        default: return nil
        }
    }

    /// Exact solid swatches in ce61 fabu/index.wxss. These are display-only values;
    /// the existing create/update payload continues to contain the enum string.
    public var backgroundRGB: UInt32 {
        switch self {
        case .black: return 0x0A0A0A
        case .blue: return 0x14294F
        case .red: return 0x4E1C24
        case .yellow: return 0x4E4114
        case .white: return 0xF5F6F8
        }
    }
    public var foregroundRGB: UInt32 { self == .white ? 0x111318 : 0xFFFFFF }
}

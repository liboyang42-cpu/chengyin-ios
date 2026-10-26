import Foundation

/// Reform plan v9 §12.2 (MV01, MV03, MV05, MV12). Semantic map roles, not brand colors.
/// The built-in palette is the plan's *candidate* table; it is not an approved visual design.
public enum MapSemanticRole: String, CaseIterable, Codable {
    case ground, water, green, majorRoad, roadLabel, currentTargetRoute, completedUnavailable, fogOverlay, operationZone
}

/// Follows the system appearance. A map never forces a global dark override (MV01).
public enum MapAppearance: String, CaseIterable, Codable {
    case day, night
    public static func resolve(systemIsDark: Bool) -> MapAppearance { systemIsDark ? .night : .day }
}

public struct MapStyleColor: Hashable, Codable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double
    public init?(hex: String, opacity: Double = 1) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let value = UInt32(digits, radix: 16), opacity.isFinite, (0...1).contains(opacity) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255; green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255; self.opacity = opacity
    }
    /// WCAG 2.x relative luminance. Color math only; real basemap legibility needs device review.
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public static func contrastRatio(_ a: MapStyleColor, _ b: MapStyleColor) -> Double {
        let (x, y) = (a.relativeLuminance, b.relativeLuminance)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

/// MV03 bottom-to-top order. Route/target stays above fog; own location and controls stay on top.
public enum MapLayerOrder: Int, CaseIterable, Comparable {
    case basemap = 0, operationZone, fog, routeAndTarget, gameMarkers, consentedPeers, ownLocation, controls
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// MV05: every state has a distinct symbol and text; color is never the only signal.
/// Selection is UI-only and never changes task, eligibility or ownership.
public enum MapMarkerVisualState: String, CaseIterable, Codable {
    case standard, interactive, selected, active, completed, locked, unavailable, inReview
    public var symbolName: String {
        switch self {
        case .standard: "mappin"
        case .interactive: "hand.tap"
        case .selected: "scope"
        case .active: "figure.walk"
        case .completed: "checkmark.circle"
        case .locked: "lock"
        case .unavailable: "nosign"
        case .inReview: "hourglass"
        }
    }
    /// Emphasis is expressed by stroke width as well as color.
    public var strokeWidth: Double {
        switch self {
        case .selected: 3
        case .active: 2.5
        case .interactive: 1.5
        default: 1
        }
    }
    public var allowsPrimaryAction: Bool { ![.locked, .unavailable, .inReview, .completed].contains(self) }
}

/// MV12 versioned style manifest. Remote manifests carry only tokens, never business rules.
public struct MapVisualStyleManifest: Equatable {
    public enum Approval: String, Codable { case candidate, approved }
    public let version: String
    public let approval: Approval
    public let tokens: [MapAppearance: [MapSemanticRole: MapStyleColor]]
    public init(version: String, approval: Approval, tokens: [MapAppearance: [MapSemanticRole: MapStyleColor]]) throws {
        guard !version.isEmpty, version.count <= 64,
              version.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }),
              Set(tokens.keys) == Set(MapAppearance.allCases),
              tokens.values.allSatisfy({ Set($0.keys) == Set(MapSemanticRole.allCases) }) else {
            throw MapVisualStyleFailure.invalidManifest
        }
        self.version = version; self.approval = approval; self.tokens = tokens
    }
    public func color(_ role: MapSemanticRole, _ appearance: MapAppearance) -> MapStyleColor {
        tokens[appearance]![role]!
    }

    /// Reform plan v9 §12 proposal table. Fog/operation masks are neutral with untested opacity.
    public static let candidate: MapVisualStyleManifest = {
        func c(_ hex: String, _ opacity: Double = 1) -> MapStyleColor { MapStyleColor(hex: hex, opacity: opacity)! }
        return try! MapVisualStyleManifest(version: "plan-v9-candidate", approval: .candidate, tokens: [
            .day: [.ground: c("#F5F4F0"), .water: c("#D8E5EA"), .green: c("#E0E7DC"), .majorRoad: c("#FFFFFF"),
                   .roadLabel: c("#353A42"), .currentTargetRoute: c("#006C70"), .completedUnavailable: c("#595E66"),
                   .fogOverlay: c("#808080", 0.35), .operationZone: c("#808080", 0.15)],
            .night: [.ground: c("#151922"), .water: c("#233944"), .green: c("#2C3B35"), .majorRoad: c("#9AA7B8"),
                     .roadLabel: c("#E3E7EE"), .currentTargetRoute: c("#63D9D3"), .completedUnavailable: c("#BAC2CD"),
                     .fogOverlay: c("#808080", 0.35), .operationZone: c("#808080", 0.15)]
        ])
    }()

    /// Exact JSON shape: {"version","approval","day":{role:hex},"night":{role:hex},"opacity":{role:Double}?}.
    /// Any unknown key, missing role or bad value returns the readable candidate (MV12 fallback).
    public static func resolve(_ data: Data?) -> MapVisualStyleManifest {
        guard let data, data.count <= 16_384,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["version", "approval", "day", "night", "opacity"]),
              let version = object["version"] as? String,
              let approval = (object["approval"] as? String).flatMap(Approval.init(rawValue:)) else { return candidate }
        let opacity = (object["opacity"] as? [String: Any]) ?? [:]
        guard Set(opacity.keys).isSubset(of: Set(MapSemanticRole.allCases.map(\.rawValue))) else { return candidate }
        var tokens: [MapAppearance: [MapSemanticRole: MapStyleColor]] = [:]
        for appearance in MapAppearance.allCases {
            guard let raw = object[appearance.rawValue] as? [String: Any],
                  Set(raw.keys) == Set(MapSemanticRole.allCases.map(\.rawValue)) else { return candidate }
            var roles: [MapSemanticRole: MapStyleColor] = [:]
            for role in MapSemanticRole.allCases {
                let alpha = opacity[role.rawValue].map { value -> Double in
                    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return .nan }
                    return number.doubleValue
                } ?? 1
                guard let hex = raw[role.rawValue] as? String, let color = MapStyleColor(hex: hex, opacity: alpha) else { return candidate }
                roles[role] = color
            }
            tokens[appearance] = roles
        }
        return (try? MapVisualStyleManifest(version: version, approval: approval, tokens: tokens)) ?? candidate
    }

    /// Text-on-ground and route-on-ground pairs below the proposed thresholds (4.5:1 text, 3:1 key boundary).
    /// A clean result is arithmetic only; it is not visual acceptance against a rendered basemap.
    public func contrastShortfalls() -> [String] {
        var result: [String] = []
        for appearance in MapAppearance.allCases {
            let ground = color(.ground, appearance)
            if MapStyleColor.contrastRatio(color(.roadLabel, appearance), ground) < 4.5 { result.append("\(appearance.rawValue).roadLabel") }
            if MapStyleColor.contrastRatio(color(.currentTargetRoute, appearance), ground) < 3 { result.append("\(appearance.rawValue).currentTargetRoute") }
            if MapStyleColor.contrastRatio(color(.completedUnavailable, appearance), ground) < 3 { result.append("\(appearance.rawValue).completedUnavailable") }
        }
        return result
    }
}
public enum MapVisualStyleFailure: Error, Equatable { case invalidManifest }

import Foundation

public enum SettingsLegalType: String, CaseIterable, Identifiable {
    case userAgreement = "user_agreement", privacyPolicy = "privacy_policy", cancellationNotice = "cancellation_notice"
    public var id: String { rawValue }
    public var titleKey: String { "settingsNative.legal.\(rawValue)" }
    /// Flutter's unknown legal-route key falls back to the user agreement.
    public static func resolve(_ raw: String) -> Self { Self(rawValue: raw) ?? .userAgreement }
}
public struct SettingsLegalSection: Equatable {
    public let heading: String
    public let body: String
    public init(heading: String, body: String) { self.heading = heading; self.body = body }
}
public struct SettingsLegalDocument: Equatable {
    public let type: SettingsLegalType
    public let title: String
    public let version: String
    public let effectiveDate: String
    public let intro: String
    public let sections: [SettingsLegalSection]
    public let languageCode: String
    // Source availability does not establish native-app legal adequacy or release approval.
    public var isReleaseApproved: Bool { false }
    public init(type: SettingsLegalType, title: String, version: String, effectiveDate: String,
                intro: String, sections: [SettingsLegalSection], languageCode: String = "zh-Hans") {
        self.type = type; self.title = title; self.version = version; self.effectiveDate = effectiveDate
        self.intro = intro; self.sections = sections; self.languageCode = languageCode
    }
}
public enum SettingsLegalMissingReason: String, Equatable {
    case pendingSourceText, regionalTextNotProvided, missingMarket
    public var messageKey: String { "settingsNative.legal.\(rawValue)" }
}
public enum SettingsLegalAvailability: Equatable {
    case sourceDocument(SettingsLegalDocument)
    case missing(SettingsLegalMissingReason)
}
@MainActor public protocol SettingsLegalReading: AnyObject {
    func document(type: SettingsLegalType, market: RegionalMarket?) async throws -> SettingsLegalAvailability
}
@MainActor public final class SettingsBundledLegalReader: SettingsLegalReading {
    public init() {}
    public func document(type: SettingsLegalType, market: RegionalMarket?) async throws -> SettingsLegalAvailability {
        try Task.checkCancellation()
        return SettingsSourceLegalCatalog.document(type: type, market: market)
    }
}
public enum SettingsLegalState: Equatable {
    case idle, loading, loaded(SettingsLegalAvailability), failed
}
@MainActor public final class SettingsLegalCoordinator {
    public private(set) var state: SettingsLegalState = .idle
    public var onChange: ((SettingsLegalState) -> Void)?
    private let reader: any SettingsLegalReading
    private var generation: UInt64 = 0
    public init(reader: any SettingsLegalReading) { self.reader = reader }
    public func invalidate() {
        generation &+= 1; state = .idle; onChange?(state)
    }
    public func load(type: SettingsLegalType, market: RegionalMarket?) async {
        generation &+= 1
        let current = generation
        state = .loading; onChange?(state)
        do {
            let value = try await reader.document(type: type, market: market)
            guard generation == current, !Task.isCancelled else { return }
            state = .loaded(value)
        } catch {
            guard generation == current, !Task.isCancelled else { return }
            state = .failed
        }
        onChange?(state)
    }
}

/// Preserve paragraph/list text exactly; only split a known source list marker for hanging indent.
public struct SettingsLegalLine: Equatable {
    public let marker: String?
    public let text: String
    public static func lines(in paragraph: String) -> [Self] {
        let regex = try? NSRegularExpression(pattern: #"^(\d{1,2}[.、]|[·•\-]|[一二三四五六七八九十]+、)\s*"#)
        return paragraph.components(separatedBy: "\n").map { line in
            let whole = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex?.firstMatch(in: line, range: whole), let range = Range(match.range, in: line) {
                return Self(marker: String(line[range]), text: String(line[range.upperBound...]))
            }
            return Self(marker: nil, text: line)
        }
    }
}

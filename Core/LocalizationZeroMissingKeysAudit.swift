import Foundation

/// Canonical `.xcstrings` catalogs audited for zero missing localization keys.
public enum LocalizationCatalogName: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case localizable = "Localizable.xcstrings"
    case roamPrivateTools = "RoamPrivateTools.xcstrings"
    case merchantStoreParity = "MerchantStoreParity.xcstrings"
    case memberProfile = "MemberProfile.xcstrings"

    public var tableName: String {
        switch self {
        case .localizable:
            return "Localizable"
        case .roamPrivateTools:
            return "RoamPrivateTools"
        case .merchantStoreParity:
            return "MerchantStoreParity"
        case .memberProfile:
            return "MemberProfile"
        }
    }
}

/// Required bilingual locales across all shipping `.xcstrings` tables.
public enum RequiredLocalizationLocale: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case en = "en"
    case zhHans = "zh-Hans"
}

/// One audited entry from an `.xcstrings` catalog.
public struct LocalizationCatalogEntry: Equatable, Sendable {
    public let catalog: LocalizationCatalogName
    public let key: String
    public let translations: [RequiredLocalizationLocale: String]
    public let stateByLocale: [RequiredLocalizationLocale: String]

    public init(
        catalog: LocalizationCatalogName,
        key: String,
        translations: [RequiredLocalizationLocale: String],
        stateByLocale: [RequiredLocalizationLocale: String] = [
            .en: "translated",
            .zhHans: "translated"
        ]
    ) {
        self.catalog = catalog
        self.key = key
        self.translations = translations
        self.stateByLocale = stateByLocale
    }
}

public enum LocalizationAuditViolation: Equatable, Sendable {
    case emptyKey(catalog: LocalizationCatalogName)
    case missingLocale(catalog: LocalizationCatalogName, key: String, locale: RequiredLocalizationLocale)
    case untranslatedState(catalog: LocalizationCatalogName, key: String, locale: RequiredLocalizationLocale, state: String)
    case emptyTranslation(catalog: LocalizationCatalogName, key: String, locale: RequiredLocalizationLocale)
    case unresolvedPlaceholder(catalog: LocalizationCatalogName, key: String, locale: RequiredLocalizationLocale)
    case formatSpecifierMismatch(catalog: LocalizationCatalogName, key: String, enSpecifiers: [String], zhSpecifiers: [String])
    case untrackedDotKeyInView(viewName: String, key: String)
}

public struct LocalizationZeroMissingKeysAuditReport: Equatable, Sendable {
    public let auditedCatalogs: [LocalizationCatalogName]
    public let totalEntriesAudited: Int
    public let totalViewsAudited: Int
    public let violations: [LocalizationAuditViolation]

    public init(
        auditedCatalogs: [LocalizationCatalogName],
        totalEntriesAudited: Int,
        totalViewsAudited: Int,
        violations: [LocalizationAuditViolation]
    ) {
        self.auditedCatalogs = auditedCatalogs
        self.totalEntriesAudited = totalEntriesAudited
        self.totalViewsAudited = totalViewsAudited
        self.violations = violations
    }

    public var isPassing: Bool {
        violations.isEmpty
    }
}

/// Pure audit evaluator verifying bilingual `.xcstrings` completeness and `Text(verbatim:)`
/// compliance for Reform Plan v9 (`F`/`G`/`H`) and release diagnostics SwiftUI views.
public enum LocalizationZeroMissingKeysAudit {
    public static let requiredCatalogs: [LocalizationCatalogName] = LocalizationCatalogName.allCases
    public static let requiredLocales: [RequiredLocalizationLocale] = RequiredLocalizationLocale.allCases

    public static func auditEntry(_ entry: LocalizationCatalogEntry) -> [LocalizationAuditViolation] {
        let trimmedKey = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return [.emptyKey(catalog: entry.catalog)]
        }

        var issues: [LocalizationAuditViolation] = []
        for locale in requiredLocales {
            guard let value = entry.translations[locale] else {
                issues.append(.missingLocale(catalog: entry.catalog, key: entry.key, locale: locale))
                continue
            }
            let state = entry.stateByLocale[locale] ?? "missing"
            if state != "translated" {
                issues.append(.untranslatedState(catalog: entry.catalog, key: entry.key, locale: locale, state: state))
            }
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.emptyTranslation(catalog: entry.catalog, key: entry.key, locale: locale))
            }
            if hasUnresolvedTemplateMarker(value) {
                issues.append(.unresolvedPlaceholder(catalog: entry.catalog, key: entry.key, locale: locale))
            }
        }

        if let enValue = entry.translations[.en], let zhValue = entry.translations[.zhHans] {
            let enSpecs = extractFormatSpecifiers(from: enValue)
            let zhSpecs = extractFormatSpecifiers(from: zhValue)
            if enSpecs != zhSpecs {
                issues.append(
                    .formatSpecifierMismatch(
                        catalog: entry.catalog,
                        key: entry.key,
                        enSpecifiers: enSpecs,
                        zhSpecifiers: zhSpecs
                    )
                )
            }
        }

        return issues
    }

    /// Audits a SwiftUI view source snippet to ensure no untracked `Text("foo.bar")` localization
    /// keys are introduced without `Text(verbatim:)` or an explicit `tableName:`.
    public static func auditSwiftUIViewSource(
        viewName: String,
        source: String
    ) -> [LocalizationAuditViolation] {
        let pattern = #"(?<![\w.])Text\s*\(\s*"([A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+)"\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, range: range)
        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let keyRange = Range(match.range(at: 1), in: source) else {
                return nil
            }
            return .untrackedDotKeyInView(viewName: viewName, key: String(source[keyRange]))
        }
    }

    public static func runAudit(
        entries: [LocalizationCatalogEntry],
        viewSources: [(viewName: String, source: String)] = []
    ) -> LocalizationZeroMissingKeysAuditReport {
        var allViolations: [LocalizationAuditViolation] = []
        for entry in entries {
            allViolations.append(contentsOf: auditEntry(entry))
        }
        for view in viewSources {
            allViolations.append(contentsOf: auditSwiftUIViewSource(viewName: view.viewName, source: view.source))
        }
        let catalogs = Array(Set(entries.map(\.catalog))).sorted { $0.rawValue < $1.rawValue }
        return LocalizationZeroMissingKeysAuditReport(
            auditedCatalogs: catalogs.isEmpty ? requiredCatalogs : catalogs,
            totalEntriesAudited: entries.count,
            totalViewsAudited: viewSources.count,
            violations: allViolations
        )
    }

    private static func hasUnresolvedTemplateMarker(_ text: String) -> Bool {
        text.contains("<#") || text.contains("#>") || text.contains("{{") || text.contains("}}") || text.contains("TODO:")
    }

    private static func extractFormatSpecifiers(from text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:lld|ld|lu|zu|d|i|u|f|g|s|@)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let specRange = Range(match.range, in: text) else { return nil }
            let raw = String(text[specRange])
            // Strip positional index like `1$` so reordered arguments across locales still match by type.
            return raw.replacingOccurrences(of: #"^\d+\$"#, with: "", options: .regularExpression)
        }.sorted()
    }
}

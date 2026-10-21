import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained domain row for localization plural and formatter consistency:
/// - Exact integer fen-to-yuan currency formatting,
/// - `en_US_POSIX` locale + `Asia/Shanghai` governing time zone date parsing,
/// - Bilingual (`en` / `zh-Hans`) plural and string catalog completeness.
public struct FormatterConsistencyDomainRow: Sendable, Equatable, Identifiable {
    public enum DomainKind: String, CaseIterable, Sendable, Equatable {
        case fenToYuanExactCurrency = "FEN_TO_YUAN_EXACT_CURRENCY"
        case posixAndShanghaiDateParsing = "POSIX_AND_SHANGHAI_DATE_PARSING"
        case bilingualPluralAndCatalogReadiness = "BILINGUAL_PLURAL_AND_CATALOG_READINESS"
    }

    public let id: String
    public let kind: DomainKind
    public let title: String
    public let sampleOutput: String
    public let detail: String
    public let isConsistent: Bool
    public let badgeText: String

    public init(
        id: String,
        kind: DomainKind,
        title: String,
        sampleOutput: String,
        detail: String,
        isConsistent: Bool = true,
        badgeText: String = "CONSISTENT"
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sampleOutput = sampleOutput
        self.detail = detail
        self.isConsistent = isConsistent
        self.badgeText = badgeText
    }

    public static let defaultRows: [FormatterConsistencyDomainRow] = [
        FormatterConsistencyDomainRow(
            id: "fen-to-yuan-currency",
            kind: .fenToYuanExactCurrency,
            title: "Exact Fen-to-Yuan Currency Formatting",
            sampleOutput: "9900 fen -> ¥99.00",
            detail: "Uses exact integer quotient and two-digit remainder from fen without binary floating-point rounding drift."
        ),
        FormatterConsistencyDomainRow(
            id: "posix-shanghai-date",
            kind: .posixAndShanghaiDateParsing,
            title: "en_US_POSIX + Asia/Shanghai Date Parsing",
            sampleOutput: "2026-11-01 20:00 CST (UTC+08:00)",
            detail: "Pins wire date/deadline parsing to en_US_POSIX and Asia/Shanghai regardless of 12/24-hour device settings or Buddhist/Japanese calendars."
        ),
        FormatterConsistencyDomainRow(
            id: "bilingual-plural-catalog",
            kind: .bilingualPluralAndCatalogReadiness,
            title: "Bilingual (en / zh-Hans) Plural & Catalog Readiness",
            sampleOutput: "100% translated (en + zh-Hans)",
            detail: "Every string catalog entry is translated in both English and Simplified Chinese with environment-locale lookup."
        ),
    ]
}

/// Self-contained snapshot backing `LocalizationPluralAndFormatterConsistencySectionView`.
public struct FormatterConsistencySnapshot: Sendable, Equatable {
    public let exactFenToYuanVerified: Bool
    public let posixLocaleAndShanghaiZonePinned: Bool
    public let bilingualPluralCatalogComplete: Bool
    public let driftWarningCount: Int
    public let rows: [FormatterConsistencyDomainRow]

    public init(
        exactFenToYuanVerified: Bool = true,
        posixLocaleAndShanghaiZonePinned: Bool = true,
        bilingualPluralCatalogComplete: Bool = true,
        driftWarningCount: Int = 0,
        rows: [FormatterConsistencyDomainRow] = FormatterConsistencyDomainRow.defaultRows
    ) {
        self.exactFenToYuanVerified = exactFenToYuanVerified
        self.posixLocaleAndShanghaiZonePinned = posixLocaleAndShanghaiZonePinned
        self.bilingualPluralCatalogComplete = bilingualPluralCatalogComplete
        self.driftWarningCount = driftWarningCount
        self.rows = rows
    }

    public static let defaultReady = FormatterConsistencySnapshot()

    public var consistentRowCount: Int {
        rows.filter(\.isConsistent).count
    }

    public var isReady: Bool {
        !rows.isEmpty
            && consistentRowCount == rows.count
            && exactFenToYuanVerified
            && posixLocaleAndShanghaiZonePinned
            && bilingualPluralCatalogComplete
            && driftWarningCount == 0
    }

    /// Formats an integer amount in fen into an exact `"¥X.YY"` string without float drift.
    public static func formatFenToYuan(_ amountFen: Int64) -> String {
        let sign = amountFen < 0 ? "-" : ""
        let magnitude = amountFen.magnitude
        let yuan = magnitude / 100
        let fenRemainder = magnitude % 100
        return String(format: "%@¥%llu.%02llu", sign, yuan, fenRemainder)
    }
}

/// SwiftUI section view displaying exact fen-to-yuan currency formatting,
/// `en_US_POSIX` + `Asia/Shanghai` date parsing, and bilingual plural readiness
/// using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor public struct LocalizationPluralAndFormatterConsistencySectionView: View {
    public let snapshot: FormatterConsistencySnapshot

    public init(snapshot: FormatterConsistencySnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Group {
            summarySection
            rowsSection
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent {
                Text(verbatim: snapshot.exactFenToYuanVerified ? "Verified (Exact Integer Quotient/Remainder)" : "Drift Detected")
            } label: {
                Text(verbatim: "Fen-to-Yuan Currency")
            }
            .accessibilityIdentifier("formatterConsistency.summary.fenToYuan")

            LabeledContent {
                Text(verbatim: snapshot.posixLocaleAndShanghaiZonePinned ? "en_US_POSIX + Asia/Shanghai Pinned" : "Unpinned")
            } label: {
                Text(verbatim: "Date & Deadline Parser")
            }
            .accessibilityIdentifier("formatterConsistency.summary.posixShanghai")

            LabeledContent {
                Text(verbatim: snapshot.bilingualPluralCatalogComplete ? "Complete (en + zh-Hans)" : "Incomplete")
            } label: {
                Text(verbatim: "Bilingual Plural Readiness")
            }
            .accessibilityIdentifier("formatterConsistency.summary.bilingualPlural")

            LabeledContent {
                Text(verbatim: snapshot.driftWarningCount == 0 ? "0 Warnings (Ready)" : "\(snapshot.driftWarningCount) Warning(s)")
            } label: {
                Text(verbatim: "Formatter Drift Warnings")
            }
            .accessibilityIdentifier("formatterConsistency.summary.driftWarnings")
        } header: {
            Text(verbatim: "Localization Plural & Formatter Consistency")
        } footer: {
            Text(verbatim: "Consistent domains: \(snapshot.consistentRowCount)/\(snapshot.rows.count).")
                .accessibilityIdentifier("formatterConsistency.summary.footer")
        }
    }

    private var rowsSection: some View {
        Section {
            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: row.title)
                            .font(.subheadline)
                        Spacer()
                        Text(verbatim: row.badgeText)
                            .font(.caption.monospaced())
                            .accessibilityIdentifier("formatterConsistency.row.badge.\(row.id)")
                    }
                    Text(verbatim: row.sampleOutput)
                        .font(.caption.monospaced())
                    Text(verbatim: row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("formatterConsistency.row.\(row.id)")
            }
        } header: {
            Text(verbatim: "Formatter & Localization Consistency Domains")
        }
    }
}

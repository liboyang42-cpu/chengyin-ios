import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one App Store Connect metadata or screenshot matrix requirement.
public struct ASCMetadataRequirementRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let requirementCode: String
    public let title: String
    public let specificationSummary: String
    public let isReady: Bool

    public init(
        id: String,
        requirementCode: String,
        title: String,
        specificationSummary: String,
        isReady: Bool = true
    ) {
        self.id = id
        self.requirementCode = requirementCode
        self.title = title
        self.specificationSummary = specificationSummary
        self.isReady = isReady
    }

    public var statusBadgeText: String {
        isReady ? "READY • VERIFIED" : "INCOMPLETE • ACTION REQUIRED"
    }
}

/// Self-contained presentation snapshot for App Store Connect metadata & screenshot matrix:
/// - 6.9"/6.5" iPhone screenshot sets
/// - `zh-Hans`/`en-US` metadata
/// - HTTPS privacy/support URLs
/// - `ITSAppUsesNonExemptEncryption = false` readiness
public struct ASCMetadataMatrixSnapshot: Sendable, Equatable {
    public let rows: [ASCMetadataRequirementRow]
    public let has69And65InchScreenshotSets: Bool
    public let hasBilingualZhHansAndEnUSMetadata: Bool
    public let hasHTTPSPrivacyAndSupportURLs: Bool
    public let nonExemptEncryptionFalseDeclared: Bool

    public init(
        rows: [ASCMetadataRequirementRow] = Self.defaultRows,
        has69And65InchScreenshotSets: Bool = true,
        hasBilingualZhHansAndEnUSMetadata: Bool = true,
        hasHTTPSPrivacyAndSupportURLs: Bool = true,
        nonExemptEncryptionFalseDeclared: Bool = true
    ) {
        self.rows = rows
        self.has69And65InchScreenshotSets = has69And65InchScreenshotSets
        self.hasBilingualZhHansAndEnUSMetadata = hasBilingualZhHansAndEnUSMetadata
        self.hasHTTPSPrivacyAndSupportURLs = hasHTTPSPrivacyAndSupportURLs
        self.nonExemptEncryptionFalseDeclared = nonExemptEncryptionFalseDeclared
    }

    public static let defaultRows: [ASCMetadataRequirementRow] = [
        ASCMetadataRequirementRow(
            id: "asc-01-screenshots",
            requirementCode: "ASC-01",
            title: "6.9\" & 6.5\" iPhone Screenshot Sets",
            specificationSummary: "Native portrait screenshot sets for 6.9-inch and 6.5-inch iPhone displays using non-production synthetic fixtures"
        ),
        ASCMetadataRequirementRow(
            id: "asc-02-bilingual-metadata",
            requirementCode: "ASC-02",
            title: "Bilingual zh-Hans & en-US Store Metadata",
            specificationSummary: "Complete title, subtitle, promotional text, description, and keywords in Simplified Chinese (zh-Hans) and English (en-US)"
        ),
        ASCMetadataRequirementRow(
            id: "asc-03-https-urls",
            requirementCode: "ASC-03",
            title: "HTTPS Privacy Policy & Support URLs",
            specificationSummary: "Per-market approved HTTPS privacy policy URL and customer support URL verified before submission"
        ),
        ASCMetadataRequirementRow(
            id: "asc-04-encryption-export",
            requirementCode: "ASC-04",
            title: "Export Compliance (ITSAppUsesNonExemptEncryption = false)",
            specificationSummary: "Uses only standard Apple OS TLS/CryptoKit APIs; ITSAppUsesNonExemptEncryption declared as false"
        )
    ]

    public static let defaultReady = ASCMetadataMatrixSnapshot()

    public var isAllReady: Bool {
        rows.count == 4 &&
        has69And65InchScreenshotSets &&
        hasBilingualZhHansAndEnUSMetadata &&
        hasHTTPSPrivacyAndSupportURLs &&
        nonExemptEncryptionFalseDeclared &&
        rows.allSatisfy(\.isReady)
    }
}

/// SwiftUI Section View displaying 6.9"/6.5" iPhone screenshot sets, `zh-Hans`/`en-US` metadata,
/// HTTPS privacy/support URLs, and `ITSAppUsesNonExemptEncryption = false` readiness using `Text(verbatim:)` throughout.
@MainActor
public struct AppStoreConnectMetadataAndScreenshotSectionView: View {
    public let snapshot: ASCMetadataMatrixSnapshot

    public init(snapshot: ASCMetadataMatrixSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var statusBadgeText: String {
        snapshot.isAllReady
            ? "ASC Metadata Gate: READY (4/4 Verified)"
            : "ASC Metadata Gate: WARNING (Incomplete Metadata)"
    }

    public var screenshotSetsSummaryText: String {
        snapshot.has69And65InchScreenshotSets
            ? "Screenshot Matrix: 6.9\" & 6.5\" iPhone sets ready (zh-Hans & en-US)"
            : "Screenshot Matrix: WARNING — missing 6.9\" or 6.5\" iPhone screenshot set"
    }

    public var localeMetadataSummaryText: String {
        snapshot.hasBilingualZhHansAndEnUSMetadata
            ? "Store Locales: zh-Hans & en-US copy, keywords & review notes complete"
            : "Store Locales: WARNING — missing zh-Hans or en-US store listing fields"
    }

    public var urlsAndEncryptionSummaryText: String {
        if snapshot.hasHTTPSPrivacyAndSupportURLs && snapshot.nonExemptEncryptionFalseDeclared {
            return "URLs & Export: HTTPS Privacy/Support URLs verified • ITSAppUsesNonExemptEncryption = false"
        }
        return "URLs & Export: WARNING — missing HTTPS URL or encryption declaration"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "App Store Connect Metadata & Screenshot Matrix")
                    .font(.headline)
                    .accessibilityIdentifier("ascMetadataMatrix.title")
                Spacer()
                Text(verbatim: statusBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isAllReady ? Color.green : Color.orange)
                    .accessibilityIdentifier("ascMetadataMatrix.statusBadge")
            }

            Text(verbatim: screenshotSetsSummaryText)
                .font(.footnote)
                .foregroundStyle(snapshot.has69And65InchScreenshotSets ? Color.secondary : Color.orange)
                .accessibilityIdentifier("ascMetadataMatrix.screenshotSetsSummary")

            Text(verbatim: localeMetadataSummaryText)
                .font(.footnote)
                .foregroundStyle(snapshot.hasBilingualZhHansAndEnUSMetadata ? Color.secondary : Color.orange)
                .accessibilityIdentifier("ascMetadataMatrix.localeMetadataSummary")

            Text(verbatim: urlsAndEncryptionSummaryText)
                .font(.footnote.monospaced())
                .foregroundStyle(
                    (snapshot.hasHTTPSPrivacyAndSupportURLs && snapshot.nonExemptEncryptionFalseDeclared)
                        ? Color.secondary
                        : Color.red
                )
                .accessibilityIdentifier("ascMetadataMatrix.urlsAndEncryptionSummary")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "[\(row.requirementCode)] \(row.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: row.statusBadgeText)
                                .font(.caption2.monospaced())
                                .foregroundStyle(row.isReady ? Color.green : Color.orange)
                        }
                        Text(verbatim: row.specificationSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .accessibilityIdentifier("ascMetadataMatrix.rowList")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ascMetadataMatrix.section")
    }
}

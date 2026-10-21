import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one iOS 17+ App Store privacy manifest audit item.
public struct PrivacyManifestCheckRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let categoryCode: String
    public let title: String
    public let declarationSummary: String
    public let isCompliant: Bool

    public init(
        id: String,
        categoryCode: String,
        title: String,
        declarationSummary: String,
        isCompliant: Bool = true
    ) {
        self.id = id
        self.categoryCode = categoryCode
        self.title = title
        self.declarationSummary = declarationSummary
        self.isCompliant = isCompliant
    }

    public var statusBadgeText: String {
        isCompliant ? "COMPLIANT" : "NON-COMPLIANT"
    }
}

/// Self-contained presentation snapshot for iOS 17+ privacy manifest readiness:
/// - `NSPrivacyTracking == false`
/// - Required-reason API categories
/// - `Info.plist` usage descriptions
/// - `W13.5` location permission decoupling
public struct AppStorePrivacyManifestSnapshot: Equatable, Sendable {
    public static let requiredReasonAPICategories: [String] = [
        "NSPrivacyAccessedAPICategoryUserDefaults (CA92.1)",
        "NSPrivacyAccessedAPICategoryFileTimestamp (C617.1)",
        "NSPrivacyAccessedAPICategorySystemBootTime (35F9.1)"
    ]

    public let checks: [PrivacyManifestCheckRow]
    public let nsPrivacyTrackingEnabled: Bool
    public let trackingDomainCount: Int
    public let declaredRequiredReasonCategories: [String]
    public let w13LocationPermissionDecoupled: Bool

    public init(
        checks: [PrivacyManifestCheckRow] = Self.defaultChecks,
        nsPrivacyTrackingEnabled: Bool = false,
        trackingDomainCount: Int = 0,
        declaredRequiredReasonCategories: [String] = Self.requiredReasonAPICategories,
        w13LocationPermissionDecoupled: Bool = true
    ) {
        self.checks = checks
        self.nsPrivacyTrackingEnabled = nsPrivacyTrackingEnabled
        self.trackingDomainCount = max(0, trackingDomainCount)
        self.declaredRequiredReasonCategories = declaredRequiredReasonCategories
        self.w13LocationPermissionDecoupled = w13LocationPermissionDecoupled
    }

    public static let defaultChecks: [PrivacyManifestCheckRow] = [
        PrivacyManifestCheckRow(
            id: "PM-01-tracking",
            categoryCode: "NSPrivacyTracking",
            title: "Zero Cross-App Tracking & Empty Tracking Domains",
            declarationSummary: "NSPrivacyTracking == false; NSPrivacyTrackingDomains == []; zero IDFA or third-party ad SDK collection"
        ),
        PrivacyManifestCheckRow(
            id: "PM-02-required-reason-apis",
            categoryCode: "RequiredReasonAPIs",
            title: "iOS 17+ Required-Reason API Declarations",
            declarationSummary: "Declares UserDefaults (CA92.1), FileTimestamp (C617.1), and SystemBootTime (35F9.1) strictly for app-scoped state and signposts"
        ),
        PrivacyManifestCheckRow(
            id: "PM-03-infoplist-usage",
            categoryCode: "InfoPlistUsage",
            title: "Info.plist Purpose Strings & ATS Enforcement",
            declarationSummary: "Explicit NSCameraUsageDescription and NSMotionUsageDescription present; NSAllowsArbitraryLoads absent"
        ),
        PrivacyManifestCheckRow(
            id: "PM-04-w13-location-decoupling",
            categoryCode: "W13.5-Location",
            title: "W13.5 Location Permission & Sharing Decoupling",
            declarationSummary: "Manual-area map browse requires zero location permission; preciseGrantEnabled defaults to false behind 6-item disclosure gate"
        )
    ]

    public static let verifiedDefault = AppStorePrivacyManifestSnapshot()

    public var isManifestReady: Bool {
        checks.count == 4 &&
        !nsPrivacyTrackingEnabled &&
        trackingDomainCount == 0 &&
        !declaredRequiredReasonCategories.isEmpty &&
        w13LocationPermissionDecoupled &&
        checks.allSatisfy(\.isCompliant)
    }
}

/// SwiftUI Section View rendering iOS 17+ App Store privacy manifest readiness using `Text(verbatim:)` throughout.
@MainActor
public struct AppStorePrivacyManifestSectionView: View {
    public let snapshot: AppStorePrivacyManifestSnapshot

    public init(snapshot: AppStorePrivacyManifestSnapshot = .verifiedDefault) {
        self.snapshot = snapshot
    }

    public var statusBadgeText: String {
        snapshot.isManifestReady
            ? "Privacy Manifest: READY (4/4 Checks Compliant)"
            : "Privacy Manifest: ACTION REQUIRED"
    }

    public var trackingBannerText: String {
        "NSPrivacyTracking: \(snapshot.nsPrivacyTrackingEnabled ? "true (VIOLATION)" : "false") • Tracking Domains: \(snapshot.trackingDomainCount)"
    }

    public var locationDecouplingBannerText: String {
        snapshot.w13LocationPermissionDecoupled
            ? "W13.5 Location Decoupling: ENFORCED (Manual browse independent of GPS grant; precise share OFF)"
            : "W13.5 Location Decoupling: VIOLATION (Permission coupled)"
    }

    public var requiredReasonSummaryText: String {
        "Required-Reason APIs (\(snapshot.declaredRequiredReasonCategories.count)): " +
            snapshot.declaredRequiredReasonCategories.joined(separator: ", ")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "iOS 17+ App Store Privacy Manifest Audit")
                    .font(.headline)
                    .accessibilityIdentifier("privacyManifestAudit.title")
                Spacer()
                Text(verbatim: statusBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isManifestReady ? Color.green : Color.red)
                    .accessibilityIdentifier("privacyManifestAudit.statusBadge")
            }

            Text(verbatim: trackingBannerText)
                .font(.footnote.monospaced())
                .foregroundStyle(snapshot.nsPrivacyTrackingEnabled || snapshot.trackingDomainCount > 0 ? Color.red : Color.secondary)
                .accessibilityIdentifier("privacyManifestAudit.trackingBanner")

            Text(verbatim: locationDecouplingBannerText)
                .font(.footnote)
                .foregroundStyle(snapshot.w13LocationPermissionDecoupled ? Color.secondary : Color.red)
                .accessibilityIdentifier("privacyManifestAudit.locationDecouplingBanner")

            Text(verbatim: requiredReasonSummaryText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("privacyManifestAudit.requiredReasonSummary")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.checks) { check in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "[\(check.categoryCode)] \(check.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: check.statusBadgeText)
                                .font(.caption2.monospaced())
                                .foregroundStyle(check.isCompliant ? Color.green : Color.red)
                        }
                        Text(verbatim: check.declarationSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .accessibilityIdentifier("privacyManifestAudit.checkList")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("privacyManifestAudit.section")
    }
}

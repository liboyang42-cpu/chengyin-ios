import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained App Store Review rejection defense rule row for `AppStoreReviewRejectionPreventionSectionView`.
public struct RejectionDefenseRuleRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let guidelineCode: String
    public let title: String
    public let defenseSummary: String
    public let isDefenseVerified: Bool

    public init(
        id: String? = nil,
        guidelineCode: String,
        title: String,
        defenseSummary: String,
        isDefenseVerified: Bool = true
    ) {
        self.id = id ?? guidelineCode
        self.guidelineCode = guidelineCode
        self.title = title
        self.defenseSummary = defenseSummary
        self.isDefenseVerified = isDefenseVerified
    }

    public var rowAccessibilityIdentifier: String {
        "reviewRejectionPlaybook.rule.\(id)"
    }

    public var statusAccessibilityIdentifier: String {
        "reviewRejectionPlaybook.status.\(id)"
    }
}

/// Self-contained snapshot covering the Top-8 App Store Review Rejection Prevention defenses
/// (`2.1`, `1.2`, `3.1.1`, `4.8`, `5.1.1(i)`, `5.1.1(v)`, `5.1.2`, `ITMS-91053`).
public struct RejectionPreventionPlaybookSnapshot: Sendable, Equatable {
    public static let canonicalGuidelineCodes: [String] = [
        "2.1",
        "1.2",
        "3.1.1",
        "4.8",
        "5.1.1(i)",
        "5.1.1(v)",
        "5.1.2",
        "ITMS-91053"
    ]

    public let rules: [RejectionDefenseRuleRow]

    public init(rules: [RejectionDefenseRuleRow]) {
        self.rules = rules
    }

    public var verifiedRuleCount: Int {
        rules.filter(\.isDefenseVerified).count
    }

    public var undefendedGuidelineCodes: [String] {
        rules.filter { !$0.isDefenseVerified }.map(\.guidelineCode)
    }

    public var isAllReady: Bool {
        rules.count == Self.canonicalGuidelineCodes.count &&
            rules.map(\.guidelineCode) == Self.canonicalGuidelineCodes &&
            undefendedGuidelineCodes.isEmpty
    }

    public static let defaultReady = RejectionPreventionPlaybookSnapshot(
        rules: [
            RejectionDefenseRuleRow(
                id: "2.1",
                guidelineCode: "2.1",
                title: "App Completeness & Out-of-City LBS Preview",
                defenseSummary: "Pre-seeded city/POI roam preview and multi-role reviewer walkthrough without blank screens",
                isDefenseVerified: true
            ),
            RejectionDefenseRuleRow(
                id: "1.2",
                guidelineCode: "1.2",
                title: "User-Generated Content Moderation & Report/Block",
                defenseSummary: "Square & IM report/block actions, keyword filter, and immediate 404/DELETED media eviction",
                isDefenseVerified: true
            ),
            RejectionDefenseRuleRow(
                id: "3.1.1",
                guidelineCode: "3.1.1",
                title: "In-App Purchase & Digital vs Physical Payment Boundary",
                defenseSummary: "StoreKit 2 handles digital entitlements; physical event payments remain gated by market",
                isDefenseVerified: true
            ),
            RejectionDefenseRuleRow(
                id: "4.8",
                guidelineCode: "4.8",
                title: "Sign in with Apple Parity & Credential Hygiene",
                defenseSummary: "Equivalent privacy-preserving sign-in option whenever third-party login is enabled",
                isDefenseVerified: true
            ),
            RejectionDefenseRuleRow(
                id: "5.1.1(i)",
                guidelineCode: "5.1.1(i)",
                title: "Privacy Policy & Contextual Permission Prompts",
                defenseSummary: "Just-in-time Location, Camera, Photo, and Microphone prompts with non-blocking browse fallback",
                isDefenseVerified: true
            ),
            RejectionDefenseRuleRow(
                id: "5.1.1(v)",
                guidelineCode: "5.1.1(v)",
                title: "In-App Account Deletion & Consent Withdrawal",
                defenseSummary: "Direct settings entry for account deregistration, token purge, and NPC memory clear",
                isDefenseVerified: true
            ),
            RejectionDefenseRuleRow(
                id: "5.1.2",
                guidelineCode: "5.1.2",
                title: "Data Use & Sharing / Zero Unauthorized Tracking",
                defenseSummary: "NSPrivacyTracking = false, zero IDFA collection, and scenario-isolated NPC AI prompts",
                isDefenseVerified: true
            ),
            RejectionDefenseRuleRow(
                id: "ITMS-91053",
                guidelineCode: "ITMS-91053",
                title: "PrivacyInfo.xcprivacy Required-Reason API Declarations",
                defenseSummary: "Bundled PrivacyInfo.xcprivacy declares UserDefaults, FileTimestamp, and SystemBootTime APIs",
                isDefenseVerified: true
            )
        ]
    )

    public static func withUndefendedGuidelines(
        _ codes: Set<String>
    ) -> RejectionPreventionPlaybookSnapshot {
        let updated = defaultReady.rules.map { rule in
            guard codes.contains(rule.guidelineCode) || codes.contains(rule.id) else {
                return rule
            }
            return RejectionDefenseRuleRow(
                id: rule.id,
                guidelineCode: rule.guidelineCode,
                title: rule.title,
                defenseSummary: rule.defenseSummary,
                isDefenseVerified: false
            )
        }
        return RejectionPreventionPlaybookSnapshot(rules: updated)
    }
}

@MainActor
public struct AppStoreReviewRejectionPreventionSectionView: View {
    public let snapshot: RejectionPreventionPlaybookSnapshot
    public var onSelectRule: ((RejectionDefenseRuleRow) -> Void)?

    public init(
        snapshot: RejectionPreventionPlaybookSnapshot = .defaultReady,
        onSelectRule: ((RejectionDefenseRuleRow) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectRule = onSelectRule
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            summaryBanner
            ForEach(snapshot.rules) { rule in
                ruleCard(rule)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviewRejectionPlaybook.section")
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.teal)
            Text(verbatim: "App Store Review Rejection Prevention Playbook")
                .font(.headline)
                .accessibilityIdentifier("reviewRejectionPlaybook.header")
            Spacer()
            Text(verbatim: headerBadgeText)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(headerBadgeTint.opacity(0.16))
                )
                .foregroundStyle(headerBadgeTint)
                .accessibilityIdentifier("reviewRejectionPlaybook.summaryBadge")
        }
    }

    private var summaryBanner: some View {
        HStack(spacing: 8) {
            pill(
                text: "Defended: \(snapshot.verifiedRuleCount)/\(snapshot.rules.count)",
                tint: snapshot.isAllReady ? .green : .red
            )
            pill(
                text: "Guidelines 2.1 · 1.2 · 3.1.1 · 4.8 · 5.1.x · ITMS-91053",
                tint: .blue
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reviewRejectionPlaybook.summaryBanner")
    }

    private func ruleCard(_ rule: RejectionDefenseRuleRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(verbatim: "[\(rule.guidelineCode)] \(rule.title)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: rule.isDefenseVerified ? "DEFENDED" : "UNDEFENDED WARNING")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill((rule.isDefenseVerified ? Color.green : Color.red).opacity(0.16))
                    )
                    .foregroundStyle(rule.isDefenseVerified ? Color.green : Color.red)
                    .accessibilityIdentifier(rule.statusAccessibilityIdentifier)
            }

            Text(verbatim: rule.defenseSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectRule?(rule)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(rule.rowAccessibilityIdentifier)
    }

    private func pill(text: String, tint: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .foregroundStyle(tint)
    }

    public var headerBadgeText: String {
        if snapshot.isAllReady {
            return "ALL 8 GUIDELINES DEFENDED"
        }
        return "WARNING: \(snapshot.undefendedGuidelineCodes.count) UNDEFENDED"
    }

    private var headerBadgeTint: Color {
        snapshot.isAllReady ? .green : .red
    }
}

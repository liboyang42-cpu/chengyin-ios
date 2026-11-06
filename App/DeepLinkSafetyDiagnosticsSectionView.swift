import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained Universal Link & deep-link safety rule row covering HTTPS host allowlist,
/// `w2-12` `memberID <= 0` incomplete link fallback, cross-market realm isolation, and
/// zero auto-mutation guarantees.
public struct DeepLinkSafetyRuleRow: Identifiable, Equatable, Sendable {
    public enum Category: String, CaseIterable, Equatable, Sendable {
        case httpsHostAllowlist = "HTTPS_HOST_ALLOWLIST"
        case incompleteMemberIDFallback = "W2_12_INCOMPLETE_MEMBER_ID_FALLBACK"
        case crossMarketRealmIsolation = "CROSS_MARKET_REALM_ISOLATION"
        case zeroAutoMutationGuarantee = "ZERO_AUTO_MUTATION_GUARANTEE"
    }

    public let id: String
    public let category: Category
    public let title: String
    public let detail: String
    public let isEnforced: Bool
    public let badgeText: String

    public init(
        id: String,
        category: Category,
        title: String,
        detail: String,
        isEnforced: Bool = true,
        badgeText: String = "ENFORCED"
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.isEnforced = isEnforced
        self.badgeText = badgeText
    }

    public static let defaultRules: [DeepLinkSafetyRuleRow] = [
        DeepLinkSafetyRuleRow(
            id: "https-host-allowlist",
            category: .httpsHostAllowlist,
            title: "HTTPS Host Allowlist Only",
            detail: "Universal Links require an explicit HTTPS scheme and an allowlisted regional host; custom schemes or unknown hosts are rejected."
        ),
        DeepLinkSafetyRuleRow(
            id: "w2-12-member-id-fallback",
            category: .incompleteMemberIDFallback,
            title: "w2-12 Incomplete Member Link Fallback (memberID <= 0)",
            detail: "Missing, zero, or negative memberID parameters route to a safe incomplete-link fallback state without issuing profile requests."
        ),
        DeepLinkSafetyRuleRow(
            id: "cross-market-realm-isolation",
            category: .crossMarketRealmIsolation,
            title: "Cross-Market & Auth Realm Isolation",
            detail: "Links targeting a foreign market or mismatched auth realm are blocked and never cross-read or cross-write regional session storage."
        ),
        DeepLinkSafetyRuleRow(
            id: "zero-auto-mutation",
            category: .zeroAutoMutationGuarantee,
            title: "Zero Auto-Mutation Guarantee",
            detail: "Opening a deep link is strictly a read-only navigation intent and never triggers background POST/PUT/DELETE mutations or payments."
        ),
    ]
}

/// Self-contained snapshot backing `DeepLinkSafetyDiagnosticsSectionView`.
public struct DeepLinkSafetySnapshot: Equatable, Sendable {
    public enum Outcome: String, Equatable, Sendable {
        case acceptedReadOnlyRoute = "ACCEPTED_READ_ONLY_ROUTE"
        case incompleteMemberIDFallback = "INCOMPLETE_MEMBER_ID_FALLBACK"
        case rejectedUntrustedHostOrScheme = "REJECTED_UNTRUSTED_HOST_OR_SCHEME"
        case rejectedCrossMarketRealm = "REJECTED_CROSS_MARKET_REALM"
        case rejectedMutationAttempt = "REJECTED_MUTATION_ATTEMPT"
    }

    public let activeMarketCode: String
    public let activeAuthRealm: String
    public let allowlistedHTTPSHostsCount: Int
    public let lastEvaluatedOutcome: Outcome
    public let lastEvaluatedSummary: String
    public let rules: [DeepLinkSafetyRuleRow]

    public init(
        activeMarketCode: String = "cn",
        activeAuthRealm: String = "cn-prod",
        allowlistedHTTPSHostsCount: Int = 1,
        lastEvaluatedOutcome: Outcome = .acceptedReadOnlyRoute,
        lastEvaluatedSummary: String = "Verified read-only Universal Link route on allowlisted HTTPS host.",
        rules: [DeepLinkSafetyRuleRow] = DeepLinkSafetyRuleRow.defaultRules
    ) {
        self.activeMarketCode = activeMarketCode
        self.activeAuthRealm = activeAuthRealm
        self.allowlistedHTTPSHostsCount = allowlistedHTTPSHostsCount
        self.lastEvaluatedOutcome = lastEvaluatedOutcome
        self.lastEvaluatedSummary = lastEvaluatedSummary
        self.rules = rules
    }

    public static let standard = DeepLinkSafetySnapshot()

    public var enforcedRuleCount: Int {
        rules.filter(\.isEnforced).count
    }

    public var allRulesEnforced: Bool {
        !rules.isEmpty && enforcedRuleCount == rules.count && allowlistedHTTPSHostsCount > 0
    }

    /// Deep links never auto-mutate client or server state.
    public var allowsAutoMutation: Bool {
        false
    }

    /// Evaluates a candidate member/card Universal Link against the four deep-link safety invariants.
    public static func evaluateMemberCardLink(
        scheme: String,
        host: String,
        allowlistedHTTPSHosts: Set<String>,
        linkMarketCode: String,
        activeMarketCode: String,
        linkRealm: String,
        activeAuthRealm: String,
        memberID: Int?,
        attemptsMutation: Bool = false,
        rules: [DeepLinkSafetyRuleRow] = DeepLinkSafetyRuleRow.defaultRules
    ) -> DeepLinkSafetySnapshot {
        let normalizedScheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedAllowlist = Set(allowlistedHTTPSHosts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        guard normalizedScheme == "https",
              !normalizedHost.isEmpty,
              normalizedAllowlist.contains(normalizedHost)
        else {
            return DeepLinkSafetySnapshot(
                activeMarketCode: activeMarketCode,
                activeAuthRealm: activeAuthRealm,
                allowlistedHTTPSHostsCount: normalizedAllowlist.count,
                lastEvaluatedOutcome: .rejectedUntrustedHostOrScheme,
                lastEvaluatedSummary: "Rejected link: requires HTTPS and an allowlisted regional host.",
                rules: rules
            )
        }

        guard linkMarketCode == activeMarketCode, linkRealm == activeAuthRealm else {
            return DeepLinkSafetySnapshot(
                activeMarketCode: activeMarketCode,
                activeAuthRealm: activeAuthRealm,
                allowlistedHTTPSHostsCount: normalizedAllowlist.count,
                lastEvaluatedOutcome: .rejectedCrossMarketRealm,
                lastEvaluatedSummary: "Rejected link: target market or auth realm does not match active session scope.",
                rules: rules
            )
        }

        guard !attemptsMutation else {
            return DeepLinkSafetySnapshot(
                activeMarketCode: activeMarketCode,
                activeAuthRealm: activeAuthRealm,
                allowlistedHTTPSHostsCount: normalizedAllowlist.count,
                lastEvaluatedOutcome: .rejectedMutationAttempt,
                lastEvaluatedSummary: "Rejected link: deep links are read-only and never auto-trigger write mutations.",
                rules: rules
            )
        }

        guard let memberID, memberID > 0 else {
            return DeepLinkSafetySnapshot(
                activeMarketCode: activeMarketCode,
                activeAuthRealm: activeAuthRealm,
                allowlistedHTTPSHostsCount: normalizedAllowlist.count,
                lastEvaluatedOutcome: .incompleteMemberIDFallback,
                lastEvaluatedSummary: "w2-12 fallback: memberID is missing or <= 0; routed to safe incomplete-link presentation.",
                rules: rules
            )
        }

        return DeepLinkSafetySnapshot(
            activeMarketCode: activeMarketCode,
            activeAuthRealm: activeAuthRealm,
            allowlistedHTTPSHostsCount: normalizedAllowlist.count,
            lastEvaluatedOutcome: .acceptedReadOnlyRoute,
            lastEvaluatedSummary: "Accepted read-only member route (#\(memberID)) within \(activeMarketCode)/\(activeAuthRealm).",
            rules: rules
        )
    }
}

/// SwiftUI diagnostics section view rendering Universal Link & deep-link safety guarantees
/// using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor public struct DeepLinkSafetyDiagnosticsSectionView: View {
    public let snapshot: DeepLinkSafetySnapshot

    public init(snapshot: DeepLinkSafetySnapshot = .standard) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Group {
            summarySection
            rulesSection
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent {
                Text(verbatim: "\(snapshot.activeMarketCode.uppercased()) • \(snapshot.activeAuthRealm)")
            } label: {
                Text(verbatim: "Active Market & Realm")
            }
            .accessibilityIdentifier("deepLinkSafety.summary.marketRealm")

            LabeledContent {
                Text(verbatim: "\(snapshot.allowlistedHTTPSHostsCount) HTTPS host(s)")
            } label: {
                Text(verbatim: "Allowlisted Universal Link Hosts")
            }
            .accessibilityIdentifier("deepLinkSafety.summary.hostAllowlist")

            LabeledContent {
                Text(verbatim: snapshot.allowsAutoMutation ? "UNSAFE" : "DISABLED (Read-Only Navigation)")
            } label: {
                Text(verbatim: "Auto-Mutation Policy")
            }
            .accessibilityIdentifier("deepLinkSafety.summary.zeroAutoMutation")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: "Last Evaluated Link Outcome")
                        .font(.subheadline)
                    Spacer()
                    Text(verbatim: snapshot.lastEvaluatedOutcome.rawValue)
                        .font(.caption.monospaced())
                }
                Text(verbatim: snapshot.lastEvaluatedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("deepLinkSafety.summary.lastOutcome")
        } header: {
            Text(verbatim: "Universal Link & Deep-Link Safety Diagnostics")
        } footer: {
            Text(verbatim: "Enforced rules: \(snapshot.enforcedRuleCount)/\(snapshot.rules.count). Incomplete memberID <= 0 links fall back safely (w2-12).")
                .accessibilityIdentifier("deepLinkSafety.summary.footer")
        }
    }

    private var rulesSection: some View {
        Section {
            ForEach(snapshot.rules) { rule in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: rule.title)
                            .font(.subheadline)
                        Spacer()
                        Text(verbatim: rule.badgeText)
                            .font(.caption.monospaced())
                            .accessibilityIdentifier("deepLinkSafety.rule.badge.\(rule.id)")
                    }
                    Text(verbatim: rule.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("deepLinkSafety.rule.\(rule.id)")
            }
        } header: {
            Text(verbatim: "Deep-Link Safety Invariants")
        }
    }
}

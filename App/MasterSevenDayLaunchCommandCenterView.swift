import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained pillar item for the unified 7-Day Launch Command Center:
/// 1. `Day 1–7 Launch Critical Path`,
/// 2. `Native Superset Over Mini-Program Policy`,
/// 3. `Final Zero-Gap Certificate`,
/// 4. `App Store Review Demo Readiness`,
/// 5. `Account Deletion & PIPL Compliance`,
/// 6. `Runtime Crash/Cache/Keychain Resilience`.
public struct SevenDayCommandPillarItem: Sendable, Equatable, Identifiable {
    public enum PillarType: String, CaseIterable, Sendable, Equatable {
        case dayOneToSevenCriticalPath = "DAY_1_TO_7_LAUNCH_CRITICAL_PATH"
        case nativeSupersetOverMiniProgramPolicy = "NATIVE_SUPERSET_OVER_MINI_PROGRAM_POLICY"
        case finalZeroGapCertificate = "FINAL_ZERO_GAP_CERTIFICATE"
        case appStoreReviewDemoReadiness = "APP_STORE_REVIEW_DEMO_READINESS"
        case accountDeletionAndPIPLCompliance = "ACCOUNT_DELETION_AND_PIPL_COMPLIANCE"
        case runtimeCrashCacheKeychainResilience = "RUNTIME_CRASH_CACHE_KEYCHAIN_RESILIENCE"
    }

    public let id: String
    public let pillarType: PillarType
    public let title: String
    public let summary: String
    public let isReady: Bool
    public let statusBadge: String

    public init(
        id: String,
        pillarType: PillarType,
        title: String,
        summary: String,
        isReady: Bool = false,
        statusBadge: String = "NOT_VERIFIED"
    ) {
        self.id = id
        self.pillarType = pillarType
        self.title = title
        self.summary = summary
        self.isReady = isReady
        self.statusBadge = statusBadge
    }

    public static let defaultPillars: [SevenDayCommandPillarItem] = [
        SevenDayCommandPillarItem(
            id: "day-1-7-critical-path",
            pillarType: .dayOneToSevenCriticalPath,
            title: "Day 1–7 Launch Critical Path",
            summary: "Seven daily milestones require 40-hex-SHA-bound test results and external ops sign-off; no evidence means not verified."
        ),
        SevenDayCommandPillarItem(
            id: "native-superset-policy",
            pillarType: .nativeSupersetOverMiniProgramPolicy,
            title: "Native Superset Over Mini-Program Policy",
            summary: "Preserves 100% WeChat mini-program parity while gating App-only Reform Plan v9 capabilities safely behind ReformWorldCapabilities.disabled."
        ),
        SevenDayCommandPillarItem(
            id: "final-zero-gap-certificate",
            pillarType: .finalZeroGapCertificate,
            title: "Final Zero-Gap Certificate",
            summary: "Phase 0..Phase 5, MV01..MV41 (41/41), U01..U08 (8/8), and W02..W20 (19/19) reconciled with zero unowned gaps."
        ),
        SevenDayCommandPillarItem(
            id: "app-store-review-demo-readiness",
            pillarType: .appStoreReviewDemoReadiness,
            title: "App Store Review Demo Readiness",
            summary: "Guideline 2.1 Guest, Player, Merchant, and Club Admin walkthroughs ready with out-of-city LBS preview fallback."
        ),
        SevenDayCommandPillarItem(
            id: "account-deletion-and-pipl",
            pillarType: .accountDeletionAndPIPLCompliance,
            title: "Account Deletion & PIPL Compliance",
            summary: "Guideline 5.1.1(v) in-app account deletion, explicit voluntary location consent disclosures, and immediate local token/cache purge enforced."
        ),
        SevenDayCommandPillarItem(
            id: "runtime-crash-cache-keychain-resilience",
            pillarType: .runtimeCrashCacheKeychainResilience,
            title: "Runtime Crash/Cache/Keychain Resilience",
            summary: "thisDeviceOnly Keychain attributes, durable CAS recovery journals, single-flight 401 invalidation, and lifecycle-cancelled polling verified."
        ),
    ]
}

/// Self-contained snapshot backing `MasterSevenDayLaunchCommandCenterView`.
public struct MasterSevenDayLaunchCommandSnapshot: Sendable, Equatable {
    public let targetWindowLabel: String
    public let zeroGapCertificateIssued: Bool
    public let nativeSupersetPolicyEnforced: Bool
    public let blockedPillarCount: Int
    public let pillars: [SevenDayCommandPillarItem]

    public init(
        targetWindowLabel: String = "Day 1–Day 7 Launch Window",
        zeroGapCertificateIssued: Bool = false,
        nativeSupersetPolicyEnforced: Bool = false,
        blockedPillarCount: Int? = nil,
        pillars: [SevenDayCommandPillarItem] = SevenDayCommandPillarItem.defaultPillars
    ) {
        self.targetWindowLabel = targetWindowLabel
        self.zeroGapCertificateIssued = zeroGapCertificateIssued
        self.nativeSupersetPolicyEnforced = nativeSupersetPolicyEnforced
        self.pillars = pillars
        self.blockedPillarCount = blockedPillarCount ?? pillars.filter { !$0.isReady }.count
    }

    /// Fail-closed default: no pillar, certificate or policy is reported as verified.
    public static let unverified = MasterSevenDayLaunchCommandSnapshot()

    /// Deprecated name kept for source compatibility; it is fail-closed (NOT ready).
    public static let defaultReady = MasterSevenDayLaunchCommandSnapshot.unverified

    /// Reads the Core fail-closed 7-day result into pillar 1. Other pillars stay unverified
    /// until their own evidence is wired, so this never yields a ready command center by itself.
    public static func from(
        sevenDayEvaluation: SevenDayLaunchMilestoneEvaluation
    ) -> MasterSevenDayLaunchCommandSnapshot {
        var pillars = SevenDayCommandPillarItem.defaultPillars
        let verified = sevenDayEvaluation.isSevenDayLaunchFullyVerified
        pillars[0] = SevenDayCommandPillarItem(
            id: pillars[0].id,
            pillarType: pillars[0].pillarType,
            title: pillars[0].title,
            summary: verified
                ? "Verified against commit \(sevenDayEvaluation.boundCommitSHA ?? "")."
                : "Verified days \(sevenDayEvaluation.verifiedDays)/7, failed \(sevenDayEvaluation.failedDays).",
            isReady: verified,
            statusBadge: verified ? "VERIFIED" : (sevenDayEvaluation.failedDays > 0 ? "FAILED" : "NOT_VERIFIED")
        )
        return MasterSevenDayLaunchCommandSnapshot(pillars: pillars)
    }

    public var readyPillarCount: Int {
        pillars.filter(\.isReady).count
    }

    public var isCommandCenterLaunchReady: Bool {
        pillars.count == 6
            && readyPillarCount == 6
            && zeroGapCertificateIssued
            && nativeSupersetPolicyEnforced
            && blockedPillarCount == 0
    }
}

/// Unified 7-Day Launch Command Center SwiftUI view using `Text(verbatim:)` throughout
/// (0 new localization keys) and `.accessibilityIdentifier("sevenDayCommandCenter.*")` hooks.
@MainActor public struct MasterSevenDayLaunchCommandCenterView: View {
    public let snapshot: MasterSevenDayLaunchCommandSnapshot

    public init(snapshot: MasterSevenDayLaunchCommandSnapshot = .unverified) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Group {
            summarySection
            pillarsSection
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent {
                Text(verbatim: snapshot.isCommandCenterLaunchReady
                    ? "LAUNCH READY (6/6 Pillars Verified)"
                    : "NOT VERIFIED (\(snapshot.blockedPillarCount) Pillar(s) Pending)")
            } label: {
                Text(verbatim: "Command Center Status")
            }
            .accessibilityIdentifier("sevenDayCommandCenter.summary.status")

            LabeledContent {
                Text(verbatim: snapshot.targetWindowLabel)
            } label: {
                Text(verbatim: "Execution Window")
            }
            .accessibilityIdentifier("sevenDayCommandCenter.summary.window")

            LabeledContent {
                Text(verbatim: snapshot.nativeSupersetPolicyEnforced
                    ? "Enforced (Mini-Program Parity + Gated App Superset)"
                    : "Policy Drift")
            } label: {
                Text(verbatim: "Native Superset Policy")
            }
            .accessibilityIdentifier("sevenDayCommandCenter.summary.supersetPolicy")

            LabeledContent {
                Text(verbatim: snapshot.zeroGapCertificateIssued ? "Issued (0 Unowned Gaps)" : "Pending")
            } label: {
                Text(verbatim: "Final Zero-Gap Certificate")
            }
            .accessibilityIdentifier("sevenDayCommandCenter.summary.zeroGap")
        } header: {
            Text(verbatim: "Master 7-Day Launch Command Center")
        } footer: {
            Text(verbatim: "Ready pillars: \(snapshot.readyPillarCount)/\(snapshot.pillars.count).")
                .accessibilityIdentifier("sevenDayCommandCenter.summary.footer")
        }
    }

    private var pillarsSection: some View {
        Section {
            ForEach(snapshot.pillars) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: item.title)
                            .font(.subheadline)
                        Spacer()
                        Text(verbatim: item.statusBadge)
                            .font(.caption.monospaced())
                            .accessibilityIdentifier("sevenDayCommandCenter.pillar.badge.\(item.id)")
                    }
                    Text(verbatim: item.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("sevenDayCommandCenter.pillar.\(item.id)")
            }
        } header: {
            Text(verbatim: "7-Day Launch Command Pillars (6 Pillars)")
        }
    }
}

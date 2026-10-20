import Foundation

/// Verification state of an individual release acceptance pillar or check.
public enum ReleaseCheckStatus: String, Sendable, Equatable, CaseIterable {
    case passed
    case failed
    case pending
    case notRun
}

/// External evidence record required to evaluate a release certificate pillar against a specific commit SHA.
public struct ReleasePillarEvidenceInput: Sendable, Equatable, Identifiable {
    public var id: String { pillarID }
    public let pillarID: String
    public let targetCommitSHA: String
    public let evaluatedAtISO8601: String
    public let status: ReleaseCheckStatus
    public let completedCount: Int
    public let requiredCount: Int
    public let openBlockerCount: Int
    public let hasMergeConflict: Bool
    public let evidenceLinks: [String]

    public init(
        pillarID: String,
        targetCommitSHA: String,
        evaluatedAtISO8601: String,
        status: ReleaseCheckStatus,
        completedCount: Int,
        requiredCount: Int,
        openBlockerCount: Int,
        hasMergeConflict: Bool = false,
        evidenceLinks: [String]
    ) {
        self.pillarID = pillarID
        self.targetCommitSHA = targetCommitSHA
        self.evaluatedAtISO8601 = evaluatedAtISO8601
        self.status = status
        self.completedCount = completedCount
        self.requiredCount = requiredCount
        self.openBlockerCount = openBlockerCount
        self.hasMergeConflict = hasMergeConflict
        self.evidenceLinks = evidenceLinks
    }
}

/// Single pillar in the Final Release Signoff & Zero-Gap Certificate.
/// Never defaults to certified: requires explicit `.passed` status, non-empty commit SHA, timestamp, and evidence links.
public struct ReleaseCertificatePillar: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let completedCount: Int
    public let requiredCount: Int
    public let zeroOpenBlockers: Bool
    public let status: ReleaseCheckStatus
    public let commitSHA: String
    public let evaluatedAtISO8601: String
    public let evidenceLinks: [String]

    public init(
        id: String,
        title: String,
        completedCount: Int,
        requiredCount: Int,
        zeroOpenBlockers: Bool = false,
        status: ReleaseCheckStatus = .notRun,
        commitSHA: String = "",
        evaluatedAtISO8601: String = "",
        evidenceLinks: [String] = []
    ) {
        self.id = id
        self.title = title
        self.completedCount = completedCount
        self.requiredCount = requiredCount
        self.zeroOpenBlockers = zeroOpenBlockers
        self.status = status
        self.commitSHA = commitSHA
        self.evaluatedAtISO8601 = evaluatedAtISO8601
        self.evidenceLinks = evidenceLinks
    }

    public var isPreviewOrFixtureSHA: Bool {
        let lower = commitSHA.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.contains("fixture") || lower.contains("preview") || lower.contains("mock")
    }

    public static func isValidISO8601Timestamp(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20, trimmed.contains("T"),
              (trimmed.hasSuffix("Z") || trimmed.contains("+") || trimmed.dropFirst(10).contains("-")) else {
            return false
        }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: trimmed) != nil
    }

    public var hasValidEvidence: Bool {
        let trimmedSHA = commitSHA.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedSHA.isEmpty &&
            !isPreviewOrFixtureSHA &&
            Self.isValidISO8601Timestamp(evaluatedAtISO8601) &&
            !evidenceLinks.isEmpty &&
            evidenceLinks.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var isCertified: Bool {
        status == .passed &&
        completedCount >= requiredCount &&
        requiredCount > 0 &&
        zeroOpenBlockers &&
        hasValidEvidence
    }
}

/// Final Release Signoff & Zero-Gap Certificate evaluator.
/// Default state is fail-closed (`unverified` / `isZeroGapCertified == false`) until all 6 pillars
/// supply passing evidence bound to the exact target `commitSHA` with zero open blockers and no merge conflicts.
public struct FinalReleaseSignoffAndZeroGapCertificateContract: Sendable, Equatable {
    public static let totalBatches = 15
    public static let totalParallelLanes = 175

    public static let masterDocuments: [String] = [
        "交接文档_20261020.md",
        "落地清单.md",
        "工单-统一实施版.md"
    ]

    /// Unverified baseline definitions. Without external evidence records bound to a target SHA,
    /// every pillar starts in `.notRun` with `completedCount = 0` and `zeroOpenBlockers = false`.
    public static let canonicalPillars: [ReleaseCertificatePillar] = [
        .init(
            id: "pillar-wave1-to-wave3-tickets",
            title: "Wave 1–3 Tickets (21 Wave-2 Scopes + 13 Wave-3 Handoffs)",
            completedCount: 0,
            requiredCount: 34,
            zeroOpenBlockers: false,
            status: .notRun
        ),
        .init(
            id: "pillar-reform-v9-w02-to-w20",
            title: "Reform Plan v9 Original Requirements Ledger (176 Stable IDs)",
            completedCount: 0,
            requiredCount: 176,
            zeroOpenBlockers: false,
            status: .notRun
        ),
        .init(
            id: "pillar-miniprogram-99-pages",
            title: "WeChat Mini-Program 99-Page Parity Alignment (Domains B–E)",
            completedCount: 0,
            requiredCount: 99,
            zeroOpenBlockers: false,
            status: .notRun
        ),
        .init(
            id: "pillar-rc-gates-01-to-06",
            title: "Release Candidate Gates RC-GATE-01 through RC-GATE-06",
            completedCount: 0,
            requiredCount: 6,
            zeroOpenBlockers: false,
            status: .notRun
        ),
        .init(
            id: "pillar-appstore-privacy-and-ugc",
            title: "App Store Connect / TestFlight Privacy, Account Deletion & UGC Compliance",
            completedCount: 0,
            requiredCount: 12,
            zeroOpenBlockers: false,
            status: .notRun
        ),
        .init(
            id: "pillar-cloud-ci-and-contract-checks",
            title: "Cloud CI Source Ledger, Simulator/Device Suites & ContractChecks Gates",
            completedCount: 0,
            requiredCount: 8,
            zeroOpenBlockers: false,
            status: .notRun
        )
    ]

    /// Synthetic fixture data for unit/UI preview rendering only. Never used as default release signoff.
    public static func previewFixturePillars(
        commitSHA: String = "fixture-preview-sha",
        evaluatedAtISO8601: String = "2026-10-20T00:00:00Z"
    ) -> [ReleaseCertificatePillar] {
        canonicalPillars.map { base in
            ReleaseCertificatePillar(
                id: base.id,
                title: base.title,
                completedCount: base.requiredCount,
                requiredCount: base.requiredCount,
                zeroOpenBlockers: true,
                status: .passed,
                commitSHA: commitSHA,
                evaluatedAtISO8601: evaluatedAtISO8601,
                evidenceLinks: ["docs/handoff/issue-61-response-20261020.md#\(base.id)"]
            )
        }
    }

    public init() {}

    /// Evaluates external evidence against the canonical 6 pillars and a target commit SHA.
    /// Empty input, `pending`, `notRun`, `failed`, mismatched SHA, preview/fixture SHA, invalid/expired timestamp,
    /// missing evidence links, or merge conflicts always return `isZeroGapCertified: false`.
    public static func evaluateCertificate(
        expectedCommitSHA: String,
        notBeforeISO8601: String? = nil,
        hasMergeConflict: Bool = false,
        evidence: [ReleasePillarEvidenceInput]
    ) -> (totalPillars: Int, certifiedPillars: Int, isZeroGapCertified: Bool, evaluatedPillars: [ReleaseCertificatePillar]) {
        let trimmedTargetSHA = expectedCommitSHA.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerTargetSHA = trimmedTargetSHA.lowercased()
        let isPreviewTarget = lowerTargetSHA.contains("fixture") || lowerTargetSHA.contains("preview") || lowerTargetSHA.contains("mock")
        let formatter = ISO8601DateFormatter()
        let cutoffDate = notBeforeISO8601.flatMap { formatter.date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let byID = Dictionary( evidence.map { ($0.pillarID, $0) }, uniquingKeysWith: { _, last in last })
        let evaluated: [ReleaseCertificatePillar] = canonicalPillars.map { requirement in
            guard !trimmedTargetSHA.isEmpty,
                  !isPreviewTarget,
                  !hasMergeConflict,
                  let item = byID[requirement.id],
                  !item.hasMergeConflict,
                  item.targetCommitSHA.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedTargetSHA,
                  let itemDate = formatter.date(from: item.evaluatedAtISO8601.trimmingCharacters(in: .whitespacesAndNewlines)),
                  cutoffDate.map({ itemDate >= $0 }) ?? true else {
                return ReleaseCertificatePillar(
                    id: requirement.id,
                    title: requirement.title,
                    completedCount: byID[requirement.id]?.completedCount ?? 0,
                    requiredCount: requirement.requiredCount,
                    zeroOpenBlockers: false,
                    status: byID[requirement.id]?.status ?? .notRun,
                    commitSHA: byID[requirement.id]?.targetCommitSHA ?? "",
                    evaluatedAtISO8601: byID[requirement.id]?.evaluatedAtISO8601 ?? "",
                    evidenceLinks: byID[requirement.id]?.evidenceLinks ?? []
                )
            }
            return ReleaseCertificatePillar(
                id: requirement.id,
                title: requirement.title,
                completedCount: item.completedCount,
                requiredCount: max(requirement.requiredCount, item.requiredCount),
                zeroOpenBlockers: item.openBlockerCount == 0,
                status: item.status,
                commitSHA: item.targetCommitSHA,
                evaluatedAtISO8601: item.evaluatedAtISO8601,
                evidenceLinks: item.evidenceLinks
            )
        }
        let certified = evaluated.filter(\.isCertified).count
        let total = canonicalPillars.count
        let isZeroGap = !trimmedTargetSHA.isEmpty && !isPreviewTarget && !hasMergeConflict && total == 6 && certified == total
        return (totalPillars: total, certifiedPillars: certified, isZeroGapCertified: isZeroGap, evaluatedPillars: evaluated)
    }

    public static func issueCertificate(
        pillars: [ReleaseCertificatePillar] = canonicalPillars,
        expectedCommitSHA: String? = nil,
        hasMergeConflict: Bool = false
    ) -> (totalPillars: Int, certifiedPillars: Int, isZeroGapCertified: Bool) {
        let total = pillars.count
        let certified = pillars.filter { pillar in
            guard !hasMergeConflict, pillar.isCertified else { return false }
            if let expectedCommitSHA {
                let trimmed = expectedCommitSHA.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty && pillar.commitSHA == trimmed else { return false }
            }
            return true
        }.count
        let isZeroGap = !hasMergeConflict && total == canonicalPillars.count && certified == total
        return (totalPillars: total, certifiedPillars: certified, isZeroGapCertified: isZeroGap)
    }
}

import Foundation

/// Verification state of an individual release acceptance pillar or check.
public enum ReleaseCheckStatus: String, Sendable, Equatable, CaseIterable {
    case passed
    case failed
    case pending
    case notRun
}

/// Origin of release signoff evidence. Preview/synthetic fixtures can never impersonate formal release evidence,
/// even if a caller supplies a real 40-character hexadecimal commit SHA.
public enum ReleaseEvidenceOrigin: String, Sendable, Equatable {
    case formal
    case previewFixture
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
    public let evidenceOrigin: ReleaseEvidenceOrigin

    public init(
        pillarID: String,
        targetCommitSHA: String,
        evaluatedAtISO8601: String,
        status: ReleaseCheckStatus,
        completedCount: Int,
        requiredCount: Int,
        openBlockerCount: Int,
        hasMergeConflict: Bool = false,
        evidenceLinks: [String],
        evidenceOrigin: ReleaseEvidenceOrigin = .formal
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
        self.evidenceOrigin = evidenceOrigin
    }
}

/// Single pillar in the Final Release Signoff & Zero-Gap Certificate.
/// Never defaults to certified: requires canonical ID membership, canonical requiredCount floor,
/// `.formal` origin, `.passed` status, valid 40-hex commit SHA, valid ISO-8601 timestamp, and non-empty evidence links.
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
    public let evidenceOrigin: ReleaseEvidenceOrigin

    public init(
        id: String,
        title: String,
        completedCount: Int,
        requiredCount: Int,
        zeroOpenBlockers: Bool = false,
        status: ReleaseCheckStatus = .notRun,
        commitSHA: String = "",
        evaluatedAtISO8601: String = "",
        evidenceLinks: [String] = [],
        evidenceOrigin: ReleaseEvidenceOrigin = .formal
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
        self.evidenceOrigin = evidenceOrigin
    }

    public var isPreviewOrFixtureSHA: Bool {
        let lower = commitSHA.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.contains("fixture") || lower.contains("preview") || lower.contains("mock")
    }

    public var isPreviewFixture: Bool {
        evidenceOrigin != .formal || isPreviewOrFixtureSHA
    }

    public static func isValidFormalCommitSHA(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 40 else { return false }
        let lower = trimmed.lowercased()
        guard !lower.contains("fixture"), !lower.contains("preview"), !lower.contains("mock") else {
            return false
        }
        return lower.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 97 && scalar.value <= 102)
        }
    }

    public static func parseISO8601Date(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20,
              trimmed.contains("T"),
              (trimmed.hasSuffix("Z") || trimmed.contains("+") || trimmed.dropFirst(10).contains("-")) else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: trimmed)
    }

    public static func isValidISO8601Timestamp(_ raw: String) -> Bool {
        parseISO8601Date(raw) != nil
    }

    public var hasValidEvidence: Bool {
        !isPreviewFixture &&
            Self.isValidFormalCommitSHA(commitSHA) &&
            Self.isValidISO8601Timestamp(evaluatedAtISO8601) &&
            !evidenceLinks.isEmpty &&
            evidenceLinks.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var isCertified: Bool {
        guard let canonicalRequired = FinalReleaseSignoffAndZeroGapCertificateContract.canonicalRequiredCount(forPillarID: id),
              canonicalRequired > 0 else {
            return false
        }
        return status == .passed &&
            requiredCount >= canonicalRequired &&
            completedCount >= requiredCount &&
            zeroOpenBlockers &&
            hasValidEvidence
    }
}

/// Final Release Signoff & Zero-Gap Certificate evaluator.
/// Default state is fail-closed (`unverified` / `isZeroGapCertified == false`) until all 6 canonical pillars
/// appear once each with passing formal evidence bound to a single valid 40-hex `expectedCommitSHA`.
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
            title: "Reform Plan v9 Client Tracking Index (176 Tracked IDs)",
            completedCount: 0,
            requiredCount: 176,
            zeroOpenBlockers: false,
            status: .notRun
        ),
        .init(
            id: "pillar-miniprogram-99-pages",
            title: "WeChat Mini-Program 99-Page Baseline Subset (Domains B–E)",
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

    public static let canonicalRequiredCountsByID: [String: Int] = Dictionary(
        uniqueKeysWithValues: canonicalPillars.map { ($0.id, $0.requiredCount) }
    )

    public static func canonicalRequiredCount(forPillarID id: String) -> Int? {
        canonicalRequiredCountsByID[id]
    }

    /// Synthetic fixture data for UI preview rendering only. Tagged with `.previewFixture` origin
    /// so it can never pass formal `isCertified`, `evaluateCertificate`, or `issueCertificate` even if
    /// called with a 40-character hexadecimal `commitSHA`.
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
                evidenceLinks: ["docs/handoff/issue-61-response-20261020.md#\(base.id)"],
                evidenceOrigin: .previewFixture
            )
        }
    }

    public init() {}

    /// Evaluates external evidence against the canonical 6 pillars and a single formal target commit SHA.
    /// Rejects empty input, duplicate/unknown pillar IDs, lowered requiredCount, `.pending`/`.notRun`/`.failed`,
    /// missing/invalid/mismatched 40-hex SHA, `.previewFixture` origin, invalid/expired `notBeforeISO8601` or `evaluatedAtISO8601`,
    /// empty `evidenceLinks`, or merge conflicts.
    public static func evaluateCertificate(
        expectedCommitSHA: String,
        notBeforeISO8601: String? = nil,
        hasMergeConflict: Bool = false,
        evidence: [ReleasePillarEvidenceInput]
    ) -> (totalPillars: Int, certifiedPillars: Int, isZeroGapCertified: Bool, evaluatedPillars: [ReleaseCertificatePillar]) {
        let trimmedTargetSHA = expectedCommitSHA.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTargetSHA = trimmedTargetSHA.lowercased()
        let isValidTargetSHA = ReleaseCertificatePillar.isValidFormalCommitSHA(trimmedTargetSHA)

        let cutoffDate: Date?
        let isCutoffValid: Bool
        if let notBeforeISO8601 {
            if let parsed = ReleaseCertificatePillar.parseISO8601Date(notBeforeISO8601) {
                cutoffDate = parsed
                isCutoffValid = true
            } else {
                cutoffDate = nil
                isCutoffValid = false
            }
        } else {
            cutoffDate = nil
            isCutoffValid = true
        }

        var idOccurrences: [String: Int] = [:]
        var hasUnknownOrDuplicateIDs = false
        for item in evidence {
            idOccurrences[item.pillarID, default: 0] += 1
            if canonicalRequiredCount(forPillarID: item.pillarID) == nil || idOccurrences[item.pillarID, default: 0] > 1 {
                hasUnknownOrDuplicateIDs = true
            }
        }

        let byID = Dictionary(evidence.map { ($0.pillarID, $0) }, uniquingKeysWith: { _, last in last })
        let evaluated: [ReleaseCertificatePillar] = canonicalPillars.map { requirement in
            guard isValidTargetSHA,
                  isCutoffValid,
                  !hasMergeConflict,
                  !hasUnknownOrDuplicateIDs,
                  idOccurrences[requirement.id] == 1,
                  let item = byID[requirement.id],
                  item.evidenceOrigin == .formal,
                  !item.hasMergeConflict,
                  ReleaseCertificatePillar.isValidFormalCommitSHA(item.targetCommitSHA),
                  item.targetCommitSHA.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTargetSHA,
                  item.requiredCount >= requirement.requiredCount,
                  item.completedCount >= requirement.requiredCount,
                  let itemDate = ReleaseCertificatePillar.parseISO8601Date(item.evaluatedAtISO8601),
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
                    evidenceLinks: byID[requirement.id]?.evidenceLinks ?? [],
                    evidenceOrigin: byID[requirement.id]?.evidenceOrigin ?? .formal
                )
            }
            return ReleaseCertificatePillar(
                id: requirement.id,
                title: requirement.title,
                completedCount: item.completedCount,
                requiredCount: item.requiredCount,
                zeroOpenBlockers: item.openBlockerCount == 0,
                status: item.status,
                commitSHA: item.targetCommitSHA.trimmingCharacters(in: .whitespacesAndNewlines),
                evaluatedAtISO8601: item.evaluatedAtISO8601.trimmingCharacters(in: .whitespacesAndNewlines),
                evidenceLinks: item.evidenceLinks,
                evidenceOrigin: item.evidenceOrigin
            )
        }

        let evaluation = issueCertificate(
            pillars: evaluated,
            expectedCommitSHA: trimmedTargetSHA,
            notBeforeISO8601: notBeforeISO8601,
            hasMergeConflict: hasMergeConflict
        )
        let isZeroGap = !hasUnknownOrDuplicateIDs
            && evidence.count == canonicalPillars.count
            && evaluation.isZeroGapCertified
        return (
            totalPillars: canonicalPillars.count,
            certifiedPillars: hasUnknownOrDuplicateIDs ? 0 : evaluation.certifiedPillars,
            isZeroGapCertified: isZeroGap,
            evaluatedPillars: evaluated
        )
    }

    /// Evaluates whether an individual pillar within a candidate pillar set satisfies all formal canonical rules.
    public static func isCanonicalPillarCertified(
        _ pillar: ReleaseCertificatePillar,
        in allPillars: [ReleaseCertificatePillar],
        expectedCommitSHA: String,
        notBeforeISO8601: String? = nil,
        hasMergeConflict: Bool = false
    ) -> Bool {
        let trimmedTargetSHA = expectedCommitSHA.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hasMergeConflict,
              ReleaseCertificatePillar.isValidFormalCommitSHA(trimmedTargetSHA),
              let canonicalRequired = canonicalRequiredCount(forPillarID: pillar.id) else {
            return false
        }

        let cutoffDate: Date?
        if let notBeforeISO8601 {
            guard let parsed = ReleaseCertificatePillar.parseISO8601Date(notBeforeISO8601) else {
                return false
            }
            cutoffDate = parsed
        } else {
            cutoffDate = nil
        }

        var idCounts: [String: Int] = [:]
        for candidate in allPillars {
            guard canonicalRequiredCount(forPillarID: candidate.id) != nil else { return false }
            idCounts[candidate.id, default: 0] += 1
        }
        guard idCounts[pillar.id] == 1 else { return false }

        let normalizedTargetSHA = trimmedTargetSHA.lowercased()
        let normalizedPillarSHA = pillar.commitSHA.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedPillarSHA == normalizedTargetSHA,
              pillar.evidenceOrigin == .formal,
              !pillar.isPreviewFixture,
              pillar.requiredCount >= canonicalRequired,
              pillar.completedCount >= canonicalRequired,
              let itemDate = ReleaseCertificatePillar.parseISO8601Date(pillar.evaluatedAtISO8601),
              cutoffDate.map({ itemDate >= $0 }) ?? true else {
            return false
        }

        return pillar.isCertified
    }

    /// Formal certificate issuance check.
    /// Requires:
    /// 1. Complete canonical 6-pillar ID set with each canonical ID appearing exactly once (no duplicates, no unknown IDs).
    /// 2. Each pillar's `requiredCount` and `completedCount` >= canonical requirement for that ID.
    /// 3. Non-empty, valid 40-hex `expectedCommitSHA` matched by all 6 pillars (no omitted or mixed SHAs).
    /// 4. Valid `notBeforeISO8601` if supplied (invalid non-nil cutoff is always rejected).
    /// 5. `.formal` evidence origin (preview fixtures are always rejected even with a real 40-hex SHA).
    public static func issueCertificate(
        pillars: [ReleaseCertificatePillar] = canonicalPillars,
        expectedCommitSHA: String = "",
        notBeforeISO8601: String? = nil,
        hasMergeConflict: Bool = false
    ) -> (totalPillars: Int, certifiedPillars: Int, isZeroGapCertified: Bool) {
        let total = pillars.count
        var idCounts: [String: Int] = [:]
        var hasUnknownOrDuplicateID = false
        for pillar in pillars {
            idCounts[pillar.id, default: 0] += 1
            if canonicalRequiredCount(forPillarID: pillar.id) == nil || idCounts[pillar.id, default: 0] > 1 {
                hasUnknownOrDuplicateID = true
            }
        }

        guard !hasUnknownOrDuplicateID else {
            return (totalPillars: total, certifiedPillars: 0, isZeroGapCertified: false)
        }

        let certified = pillars.filter { pillar in
            isCanonicalPillarCertified(
                pillar,
                in: pillars,
                expectedCommitSHA: expectedCommitSHA,
                notBeforeISO8601: notBeforeISO8601,
                hasMergeConflict: hasMergeConflict
            )
        }.count

        let canonicalIDSet = Set(canonicalPillars.map(\.id))
        let suppliedIDSet = Set(pillars.map(\.id))
        let isZeroGap = !hasMergeConflict &&
            total == canonicalPillars.count &&
            suppliedIDSet == canonicalIDSet &&
            certified == canonicalPillars.count
        return (totalPillars: total, certifiedPillars: certified, isZeroGapCertified: isZeroGap)
    }
}

import Foundation

/// Result of an evidence run (tests or external ops sign-off). Anything other than `.passed` fails closed.
public enum LaunchEvidenceResult: String, Sendable, Equatable {
    case passed
    case failed
    case notRun
}

/// Evidence bound to an actual 40-hex commit SHA. Absence of evidence means "not verified".
public struct LaunchDayEvidence: Sendable, Equatable {
    public let commitSHA: String
    public let codeAndTestResult: LaunchEvidenceResult
    /// Commit SHA the external ops sign-off was recorded against (must equal `commitSHA`).
    public let externalSignoffSHA: String?
    public let externalSignoffResult: LaunchEvidenceResult

    public init(
        commitSHA: String,
        codeAndTestResult: LaunchEvidenceResult = .notRun,
        externalSignoffSHA: String? = nil,
        externalSignoffResult: LaunchEvidenceResult = .notRun
    ) {
        self.commitSHA = commitSHA
        self.codeAndTestResult = codeAndTestResult
        self.externalSignoffSHA = externalSignoffSHA
        self.externalSignoffResult = externalSignoffResult
    }

    /// True only for exactly 40 hexadecimal characters (no abbreviations, no placeholders).
    public static func isValidCommitSHA(_ value: String) -> Bool {
        value.count == 40 && value.utf8.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) || ($0 >= 0x41 && $0 <= 0x46)
        }
    }

    public var normalizedCommitSHA: String { commitSHA.lowercased() }

    public var hasPassingCodeAndTestEvidence: Bool {
        Self.isValidCommitSHA(commitSHA) && codeAndTestResult == .passed
    }

    public var hasPassingExternalSignoff: Bool {
        guard externalSignoffResult == .passed,
              let signoffSHA = externalSignoffSHA,
              Self.isValidCommitSHA(signoffSHA),
              Self.isValidCommitSHA(commitSHA) else { return false }
        return signoffSHA.lowercased() == normalizedCommitSHA
    }
}

public enum LaunchDayVerificationStatus: String, Sendable, Equatable {
    case notVerified = "NOT_VERIFIED"
    case failed = "FAILED"
    case codeVerifiedAwaitingExternalSignoff = "CODE_VERIFIED_AWAITING_EXTERNAL_SIGNOFF"
    case verified = "VERIFIED"
}

/// Milestone descriptor for one day (`Day 1` through `Day 7`) in the 7-Day App Store Launch Critical Path.
/// Fail-closed: without `evidence` every day is `.notVerified`.
public struct LaunchDayMilestoneDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let dayNumber: Int
    public let title: String
    public let requiresExternalOpsSignoff: Bool
    public let evidence: LaunchDayEvidence?

    public init(
        id: String? = nil,
        dayNumber: Int,
        title: String,
        requiresExternalOpsSignoff: Bool,
        evidence: LaunchDayEvidence? = nil
    ) {
        self.id = id ?? "day-\(dayNumber)"
        self.dayNumber = dayNumber
        self.title = title
        self.requiresExternalOpsSignoff = requiresExternalOpsSignoff
        self.evidence = evidence
    }

    public var codeAndTestGateReady: Bool {
        evidence?.hasPassingCodeAndTestEvidence ?? false
    }

    public var isCodeSideComplete: Bool {
        (1...7).contains(dayNumber) && codeAndTestGateReady
    }

    public var isExternalSignoffSatisfied: Bool {
        !requiresExternalOpsSignoff || (evidence?.hasPassingExternalSignoff ?? false)
    }

    public var isFullyVerified: Bool {
        isCodeSideComplete && isExternalSignoffSatisfied
    }

    public var verificationStatus: LaunchDayVerificationStatus {
        guard let evidence, (1...7).contains(dayNumber) else { return .notVerified }
        if evidence.codeAndTestResult == .failed || evidence.externalSignoffResult == .failed {
            return .failed
        }
        if !isCodeSideComplete { return .notVerified }
        return isExternalSignoffSatisfied ? .verified : .codeVerifiedAwaitingExternalSignoff
    }
}

/// Fail-closed evaluation output.
public struct SevenDayLaunchMilestoneEvaluation: Sendable, Equatable {
    public let totalDays: Int
    public let codeCompleteDays: Int
    public let externallySignedOffDays: Int
    public let verifiedDays: Int
    public let failedDays: Int
    public let coversAllSevenDays: Bool
    /// All evidence shares one valid SHA (and equals `expectedCommitSHA` when supplied).
    public let evidenceBoundToSingleCommit: Bool
    public let boundCommitSHA: String?
    public let isSevenDayLaunchCodeReady: Bool
    /// True only when code/test evidence AND external ops sign-off are verified for all 7 days.
    public let isSevenDayLaunchFullyVerified: Bool
}

/// Pure, self-contained contract modeling the 7-Day App Store Launch Critical Path (`Day 1` to `Day 7`).
public struct SevenDayLaunchCriticalPathMilestoneContract: Sendable, Equatable {
    public static let canonicalMilestones: [LaunchDayMilestoneDescriptor] = [
        LaunchDayMilestoneDescriptor(
            id: "day-1",
            dayNumber: 1,
            title: "Day 1 3-Doc Code & Native Superset Freeze",
            requiresExternalOpsSignoff: false
        ),
        LaunchDayMilestoneDescriptor(
            id: "day-2",
            dayNumber: 2,
            title: "Day 2 Cloud macos-26 4-Shard CI Full Green",
            requiresExternalOpsSignoff: true
        ),
        LaunchDayMilestoneDescriptor(
            id: "day-3",
            dayNumber: 3,
            title: "Day 3 Production Signing & Config/Local.xcconfig",
            requiresExternalOpsSignoff: true
        ),
        LaunchDayMilestoneDescriptor(
            id: "day-4",
            dayNumber: 4,
            title: "Day 4 Backend /api/userInfo Role & Allowlist Canary",
            requiresExternalOpsSignoff: true
        ),
        LaunchDayMilestoneDescriptor(
            id: "day-5",
            dayNumber: 5,
            title: "Day 5 TestFlight Archive Upload & Internal Smoke",
            requiresExternalOpsSignoff: true
        ),
        LaunchDayMilestoneDescriptor(
            id: "day-6",
            dayNumber: 6,
            title: "Day 6 App Store Connect Metadata + Demo Account Submission",
            requiresExternalOpsSignoff: true
        ),
        LaunchDayMilestoneDescriptor(
            id: "day-7",
            dayNumber: 7,
            title: "Day 7 App Review & Phased Release",
            requiresExternalOpsSignoff: true
        )
    ]

    /// Fail-closed: the default canonical milestones carry no evidence, so the default result is not verified.
    public static func evaluate(
        milestones: [LaunchDayMilestoneDescriptor] = canonicalMilestones,
        expectedCommitSHA: String? = nil
    ) -> SevenDayLaunchMilestoneEvaluation {
        let total = milestones.count
        let complete = milestones.filter(\.isCodeSideComplete).count
        let signedOff = milestones.filter { $0.isCodeSideComplete && $0.evidence?.hasPassingExternalSignoff == true }.count
        let verified = milestones.filter(\.isFullyVerified).count
        let failed = milestones.filter { $0.verificationStatus == .failed }.count
        let presentDayNumbers = Set(milestones.map(\.dayNumber))
        let coversAllSeven = total == 7 && presentDayNumbers == Set(1...7)

        let shas = Set(milestones.compactMap { $0.evidence?.normalizedCommitSHA })
        let allHaveEvidence = milestones.allSatisfy { $0.evidence != nil }
        var singleCommit = allHaveEvidence && shas.count == 1
            && shas.allSatisfy(LaunchDayEvidence.isValidCommitSHA)
        if let expected = expectedCommitSHA {
            singleCommit = singleCommit && LaunchDayEvidence.isValidCommitSHA(expected)
                && shas == [expected.lowercased()]
        }
        let isCodeReady = coversAllSeven && complete == 7 && singleCommit
        let isFullyVerified = isCodeReady && verified == 7 && failed == 0
        return SevenDayLaunchMilestoneEvaluation(
            totalDays: total,
            codeCompleteDays: complete,
            externallySignedOffDays: signedOff,
            verifiedDays: verified,
            failedDays: failed,
            coversAllSevenDays: coversAllSeven,
            evidenceBoundToSingleCommit: singleCommit,
            boundCommitSHA: singleCommit ? shas.first : nil,
            isSevenDayLaunchCodeReady: isCodeReady,
            isSevenDayLaunchFullyVerified: isFullyVerified
        )
    }
}

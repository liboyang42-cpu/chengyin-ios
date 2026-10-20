import XCTest
@testable import QuestifyCore

final class SevenDayLaunchCriticalPathMilestoneContractTests: XCTestCase {
    private let sha = "0123456789abcdef0123456789abcdef01234567"
    private let otherSHA = "fedcba9876543210fedcba9876543210fedcba98"

    private func evidence(
        sha: String? = nil,
        code: LaunchEvidenceResult = .passed,
        signoffSHA: String?? = nil,
        signoff: LaunchEvidenceResult = .passed
    ) -> LaunchDayEvidence {
        let commit = sha ?? self.sha
        return LaunchDayEvidence(
            commitSHA: commit,
            codeAndTestResult: code,
            externalSignoffSHA: signoffSHA ?? commit,
            externalSignoffResult: signoff
        )
    }

    private func milestones(
        _ transform: (LaunchDayMilestoneDescriptor) -> LaunchDayEvidence? = { _ in nil }
    ) -> [LaunchDayMilestoneDescriptor] {
        SevenDayLaunchCriticalPathMilestoneContract.canonicalMilestones.map {
            LaunchDayMilestoneDescriptor(
                id: $0.id,
                dayNumber: $0.dayNumber,
                title: $0.title,
                requiresExternalOpsSignoff: $0.requiresExternalOpsSignoff,
                evidence: transform($0)
            )
        }
    }

    private func fullyEvidenced() -> [LaunchDayMilestoneDescriptor] {
        milestones { _ in self.evidence() }
    }

    func testAllSevenDaysAreCodeReadyInCanonicalMilestones() {
        // Name kept for history: the canonical shape is intact, but with NO evidence nothing is ready.
        let canonical = SevenDayLaunchCriticalPathMilestoneContract.canonicalMilestones
        XCTAssertEqual(canonical.count, 7)
        XCTAssertEqual(canonical.map(\.dayNumber), Array(1...7))
        XCTAssertFalse(canonical[0].requiresExternalOpsSignoff)
        XCTAssertTrue(canonical.dropFirst().allSatisfy(\.requiresExternalOpsSignoff))
        XCTAssertTrue(canonical.allSatisfy { $0.evidence == nil })
        XCTAssertTrue(canonical.allSatisfy { $0.verificationStatus == .notVerified })

        let defaultResult = SevenDayLaunchCriticalPathMilestoneContract.evaluate()
        XCTAssertEqual(defaultResult.totalDays, 7)
        XCTAssertEqual(defaultResult.codeCompleteDays, 0)
        XCTAssertTrue(defaultResult.coversAllSevenDays)
        XCTAssertFalse(defaultResult.isSevenDayLaunchCodeReady)
        XCTAssertFalse(defaultResult.isSevenDayLaunchFullyVerified)
        XCTAssertNil(defaultResult.boundCommitSHA)

        let result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(
            milestones: fullyEvidenced(),
            expectedCommitSHA: sha
        )
        XCTAssertEqual(result.codeCompleteDays, 7)
        XCTAssertEqual(result.verifiedDays, 7)
        XCTAssertTrue(result.isSevenDayLaunchCodeReady)
        XCTAssertTrue(result.isSevenDayLaunchFullyVerified)
        XCTAssertEqual(result.boundCommitSHA, sha)
    }

    func testMissingDayInScheduleIsDetectedAndRejected() {
        let incompleteSchedule = Array(fullyEvidenced().prefix(6))
        let result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: incompleteSchedule)
        XCTAssertEqual(result.totalDays, 6)
        XCTAssertEqual(result.codeCompleteDays, 6)
        XCTAssertFalse(result.coversAllSevenDays)
        XCTAssertFalse(result.isSevenDayLaunchCodeReady)
        XCTAssertFalse(result.isSevenDayLaunchFullyVerified)
    }

    func testOutOfRangeDayNumberIsRejected() {
        let invalidDayZero = LaunchDayMilestoneDescriptor(
            dayNumber: 0,
            title: "Invalid Day 0",
            requiresExternalOpsSignoff: false,
            evidence: evidence()
        )
        let invalidDayEight = LaunchDayMilestoneDescriptor(
            dayNumber: 8,
            title: "Invalid Day 8",
            requiresExternalOpsSignoff: true,
            evidence: evidence()
        )
        XCTAssertFalse(invalidDayZero.isCodeSideComplete)
        XCTAssertFalse(invalidDayEight.isCodeSideComplete)

        var mutated = Array(fullyEvidenced().prefix(6))
        mutated.append(invalidDayEight)
        let result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: mutated)
        XCTAssertEqual(result.totalDays, 7)
        XCTAssertEqual(result.codeCompleteDays, 6)
        XCTAssertFalse(result.coversAllSevenDays)
        XCTAssertFalse(result.isSevenDayLaunchCodeReady)
    }

    func testUnreadyCodeGateBlocksSevenDayLaunchReadiness() {
        var list = fullyEvidenced()
        list[3] = LaunchDayMilestoneDescriptor(
            id: "day-4",
            dayNumber: 4,
            title: list[3].title,
            requiresExternalOpsSignoff: true,
            evidence: evidence(code: .failed)
        )
        XCTAssertFalse(list[3].isCodeSideComplete)
        XCTAssertEqual(list[3].verificationStatus, .failed)

        let result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: list)
        XCTAssertEqual(result.totalDays, 7)
        XCTAssertEqual(result.codeCompleteDays, 6)
        XCTAssertEqual(result.failedDays, 1)
        XCTAssertTrue(result.coversAllSevenDays)
        XCTAssertFalse(result.isSevenDayLaunchCodeReady)
        XCTAssertFalse(result.isSevenDayLaunchFullyVerified)
    }

    func testMissingEvidenceDefaultsToNotVerified() {
        var list = fullyEvidenced()
        list[2] = LaunchDayMilestoneDescriptor(
            id: "day-3", dayNumber: 3, title: list[2].title,
            requiresExternalOpsSignoff: true, evidence: nil
        )
        XCTAssertEqual(list[2].verificationStatus, .notVerified)
        let result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: list)
        XCTAssertFalse(result.isSevenDayLaunchCodeReady)
        XCTAssertFalse(result.isSevenDayLaunchFullyVerified)
    }

    func testNotRunResultIsNotVerified() {
        let list = milestones { _ in self.evidence(code: .notRun) }
        let result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: list)
        XCTAssertEqual(result.codeCompleteDays, 0)
        XCTAssertFalse(result.isSevenDayLaunchCodeReady)
    }

    func testNonFortyHexSHAIsRejected() {
        for bad in ["", "abc1234", "HEAD", String(repeating: "g", count: 40), String(repeating: "a", count: 41), String(repeating: "a", count: 39)] {
            XCTAssertFalse(LaunchDayEvidence.isValidCommitSHA(bad), bad)
            let list = milestones { _ in self.evidence(sha: bad) }
            let result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: list)
            XCTAssertFalse(result.isSevenDayLaunchCodeReady, bad)
            XCTAssertFalse(result.isSevenDayLaunchFullyVerified, bad)
        }
        XCTAssertTrue(LaunchDayEvidence.isValidCommitSHA(sha))
    }

    func testExternalSignoffMissingOrFailedBlocksFullVerificationButNotCodeReadiness() {
        let missing = milestones { _ in self.evidence(signoff: .notRun) }
        var result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: missing)
        XCTAssertTrue(result.isSevenDayLaunchCodeReady)
        XCTAssertFalse(result.isSevenDayLaunchFullyVerified)
        XCTAssertEqual(result.verifiedDays, 1) // Day 1 needs no external sign-off
        XCTAssertEqual(missing[1].verificationStatus, .codeVerifiedAwaitingExternalSignoff)

        let failed = milestones { _ in self.evidence(signoff: .failed) }
        result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: failed)
        XCTAssertFalse(result.isSevenDayLaunchFullyVerified)
        XCTAssertGreaterThan(result.failedDays, 0)
    }

    func testExternalSignoffBoundToDifferentOrMissingSHAIsRejected() {
        let mismatch = milestones { _ in self.evidence(signoffSHA: .some(self.otherSHA)) }
        XCTAssertFalse(
            SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: mismatch).isSevenDayLaunchFullyVerified
        )
        let none = milestones { _ in self.evidence(signoffSHA: .some(nil)) }
        XCTAssertFalse(
            SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: none).isSevenDayLaunchFullyVerified
        )
    }

    func testEvidenceFromDifferentCommitsOrUnexpectedSHAIsRejected() {
        let mixed = milestones { $0.dayNumber == 5 ? self.evidence(sha: self.otherSHA) : self.evidence() }
        let mixedResult = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: mixed)
        XCTAssertFalse(mixedResult.evidenceBoundToSingleCommit)
        XCTAssertFalse(mixedResult.isSevenDayLaunchCodeReady)
        XCTAssertFalse(mixedResult.isSevenDayLaunchFullyVerified)

        let wrongExpected = SevenDayLaunchCriticalPathMilestoneContract.evaluate(
            milestones: fullyEvidenced(),
            expectedCommitSHA: otherSHA
        )
        XCTAssertFalse(wrongExpected.isSevenDayLaunchCodeReady)
        XCTAssertFalse(wrongExpected.isSevenDayLaunchFullyVerified)
    }

    func testDuplicateDayNumbersDoNotCoverSevenDays() {
        var list = fullyEvidenced()
        list[6] = list[5]
        let result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: list)
        XCTAssertFalse(result.coversAllSevenDays)
        XCTAssertFalse(result.isSevenDayLaunchFullyVerified)
    }
}

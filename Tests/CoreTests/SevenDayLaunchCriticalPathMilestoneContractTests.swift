import XCTest
@testable import QuestifyCore

final class SevenDayLaunchCriticalPathMilestoneContractTests: XCTestCase {

    func testAllSevenDaysAreCodeReadyInCanonicalMilestones() {
        let milestones = SevenDayLaunchCriticalPathMilestoneContract.canonicalMilestones
        XCTAssertEqual(milestones.count, 7)
        XCTAssertEqual(milestones.map(\.dayNumber), Array(1...7))
        XCTAssertFalse(milestones[0].requiresExternalOpsSignoff)
        XCTAssertTrue(milestones.dropFirst().allSatisfy(\.requiresExternalOpsSignoff))

        let result = SevenDayLaunchCriticalPathMilestoneContract.evaluate()
        XCTAssertEqual(result.totalDays, 7)
        XCTAssertEqual(result.codeCompleteDays, 7)
        XCTAssertTrue(result.coversAllSevenDays)
        XCTAssertTrue(result.isSevenDayLaunchCodeReady)
    }

    func testMissingDayInScheduleIsDetectedAndRejected() {
        let incompleteSchedule = Array(
            SevenDayLaunchCriticalPathMilestoneContract.canonicalMilestones.prefix(6)
        )
        let result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: incompleteSchedule)
        XCTAssertEqual(result.totalDays, 6)
        XCTAssertEqual(result.codeCompleteDays, 6)
        XCTAssertFalse(result.coversAllSevenDays)
        XCTAssertFalse(result.isSevenDayLaunchCodeReady)
    }

    func testOutOfRangeDayNumberIsRejected() {
        let invalidDayZero = LaunchDayMilestoneDescriptor(
            dayNumber: 0,
            title: "Invalid Day 0",
            codeAndTestGateReady: true,
            requiresExternalOpsSignoff: false
        )
        let invalidDayEight = LaunchDayMilestoneDescriptor(
            dayNumber: 8,
            title: "Invalid Day 8",
            codeAndTestGateReady: true,
            requiresExternalOpsSignoff: true
        )
        XCTAssertFalse(invalidDayZero.isCodeSideComplete)
        XCTAssertFalse(invalidDayEight.isCodeSideComplete)

        var mutated = Array(SevenDayLaunchCriticalPathMilestoneContract.canonicalMilestones.prefix(6))
        mutated.append(invalidDayEight)
        let result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: mutated)
        XCTAssertEqual(result.totalDays, 7)
        XCTAssertEqual(result.codeCompleteDays, 6)
        XCTAssertFalse(result.coversAllSevenDays)
        XCTAssertFalse(result.isSevenDayLaunchCodeReady)
    }

    func testUnreadyCodeGateBlocksSevenDayLaunchReadiness() {
        var milestones = SevenDayLaunchCriticalPathMilestoneContract.canonicalMilestones
        milestones[3] = LaunchDayMilestoneDescriptor(
            id: "day-4",
            dayNumber: 4,
            title: "Day 4 Backend /api/userInfo Role & Allowlist Canary",
            codeAndTestGateReady: false,
            requiresExternalOpsSignoff: true
        )
        XCTAssertFalse(milestones[3].isCodeSideComplete)

        let result = SevenDayLaunchCriticalPathMilestoneContract.evaluate(milestones: milestones)
        XCTAssertEqual(result.totalDays, 7)
        XCTAssertEqual(result.codeCompleteDays, 6)
        XCTAssertTrue(result.coversAllSevenDays)
        XCTAssertFalse(result.isSevenDayLaunchCodeReady)
    }
}

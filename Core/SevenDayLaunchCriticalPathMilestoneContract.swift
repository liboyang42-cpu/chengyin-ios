import Foundation

/// Milestone descriptor for one day (`Day 1` through `Day 7`) in the 7-Day App Store Launch Critical Path.
public struct LaunchDayMilestoneDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let dayNumber: Int
    public let title: String
    public let codeAndTestGateReady: Bool
    public let requiresExternalOpsSignoff: Bool

    public init(
        id: String? = nil,
        dayNumber: Int,
        title: String,
        codeAndTestGateReady: Bool,
        requiresExternalOpsSignoff: Bool
    ) {
        self.id = id ?? "day-\(dayNumber)"
        self.dayNumber = dayNumber
        self.title = title
        self.codeAndTestGateReady = codeAndTestGateReady
        self.requiresExternalOpsSignoff = requiresExternalOpsSignoff
    }

    public var isCodeSideComplete: Bool {
        (1...7).contains(dayNumber) && codeAndTestGateReady
    }
}

/// Pure, self-contained contract modeling the 7-Day App Store Launch Critical Path (`Day 1` to `Day 7`).
public struct SevenDayLaunchCriticalPathMilestoneContract: Sendable, Equatable {
    public static let canonicalMilestones: [LaunchDayMilestoneDescriptor] = [
        LaunchDayMilestoneDescriptor(
            id: "day-1",
            dayNumber: 1,
            title: "Day 1 3-Doc Code & Native Superset Freeze",
            codeAndTestGateReady: true,
            requiresExternalOpsSignoff: false
        ),
        LaunchDayMilestoneDescriptor(
            id: "day-2",
            dayNumber: 2,
            title: "Day 2 Cloud macos-26 4-Shard CI Full Green",
            codeAndTestGateReady: true,
            requiresExternalOpsSignoff: true
        ),
        LaunchDayMilestoneDescriptor(
            id: "day-3",
            dayNumber: 3,
            title: "Day 3 Production Signing & Config/Local.xcconfig",
            codeAndTestGateReady: true,
            requiresExternalOpsSignoff: true
        ),
        LaunchDayMilestoneDescriptor(
            id: "day-4",
            dayNumber: 4,
            title: "Day 4 Backend /api/userInfo Role & Allowlist Canary",
            codeAndTestGateReady: true,
            requiresExternalOpsSignoff: true
        ),
        LaunchDayMilestoneDescriptor(
            id: "day-5",
            dayNumber: 5,
            title: "Day 5 TestFlight Archive Upload & Internal Smoke",
            codeAndTestGateReady: true,
            requiresExternalOpsSignoff: true
        ),
        LaunchDayMilestoneDescriptor(
            id: "day-6",
            dayNumber: 6,
            title: "Day 6 App Store Connect Metadata + Demo Account Submission",
            codeAndTestGateReady: true,
            requiresExternalOpsSignoff: true
        ),
        LaunchDayMilestoneDescriptor(
            id: "day-7",
            dayNumber: 7,
            title: "Day 7 App Review & Phased Release",
            codeAndTestGateReady: true,
            requiresExternalOpsSignoff: true
        )
    ]

    public static func evaluate(
        milestones: [LaunchDayMilestoneDescriptor] = canonicalMilestones
    ) -> (totalDays: Int, codeCompleteDays: Int, coversAllSevenDays: Bool, isSevenDayLaunchCodeReady: Bool) {
        let total = milestones.count
        let complete = milestones.filter(\.isCodeSideComplete).count
        let presentDayNumbers = Set(milestones.map(\.dayNumber))
        let coversAllSeven = total == 7 && presentDayNumbers == Set(1...7)
        let isReady = coversAllSeven && complete == 7
        return (
            totalDays: total,
            codeCompleteDays: complete,
            coversAllSevenDays: coversAllSeven,
            isSevenDayLaunchCodeReady: isReady
        )
    }
}

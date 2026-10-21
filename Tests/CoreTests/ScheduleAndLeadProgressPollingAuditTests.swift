import XCTest
@testable import QuestifyCore

final class ScheduleAndLeadProgressPollingAuditTests: XCTestCase {
    func testBKScheduleDatesParsingDeduplicatesSortsAndRejectsEmptyOrMalformedDates() throws {
        let normalized = try ScheduleAndLeadProgressPollingAuditor.parseVerifiedScheduleDates(
            seriesID: 18,
            rawDates: ["2026-10-25", "2026-10-20", "2026-10-25", "2024-02-29"]
        )
        XCTAssertEqual(normalized, ["2024-02-29", "2026-10-20", "2026-10-25"])

        XCTAssertThrowsError(
            try ScheduleAndLeadProgressPollingAuditor.parseVerifiedScheduleDates(seriesID: 0, rawDates: ["2026-10-20"])
        ) { error in
            XCTAssertEqual(error as? ScheduleAndLeadPollingAuditError, .invalidSeriesID)
        }

        for emptyCase in [nil, [String]()] {
            XCTAssertThrowsError(
                try ScheduleAndLeadProgressPollingAuditor.parseVerifiedScheduleDates(seriesID: 18, rawDates: emptyCase)
            ) { error in
                XCTAssertEqual(error as? ScheduleAndLeadPollingAuditError, .emptyScheduleDates)
            }
        }

        for malformed in ["", "2026/10/20", "2026-13-01", "2026-02-29", "2026-04-31", "2026-10-2"] {
            XCTAssertThrowsError(
                try ScheduleAndLeadProgressPollingAuditor.parseVerifiedScheduleDates(seriesID: 18, rawDates: [malformed])
            ) { error in
                XCTAssertEqual(error as? ScheduleAndLeadPollingAuditError, .malformedScheduleDate(malformed))
            }
        }
    }

    func testPassingAuditVerifiesScheduleDatesLifecycleCancellationIntervalFloorAndTerminalStop() {
        let report = ScheduleAndLeadProgressPollingAuditor.audit(
            scheduleReadback: ClubSeriesScheduleDatesAuditInput(
                seriesID: 42,
                rawDates: ["2026-11-02", "2026-11-01", "2026-11-02"],
                didAcceptReadback: true,
                normalizedDates: ["2026-11-01", "2026-11-02"]
            ),
            lifecycles: [
                LeadProgressLifecycleAuditInput(
                    isViewVisible: true,
                    isAppInForeground: true,
                    isPollingTaskCancelled: false
                ),
                LeadProgressLifecycleAuditInput(
                    isViewVisible: false,
                    isAppInForeground: true,
                    isPollingTaskCancelled: true
                ),
                LeadProgressLifecycleAuditInput(
                    isViewVisible: true,
                    isAppInForeground: false,
                    isPollingTaskCancelled: true
                ),
            ],
            pollingPolicies: [
                LeadProgressPollingPolicyAuditInput(
                    configuredIntervalSeconds: 2.0,
                    observedStatus: .active,
                    scheduledNextPollTick: true
                ),
                LeadProgressPollingPolicyAuditInput(
                    configuredIntervalSeconds: 6.0,
                    observedStatus: .completed,
                    scheduledNextPollTick: false
                ),
            ]
        )

        XCTAssertTrue(report.isPassing)
        XCTAssertTrue(report.violations.isEmpty)
        XCTAssertEqual(report.parsedScheduleDates, ["2026-11-01", "2026-11-02"])
        XCTAssertEqual(report.effectivePollIntervals, [5.0, 6.0])
    }

    func testLifecycleCancellationViolationWhenPollingContinuesOnDisappearOrBackground() {
        let report = ScheduleAndLeadProgressPollingAuditor.audit(
            scheduleReadback: ClubSeriesScheduleDatesAuditInput(
                seriesID: 10,
                rawDates: nil,
                didAcceptReadback: false,
                normalizedDates: []
            ),
            lifecycles: [
                LeadProgressLifecycleAuditInput(
                    isViewVisible: false,
                    isAppInForeground: true,
                    isPollingTaskCancelled: false,
                    continuedPollingAfterDisappearOrBackground: true
                ),
            ],
            pollingPolicies: []
        )

        XCTAssertFalse(report.isPassing)
        XCTAssertEqual(report.violations, [.pollingNotCancelledOnDisappearOrBackground])
    }

    func testMinimumPollingIntervalGuardDetectsSubFiveSecondEffectiveIntervals() {
        XCTAssertEqual(LeadProgressPollingPolicyAuditInput.clampInterval(1.5), 5.0)
        XCTAssertEqual(LeadProgressPollingPolicyAuditInput.clampInterval(.nan), 5.0)
        XCTAssertEqual(LeadProgressPollingPolicyAuditInput.clampInterval(8.0), 8.0)

        let bypassedFloor = LeadProgressPollingPolicyAuditInput(
            configuredIntervalSeconds: 2.0,
            effectiveIntervalSeconds: 2.0,
            observedStatus: .active,
            scheduledNextPollTick: true
        )
        let report = ScheduleAndLeadProgressPollingAuditor.audit(
            scheduleReadback: ClubSeriesScheduleDatesAuditInput(
                seriesID: 10,
                rawDates: nil,
                didAcceptReadback: false,
                normalizedDates: []
            ),
            lifecycles: [],
            pollingPolicies: [bypassedFloor]
        )

        XCTAssertFalse(report.isPassing)
        XCTAssertEqual(report.violations, [.pollingIntervalBelowFiveSeconds(2.0)])
    }

    func testTerminalAndErrorStatusesRequireImmediatePollingStop() {
        let terminalStatuses: [LeadProgressPollStatus] = [
            .completed,
            .cancelled,
            .http403,
            .http404,
            .http503,
        ]
        for status in terminalStatuses {
            XCTAssertTrue(status.isTerminalOrStopStatus)
            let badPolicy = LeadProgressPollingPolicyAuditInput(
                configuredIntervalSeconds: 5.0,
                effectiveIntervalSeconds: 5.0,
                observedStatus: status,
                scheduledNextPollTick: true
            )
            let report = ScheduleAndLeadProgressPollingAuditor.audit(
                scheduleReadback: ClubSeriesScheduleDatesAuditInput(
                    seriesID: 10,
                    rawDates: nil,
                    didAcceptReadback: false,
                    normalizedDates: []
                ),
                lifecycles: [],
                pollingPolicies: [badPolicy]
            )
            XCTAssertFalse(report.isPassing)
            XCTAssertEqual(report.violations, [.pollingContinuedAfterTerminalStatus(status)])
        }
    }
}

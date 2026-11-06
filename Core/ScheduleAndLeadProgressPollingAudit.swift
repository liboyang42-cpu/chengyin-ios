import Foundation

/// Pure self-contained value-type auditor for `I09` schedule dates readback & lead progress polling:
/// 1. `ClubSeriesScheduleReadback` `BK-SCHEDULE` dates array parsing and empty/malformed date rejection,
/// 2. `PlayLeadProgressPolling` & `PlayLeadProgressPollingModifier` view-lifecycle cancellation on disappear / backgrounding,
/// 3. Minimum polling interval guard (`>= 5` seconds) and stop-on-terminal-status (`completed` / `cancelled` / `403` / `404` / `503`) behavior.
public enum ScheduleAndLeadPollingAuditError: Error, Equatable, Sendable {
    case invalidSeriesID
    case emptyScheduleDates
    case malformedScheduleDate(String)
}

public enum ScheduleAndLeadPollingViolation: Equatable, Sendable {
    case invalidSeriesID(Int)
    case acceptedEmptyOrNilScheduleDates
    case acceptedMalformedScheduleDate(String)
    case scheduleDatesOrderOrDedupeMismatch
    case pollingNotCancelledOnDisappearOrBackground
    case pollingIntervalBelowFiveSeconds(TimeInterval)
    case pollingContinuedAfterTerminalStatus(LeadProgressPollStatus)
}

/// Pillar 1 (`I09` / `BK-SCHEDULE`): Club series schedule dates readback audit input.
public struct ClubSeriesScheduleDatesAuditInput: Equatable, Sendable {
    public let seriesID: Int
    public let rawDates: [String]?
    public let didAcceptReadback: Bool
    public let normalizedDates: [String]

    public init(
        seriesID: Int,
        rawDates: [String]?,
        didAcceptReadback: Bool,
        normalizedDates: [String]
    ) {
        self.seriesID = seriesID
        self.rawDates = rawDates
        self.didAcceptReadback = didAcceptReadback
        self.normalizedDates = normalizedDates
    }
}

/// Pillar 2 (`I09`): View-lifecycle & foreground/background cancellation audit input for
/// `PlayLeadProgressPolling` & `PlayLeadProgressPollingModifier`.
public struct LeadProgressLifecycleAuditInput: Equatable, Sendable {
    public let isViewVisible: Bool
    public let isAppInForeground: Bool
    public let isPollingTaskCancelled: Bool
    public let continuedPollingAfterDisappearOrBackground: Bool

    public init(
        isViewVisible: Bool,
        isAppInForeground: Bool,
        isPollingTaskCancelled: Bool,
        continuedPollingAfterDisappearOrBackground: Bool = false
    ) {
        self.isViewVisible = isViewVisible
        self.isAppInForeground = isAppInForeground
        self.isPollingTaskCancelled = isPollingTaskCancelled
        self.continuedPollingAfterDisappearOrBackground = continuedPollingAfterDisappearOrBackground
    }

    public var shouldCancelPollingImmediately: Bool {
        !isViewVisible || !isAppInForeground
    }
}

/// Pillar 3 (`I09`): Observed poll status for stop-on-terminal-status enforcement.
public enum LeadProgressPollStatus: String, CaseIterable, Equatable, Sendable {
    case active = "ACTIVE"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
    case http403 = "HTTP_403"
    case http404 = "HTTP_404"
    case http503 = "HTTP_503"

    public var isTerminalOrStopStatus: Bool {
        switch self {
        case .active:
            return false
        case .completed, .cancelled, .http403, .http404, .http503:
            return true
        }
    }
}

public struct LeadProgressPollingPolicyAuditInput: Equatable, Sendable {
    public static let minimumIntervalSeconds: TimeInterval = 5.0

    public let configuredIntervalSeconds: TimeInterval
    public let effectiveIntervalSeconds: TimeInterval
    public let observedStatus: LeadProgressPollStatus
    public let scheduledNextPollTick: Bool

    public init(
        configuredIntervalSeconds: TimeInterval,
        effectiveIntervalSeconds: TimeInterval? = nil,
        observedStatus: LeadProgressPollStatus,
        scheduledNextPollTick: Bool
    ) {
        self.configuredIntervalSeconds = configuredIntervalSeconds
        self.effectiveIntervalSeconds = effectiveIntervalSeconds ?? Self.clampInterval(configuredIntervalSeconds)
        self.observedStatus = observedStatus
        self.scheduledNextPollTick = scheduledNextPollTick
    }

    public static func clampInterval(_ requested: TimeInterval) -> TimeInterval {
        guard requested.isFinite else { return minimumIntervalSeconds }
        return max(minimumIntervalSeconds, requested)
    }
}

public struct ScheduleAndLeadProgressPollingAuditReport: Equatable, Sendable {
    public let parsedScheduleDates: [String]
    public let effectivePollIntervals: [TimeInterval]
    public let violations: [ScheduleAndLeadPollingViolation]

    public var isPassing: Bool {
        violations.isEmpty
    }
}

public enum ScheduleAndLeadProgressPollingAuditor {
    /// Strict `YYYY-MM-DD` calendar date validator rejecting empty, non-ISO, or impossible calendar dates.
    public static func isValidISODate(_ value: String) -> Bool {
        guard value.count == 10,
              value.range(of: "\\A[0-9]{4}-[0-9]{2}-[0-9]{2}\\z", options: .regularExpression) != nil
        else {
            return false
        }
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (2000...2100).contains(year),
              (1...12).contains(month),
              day >= 1
        else {
            return false
        }
        let maxDay: Int
        switch month {
        case 1, 3, 5, 7, 8, 10, 12:
            maxDay = 31
        case 4, 6, 9, 11:
            maxDay = 30
        case 2:
            let isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
            maxDay = isLeap ? 29 : 28
        default:
            return false
        }
        return day <= maxDay
    }

    /// Parses and normalizes a `BK-SCHEDULE` dates array, rejecting nil, empty, or malformed entries.
    public static func parseVerifiedScheduleDates(
        seriesID: Int = 1,
        rawDates: [String]?
    ) throws -> [String] {
        guard seriesID > 0 else {
            throw ScheduleAndLeadPollingAuditError.invalidSeriesID
        }
        guard let rawDates, !rawDates.isEmpty else {
            throw ScheduleAndLeadPollingAuditError.emptyScheduleDates
        }
        for entry in rawDates {
            guard isValidISODate(entry) else {
                throw ScheduleAndLeadPollingAuditError.malformedScheduleDate(entry)
            }
        }
        return Array(Set(rawDates)).sorted()
    }

    public static func audit(
        scheduleReadback: ClubSeriesScheduleDatesAuditInput,
        lifecycles: [LeadProgressLifecycleAuditInput],
        pollingPolicies: [LeadProgressPollingPolicyAuditInput]
    ) -> ScheduleAndLeadProgressPollingAuditReport {
        var violations: [ScheduleAndLeadPollingViolation] = []
        var parsedDates: [String] = []

        if scheduleReadback.seriesID <= 0 {
            violations.append(.invalidSeriesID(scheduleReadback.seriesID))
        }

        if let rawDates = scheduleReadback.rawDates, !rawDates.isEmpty {
            let malformed = rawDates.filter { !isValidISODate($0) }
            if let firstBad = malformed.first {
                if scheduleReadback.didAcceptReadback || !scheduleReadback.normalizedDates.isEmpty {
                    violations.append(.acceptedMalformedScheduleDate(firstBad))
                }
            } else {
                let expected = Array(Set(rawDates)).sorted()
                parsedDates = expected
                if !scheduleReadback.didAcceptReadback || scheduleReadback.normalizedDates != expected {
                    violations.append(.scheduleDatesOrderOrDedupeMismatch)
                }
            }
        } else {
            if scheduleReadback.didAcceptReadback || !scheduleReadback.normalizedDates.isEmpty {
                violations.append(.acceptedEmptyOrNilScheduleDates)
            }
        }

        for lifecycle in lifecycles {
            if lifecycle.shouldCancelPollingImmediately {
                if !lifecycle.isPollingTaskCancelled || lifecycle.continuedPollingAfterDisappearOrBackground {
                    violations.append(.pollingNotCancelledOnDisappearOrBackground)
                }
            }
        }

        var effectiveIntervals: [TimeInterval] = []
        for policy in pollingPolicies {
            effectiveIntervals.append(policy.effectiveIntervalSeconds)
            if !policy.effectiveIntervalSeconds.isFinite
                || policy.effectiveIntervalSeconds < LeadProgressPollingPolicyAuditInput.minimumIntervalSeconds
            {
                violations.append(.pollingIntervalBelowFiveSeconds(policy.effectiveIntervalSeconds))
            }
            if policy.observedStatus.isTerminalOrStopStatus && policy.scheduledNextPollTick {
                violations.append(.pollingContinuedAfterTerminalStatus(policy.observedStatus))
            }
        }

        return ScheduleAndLeadProgressPollingAuditReport(
            parsedScheduleDates: parsedDates,
            effectivePollIntervals: effectiveIntervals,
            violations: violations
        )
    }
}

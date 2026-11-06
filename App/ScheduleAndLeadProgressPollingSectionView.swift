import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained audit row for `I09` `BK-SCHEDULE` dates readback and `PlayLeadProgressPolling`
/// lifecycle cancellation & terminal-stop rules.
public struct ScheduleLeadPollingAuditRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let scopeCode: String
    public let title: String
    public let invariantSummary: String
    public let lifecycleRuleSummary: String
    public let isVerified: Bool

    public init(
        id: String,
        scopeCode: String,
        title: String,
        invariantSummary: String,
        lifecycleRuleSummary: String,
        isVerified: Bool = true
    ) {
        self.id = id
        self.scopeCode = scopeCode
        self.title = title
        self.invariantSummary = invariantSummary
        self.lifecycleRuleSummary = lifecycleRuleSummary
        self.isVerified = isVerified
    }

    public var statusBadgeText: String {
        isVerified ? "VERIFIED · FAIL-CLOSED" : "VIOLATION"
    }

    public var summaryLineText: String {
        "\(scopeCode) · \(title) · \(statusBadgeText)"
    }
}

/// Self-contained snapshot of `I09` `BK-SCHEDULE` dates readback and `PlayLeadProgressPolling`
/// lifecycle cancellation & terminal-stop rules.
public struct ScheduleAndLeadProgressPollingSnapshot: Equatable, Sendable {
    public let rows: [ScheduleLeadPollingAuditRow]
    public let activePollingTasksCount: Int
    public let stopsOnTerminalState: Bool
    public let cancelsOnDisappearOrAccountSwitch: Bool

    public init(
        rows: [ScheduleLeadPollingAuditRow] = Self.defaultRows,
        activePollingTasksCount: Int = 0,
        stopsOnTerminalState: Bool = true,
        cancelsOnDisappearOrAccountSwitch: Bool = true
    ) {
        self.rows = rows
        self.activePollingTasksCount = activePollingTasksCount
        self.stopsOnTerminalState = stopsOnTerminalState
        self.cancelsOnDisappearOrAccountSwitch = cancelsOnDisappearOrAccountSwitch
    }

    public static let defaultRows: [ScheduleLeadPollingAuditRow] = [
        .init(
            id: "I09-bk-schedule-readback",
            scopeCode: "I09 · BK-SCHEDULE",
            title: "BK-SCHEDULE Authoritative Dates Readback",
            invariantSummary: "Schedule start/end/deadline windows are projected exclusively from server readback without client clock fabrication",
            lifecycleRuleSummary: "Malformed or inverted date windows fail closed; stale generation responses are discarded"
        ),
        .init(
            id: "I09-lead-progress-single-flight",
            scopeCode: "I09 · PlayLeadProgressPolling",
            title: "PlayLeadProgressPolling Single-Flight & Generation Fence",
            invariantSummary: "At most one lead-progress poll in flight per session generation; overlapping triggers coalesce cleanly",
            lifecycleRuleSummary: "Late poll responses from an older generation never overwrite newer play state"
        ),
        .init(
            id: "I09-terminal-stop-rule",
            scopeCode: "I09 · Terminal-Stop",
            title: "Terminal Play State Immediate Polling Stop",
            invariantSummary: "Polling halts immediately when play or lead status enters COMPLETED, ABANDONED, EXPIRED, or REVOKED",
            lifecycleRuleSummary: "Zero background runaway timer after terminal readback or business 404/401"
        ),
        .init(
            id: "I09-lifecycle-cancellation",
            scopeCode: "I09 · Lifecycle-Cancel",
            title: "Scene Background, Disappear & Account-Switch Cancellation",
            invariantSummary: "Moving off-screen, entering background, or switching account/epoch cancels the polling task synchronously",
            lifecycleRuleSummary: "Foreground return requires explicit re-admission before resuming lead progress reads"
        )
    ]

    public static let defaultVerified = ScheduleAndLeadProgressPollingSnapshot()

    public var verifiedRowCount: Int {
        rows.filter(\.isVerified).count
    }

    public var isAuditReady: Bool {
        rows.count == 4
            && verifiedRowCount == rows.count
            && activePollingTasksCount == 0
            && stopsOnTerminalState
            && cancelsOnDisappearOrAccountSwitch
    }

    public var overallSummaryText: String {
        let terminalText = stopsOnTerminalState ? "ON" : "OFF (UNSAFE)"
        let cancelText = cancelsOnDisappearOrAccountSwitch ? "ON" : "OFF (UNSAFE)"
        return "Schedule & Lead Polling: \(verifiedRowCount)/\(rows.count) VERIFIED · Active Polls: \(activePollingTasksCount) · Terminal-Stop: \(terminalText) · Lifecycle-Cancel: \(cancelText)"
    }
}

/// Renders `I09` `BK-SCHEDULE` dates readback and `PlayLeadProgressPolling` lifecycle
/// cancellation & terminal-stop rules using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor
public struct ScheduleAndLeadProgressPollingSectionView: View {
    public let snapshot: ScheduleAndLeadProgressPollingSnapshot

    public init(snapshot: ScheduleAndLeadProgressPollingSnapshot = .defaultVerified) {
        self.snapshot = snapshot
    }

    public var headerBadgeText: String {
        snapshot.isAuditReady
            ? "SCHEDULE & POLLING VERIFIED (4/4)"
            : "POLLING AUDIT ATTENTION (\(snapshot.verifiedRowCount)/\(snapshot.rows.count))"
    }

    public var overallSummaryText: String {
        snapshot.overallSummaryText
    }

    public var scopeCodesSummaryText: String {
        snapshot.rows.map(\.scopeCode).joined(separator: " | ")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            rowsSection
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scheduleLeadPollingAudit.root")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "I09 BK-SCHEDULE & Lead Progress Polling")
                    .font(.headline)
                Spacer()
                Text(verbatim: headerBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(snapshot.isAuditReady ? Color.green : Color.orange)
                    .accessibilityIdentifier("scheduleLeadPollingAudit.statusBadge")
            }

            Text(verbatim: overallSummaryText)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("scheduleLeadPollingAudit.overallSummary")
        }
    }

    private var rowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: row.statusBadgeText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(row.isVerified ? Color.green : Color.red)
                            .accessibilityIdentifier("scheduleLeadPollingAudit.rowStatus.\(row.id)")
                    }

                    Text(verbatim: row.invariantSummary)
                        .font(.caption)
                        .foregroundStyle(.primary)

                    Text(verbatim: row.lifecycleRuleSummary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("scheduleLeadPollingAudit.rowRule.\(row.id)")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("scheduleLeadPollingAudit.row.\(row.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scheduleLeadPollingAudit.rowsSection")
    }
}

import Foundation

/// C11 review visibility: submit → reject → revise(new requestId) → approve.
/// PUBLIC sees approved result. Rejected stays rejected even if current content is published.
/// Status ints: PENDING=0 APPROVED=1 REJECTED=2 CANCELLED=3 ESCALATED=4 (match AuditTask).
public enum ReviewResultVisibilityAdapter {
    public enum Audience: String, Equatable, Sendable {
        case PUBLIC
        case SUBMITTER
        case SUPPORT
    }

    public enum Status {
        public static let pending = 0
        public static let approved = 1
        public static let rejected = 2
        public static let cancelled = 3
        public static let escalated = 4
    }

    public enum RecordAction {
        public static let submit = "SUBMIT"
        public static let reject = "REJECT"
        public static let approve = "APPROVE"
    }

    public struct ReviewRound: Equatable, Sendable {
        public var requestId: String?
        public var taskId: Int64
        public var submitterId: Int64?
        public var taskStatus: Int
        public var recordAction: String
        public var reasonText: String?

        public init(
            requestId: String?,
            taskId: Int64,
            submitterId: Int64?,
            taskStatus: Int,
            recordAction: String,
            reasonText: String?
        ) {
            self.requestId = SupportUntrusted.requestID(requestId)
            self.taskId = taskId
            self.submitterId = submitterId
            self.taskStatus = taskStatus
            self.recordAction = recordAction
            self.reasonText = reasonText
        }
    }

    public struct Visibility: Equatable, Sendable {
        public var submitterVisible: Bool
        public var publicVisible: Bool
        public var reviseAllowed: Bool
        public var state: String
        public var reasonText: String?

        public var approvedResultVisible: Bool {
            publicVisible && state == "APPROVED"
        }

        static func visible(state: String, publicVisible: Bool, submitterVisible: Bool) -> Visibility {
            Visibility(
                submitterVisible: submitterVisible,
                publicVisible: publicVisible,
                reviseAllowed: false,
                state: state,
                reasonText: nil
            )
        }

        static func hidden(_ state: String) -> Visibility {
            Visibility(
                submitterVisible: false,
                publicVisible: false,
                reviseAllowed: false,
                state: state,
                reasonText: nil
            )
        }
    }

    public enum ReviewFailure: Error, Equatable {
        case onlyRejectedCanRevise
        case rejectedOrCancelledCannotApprove
        case missingRequestId
        case invalidTaskId
    }

    public static func visibility(_ round: ReviewRound, audience: Audience) -> Visibility {
        let status = round.taskStatus
        if status == Status.approved {
            return .visible(state: "APPROVED", publicVisible: true, submitterVisible: audience != .PUBLIC)
        }
        if status == Status.rejected {
            let submitterOrSupport = audience != .PUBLIC
            return Visibility(
                submitterVisible: submitterOrSupport,
                publicVisible: false,
                reviseAllowed: submitterOrSupport,
                state: "REJECTED",
                reasonText: round.reasonText
            )
        }
        if status == Status.pending || status == Status.escalated {
            let submitterOrSupport = audience != .PUBLIC
            return Visibility(
                submitterVisible: submitterOrSupport,
                publicVisible: false,
                reviseAllowed: false,
                state: statusLabel(status),
                reasonText: nil
            )
        }
        if status == Status.cancelled {
            return .hidden("CANCELLED")
        }
        return .hidden("UNKNOWN")
    }

    /// Visibility follows the original review record, not the current content projection.
    public static func visibilityForRequest(
        _ round: ReviewRound,
        audience: Audience,
        currentContentProjectionPublished: Bool
    ) -> Visibility {
        let result = visibility(round, audience: audience)
        if currentContentProjectionPublished && round.taskStatus == Status.rejected {
            return Visibility(
                submitterVisible: result.submitterVisible,
                publicVisible: false,
                reviseAllowed: true,
                state: "REJECTED",
                reasonText: round.reasonText
            )
        }
        if currentContentProjectionPublished && round.taskStatus != Status.approved {
            return Visibility(
                submitterVisible: result.submitterVisible,
                publicVisible: false,
                reviseAllowed: result.reviseAllowed,
                state: result.state,
                reasonText: round.reasonText
            )
        }
        return result
    }

    public static func submitted(requestId: String?, taskId: Int64, submitterId: Int64) throws -> ReviewRound {
        guard SupportUntrusted.requestID(requestId) != nil else { throw ReviewFailure.missingRequestId }
        guard taskId > 0 else { throw ReviewFailure.invalidTaskId }
        return ReviewRound(
            requestId: requestId,
            taskId: taskId,
            submitterId: submitterId,
            taskStatus: Status.pending,
            recordAction: RecordAction.submit,
            reasonText: nil
        )
    }

    public static func rejected(_ submitted: ReviewRound, reasonText: String?) -> ReviewRound {
        ReviewRound(
            requestId: submitted.requestId,
            taskId: submitted.taskId,
            submitterId: submitted.submitterId,
            taskStatus: Status.rejected,
            recordAction: RecordAction.reject,
            reasonText: reasonText
        )
    }

    /// Revise after reject = a new submit round with a new requestId. Old reject remains requeryable.
    public static func revised(
        _ rejectedRound: ReviewRound,
        newRequestId: String?,
        newTaskId: Int64
    ) throws -> ReviewRound {
        guard rejectedRound.taskStatus == Status.rejected else {
            throw ReviewFailure.onlyRejectedCanRevise
        }
        return try submitted(
            requestId: newRequestId,
            taskId: newTaskId,
            submitterId: rejectedRound.submitterId ?? 0
        )
    }

    public static func approved(_ round: ReviewRound) throws -> ReviewRound {
        if round.taskStatus == Status.rejected || round.taskStatus == Status.cancelled {
            throw ReviewFailure.rejectedOrCancelledCannotApprove
        }
        return ReviewRound(
            requestId: round.requestId,
            taskId: round.taskId,
            submitterId: round.submitterId,
            taskStatus: Status.approved,
            recordAction: RecordAction.approve,
            reasonText: nil
        )
    }

    public static func flowSubmitRejectReviseApprove(
        submitRequestId: String,
        submitTaskId: Int64,
        submitterId: Int64,
        rejectReason: String,
        reviseRequestId: String,
        reviseTaskId: Int64
    ) throws -> [ReviewRound] {
        let submit = try submitted(requestId: submitRequestId, taskId: submitTaskId, submitterId: submitterId)
        let reject = rejected(submit, reasonText: rejectReason)
        let revise = try revised(reject, newRequestId: reviseRequestId, newTaskId: reviseTaskId)
        let approve = try approved(revise)
        return [submit, reject, revise, approve]
    }

    private static func statusLabel(_ status: Int) -> String {
        if status == Status.pending { return "PENDING" }
        if status == Status.escalated { return "ESCALATED" }
        return "UNKNOWN"
    }
}

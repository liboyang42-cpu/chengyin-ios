import Foundation

/// Pure self-contained value-type auditor for `w2-14/15/16` club access, enrollment & settlement parity:
/// 1. `/api/club/access/me` `POST` `application/x-www-form-urlencoded` contract (Wave-1 P0 fix),
/// 2. `ClubGovernanceCoordinator` operation permission check (`pending.command.operation.permission`),
/// 3. `ClubEnrollmentReader` `nonisolated` static formatting (`formatHeaderLine`, `formatPaymentRefundSummary`, `failureTitle`),
/// 4. `w2-16` `ClubOpsJoinNotifyPresentation` & `ClubOpsSettlementPresentation`.
public enum ClubAccessAndSettlementParityViolation: Equatable, Sendable {
    case accessMeMethodOrContentTypeMismatch
    case accessMeMissingAuthToken
    case governanceOperationDispatchedWithoutPermission(operation: String, requiredPermission: String)
    case invalidEnrollmentFormattingInput
    case enrollmentFormattingMismatch
    case invalidJoinNotifyPresentation
    case settlementNetAmountMismatch(expectedNetFen: Int64, actualNetFen: Int64)
    case unverifiedSettledStatusPresentation
}

/// Pillar 1 (`w2-14` / Wave-1 P0 fix): `/api/club/access/me` POST form-urlencoded contract input.
public struct ClubAccessMeContractAuditInput: Equatable, Sendable {
    public static let expectedPath = "/api/club/access/me"
    public static let expectedMethod = "POST"
    public static let expectedContentType = "application/x-www-form-urlencoded"
    public static let expectedAccept = "application/json"

    public let path: String
    public let httpMethod: String
    public let contentType: String?
    public let acceptHeader: String?
    public let hasValidAuthToken: Bool

    public init(
        path: String = Self.expectedPath,
        httpMethod: String = Self.expectedMethod,
        contentType: String? = Self.expectedContentType,
        acceptHeader: String? = Self.expectedAccept,
        hasValidAuthToken: Bool = true
    ) {
        self.path = path
        self.httpMethod = httpMethod
        self.contentType = contentType
        self.acceptHeader = acceptHeader
        self.hasValidAuthToken = hasValidAuthToken
    }

    public var isFormURLEncodedPOST: Bool {
        path == Self.expectedPath
            && httpMethod.uppercased() == Self.expectedMethod
            && contentType?.lowercased().hasPrefix(Self.expectedContentType) == true
            && acceptHeader?.lowercased() == Self.expectedAccept
    }
}

/// Pillar 2 (`w2-14`): `ClubGovernanceCoordinator` operation permission check (`pending.command.operation.permission`).
public struct ClubGovernanceOperationAuditInput: Equatable, Sendable {
    public let operationName: String
    public let requiredPermission: String
    public let grantedPermissions: Set<String>
    public let didAllowDispatch: Bool

    public init(
        operationName: String,
        requiredPermission: String,
        grantedPermissions: Set<String>,
        didAllowDispatch: Bool
    ) {
        self.operationName = operationName
        self.requiredPermission = requiredPermission
        self.grantedPermissions = grantedPermissions
        self.didAllowDispatch = didAllowDispatch
    }

    public var hasRequiredOperationPermission: Bool {
        let trimmed = requiredPermission.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && grantedPermissions.contains(trimmed)
    }
}

/// Pillar 3 (`w2-15`): `ClubEnrollmentReader` `nonisolated` static formatting helpers and audit input.
public enum ClubEnrollmentFormatter {
    public nonisolated static func formatHeaderLine(
        activityTitle: String,
        enrolledCount: Int,
        capacity: Int?
    ) -> String {
        let cleanTitle = activityTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let titlePart = cleanTitle.isEmpty ? "Untitled Activity" : cleanTitle
        let clampedEnrolled = max(0, enrolledCount)
        if let capacity, capacity > 0 {
            return "\(titlePart) • Enrolled \(clampedEnrolled)/\(capacity)"
        }
        return "\(titlePart) • Enrolled \(clampedEnrolled)"
    }

    public nonisolated static func formatPaymentRefundSummary(
        paidAmountFen: Int64,
        refundedAmountFen: Int64,
        statusLabel: String
    ) -> String {
        let cleanStatus = statusLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedStatus = cleanStatus.isEmpty ? "UNKNOWN" : cleanStatus
        return String(
            format: "Paid ¥%.2f • Refunded ¥%.2f • %@",
            Double(max(0, paidAmountFen)) / 100.0,
            Double(max(0, refundedAmountFen)) / 100.0,
            resolvedStatus
        )
    }

    public nonisolated static func failureTitle(forStatusCode statusCode: Int?) -> String {
        switch statusCode {
        case 401:
            return "Authentication Required"
        case 403:
            return "Club Enrollment Permission Denied"
        case 404:
            return "Club Activity Not Found"
        default:
            return "Club Enrollment Read Unavailable"
        }
    }
}

public struct ClubEnrollmentFormattingAuditInput: Equatable, Sendable {
    public let activityTitle: String
    public let enrolledCount: Int
    public let capacity: Int?
    public let paidAmountFen: Int64
    public let refundedAmountFen: Int64
    public let statusLabel: String
    public let failureStatusCode: Int?
    public let renderedHeaderLine: String
    public let renderedPaymentRefundSummary: String
    public let renderedFailureTitle: String

    public init(
        activityTitle: String,
        enrolledCount: Int,
        capacity: Int?,
        paidAmountFen: Int64,
        refundedAmountFen: Int64,
        statusLabel: String,
        failureStatusCode: Int?,
        renderedHeaderLine: String? = nil,
        renderedPaymentRefundSummary: String? = nil,
        renderedFailureTitle: String? = nil
    ) {
        self.activityTitle = activityTitle
        self.enrolledCount = enrolledCount
        self.capacity = capacity
        self.paidAmountFen = paidAmountFen
        self.refundedAmountFen = refundedAmountFen
        self.statusLabel = statusLabel
        self.failureStatusCode = failureStatusCode
        self.renderedHeaderLine = renderedHeaderLine ?? ClubEnrollmentFormatter.formatHeaderLine(
            activityTitle: activityTitle,
            enrolledCount: enrolledCount,
            capacity: capacity
        )
        self.renderedPaymentRefundSummary = renderedPaymentRefundSummary ?? ClubEnrollmentFormatter.formatPaymentRefundSummary(
            paidAmountFen: paidAmountFen,
            refundedAmountFen: refundedAmountFen,
            statusLabel: statusLabel
        )
        self.renderedFailureTitle = renderedFailureTitle ?? ClubEnrollmentFormatter.failureTitle(
            forStatusCode: failureStatusCode
        )
    }
}

/// Pillar 4 (`w2-16`): `ClubOpsJoinNotifyPresentation` & `ClubOpsSettlementPresentation` audit inputs.
public struct ClubOpsJoinNotifyAuditInput: Equatable, Sendable {
    public let clubID: Int
    public let pendingApplicantCount: Int
    public let notifyEnabled: Bool
    public let latestNotifyRevision: Int64

    public init(
        clubID: Int,
        pendingApplicantCount: Int,
        notifyEnabled: Bool,
        latestNotifyRevision: Int64
    ) {
        self.clubID = clubID
        self.pendingApplicantCount = pendingApplicantCount
        self.notifyEnabled = notifyEnabled
        self.latestNotifyRevision = latestNotifyRevision
    }
}

public struct ClubOpsSettlementAuditInput: Equatable, Sendable {
    public static let allowedStatuses: Set<String> = ["PENDING", "SETTLED", "FROZEN", "UNAVAILABLE"]

    public let clubID: Int
    public let grossAmountFen: Int64
    public let platformFeeFen: Int64
    public let settledNetAmountFen: Int64
    public let settlementStatus: String
    public let readbackVerified: Bool

    public init(
        clubID: Int,
        grossAmountFen: Int64,
        platformFeeFen: Int64,
        settledNetAmountFen: Int64,
        settlementStatus: String,
        readbackVerified: Bool
    ) {
        self.clubID = clubID
        self.grossAmountFen = grossAmountFen
        self.platformFeeFen = platformFeeFen
        self.settledNetAmountFen = settledNetAmountFen
        self.settlementStatus = settlementStatus
        self.readbackVerified = readbackVerified
    }
}

public struct ClubAccessAndSettlementParityAuditReport: Equatable, Sendable {
    public let formattedHeaderLine: String
    public let formattedPaymentRefundSummary: String
    public let formattedFailureTitle: String
    public let violations: [ClubAccessAndSettlementParityViolation]

    public var isPassing: Bool {
        violations.isEmpty
    }
}

public enum ClubAccessAndSettlementParityAuditor {
    public static func audit(
        accessMeContract: ClubAccessMeContractAuditInput,
        governanceOperations: [ClubGovernanceOperationAuditInput],
        enrollmentFormatting: ClubEnrollmentFormattingAuditInput,
        joinNotify: ClubOpsJoinNotifyAuditInput,
        settlement: ClubOpsSettlementAuditInput
    ) -> ClubAccessAndSettlementParityAuditReport {
        var violations: [ClubAccessAndSettlementParityViolation] = []

        // 1. /api/club/access/me POST form-urlencoded check
        if !accessMeContract.isFormURLEncodedPOST {
            violations.append(.accessMeMethodOrContentTypeMismatch)
        }
        if !accessMeContract.hasValidAuthToken {
            violations.append(.accessMeMissingAuthToken)
        }

        // 2. ClubGovernanceCoordinator operation permission check (pending.command.operation.permission)
        for op in governanceOperations {
            if op.didAllowDispatch && !op.hasRequiredOperationPermission {
                violations.append(
                    .governanceOperationDispatchedWithoutPermission(
                        operation: op.operationName,
                        requiredPermission: op.requiredPermission
                    )
                )
            }
        }

        // 3. ClubEnrollmentReader nonisolated static formatting check
        let expectedHeader = ClubEnrollmentFormatter.formatHeaderLine(
            activityTitle: enrollmentFormatting.activityTitle,
            enrolledCount: enrollmentFormatting.enrolledCount,
            capacity: enrollmentFormatting.capacity
        )
        let expectedPaymentSummary = ClubEnrollmentFormatter.formatPaymentRefundSummary(
            paidAmountFen: enrollmentFormatting.paidAmountFen,
            refundedAmountFen: enrollmentFormatting.refundedAmountFen,
            statusLabel: enrollmentFormatting.statusLabel
        )
        let expectedFailure = ClubEnrollmentFormatter.failureTitle(
            forStatusCode: enrollmentFormatting.failureStatusCode
        )

        if enrollmentFormatting.enrolledCount < 0
            || enrollmentFormatting.paidAmountFen < 0
            || enrollmentFormatting.refundedAmountFen < 0
            || enrollmentFormatting.refundedAmountFen > enrollmentFormatting.paidAmountFen
            || (enrollmentFormatting.capacity.map { $0 <= 0 } ?? false)
        {
            violations.append(.invalidEnrollmentFormattingInput)
        }
        if enrollmentFormatting.renderedHeaderLine != expectedHeader
            || enrollmentFormatting.renderedPaymentRefundSummary != expectedPaymentSummary
            || enrollmentFormatting.renderedFailureTitle != expectedFailure
        {
            violations.append(.enrollmentFormattingMismatch)
        }

        // 4. w2-16 ClubOpsJoinNotifyPresentation & ClubOpsSettlementPresentation checks
        if joinNotify.clubID <= 0
            || joinNotify.pendingApplicantCount < 0
            || joinNotify.latestNotifyRevision < 0
        {
            violations.append(.invalidJoinNotifyPresentation)
        }

        let expectedNet = settlement.grossAmountFen - settlement.platformFeeFen
        if settlement.clubID <= 0
            || settlement.grossAmountFen < 0
            || settlement.platformFeeFen < 0
            || settlement.settledNetAmountFen < 0
            || !ClubOpsSettlementAuditInput.allowedStatuses.contains(settlement.settlementStatus)
        {
            violations.append(.unverifiedSettledStatusPresentation)
        } else if settlement.settledNetAmountFen != expectedNet {
            violations.append(
                .settlementNetAmountMismatch(
                    expectedNetFen: expectedNet,
                    actualNetFen: settlement.settledNetAmountFen
                )
            )
        } else if settlement.settlementStatus == "SETTLED" && !settlement.readbackVerified {
            violations.append(.unverifiedSettledStatusPresentation)
        }

        return ClubAccessAndSettlementParityAuditReport(
            formattedHeaderLine: expectedHeader,
            formattedPaymentRefundSummary: expectedPaymentSummary,
            formattedFailureTitle: expectedFailure,
            violations: violations
        )
    }
}

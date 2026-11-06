import Foundation

/// Existing extra-approver permission code (pass-in grant; this type does not look up tokens).
public enum ExtraApproverGrant {
    public static let approvePermission = "business:clubextra:approve"
}

/// Frozen sale-time compensation terms. Isolated struct, not a Java domain type.
public struct FrozenCompensationTerms: Equatable, Sendable {
    public var topicId: Int64
    public var executingClubId: Int64?
    public var fixedCompensation: Decimal
    public var extraApproverUserId: Int64?
    public var configHash: String?
    public var frozenAt: Date?

    public init(
        topicId: Int64,
        executingClubId: Int64?,
        fixedCompensation: Decimal,
        extraApproverUserId: Int64?,
        configHash: String?,
        frozenAt: Date?
    ) {
        self.topicId = topicId
        self.executingClubId = executingClubId
        self.fixedCompensation = fixedCompensation
        self.extraApproverUserId = extraApproverUserId
        self.configHash = SupportUntrusted.requestID(configHash)
        self.frozenAt = frozenAt
    }
}

/// Current FINAL settled facts. Contrast only; must not replace frozen terms.
public struct FinalCompensationFacts: Equatable, Sendable {
    public var clubId: Int64?
    public var fixedCompensation: Decimal?
    public var pending: Bool

    public init(clubId: Int64?, fixedCompensation: Decimal?, pending: Bool) {
        self.clubId = clubId
        self.fixedCompensation = fixedCompensation
        self.pending = pending
    }

    public static func settled(clubId: Int64, fixedCompensation: Decimal) -> FinalCompensationFacts {
        FinalCompensationFacts(clubId: clubId, fixedCompensation: fixedCompensation, pending: false)
    }

    public var isPending: Bool { pending }
}

public struct CompensationViewerGrant: Equatable, Sendable {
    public var viewerId: Int64?
    public var existingPermissionCodes: Set<String>

    public init(viewerId: Int64?, existingPermissionCodes: Set<String>) {
        self.viewerId = viewerId
        self.existingPermissionCodes = existingPermissionCodes
    }
}

public struct AuditTrailEntry: Equatable, Sendable {
    public static let sourceBusinessAuditEvent = "BUSINESS_AUDIT_EVENT"
    public var source: String?
    public var action: String?
    public var sourceId: Int64?

    public init(source: String? = nil, action: String? = nil, sourceId: Int64? = nil) {
        self.source = source
        self.action = action
        self.sourceId = sourceId
    }
}

public struct CompensationEntryFailure: Error, Equatable {
    public let code: String
    public static let denied = CompensationEntryFailure(code: CompensationEntryProjection.denied)
    public static let termsMissing = CompensationEntryFailure(code: CompensationEntryProjection.termsMissing)
}

public struct CompensationRequeryView: Equatable, Sendable {
    public var requestId: String?
    public var topicId: Int64
    public var permissionCode: String
    public var frozenAt: Date?
    public var configHash: String?
    public var fixedCompensation: Decimal
    public var extraApproverUserId: Int64?
    public var auditEventCount: Int
    public var trailCount: Int
    public var currentFinalPending: Bool
}

/// C11 permissioned original compensation entry. Frozen terms stay original.
public struct CompensationEntryProjection {
    public static let denied = "COMPENSATION_VIEW_DENIED"
    public static let termsMissing = "EDITION_TERMS_MISSING"
    public static let frozenTerms = "clubEditionCompensation.requireFrozenTerms"
    public static let extraApprove = "extraApprover.canApproveExtraHours"
    public static let auditTrail = "auditTrail.trail"
    public static let auditResourceBinding = "auditTrail.resourceBinding"

    public protocol FrozenTermsSource {
        func requireFrozenTerms(topicId: Int64) -> FrozenCompensationTerms?
    }

    public protocol CompensationAuditSource {
        func eventsForRequest(_ requestId: String) -> [OriginalAuditEvent]
        func trailForTopic(_ topicId: Int64) -> [AuditTrailEntry]
    }

    public struct View: Equatable, Sendable {
        public var requestId: String?
        public var topicId: Int64
        public var viewerId: Int64
        public var permissionCode: String
        public var originalTerms: FrozenCompensationTerms
        public var originalAudit: [OriginalAuditEvent]
        public var trail: [AuditTrailEntry]
        public var currentFinal: FinalCompensationFacts?

        public var permissioned: Bool {
            permissionCode == ExtraApproverGrant.approvePermission
        }

        public var auditable: Bool {
            !originalAudit.isEmpty || !trail.isEmpty
        }

        /// Current FINAL settled amount must not replace frozen original terms.
        public var originalEntryNotReplacedByCurrentFinal: Bool {
            guard let currentFinal, !currentFinal.isPending else { return true }
            return originalTerms.configHash != nil
        }

        public func asRequeryableView() -> CompensationRequeryView {
            CompensationRequeryView(
                requestId: requestId,
                topicId: topicId,
                permissionCode: permissionCode,
                frozenAt: originalTerms.frozenAt,
                configHash: originalTerms.configHash,
                fixedCompensation: originalTerms.fixedCompensation,
                extraApproverUserId: originalTerms.extraApproverUserId,
                auditEventCount: originalAudit.count,
                trailCount: trail.count,
                currentFinalPending: currentFinal?.isPending ?? false
            )
        }
    }

    private let termsSource: FrozenTermsSource
    private let auditSource: CompensationAuditSource

    public init(termsSource: FrozenTermsSource, auditSource: CompensationAuditSource) {
        self.termsSource = termsSource
        self.auditSource = auditSource
    }

    /// Missing requestId stays Optional.none, never "".
    public func project(
        requestId: String?,
        topicId: Int64?,
        viewer: CompensationViewerGrant?,
        currentFinal: FinalCompensationFacts?
    ) throws -> CompensationEntryProjection.View? {
        guard let id = SupportUntrusted.requestID(requestId) else { return nil }
        guard let topicId, topicId > 0 else {
            throw CompensationEntryFailure(code: "invalidTopic")
        }
        guard let viewer, let viewerId = viewer.viewerId, viewerId > 0 else {
            throw CompensationEntryFailure.denied
        }
        guard viewer.existingPermissionCodes.contains(ExtraApproverGrant.approvePermission) else {
            throw CompensationEntryFailure.denied
        }
        guard let terms = termsSource.requireFrozenTerms(topicId: topicId) else {
            throw CompensationEntryFailure.termsMissing
        }
        let originalAudit = auditSource.eventsForRequest(id)
        let trail = auditSource.trailForTopic(topicId)
        return View(
            requestId: id,
            topicId: topicId,
            viewerId: viewerId,
            permissionCode: ExtraApproverGrant.approvePermission,
            originalTerms: terms,
            originalAudit: originalAudit,
            trail: trail,
            currentFinal: currentFinal
        )
    }

    public func requery(
        requestId: String?,
        topicId: Int64?,
        viewer: CompensationViewerGrant?,
        currentFinal: FinalCompensationFacts?
    ) throws -> CompensationEntryProjection.View? {
        try project(requestId: requestId, topicId: topicId, viewer: viewer, currentFinal: currentFinal)
    }

    public func recoverOriginal(
        originalRequestID requestId: String?,
        topicId: Int64?,
        viewer: CompensationViewerGrant?,
        currentFinal: FinalCompensationFacts?
    ) throws -> CompensationEntryProjection.View? {
        try requery(requestId: requestId, topicId: topicId, viewer: viewer, currentFinal: currentFinal)
    }

    public struct WaitingSource: Error, Equatable {
        public let capability: String
    }

    /// Existing ExtraApproverReachability.canApproveExtraHours as a pass-in port.
    /// Missing source is WAITING_SOURCE. Denied viewers do not read frozen terms.
    public func projectFromReachability(
        requestId: String?,
        topicId: Int64?,
        viewerId: Int64?,
        canApproveExtraHours: ((Int64) -> Bool)?,
        currentFinal: FinalCompensationFacts?
    ) throws -> CompensationEntryProjection.View? {
        guard let canApproveExtraHours else {
            throw WaitingSource(capability: Self.extraApprove)
        }
        guard let viewerId, viewerId > 0, canApproveExtraHours(viewerId) else {
            throw CompensationEntryFailure.denied
        }
        return try project(
            requestId: requestId,
            topicId: topicId,
            viewer: CompensationViewerGrant(
                viewerId: viewerId,
                existingPermissionCodes: [ExtraApproverGrant.approvePermission]),
            currentFinal: currentFinal)
    }

    /// Read AuditTrailProjectionService.trail only from an already authorized view.
    /// Rechecks the current grant. No permission, an account switch, or another
    /// resource does not call the reader. bizType stays caller-supplied.
    /// Missing reader is WAITING_SOURCE. An empty list is a real empty trail.
    public func recoverTrail(
        authorized: View?,
        viewer: CompensationViewerGrant?,
        bizType: String?,
        bizId: Int64?,
        trail: ((String, Int64) -> [String])?
    ) throws -> [String]? {
        guard let authorized, let viewer, let viewerId = viewer.viewerId, viewerId > 0,
              viewerId == authorized.viewerId,
              viewer.existingPermissionCodes.contains(ExtraApproverGrant.approvePermission) else {
            throw CompensationEntryFailure.denied
        }
        let type = bizType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !type.isEmpty, let bizId, bizId > 0 else { return nil }
        guard bizId == authorized.topicId else {
            throw CompensationEntryFailure.denied
        }
        throw WaitingSource(capability: Self.auditResourceBinding)
    }
}

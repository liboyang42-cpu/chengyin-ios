import XCTest
@testable import QuestifyCore

final class CompensationEntryProjectionTests: XCTestCase {
    func testFirstJourneyPermissionedFrozenTermsRecoverOriginal() throws {
        let frozen = frozenTerms()
        let original = OriginalAuditEvent(
            requestId: "comp-req-1", action: "COMPENSATION_FREEZE", afterJson: "FROZEN")
        let trail = AuditTrailEntry(
            source: AuditTrailEntry.sourceBusinessAuditEvent, action: "COMPENSATION_FREEZE")
        let projection = CompensationEntryProjection(
            termsSource: FixedFrozenTerms(terms: frozen),
            auditSource: RecordingAuditSource(events: [original], trail: [trail]))
        let current = FinalCompensationFacts.settled(
            clubId: 7, fixedCompensation: Decimal(string: "999.00")!)
        let viewer = CompensationViewerGrant(
            viewerId: 88, existingPermissionCodes: [ExtraApproverGrant.approvePermission])
        let view = try XCTUnwrap(projection.project(
            requestId: "comp-req-1", topicId: 10, viewer: viewer, currentFinal: current))
        let again = try XCTUnwrap(projection.requery(
            requestId: "comp-req-1", topicId: 10, viewer: viewer, currentFinal: current))
        XCTAssertTrue(view.permissioned)
        XCTAssertTrue(view.auditable)
        XCTAssertEqual(view.originalTerms.fixedCompensation, Decimal(string: "200.00"))
        XCTAssertEqual(view.originalTerms.configHash, "hash-v1")
        XCTAssertTrue(view.originalEntryNotReplacedByCurrentFinal)
        XCTAssertEqual(view.asRequeryableView(), again.asRequeryableView())
        XCTAssertEqual(view.permissionCode, ExtraApproverGrant.approvePermission)
        XCTAssertEqual(
            try projection.recoverOriginal(
                originalRequestID: "comp-req-1", topicId: 10, viewer: viewer, currentFinal: current
            )?.originalTerms.fixedCompensation,
            Decimal(string: "200.00"))
        XCTAssertNotEqual(view.originalTerms.fixedCompensation, Decimal(string: "999.00"))
    }

    func testMissingExistingPermissionIsDeniedAndDoesNotLeakTerms() {
        let audit = ForbiddenAuditSource()
        let projection = CompensationEntryProjection(
            termsSource: FixedFrozenTerms(terms: frozenTerms()), auditSource: audit)
        let stranger = CompensationViewerGrant(
            viewerId: 3, existingPermissionCodes: ["business:topic:list"])
        XCTAssertThrowsError(
            try projection.project(requestId: "comp-req-1", topicId: 10, viewer: stranger, currentFinal: nil)
        ) { error in
            XCTAssertEqual((error as? CompensationEntryFailure)?.code, CompensationEntryProjection.denied)
        }
        XCTAssertEqual(audit.reads, 0)
    }

    func testInventedPermissionCodeIsNotAccepted() {
        let projection = CompensationEntryProjection(
            termsSource: FixedFrozenTerms(terms: frozenTerms()),
            auditSource: RecordingAuditSource(events: [], trail: []))
        let forged = CompensationViewerGrant(
            viewerId: 88, existingPermissionCodes: ["business:compensation:view"])
        XCTAssertThrowsError(
            try projection.project(requestId: "comp-req-1", topicId: 10, viewer: forged, currentFinal: nil))
    }

    func testOtherViewerDoesNotRewriteFrozenOriginal() throws {
        let frozen = frozenTerms()
        let original = OriginalAuditEvent(
            requestId: "comp-req-1", action: "COMPENSATION_FREEZE", afterJson: "FROZEN")
        let trail = AuditTrailEntry(
            source: AuditTrailEntry.sourceBusinessAuditEvent, action: "COMPENSATION_FREEZE")
        let projection = CompensationEntryProjection(
            termsSource: FixedFrozenTerms(terms: frozen),
            auditSource: RecordingAuditSource(events: [original], trail: [trail]))
        let current = FinalCompensationFacts.settled(
            clubId: 7, fixedCompensation: Decimal(string: "999.00")!)
        let viewer = CompensationViewerGrant(
            viewerId: 88, existingPermissionCodes: [ExtraApproverGrant.approvePermission])
        let other = CompensationViewerGrant(
            viewerId: 3, existingPermissionCodes: [])
        let view = try XCTUnwrap(projection.project(
            requestId: "comp-req-1", topicId: 10, viewer: viewer, currentFinal: current))
        XCTAssertThrowsError(
            try projection.project(requestId: "comp-req-1", topicId: 10, viewer: other, currentFinal: current)
        ) { error in
            XCTAssertEqual((error as? CompensationEntryFailure)?.code, CompensationEntryProjection.denied)
        }
        XCTAssertEqual(
            try projection.recoverOriginal(
                originalRequestID: "comp-req-1", topicId: 10, viewer: viewer, currentFinal: current
            )?.originalTerms.fixedCompensation,
            Decimal(string: "200.00"))
        XCTAssertEqual(view.originalTerms.fixedCompensation, Decimal(string: "200.00"))
        XCTAssertNotEqual(view.originalTerms.fixedCompensation, Decimal(string: "999.00"))
    }

    func testMissingRequestIdStaysOptionalNone() throws {
        let projection = CompensationEntryProjection(
            termsSource: FixedFrozenTerms(terms: frozenTerms()),
            auditSource: RecordingAuditSource(events: [], trail: []))
        let viewer = CompensationViewerGrant(
            viewerId: 88, existingPermissionCodes: [ExtraApproverGrant.approvePermission])
        XCTAssertNil(try projection.project(requestId: nil, topicId: 10, viewer: viewer, currentFinal: nil))
        XCTAssertNil(try projection.project(requestId: "", topicId: 10, viewer: viewer, currentFinal: nil))
        XCTAssertNil(try projection.project(requestId: "  ", topicId: 10, viewer: viewer, currentFinal: nil))
    }

    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueAuditApplies() throws {
        let audit = RequestKeyedAuditSource()
        let projection = CompensationEntryProjection(
            termsSource: FixedFrozenTerms(terms: frozenTerms()),
            auditSource: audit)
        let viewer = CompensationViewerGrant(
            viewerId: 88, existingPermissionCodes: [ExtraApproverGrant.approvePermission])
        XCTAssertNil(try projection.recoverOriginal(
            originalRequestID: nil, topicId: 10, viewer: viewer, currentFinal: nil))
        XCTAssertNil(try projection.recoverOriginal(
            originalRequestID: "  ", topicId: 10, viewer: viewer, currentFinal: nil))
        let recovered = try XCTUnwrap(projection.recoverOriginal(
            originalRequestID: "c11-comp-never", topicId: 10, viewer: viewer, currentFinal: nil))
        XCTAssertEqual(recovered.requestId, "c11-comp-never")
        XCTAssertTrue(recovered.originalAudit.isEmpty)
        XCTAssertTrue(audit.byRequest.isEmpty)
        audit.byRequest["c11-comp-never"] = [
            OriginalAuditEvent(
                requestId: "c11-comp-never", targetType: "ORDER", targetId: 10,
                action: "COMPENSATION_FREEZE", afterJson: "FROZEN")
        ]
        let first = try XCTUnwrap(projection.recoverOriginal(
            originalRequestID: "c11-comp-never", topicId: 10, viewer: viewer, currentFinal: nil))
        XCTAssertEqual(first.requestId, "c11-comp-never")
        XCTAssertEqual(first.originalAudit.count, 1)
        XCTAssertEqual(first.originalAudit[0].afterJson, "FROZEN")
        XCTAssertEqual(audit.byRequest["c11-comp-never"]?.count, 1)
        XCTAssertEqual(audit.byRequest.count, 1)
    }

    func testProjectFromReachabilityConsumesPublicFrozenTermsWithoutOccupyingOnDeny() throws {
        let audit = ForbiddenAuditSource()
        let projection = CompensationEntryProjection(
            termsSource: FixedFrozenTerms(terms: frozenTerms()), auditSource: audit)
        do {
            _ = try projection.projectFromReachability(
                requestId: "comp-req-1", topicId: 10, viewerId: 88,
                canApproveExtraHours: nil, currentFinal: nil)
            XCTFail("missing extra-approver port must WAITING_SOURCE")
        } catch let waiting as CompensationEntryProjection.WaitingSource {
            XCTAssertEqual(waiting.capability, CompensationEntryProjection.extraApprove)
        }
        XCTAssertThrowsError(
            try projection.projectFromReachability(
                requestId: "comp-req-1", topicId: 10, viewerId: 88,
                canApproveExtraHours: { _ in false }, currentFinal: nil)
        ) { error in
            XCTAssertEqual((error as? CompensationEntryFailure)?.code, CompensationEntryProjection.denied)
        }
        XCTAssertEqual(audit.reads, 0)
        let allowed = CompensationEntryProjection(
            termsSource: FixedFrozenTerms(terms: frozenTerms()),
            auditSource: RecordingAuditSource(events: [], trail: []))
        let view = try XCTUnwrap(allowed.projectFromReachability(
            requestId: "comp-req-1", topicId: 10, viewerId: 88,
            canApproveExtraHours: { $0 == 88 }, currentFinal: nil))
        XCTAssertEqual(view.originalTerms.fixedCompensation, Decimal(string: "200.00"))
        XCTAssertTrue(view.permissioned)
    }

    func testRecoverTrailReadsExistingUnifiedTrailWithoutWritingAudit() throws {
        let audit = ForbiddenAuditSource()
        let projection = CompensationEntryProjection(
            termsSource: FixedFrozenTerms(terms: frozenTerms()),
            auditSource: RecordingAuditSource(events: [], trail: []))
        let grant = CompensationViewerGrant(
            viewerId: 88, existingPermissionCodes: [ExtraApproverGrant.approvePermission])
        let authorized = try XCTUnwrap(projection.project(
            requestId: "comp-req-1", topicId: 10, viewer: grant, currentFinal: nil))
        var reads = 0
        let counting: (String, Int64) -> [String] = { _, _ in
            reads += 1
            return ["written"]
        }
        XCTAssertThrowsError(try projection.recoverTrail(
            authorized: nil, viewer: grant, bizType: "ACTIVITY", bizId: 10, trail: counting)) {
            XCTAssertEqual(($0 as? CompensationEntryFailure)?.code, CompensationEntryProjection.denied)
        }
        XCTAssertThrowsError(try projection.recoverTrail(
            authorized: authorized,
            viewer: CompensationViewerGrant(viewerId: 88, existingPermissionCodes: []),
            bizType: "ACTIVITY", bizId: 10, trail: counting)) {
            XCTAssertEqual(($0 as? CompensationEntryFailure)?.code, CompensationEntryProjection.denied)
        }
        XCTAssertThrowsError(try projection.recoverTrail(
            authorized: authorized,
            viewer: CompensationViewerGrant(
                viewerId: 3, existingPermissionCodes: [ExtraApproverGrant.approvePermission]),
            bizType: "ACTIVITY", bizId: 10, trail: counting)) {
            XCTAssertEqual(($0 as? CompensationEntryFailure)?.code, CompensationEntryProjection.denied)
        }
        XCTAssertThrowsError(try projection.recoverTrail(
            authorized: authorized, viewer: grant, bizType: "ACTIVITY", bizId: 99, trail: counting)) {
            XCTAssertEqual(($0 as? CompensationEntryFailure)?.code, CompensationEntryProjection.denied)
        }
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(audit.reads, 0)
        XCTAssertNil(try projection.recoverTrail(
            authorized: authorized, viewer: grant, bizType: "  ", bizId: 10, trail: counting))
        XCTAssertNil(try projection.recoverTrail(
            authorized: authorized, viewer: grant, bizType: "ACTIVITY", bizId: 0, trail: counting))
        XCTAssertEqual(reads, 0)
        do {
            _ = try projection.recoverTrail(
                authorized: authorized, viewer: grant, bizType: "ACTIVITY", bizId: 10, trail: counting)
            XCTFail("unbound bizType must not read")
        } catch let waiting as CompensationEntryProjection.WaitingSource {
            XCTAssertEqual(waiting.capability, CompensationEntryProjection.auditResourceBinding)
        }
        do {
            _ = try projection.recoverTrail(
                authorized: authorized, viewer: grant, bizType: "ORDER", bizId: 10, trail: counting)
            XCTFail("another bizType with the same id must not read")
        } catch let waiting as CompensationEntryProjection.WaitingSource {
            XCTAssertEqual(waiting.capability, CompensationEntryProjection.auditResourceBinding)
        }
        XCTAssertEqual(reads, 0)
    }

    private func frozenTerms() -> FrozenCompensationTerms {
        FrozenCompensationTerms(
            topicId: 10, executingClubId: 7,
            fixedCompensation: Decimal(string: "200.00")!,
            extraApproverUserId: 88, configHash: "hash-v1",
            frozenAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
}

final class ForbiddenAuditSource: CompensationEntryProjection.CompensationAuditSource {
    var reads = 0
    func eventsForRequest(_ requestId: String) -> [OriginalAuditEvent] {
        reads += 1
        XCTFail("denied viewer must not read audit")
        return []
    }
    func trailForTopic(_ topicId: Int64) -> [AuditTrailEntry] {
        reads += 1
        XCTFail("denied viewer must not read trail")
        return []
    }
}

final class RequestKeyedAuditSource: CompensationEntryProjection.CompensationAuditSource {
    var byRequest: [String: [OriginalAuditEvent]] = [:]

    func eventsForRequest(_ requestId: String) -> [OriginalAuditEvent] {
        byRequest[requestId] ?? []
    }

    func trailForTopic(_ topicId: Int64) -> [AuditTrailEntry] {
        _ = topicId
        return []
    }
}

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

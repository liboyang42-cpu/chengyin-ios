import XCTest
@testable import QuestifyCore

final class SupportEventLocatorTests: XCTestCase {
    func testFirstJourneyLocateUnknownPermissionedCompensationDeletionEvidenceApproveLocaleRecoverOriginal() throws {
        XCTAssertFalse(C11SourceInventory.v12DocxPresent)
        XCTAssertFalse(C11SourceInventory.pack232Present)
        XCTAssertFalse(C11SourceInventory.unpushedIosSHAPresent)
        XCTAssertEqual(C11SourceInventory.v12Docx, "v12.docx")
        XCTAssertEqual(C11SourceInventory.pack232, "232.pack")
        XCTAssertEqual(C11SourceInventory.unpushedIosSHA, "e2d86c4")
        XCTAssertEqual(C11SourceInventory.waitingSource, "WAITING_SOURCE")

        let requestId = "c11-journey-req"
        let source = InMemoryOriginalEventSource()
            .add(OriginalAuditEvent(
                requestId: requestId, targetType: "ORDER", targetId: 501,
                action: "COMPENSATION_FREEZE", afterJson: "UNKNOWN"))
            .add(OriginalAuditEvent(
                requestId: requestId, targetType: "RUN", targetId: 77,
                action: "RUN_ATTACH", afterJson: "UNKNOWN"))
        let locator = SupportEventLocator(originalEvents: source)
        XCTAssertEqual(SupportEventLocator.projectionAppliedSuccess, "APPLIED+SUCCESS")
        let projection = SupportCurrentProjection(
            requestId: requestId, appliedState: "APPLIED+SUCCESS")

        let located = try XCTUnwrap(locator.locateByRequestId(requestId, currentProjection: projection))
        XCTAssertEqual(located.requestId, requestId)
        XCTAssertEqual(located.originalOutcome, "UNKNOWN")
        XCTAssertTrue(located.currentProjectionClaimsSuccess)
        XCTAssertTrue(located.originalIsNotProjectionSuccess)
        XCTAssertEqual(located.runId, 77)
        XCTAssertEqual(located.orderId, 501)
        XCTAssertEqual(
            try locator.requery(requestId, currentProjection: projection)?.originalOutcome,
            located.originalOutcome)
        XCTAssertEqual(
            try locator.recoverOriginal(originalRequestID: requestId, currentProjection: projection)?.originalOutcome,
            "UNKNOWN")
        XCTAssertNotEqual(located.originalOutcome, SupportEventLocator.projectionAppliedSuccess)
        XCTAssertEqual(located.asRequeryableView()["usedCurrentProjectionAsSuccess"] as? Bool, false)

        let frozen = FrozenCompensationTerms(
            topicId: 42, executingClubId: 7,
            fixedCompensation: Decimal(string: "200.00")!,
            extraApproverUserId: 88, configHash: "c11-hash",
            frozenAt: Date(timeIntervalSince1970: 2))
        let trail = AuditTrailEntry(
            source: AuditTrailEntry.sourceBusinessAuditEvent,
            action: "COMPENSATION_FREEZE", sourceId: 1)
        let compensation = CompensationEntryProjection(
            termsSource: FixedFrozenTerms(terms: frozen),
            auditSource: RecordingAuditSource(events: located.originalEvents, trail: [trail]))
        let granted = CompensationViewerGrant(
            viewerId: 88, existingPermissionCodes: [ExtraApproverGrant.approvePermission])
        let currentFinal = FinalCompensationFacts.settled(
            clubId: 7, fixedCompensation: Decimal(string: "999.00")!)
        let view = try XCTUnwrap(compensation.project(
            requestId: requestId, topicId: 42, viewer: granted, currentFinal: currentFinal))
        XCTAssertTrue(view.permissioned)
        XCTAssertTrue(view.auditable)
        XCTAssertEqual(view.originalTerms.fixedCompensation, Decimal(string: "200.00"))
        XCTAssertNotEqual(view.originalTerms.fixedCompensation, Decimal(string: "999.00"))
        XCTAssertTrue(view.originalEntryNotReplacedByCurrentFinal)
        XCTAssertEqual(
            view.asRequeryableView(),
            try compensation.requery(
                requestId: requestId, topicId: 42, viewer: granted, currentFinal: currentFinal
            )?.asRequeryableView())
        XCTAssertEqual(
            try compensation.recoverOriginal(
                originalRequestID: requestId, topicId: 42, viewer: granted, currentFinal: currentFinal
            )?.originalTerms.fixedCompensation,
            Decimal(string: "200.00"))

        let denied = CompensationViewerGrant(viewerId: 3, existingPermissionCodes: [])
        XCTAssertThrowsError(
            try compensation.project(
                requestId: requestId, topicId: 42, viewer: denied, currentFinal: currentFinal)
        ) { error in
            XCTAssertEqual((error as? CompensationEntryFailure)?.code, CompensationEntryProjection.denied)
        }

        let deregister = DataDeletionEvidenceTable.byRequestKind("ACCOUNT_DEREGISTER")
        XCTAssertTrue(deregister.contains { $0.artifact == "member_identity" && $0.removed })
        XCTAssertTrue(deregister.contains { $0.artifact == "oms_order" && $0.retained })
        XCTAssertTrue(deregister.contains {
            $0.artifact == "business_audit_event" && $0.disposition == .retainedLegal
        })
        XCTAssertFalse(DataDeletionEvidenceTable.emptyCurrentProjectionIsNeverExisted)

        let review = try ReviewResultVisibilityAdapter.flowSubmitRejectReviseApprove(
            submitRequestId: "c11-rev-1", submitTaskId: 11, submitterId: 9,
            rejectReason: "需修订", reviseRequestId: "c11-rev-2", reviseTaskId: 12)
        XCTAssertTrue(
            ReviewResultVisibilityAdapter.visibility(review[3], audience: .PUBLIC).approvedResultVisible)
        let instant = ISO8601DateFormatter().date(from: "2026-10-23T12:00:00Z")
        XCTAssertEqual(
            try VersionedLocaleDisplay.format(
                .cn, instant: instant, timeZone: TimeZone(identifier: "Asia/Shanghai")!),
            "2026-10-23 20:00:00")
        XCTAssertEqual(
            VersionedLocaleDisplay.legalGateStatus(.appStoreReview), VersionedLocaleDisplay.notRun)
        XCTAssertEqual(
            VersionedLocaleDisplay.legalGateStatus(.icpFiling), VersionedLocaleDisplay.notRun)
        XCTAssertEqual(VersionedLocaleDisplay.notRun, "NOT_RUN")
    }

    func testLocateByRequestIdReturnsOriginalUnknownNotCurrentProjectionSuccess() throws {
        let original = OriginalAuditEvent(
            requestId: "req-unknown-1", targetType: "RUN", targetId: 11,
            action: "SUBMIT", afterJson: "UNKNOWN")
        let locator = SupportEventLocator(originalEvents: InMemoryOriginalEventSource().add(original))
        let projection = SupportCurrentProjection(
            requestId: "req-unknown-1", appliedState: SupportEventLocator.projectionAppliedSuccess)
        let located = try XCTUnwrap(locator.locateByRequestId("req-unknown-1", currentProjection: projection))
        XCTAssertEqual(located.originalOutcome, "UNKNOWN")
        XCTAssertTrue(located.currentProjectionClaimsSuccess)
        XCTAssertTrue(located.originalIsNotProjectionSuccess)
        XCTAssertEqual(located.runId, 11)
        XCTAssertTrue(located.asRequeryableView()["requestId"] is String)
    }

    func testRequeryKeepsOriginalOutcome() throws {
        let original = OriginalAuditEvent(
            requestId: "req-fail-1", targetType: "ORDER", targetId: 88,
            action: "PAY", afterJson: "FAILED")
        let locator = SupportEventLocator(originalEvents: InMemoryOriginalEventSource().add(original))
        let projection = SupportCurrentProjection(
            requestId: "req-fail-1", appliedState: SupportEventLocator.projectionAppliedSuccess)
        let first = try XCTUnwrap(locator.locateByRequestId("req-fail-1", currentProjection: projection))
        let second = try XCTUnwrap(locator.requery("req-fail-1", currentProjection: projection))
        XCTAssertEqual(first.originalOutcome, "FAILED")
        XCTAssertEqual(first.originalOutcome, second.originalOutcome)
        XCTAssertEqual(second.orderId, 88)
        XCTAssertNotEqual(second.originalOutcome, SupportEventLocator.projectionAppliedSuccess)
    }

    func testLocateByRunAndOrderShareSameRequest() throws {
        let source = InMemoryOriginalEventSource()
            .add(OriginalAuditEvent(requestId: "req-same", targetType: "RUN", targetId: 2,
                                    action: "START", afterJson: "PENDING"))
            .add(OriginalAuditEvent(requestId: "req-same", targetType: "ORDER", targetId: 9,
                                    action: "CREATE", afterJson: "PENDING"))
        let locator = SupportEventLocator(originalEvents: source)
        let byRun = try XCTUnwrap(locator.locateByRunId(2, currentProjection: nil))
        let byOrder = try XCTUnwrap(locator.locateByOrderId(9, currentProjection: nil))
        XCTAssertEqual(byRun.requestId, "req-same")
        XCTAssertEqual(byOrder.requestId, "req-same")
        XCTAssertEqual(byRun.runId, 2)
        XCTAssertEqual(byOrder.orderId, 9)
    }

    func testLocateByRunRejectsADifferentTarget() {
        let locator = SupportEventLocator(originalEvents: WrongTargetSource())
        XCTAssertThrowsError(try locator.locateByRunId(7, currentProjection: nil)) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "RUN:7"))
        }
    }

    func testMissingRequestIdStaysOptionalNoneNeverEmptyString() throws {
        let locator = SupportEventLocator(originalEvents: InMemoryOriginalEventSource())
        XCTAssertNil(SupportUntrusted.requestID(nil))
        XCTAssertNil(SupportUntrusted.requestID(""))
        XCTAssertNil(SupportUntrusted.requestID("  "))
        XCTAssertNil(try locator.locateByRequestId(nil, currentProjection: nil))
        XCTAssertNil(try locator.locateByRequestId("", currentProjection: nil))
        XCTAssertNil(try locator.locateByRequestId("  ", currentProjection: nil))
        XCTAssertTrue(SupportUntrusted.jsonValue(nil) is NSNull)
        XCTAssertTrue(SupportUntrusted.jsonValue("") is NSNull)
        XCTAssertFalse(SupportUntrusted.jsonValue(nil) is String)
    }

    func testOtherRequestIdDoesNotRewriteOriginalEvents() throws {
        let original = OriginalAuditEvent(
            requestId: "req-unknown-1", targetType: "RUN", targetId: 11,
            action: "SUBMIT", afterJson: "UNKNOWN")
        let source = InMemoryOriginalEventSource().add(original)
        let locator = SupportEventLocator(originalEvents: source)
        let projection = SupportCurrentProjection(
            requestId: "req-unknown-1", appliedState: SupportEventLocator.projectionAppliedSuccess)
        let located = try XCTUnwrap(locator.locateByRequestId("req-unknown-1", currentProjection: projection))
        XCTAssertThrowsError(try locator.locateByRequestId("req-other", currentProjection: projection)) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "req-other"))
        }
        let recovered = try XCTUnwrap(
            locator.recoverOriginal(originalRequestID: "req-unknown-1", currentProjection: projection))
        XCTAssertEqual(recovered.originalOutcome, "UNKNOWN")
        XCTAssertEqual(recovered.requestId, located.requestId)
        XCTAssertEqual(recovered.originalEvents.count, 1)
        XCTAssertNotEqual(recovered.originalOutcome, SupportEventLocator.projectionAppliedSuccess)
        XCTAssertEqual(source.findByRequestId("req-unknown-1").count, 1)
        XCTAssertTrue(source.findByRequestId("req-other").isEmpty)
    }

    func testInProcessRecoverKeepsOriginalUnknownNotProjectionSuccess() throws {
        let original = OriginalAuditEvent(
            requestId: "req-fail-1", targetType: "ORDER", targetId: 88,
            action: "PAY", afterJson: "FAILED")
        let source = InMemoryOriginalEventSource().add(original)
        let first = SupportEventLocator(originalEvents: source)
        let projection = SupportCurrentProjection(
            requestId: "req-fail-1", appliedState: SupportEventLocator.projectionAppliedSuccess)
        XCTAssertEqual(try first.locateByRequestId("req-fail-1", currentProjection: projection)?.originalOutcome,
                       "FAILED")
        let restarted = SupportEventLocator(originalEvents: source)
        let recovered = try XCTUnwrap(
            restarted.recoverOriginal(originalRequestID: "req-fail-1", currentProjection: projection))
        XCTAssertEqual(recovered.originalOutcome, "FAILED")
        XCTAssertEqual(recovered.requestId, "req-fail-1")
        XCTAssertTrue(recovered.currentProjectionClaimsSuccess)
        XCTAssertTrue(recovered.originalIsNotProjectionSuccess)
        XCTAssertNil(try restarted.locateByRequestId(nil, currentProjection: projection))
        XCTAssertNil(try restarted.locateByRequestId("", currentProjection: projection))
    }

    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueWriteApplies() throws {
        let source = InMemoryOriginalEventSource()
        let locator = SupportEventLocator(originalEvents: source)
        XCTAssertNil(try locator.recoverOriginal(originalRequestID: nil, currentProjection: nil))
        XCTAssertNil(try locator.recoverOriginal(originalRequestID: "  ", currentProjection: nil))
        XCTAssertThrowsError(try locator.recoverOriginal(
            originalRequestID: "c11-never-seen", currentProjection: nil)) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "c11-never-seen"))
        }
        XCTAssertTrue(source.findByRequestId("c11-never-seen").isEmpty)
        source.add(OriginalAuditEvent(
            requestId: "c11-never-seen", targetType: "RUN", targetId: 11,
            action: "SUBMIT", afterJson: "UNKNOWN"))
        let recovered = try XCTUnwrap(
            locator.recoverOriginal(originalRequestID: "c11-never-seen", currentProjection: nil))
        XCTAssertEqual(recovered.requestId, "c11-never-seen")
        XCTAssertEqual(recovered.originalOutcome, "UNKNOWN")
        XCTAssertEqual(source.findByRequestId("c11-never-seen").count, 1)
        XCTAssertNotEqual(recovered.originalOutcome, SupportEventLocator.projectionAppliedSuccess)
    }

    func testMissingOriginalIsNotInferredFromProjection() {
        let locator = SupportEventLocator(originalEvents: InMemoryOriginalEventSource())
        let projection = SupportCurrentProjection(
            requestId: "ghost", appliedState: SupportEventLocator.projectionAppliedSuccess)
        XCTAssertThrowsError(try locator.locateByRequestId("ghost", currentProjection: projection)) { error in
            XCTAssertEqual(error as? SupportLocateFailure, .originalMissing(requestId: "ghost"))
        }
    }
}

final class WrongTargetSource: SupportEventLocator.OriginalEventSource {
    func findByRequestId(_ requestId: String) -> [OriginalAuditEvent] { [] }
    func findByTarget(targetType: String, targetId: Int64) -> OriginalAuditEvent? {
        OriginalAuditEvent(requestId: "req-other", targetType: "ORDER", targetId: 99,
                           action: "PAY", afterJson: "UNKNOWN")
    }
}

final class InMemoryOriginalEventSource: SupportEventLocator.OriginalEventSource {
    private var byRequest: [String: [OriginalAuditEvent]] = [:]
    private var byTarget: [String: OriginalAuditEvent] = [:]

    @discardableResult
    func add(_ event: OriginalAuditEvent) -> InMemoryOriginalEventSource {
        guard let id = event.requestId else { return self }
        byRequest[id, default: []].append(event)
        if let type = event.targetType, let targetId = event.targetId {
            byTarget["\(type):\(targetId)"] = event
        }
        return self
    }

    func findByRequestId(_ requestId: String) -> [OriginalAuditEvent] {
        byRequest[requestId] ?? []
    }

    func findByTarget(targetType: String, targetId: Int64) -> OriginalAuditEvent? {
        byTarget["\(targetType):\(targetId)"]
    }
}

struct FixedFrozenTerms: CompensationEntryProjection.FrozenTermsSource {
    var terms: FrozenCompensationTerms
    func requireFrozenTerms(topicId: Int64) -> FrozenCompensationTerms? {
        terms.topicId == topicId ? terms : nil
    }
}

final class RecordingAuditSource: CompensationEntryProjection.CompensationAuditSource {
    var events: [OriginalAuditEvent]
    var trail: [AuditTrailEntry]
    var reads = 0

    init(events: [OriginalAuditEvent], trail: [AuditTrailEntry]) {
        self.events = events
        self.trail = trail
    }

    func eventsForRequest(_ requestId: String) -> [OriginalAuditEvent] {
        reads += 1
        return events
    }

    func trailForTopic(_ topicId: Int64) -> [AuditTrailEntry] {
        reads += 1
        return trail
    }
}

import XCTest
@testable import Questify

@MainActor private final class SubmissionImportReader: MerchantContentServing {
    var scope = UUID(), isConfigured = true, isAuthenticated = true, permitsWrites = false
    var reads = 0, writes = 0
    var observedAt = Date(timeIntervalSince1970: 1_800_000_000)
    var active = true, merchantID = 7
    var value = try! JSONDecoder().decode(MerchantContentValue.self, from: Data(#"{"perspective":"MERCHANT","sessionId":81,"activityId":80,"revision":3,"status":"RUNNING","availableActions":["VERIFY_SUBMISSION"],"merchant":{"stations":[{"stationId":9,"nodeId":62,"nodeName":"Fixture","revision":2,"status":"ACTIVE","preparationChecklist":[],"pendingVerificationCount":1}]},"memo":"é"}"#.utf8))
    func load(_ query: MerchantContentQuery) async throws -> MerchantContentSnapshot {
        reads += 1
        let access = try JSONDecoder().decode(MerchantAccess.self, from: Data("{\"active\":\(active),\"merchant\":{\"id\":\(merchantID)},\"roleCode\":\"MERCHANT_CHECKIN\",\"permissions\":[]}".utf8))
        return .init(query: query, scope: scope, access: access, value: value, observedAt: observedAt)
    }
    func pending() throws -> [MerchantContentPendingRecord] { [] }
    func perform(_ command: MerchantContentCommand, baseline: MerchantContentSnapshot) async throws -> MerchantContentReceipt { writes += 1; throw MerchantContentFailure.disabled }
    func reconcile(_ record: MerchantContentPendingRecord) async throws -> MerchantContentReceipt { writes += 1; throw MerchantContentFailure.disabled }
    func retryStation(_ record: MerchantContentPendingRecord) async throws -> MerchantContentReceipt { writes += 1; throw MerchantContentFailure.disabled }
}
@MainActor private final class SubmissionImportHarness {
    let reader = SubmissionImportReader()
    lazy var owner = MerchantContentCoordinator(service: reader, query: .game(activityID: 80))
    let model = MerchantStationSubmissionImportModel()
    var draft = MerchantStationSubmissionDraft(text: ["submissionId": "old raw ID ", "reasonCode": "EVIDENCE_UNCLEAR", "note": " e\u{0301} \n"], approve: false)
    var stages = 0, allowStage = true
    func start() async { await owner.load(); model.activate() }
    func context() throws -> MerchantStationSubmissionContext { try XCTUnwrap(.init(snapshot: try XCTUnwrap(owner.snapshot), nodeID: 62)) }
    func open(permit: UInt64? = nil) throws -> MerchantStationSubmissionImportSession? {
        model.open(permit: permit ?? model.generation, owner: owner, context: try context(), original: draft,
            currentDraft: { [unowned self] in draft }) { [unowned self] identifier in
            guard allowStage else { return false }
            if (draft.text["submissionId"] ?? "").utf8.elementsEqual(identifier.utf8) { return true }
            var text = draft.text; text["submissionId"] = identifier
            draft = .init(text: text, approve: draft.approve); stages += 1; return true
        }
        return model.session
    }
    func preview(_ raw: String = "300") throws -> MerchantStationSubmissionImportSession {
        let session = try XCTUnwrap(open()); session.update(raw); session.preview(); return session
    }
}

@MainActor final class MerchantStationSubmissionImportTests: XCTestCase {
    func testOpenAndPreviewAreLocalAndUnverified() async throws {
        let h = SubmissionImportHarness(); await h.start(); let original = h.draft
        let session = try h.preview(#"{"submissionId":"300"}"#)
        XCTAssertEqual(session.code?.submissionID, "300"); XCTAssertEqual(session.raw, "")
        XCTAssertEqual(h.draft, original); XCTAssertEqual(h.reader.reads, 1); XCTAssertEqual(h.reader.writes, 0)
        XCTAssertNil(h.owner.review); XCTAssertNil(h.owner.receipt)
    }
    func testExplicitApplyChangesOnlyIDAndPreservesRawFieldsDecisionAndReason() async throws {
        let h = SubmissionImportHarness(); await h.start(); let original = h.draft
        let session = try h.preview(); XCTAssertTrue(session.apply())
        var expected = original.text; expected["submissionId"] = "300"
        XCTAssertEqual(h.draft, .init(text: expected, approve: original.approve)); XCTAssertEqual(h.stages, 1)
        XCTAssertNil(h.owner.review); XCTAssertEqual(h.reader.reads, 1); XCTAssertEqual(h.reader.writes, 0)
        XCTAssertEqual(session.raw, ""); XCTAssertNil(session.code); XCTAssertFalse(session.isCurrent)
    }
    func testSameIdentifierApplyIsNoOp() async throws {
        let h = SubmissionImportHarness(); h.draft = .init(text: ["submissionId": "300"], approve: true); await h.start()
        let original = h.draft; XCTAssertTrue(try h.preview().apply())
        XCTAssertEqual(h.draft, original); XCTAssertEqual(h.stages, 0)
    }
    func testCancelPreservesBytesAndPerformsNoRead() async throws {
        let h = SubmissionImportHarness(); await h.start(); let original = h.draft
        let session = try XCTUnwrap(h.open()); session.update("?submissionId=301")
        h.model.cancel(id: session.id)
        XCTAssertEqual(h.draft, original); XCTAssertEqual(h.reader.reads, 1); XCTAssertEqual(h.reader.writes, 0)
        XCTAssertEqual(session.raw, ""); XCTAssertNil(session.code); XCTAssertNil(h.model.session)
    }
    func testInvalidAndAmbiguousInputCannotStage() async throws {
        for raw in ["submission-300", #"{"submissionId":300,"submissionId":301}"#, "?submissionId=300&submissionId=301"] {
            let h = SubmissionImportHarness(); await h.start(); let original = h.draft
            let session = try h.preview(raw); XCTAssertNil(session.code); XCTAssertFalse(session.apply())
            XCTAssertEqual(h.draft, original); XCTAssertEqual(h.stages, 0); XCTAssertEqual(h.reader.writes, 0)
        }
    }
    func testOversizedInputClearsRatherThanParsingTruncatedPrefix() async throws {
        let h = SubmissionImportHarness(); await h.start(); let session = try h.preview()
        session.update("300" + String(repeating: " ", count: 4_096))
        XCTAssertEqual(session.raw, ""); XCTAssertNil(session.code); XCTAssertEqual(session.issue, "merchant.submissionImport.oversized")
        XCTAssertFalse(session.apply()); XCTAssertEqual(h.stages, 0)
    }
    func testChangingInputRetiresPriorPreview() async throws {
        let h = SubmissionImportHarness(); await h.start(); let session = try h.preview()
        session.update("301"); XCTAssertNil(session.code); session.preview()
        XCTAssertEqual(session.code?.submissionID, "301"); XCTAssertTrue(session.apply())
        XCTAssertEqual(h.draft.text["submissionId"], "301")
    }
    func testSingleUseSessionCannotStageTwice() async throws {
        let h = SubmissionImportHarness(); await h.start(); let session = try h.preview()
        XCTAssertTrue(session.apply()); XCTAssertFalse(session.apply()); XCTAssertEqual(h.stages, 1)
    }
    func testFailedFinalApplyPreservesOriginalDraft() async throws {
        let h = SubmissionImportHarness(); await h.start(); let original = h.draft
        let session = try h.preview(); h.allowStage = false
        XCTAssertFalse(session.apply()); XCTAssertEqual(h.draft, original); XCTAssertEqual(h.stages, 0)
    }
    func testRawDraftUnicodeOnlyChangeImmediatelyBlocksApply() async throws {
        let h = SubmissionImportHarness(); await h.start(); let session = try h.preview()
        var text = h.draft.text; text["note"] = " é \n"; h.draft = .init(text: text, approve: h.draft.approve)
        XCTAssertFalse(session.apply()); XCTAssertEqual(h.stages, 0); XCTAssertEqual(session.raw, "")
    }
    func testDecisionOrReasonChangeImmediatelyBlocksApply() async throws {
        for changeDecision in [true, false] {
            let h = SubmissionImportHarness(); await h.start(); let session = try h.preview()
            var text = h.draft.text; if !changeDecision { text["reasonCode"] = "ANSWER_MISMATCH" }
            h.draft = .init(text: text, approve: changeDecision ? !h.draft.approve : h.draft.approve)
            XCTAssertFalse(session.apply()); XCTAssertEqual(h.stages, 0)
        }
    }
    func testManualEditABAInvalidationCannotReviveOldSession() async throws {
        let h = SubmissionImportHarness(); await h.start(); let session = try h.preview(); let original = h.draft
        h.model.invalidate(); h.draft = .init(text: [:], approve: true); h.draft = original
        XCTAssertFalse(session.apply()); XCTAssertEqual(h.stages, 0)
    }
    func testBackgroundAndReturnCannotReviveSessionOrRenderedOpenPermit() async throws {
        let h = SubmissionImportHarness(); await h.start(); let permit = h.model.generation
        let session = try h.preview(); h.model.deactivate(); h.model.activate()
        XCTAssertEqual(session.raw, ""); XCTAssertNil(session.code); XCTAssertFalse(session.apply())
        XCTAssertNil(try h.open(permit: permit)); XCTAssertNotNil(try h.open())
    }
    func testDepartureClearsTypedPrivateInput() async throws {
        let h = SubmissionImportHarness(); await h.start(); let session = try XCTUnwrap(h.open())
        session.update(#"{"submissionId":"300"}"#); h.model.deactivate()
        XCTAssertEqual(session.raw, ""); XCTAssertNil(h.model.session); XCTAssertFalse(session.isCurrent)
    }
    func testOldCancelCannotDismissNewSession() async throws {
        let h = SubmissionImportHarness(); await h.start(); let old = try h.preview(); h.model.cancel(id: old.id)
        let newer = try XCTUnwrap(h.open()); h.model.cancel(id: old.id)
        XCTAssertTrue(h.model.session === newer); XCTAssertTrue(newer.isCurrent)
    }
    func testOldPresentationBindingCannotDismissOrExposeReopenedSession() async throws {
        let h = SubmissionImportHarness(); await h.start(); let old = try h.preview()
        let oldBinding = h.model.presentationBinding()
        XCTAssertTrue(oldBinding.wrappedValue === old)
        h.model.cancel(id: old.id); let newer = try XCTUnwrap(h.open())
        XCTAssertNil(oldBinding.wrappedValue)
        oldBinding.wrappedValue = nil
        XCTAssertTrue(h.model.session === newer); XCTAssertTrue(newer.isCurrent)
        let currentBinding = h.model.presentationBinding(); currentBinding.wrappedValue = nil
        XCTAssertNil(h.model.session); XCTAssertFalse(newer.isCurrent)
    }
    func testEmptyPresentationBindingCannotDismissLaterSession() async throws {
        let h = SubmissionImportHarness(); await h.start()
        let emptyBinding = h.model.presentationBinding(); let session = try XCTUnwrap(h.open())
        XCTAssertNil(emptyBinding.wrappedValue); emptyBinding.wrappedValue = nil
        XCTAssertTrue(h.model.session === session); XCTAssertTrue(session.isCurrent)
    }
    func testChangedScopeAuthenticationOrConfigurationBlocksBeforeLifecycleCallback() async throws {
        for change in 0..<3 {
            let h = SubmissionImportHarness(); await h.start(); let session = try h.preview()
            if change == 0 { h.reader.scope = UUID() }
            if change == 1 { h.reader.isAuthenticated = false }
            if change == 2 { h.reader.isConfigured = false }
            XCTAssertFalse(session.apply()); XCTAssertEqual(h.stages, 0); XCTAssertEqual(h.reader.writes, 0)
        }
    }
    func testNewSnapshotObservationRetiresSameValueImport() async throws {
        let h = SubmissionImportHarness(); await h.start(); let session = try h.preview()
        h.reader.observedAt.addTimeInterval(1); await h.owner.load()
        XCTAssertFalse(session.apply()); XCTAssertEqual(h.stages, 0)
    }
    func testExactProjectionBytesRejectCanonicalOnlyChangeWithSameObservation() async throws {
        let h = SubmissionImportHarness(); await h.start(); let original = try XCTUnwrap(h.owner.snapshot)
        let session = try h.preview(); var fields = try XCTUnwrap(h.reader.value.object)
        fields["memo"] = .string("e\u{0301}"); h.reader.value = .object(fields); await h.owner.load()
        XCTAssertEqual(original, h.owner.snapshot); XCTAssertFalse(session.apply()); XCTAssertEqual(h.stages, 0)
    }
    func testExistingDecisionReviewBlocksImportWithoutSending() async throws {
        let h = SubmissionImportHarness(); await h.start(); let session = try h.preview()
        h.owner.prepare(.station(.init(activityID: 80, nodeID: 62, expectedRevision: 3, action: .verify,
            payload: ["submissionId": .string("999"), "decision": .string("APPROVE")])))
        XCTAssertNotNil(h.owner.review); XCTAssertFalse(session.apply()); XCTAssertEqual(h.reader.writes, 0)
    }
    func testWrongNodeAndInactiveAccessCannotFormContext() async throws {
        let h = SubmissionImportHarness(); await h.start(); let snapshot = try XCTUnwrap(h.owner.snapshot)
        XCTAssertNil(MerchantStationSubmissionContext(snapshot: snapshot, nodeID: 63))
        h.reader.active = false; await h.owner.load()
        XCTAssertNil(MerchantStationSubmissionContext(snapshot: try XCTUnwrap(h.owner.snapshot), nodeID: 62))
    }
    func testImportedDecisionStillRequiresExistingExplicitReviewAndWriteGuard() async throws {
        let h = SubmissionImportHarness(); await h.start(); XCTAssertTrue(try h.preview().apply())
        XCTAssertNil(h.owner.review); XCTAssertFalse(h.reader.permitsWrites)
        h.owner.prepare(.station(.init(activityID: 80, nodeID: 62, expectedRevision: 3, action: .verify,
            payload: ["submissionId": .string(h.draft.text["submissionId"]!), "decision": .string("REJECT"), "reasonCode": .string(h.draft.text["reasonCode"]!)])))
        XCTAssertNotNil(h.owner.review); XCTAssertEqual(h.reader.writes, 0)
    }
}

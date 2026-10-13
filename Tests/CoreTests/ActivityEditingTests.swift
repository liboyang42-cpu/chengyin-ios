import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor private final class ActivityEditTestStorage: ProjectEditDataStorage {
    var values: [String: Data] = [:]
    var fail = false
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws { if fail { throw PublishModesError.storage }; values[key] = data }
    func remove(_ key: String) throws { values[key] = nil }
}
@MainActor private final class ActivityEditTestJournal: OperationPendingJournal {
    var value: OperationPendingRecord?
    var fail = false
    var failRead = false
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        if failRead { throw PublishModesError.storage }
        return value.flatMap { $0.ownerKey == ownerKey && $0.targetKey == targetKey ? $0 : nil }
    }
    func write(_ record: OperationPendingRecord) throws {
        if fail { throw PublishModesError.storage }
        guard value == nil || value?.operationID == record.operationID else { throw PublishModesError.uncertain }
        value = record
    }
    func clear(_ record: OperationPendingRecord) throws {
        guard value == record else { throw PublishModesError.storage }; value = nil
    }
}
@MainActor private final class ActivityEditTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var info: [String: ProjectEditJSON] = ["id": .number(41), "memberId": .number(7), "timeLocationLocked": .bool(false),
        "name": .string("Original e\u{301}"), "description": .string("Unsaved-aware content"), "imgUrl": .string("fixture://cover?raw=1"),
        "imgArr": .string("fixture://first;fixture://second"), "categoryIds": .string("3,8"), "addressName": .string("Place"),
        "address": .string("Raw address"), "longitude": .string("121.470000"), "latitude": .string("31.2300"),
        "startDate": .string("2030-01-01 09:00:00"), "endDate": .string("2030-01-01 18:00:00"), "templateId": .number(11),
        "omsTicketList": .array([.object(["id": .number(81), "price": .number(5), "totalInventory": .number(7)])]),
        "futureMetadata": .object(["unicode": .string("保留🚶🏽")])]
    var code = 200
    var status = 200
    var loseWrite = false
    var failRead = false
    var beforeRead: (() async throws -> Void)?
    var onRead: (() -> Void)?
    var onWrite: (() -> Void)?
    var writes: [URLRequest] { requests.filter { $0.url?.path == "/api/activity/update" } }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.path == "/api/activity/info" {
            if let beforeRead { try await beforeRead() }
            onRead?(); if failRead { throw URLError(.networkConnectionLost) }
            return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": .object(info)]), 200)
        }
        onWrite?(); if loseWrite { throw URLError(.networkConnectionLost) }
        return (try JSONEncoder().encode(["code": ProjectEditJSON.number(Decimal(code)), "msg": .string("exact rejection")]), status)
    }
}
@MainActor private final class ActivityEditHarness {
    let configuration = try! APIConfiguration(baseURL: URL(string: "https://activity.example.test")!)
    let session = PublishingSession(namespace: "activity-editor-tests", accountID: 7, epoch: UUID(), role: "club", region: .china)
    var credential: PublishingCredentials?
    let transport = ActivityEditTestTransport()
    let journal = ActivityEditTestJournal()
    let storage = ActivityEditTestStorage()
    var grants = ActivityEditingGrants()
    lazy var store = ActivityEditingDraftStore(storage: storage, journal: journal)
    lazy var service = ActivityEditingService(configuration: configuration, transport: transport, grants: grants,
        drafts: store, credentials: { [weak self] in self?.credential })
    init(approved: Bool = true) throws {
        credential = try PublishingCredentials(session: session, token: "synthetic-activity-token")
        if approved {
            grants = try ActivityEditingGrants(
                read: OperationEndpointApproval(baseURL: configuration.baseURL, namespace: session.namespace, accountID: 7, paths: [ActivityEditingService.readPath]),
                update: OperationEndpointApproval(baseURL: configuration.baseURL, namespace: session.namespace, accountID: 7, paths: [ActivityEditingService.updatePath]))
        }
    }
    func draft() throws -> ActivityEditingDraft {
        var draft = ActivityEditingDraft(source: try ActivityEditingSnapshot(id: 41, value: .object(transport.info), session: session))
        draft.set(.name, "Changed exact e\u{301}"); return draft
    }
}

@MainActor final class ActivityEditingTests: XCTestCase {
    func testDefaultNilGrantsDoNotDispatchAnyReadOrWrite() async throws {
        let h = try ActivityEditHarness(approved: false)
        XCTAssertFalse(h.service.canRead); XCTAssertFalse(h.service.canUpdate)
        do { _ = try await h.service.load(id: 41, session: h.session); XCTFail() } catch {}
        XCTAssertTrue(h.transport.requests.isEmpty)
    }
    func testCreateApprovalCannotAuthorizeExistingEdit() async throws {
        let h = try ActivityEditHarness(approved: false)
        let create = try OperationEndpointApproval(baseURL: h.configuration.baseURL, namespace: h.session.namespace, accountID: 7, paths: ["api/activity/publish"])
        h.grants = .init(read: create, update: create)
        XCTAssertFalse(h.service.canRead); XCTAssertFalse(h.service.canUpdate)
        do { _ = try await h.service.load(id: 41, session: h.session); XCTFail() } catch {}
        XCTAssertTrue(h.transport.requests.isEmpty)
    }
    func testInfoUsesExactFormIDAndUpdateUsesJSONWithNoInventedCASOrReplayWireFields() async throws {
        let h = try ActivityEditHarness(); let draft = try h.draft()
        let review = try await h.service.prepare(draft, session: h.session)
        let outcome = await h.service.submit(review)
        XCTAssertEqual(outcome, .acknowledged); XCTAssertEqual(h.transport.writes.count, 1)
        let read = try XCTUnwrap(h.transport.requests.first)
        XCTAssertEqual(read.httpMethod, "POST"); XCTAssertEqual(read.url?.path, "/api/activity/info")
        XCTAssertTrue(String(data: read.httpBody ?? Data(), encoding: .utf8)?.contains("41") == true)
        let write = try XCTUnwrap(h.transport.writes.first)
        XCTAssertEqual(write.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(write.httpBody))
        XCTAssertEqual(body["id"], .number(41)); XCTAssertEqual(body["name"], .string("Changed exact e\u{301}"))
        for key in ["requestId", "version", "tickets", "collaborators", "futureMetadata", "memberId"] { XCTAssertNil(body[key]) }
        XCTAssertNil(h.journal.value)
    }
    func testAllUneditedContentAndUnknownSourceArePreservedExactly() throws {
        let h = try ActivityEditHarness(); let draft = try h.draft(), body = try draft.body(session: h.session)
        for field in ActivityEditingField.allCases where field != .name { XCTAssertEqual(body[field.rawValue], h.transport.info[field.rawValue]) }
        XCTAssertEqual(draft.source.raw, h.transport.info)
        XCTAssertEqual(body["imgArr"], .string("fixture://first;fixture://second"))
    }
    func testStrictOwnerTargetRoleGateAndLockTypesRejectMalformedSnapshots() throws {
        let h = try ActivityEditHarness()
        for (key, value) in [("id", ProjectEditJSON.number(42)), ("memberId", .number(8)), ("gate", .bool(true)), ("timeLocationLocked", .string("false")), ("timeLocationLocked", .number(0))] {
            var raw = h.transport.info; raw[key] = value
            XCTAssertThrowsError(try ActivityEditingSnapshot(id: 41, value: .object(raw), session: h.session))
        }
        var raw = h.transport.info; raw.removeValue(forKey: "timeLocationLocked")
        XCTAssertThrowsError(try ActivityEditingSnapshot(id: 41, value: .object(raw), session: h.session))
    }
    func testMerchantScopeOnlyForExactOwnedNonHostedActivity() throws {
        let h = try ActivityEditHarness(); let merchant = PublishingSession(namespace: "activity-editor-tests", accountID: 7, epoch: UUID(), role: "merchant", region: .china)
        var draft = ActivityEditingDraft(source: try ActivityEditingSnapshot(id: 41, value: .object(h.transport.info), session: merchant))
        draft.set(.name, "Merchant edit"); XCTAssertEqual(try draft.body(session: merchant)["scope"], .string("MERCHANT"))
        for key in ["clubId", "topicId"] { var raw = h.transport.info; raw[key] = .number(5); XCTAssertThrowsError(try ActivityEditingSnapshot(id: 41, value: .object(raw), session: merchant)) }
    }
    func testSoldLockAllowsTextButRejectsEveryTimeAndPlaceField() throws {
        let h = try ActivityEditHarness(); h.transport.info["timeLocationLocked"] = .bool(true)
        let original = try h.draft(); XCTAssertNoThrow(try original.body(session: h.session))
        for field in ActivityEditingField.allCases where field.timeOrPlace {
            var changed = original; changed.set(field, original.text(field) + " "); XCTAssertThrowsError(try changed.body(session: h.session))
        }
    }
    func testInvalidInputsNeverBecomeAnUpdateBody() throws {
        let h = try ActivityEditHarness()
        for (field, value) in [(ActivityEditingField.name, "  "), (.startDate, "invalid"), (.endDate, "2030-01-01 09:00:00"), (.longitude, "NaN"), (.latitude, "91"), (.categoryIds, "3,3"), (.categoryIds, "3,,8"), (.templateId, "0")] {
            var draft = try h.draft(); draft.set(field, value); XCTAssertThrowsError(try draft.body(session: h.session))
        }
    }
    func testFreshContentConflictKeepsDraftAndSendsNoUpdate() async throws {
        let h = try ActivityEditHarness(); let draft = try h.draft(); h.transport.info["description"] = .string("Changed elsewhere")
        do { _ = try await h.service.prepare(draft, session: h.session); XCTFail() } catch { XCTAssertEqual(error as? PublishModesError, .conflict) }
        XCTAssertTrue(h.transport.writes.isEmpty); XCTAssertEqual(draft.text(.name), "Changed exact e\u{301}")
    }
    func testVolatileBrowseFieldsDoNotInventAContentConflict() async throws {
        let h = try ActivityEditHarness(); let draft = try h.draft(); h.transport.info["commentCount"] = .number(99)
        _ = try await h.service.prepare(draft, session: h.session); XCTAssertTrue(h.transport.writes.isEmpty)
    }
    func testFreshLockOrTicketChangeAfterReviewPreventsDispatch() async throws {
        for key in ["timeLocationLocked", "omsTicketList"] {
            let h = try ActivityEditHarness(); let review = try await h.service.prepare(h.draft(), session: h.session)
            h.transport.info[key] = key == "timeLocationLocked" ? .bool(true) : .array([])
            let result = await h.service.submit(review); XCTAssertEqual(result, .notSent); XCTAssertTrue(h.transport.writes.isEmpty)
        }
    }
    func testCancelledReviewAndDoubleConfirmationCannotSend() async throws {
        let h = try ActivityEditHarness(); let review = try await h.service.prepare(h.draft(), session: h.session)
        h.service.cancel(review); let cancelled = await h.service.submit(review); XCTAssertEqual(cancelled, .notSent)
        let second = try await h.service.prepare(h.draft(), session: h.session)
        let first = await h.service.submit(second), duplicate = await h.service.submit(second)
        XCTAssertEqual(first, .acknowledged); XCTAssertEqual(duplicate, .notSent); XCTAssertEqual(h.transport.writes.count, 1)
    }
    func testCancellationDuringPreflightCannotSend() async throws {
        let h = try ActivityEditHarness(); let review = try await h.service.prepare(h.draft(), session: h.session)
        h.transport.onRead = { h.service.cancel(review) }
        let result = await h.service.submit(review); XCTAssertEqual(result, .notSent); XCTAssertTrue(h.transport.writes.isEmpty)
    }
    func testHiddenOwnerAndAccountChangeDuringReadCannotPrepare() async throws {
        let h = try ActivityEditHarness(); var visible = true
        h.transport.onRead = { visible = false }
        do { _ = try await h.service.prepare(h.draft(), session: h.session, current: { visible }); XCTFail() } catch {}
        XCTAssertTrue(h.transport.writes.isEmpty)
        h.transport.onRead = { h.credential = nil }
        do { _ = try await h.service.load(id: 41, session: h.session); XCTFail() } catch {}
    }
    func testUnknownPersistsOriginalRequestAcrossServiceRecreationAndReadback() async throws {
        let h = try ActivityEditHarness(); h.transport.loseWrite = true
        let review = try await h.service.prepare(h.draft(), session: h.session)
        let result = await h.service.submit(review); XCTAssertEqual(result, .unknown)
        XCTAssertEqual(h.journal.value?.operationID, review.id)
        let saved = try XCTUnwrap(h.store.load(id: 41, session: h.session)); XCTAssertEqual(saved.requestID, review.id); XCTAssertEqual(saved.draft, review.draft)
        let reopened = ActivityEditingService(configuration: h.configuration, transport: h.transport, grants: h.grants, drafts: h.store, credentials: { h.credential })
        h.transport.info["name"] = .string(review.draft.text(.name))
        _ = try await reopened.load(id: 41, session: h.session)
        XCTAssertEqual(try reopened.pending(id: 41, session: h.session)?.operationID, review.id)
        do { _ = try await reopened.prepare(review.draft, session: h.session); XCTFail() } catch {}
        XCTAssertEqual(h.transport.writes.count, 1)
    }
    func testExplicitRejectionPreservesStoredDraftAndAllowsANewReviewedAttempt() async throws {
        let h = try ActivityEditHarness(); h.transport.code = 400
        let review = try await h.service.prepare(h.draft(), session: h.session)
        let result = await h.service.submit(review); XCTAssertEqual(result, .rejected("exact rejection"))
        XCTAssertNil(h.journal.value); XCTAssertEqual(try h.store.load(id: 41, session: h.session)?.draft, review.draft)
        let next = try await h.service.prepare(review.draft, session: h.session); XCTAssertNotEqual(next.id, review.id)
    }
    func testServerFailureAndStaleAcknowledgmentKeepReplayLock() async throws {
        for stale in [false, true] {
            let h = try ActivityEditHarness(); h.transport.code = stale ? 200 : 500
            let review = try await h.service.prepare(h.draft(), session: h.session)
            if stale { h.transport.onWrite = { h.credential = nil } }
            let result = await h.service.submit(review); XCTAssertEqual(result, .unknown); XCTAssertEqual(h.journal.value?.operationID, review.id)
        }
    }
    func testSecureDraftFailureAndJournalFailurePreventWrite() async throws {
        for storage in [true, false] {
            let h = try ActivityEditHarness(); let review = try await h.service.prepare(h.draft(), session: h.session)
            h.storage.fail = storage; h.journal.fail = !storage
            let result = await h.service.submit(review); XCTAssertEqual(result, .notSent); XCTAssertTrue(h.transport.writes.isEmpty)
        }
    }
    func testSavedDraftIsAccountScopedAndRetainsSourceAndRawInput() throws {
        let h = try ActivityEditHarness(); var draft = try h.draft(); draft.set(.description, "  原样\n\u{301}  ")
        try h.store.save(.init(session: h.session, draft: draft), session: h.session)
        XCTAssertEqual(try h.store.load(id: 41, session: h.session)?.draft, draft)
        let other = PublishingSession(namespace: h.session.namespace, accountID: 8, epoch: UUID(), role: "club", region: .china)
        XCTAssertNil(try h.store.load(id: 41, session: other)); XCTAssertNil(try h.store.load(id: 42, session: h.session))
    }
    func testStoredProjectionCannotForgeServerLockOrInventEditableFields() throws {
        let h = try ActivityEditHarness(); h.transport.info["timeLocationLocked"] = .bool(true)
        let original = try h.draft()
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var source = try XCTUnwrap(document["source"] as? [String: Any]); source["timeLocationLocked"] = false; document["source"] = source
        let forged = try JSONDecoder().decode(ActivityEditingDraft.self, from: JSONSerialization.data(withJSONObject: document))
        XCTAssertThrowsError(try forged.body(session: h.session))
        XCTAssertThrowsError(try h.store.save(.init(session: h.session, draft: forged), session: h.session))
        var extra = original; extra.inputs["tickets"] = "[]"
        XCTAssertThrowsError(try extra.body(session: h.session))
        XCTAssertThrowsError(try h.store.save(.init(session: h.session, draft: extra), session: h.session))
    }

    func testExactTypedWireRejectsExtraMultipartFieldsWrongIDAndTicketMutation() throws {
        let h = try ActivityEditHarness()
        let readURL = h.configuration.baseURL.appendingPathComponent(ActivityEditingService.readPath)
        let valid = try AuthRequestBuilder.makeFormRequest(url: readURL, fields: ["id": "41"], token: nil)
        XCTAssertEqual(ActivityEditingWire.path(valid, activityID: 41, configuration: h.configuration), ActivityEditingService.readPath)
        XCTAssertNil(ActivityEditingWire.path(valid, activityID: 42, configuration: h.configuration))
        let extra = try AuthRequestBuilder.makeFormRequest(url: readURL, fields: ["id": "41", "scope": "MERCHANT"], token: nil)
        XCTAssertNil(ActivityEditingWire.path(extra, activityID: 41, configuration: h.configuration))
        var body = try h.draft().body(session: h.session); body["tickets"] = .array([])
        var request = URLRequest(url: h.configuration.baseURL.appendingPathComponent(ActivityEditingService.updatePath))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        XCTAssertNil(ActivityEditingWire.path(request, activityID: 41, configuration: h.configuration))
    }

    func testChangingActivityWindowCannotInvalidateOrGuessExistingTicketWindow() throws {
        let h = try ActivityEditHarness(); var unknown = try h.draft(); unknown.set(.startDate, "2030-01-01 08:00:00")
        XCTAssertThrowsError(try unknown.body(session: h.session))
        h.transport.info["omsTicketList"] = .array([.object(["id": .number(81), "startTime": .string("2030-01-01 10:00:00"), "endTime": .string("2030-01-01 12:00:00")])])
        var valid = try h.draft(); valid.set(.startDate, "2030-01-01 08:00:00")
        XCTAssertNoThrow(try valid.body(session: h.session)); XCTAssertNil(try valid.body(session: h.session)["tickets"])
        valid.set(.endDate, "2030-01-01 11:00:00"); XCTAssertThrowsError(try valid.body(session: h.session))
    }

    func testStorageItselfRejectsAnotherOwnersLocalDraftAndForgedSameRequestPayload() async throws {
        let h = try ActivityEditHarness(); h.transport.loseWrite = true
        let review = try await h.service.prepare(h.draft(), session: h.session)
        let outcome = await h.service.submit(review); XCTAssertEqual(outcome, .unknown)
        let original = h.storage.values; var changed = review.draft; changed.set(.name, "Another editor")
        XCTAssertThrowsError(try h.store.save(.init(session: h.session, draft: changed), session: h.session))
        XCTAssertThrowsError(try h.store.save(.init(session: h.session, draft: changed, requestID: review.id), session: h.session))
        XCTAssertEqual(h.storage.values, original)
        XCTAssertEqual(try h.store.load(id: 41, session: h.session)?.requestID, review.id)
    }
    func testPendingStorageAllowsOnlyByteExactIdempotentPreservation() async throws {
        let h = try ActivityEditHarness(); h.transport.loseWrite = true
        let review = try await h.service.prepare(h.draft(), session: h.session)
        _ = await h.service.submit(review)
        let original = h.storage.values, saved = try XCTUnwrap(h.store.load(id: 41, session: h.session))
        XCTAssertNoThrow(try h.store.save(saved, session: h.session)); XCTAssertEqual(h.storage.values, original)
        XCTAssertEqual(h.journal.value?.operationID, review.id)
    }
    func testStorageJournalReadFailureCannotOverwriteExistingRecoveryBytes() throws {
        let h = try ActivityEditHarness(); let draft = try h.draft()
        try h.store.save(.init(session: h.session, draft: draft), session: h.session)
        let original = h.storage.values; h.journal.failRead = true
        var changed = draft; changed.set(.name, "Cannot save without lock evidence")
        XCTAssertThrowsError(try h.store.save(.init(session: h.session, draft: changed), session: h.session))
        XCTAssertEqual(h.storage.values, original)
    }
    func testOtherServiceUnknownDuringFinalPreflightCannotReplaceOriginalRequestDraft() async throws {
        let h = try ActivityEditHarness(); h.transport.loseWrite = true
        let first = try await h.service.prepare(h.draft(), session: h.session)
        let secondWire = ActivityEditTestTransport()
        let second = ActivityEditingService(configuration: h.configuration, transport: secondWire, grants: h.grants,
            drafts: h.store, credentials: { h.credential })
        var secondDraft = try h.draft(); secondDraft.set(.name, "Second candidate")
        let secondReview = try await second.prepare(secondDraft, session: h.session)
        secondWire.beforeRead = {
            let outcome = await h.service.submit(first); XCTAssertEqual(outcome, .unknown)
        }
        let outcome = await second.submit(secondReview); XCTAssertEqual(outcome, .unknown)
        XCTAssertEqual(h.transport.writes.count, 1); XCTAssertTrue(secondWire.writes.isEmpty)
        let saved = try XCTUnwrap(h.store.load(id: 41, session: h.session))
        XCTAssertEqual(saved.requestID, first.id); XCTAssertEqual(saved.draft, first.draft)
        XCTAssertEqual(h.journal.value?.operationID, first.id)
        let reopened = ActivityEditingService(configuration: h.configuration, transport: secondWire, grants: h.grants,
            drafts: h.store, credentials: { h.credential })
        secondWire.beforeRead = nil; _ = try await reopened.load(id: 41, session: h.session)
        XCTAssertEqual(try reopened.pending(id: 41, session: h.session)?.operationID, first.id)
        XCTAssertEqual(try h.store.load(id: 41, session: h.session)?.draft, first.draft)
    }

}

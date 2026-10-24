import XCTest
import Foundation
import SwiftUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Questify

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

@MainActor final class ActivityEditingOwnerTests: XCTestCase {
    private func owner(_ h: ActivityEditHarness) -> ActivityEditingController {
        let owner = ActivityEditingController(activityID: 41, session: h.session, service: h.service)
        owner.appear(active: true); return owner
    }
    func testNormalLoadEditReviewCancelPreservesEveryUnsavedInput() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load()
        owner.binding(.name).wrappedValue = "Edited name"; owner.binding(.description).wrappedValue = " Exact unsaved body "
        let before = owner.draft; await owner.prepare(); let review = try XCTUnwrap(owner.review)
        XCTAssertEqual(review.draft, before); XCTAssertTrue(h.transport.writes.isEmpty)
        owner.cancel(review); XCTAssertEqual(owner.draft, before); XCTAssertNil(owner.review)
    }
    func testOnlyExplicitConfirmationSendsOneCapturedBodyAndAcknowledgmentLocksEditing() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load()
        owner.binding(.name).wrappedValue = "Explicit save"; await owner.prepare()
        let review = try XCTUnwrap(owner.review); XCTAssertTrue(h.transport.writes.isEmpty)
        await owner.confirm(review); await owner.confirm(review)
        XCTAssertEqual(h.transport.writes.count, 1); XCTAssertEqual(owner.status, "acknowledged"); XCTAssertFalse(owner.editable)
    }
    func testRejectionKeepsCompleteDraftAndNextReviewUsesNewIdentity() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load(); h.transport.code = 400
        owner.binding(.description).wrappedValue = "Rejected draft retained"; let before = owner.draft
        await owner.prepare(); let review = try XCTUnwrap(owner.review); await owner.confirm(review)
        XCTAssertEqual(owner.status, "rejected"); XCTAssertEqual(owner.draft, before); XCTAssertTrue(owner.editable)
        await owner.prepare(); XCTAssertNotEqual(owner.review?.id, review.id)
    }
    func testUnknownReentryRestoresExactRequestAndReadbackCannotUnlockOrOverwrite() async throws {
        let h = try ActivityEditHarness(), first = owner(h); await first.load()
        first.binding(.name).wrappedValue = "Unknown saved input"; await first.prepare(); let review = try XCTUnwrap(first.review)
        h.transport.loseWrite = true; await first.confirm(review); first.disappear()
        let second = owner(h); XCTAssertEqual(second.pending?.operationID, review.id); XCTAssertEqual(second.draft, review.draft)
        h.transport.info["name"] = .string("Unknown saved input"); await second.load()
        second.useReadback(owner: second.ownerID); second.binding(.name).wrappedValue = "Forbidden edit"
        await second.prepare(); await second.confirm(review)
        XCTAssertEqual(second.status, "unknown"); XCTAssertEqual(second.draft, review.draft)
        XCTAssertEqual(second.pending?.operationID, review.id); XCTAssertEqual(h.transport.writes.count, 1)
    }
    func testFailedReadPreservesCurrentDraftAndOldReadbackDoesNotBecomeSave() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load()
        owner.binding(.name).wrappedValue = "Preserve"; let before = owner.draft
        h.transport.failRead = true; await owner.load()
        XCTAssertEqual(owner.draft, before); XCTAssertEqual(owner.status, "unavailable"); XCTAssertTrue(h.transport.writes.isEmpty)
    }
    func testOldBindingCannotReadOrWriteAfterHideAndReopen() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load()
        let old = owner.binding(.name); owner.disappear(); owner.appear(active: true)
        let fresh = owner.binding(.name); fresh.wrappedValue = "Fresh owner"
        XCTAssertEqual(old.wrappedValue, ""); old.wrappedValue = "Old mutation"
        XCTAssertEqual(fresh.wrappedValue, "Fresh owner")
    }
    func testAccountChangeRejectsOldInputReadAndWrite() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load()
        let old = owner.binding(.description), before = owner.draft; h.credential = nil
        XCTAssertEqual(old.wrappedValue, ""); old.wrappedValue = "Wrong account"
        XCTAssertEqual(owner.draft, before); await owner.prepare(); XCTAssertTrue(h.transport.writes.isEmpty)
    }
    func testForegroundWhileHiddenCannotCreateVisibleOwnerOrDispatch() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load()
        let count = h.transport.requests.count; owner.disappear(); owner.setActive(false); owner.setActive(true)
        await owner.load(); await owner.prepare()
        XCTAssertFalse(owner.current); XCTAssertEqual(h.transport.requests.count, count)
    }
    func testBackgroundRetiresReviewAndRepeatAppearDoesNotLoseOrdinaryDraft() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load()
        owner.binding(.name).wrappedValue = "Retain local"; await owner.prepare(); let review = try XCTUnwrap(owner.review)
        owner.setActive(false); owner.setActive(true); owner.appear(active: true); await owner.confirm(review)
        XCTAssertNil(owner.review); XCTAssertEqual(owner.draft?.text(.name), "Retain local"); XCTAssertTrue(h.transport.writes.isEmpty)
    }
    func testSoldLockedBindingsCannotChangeTimeOrPlaceButTextRemainsEditable() async throws {
        let h = try ActivityEditHarness(); h.transport.info["timeLocationLocked"] = .bool(true)
        let owner = owner(h); await owner.load(); let original = try XCTUnwrap(owner.draft)
        for field in ActivityEditingField.allCases where field.timeOrPlace { owner.binding(field).wrappedValue = "Wrong"; XCTAssertEqual(owner.draft?.text(field), original.text(field)) }
        owner.binding(.description).wrappedValue = "Correct typo"; XCTAssertEqual(owner.draft?.text(.description), "Correct typo")
    }
    func testHideDuringLoadDoesNotPublishLateDraftOrStartAnotherRead() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); h.transport.onRead = { owner.disappear() }
        await owner.load(); XCTAssertNil(owner.draft); XCTAssertNil(owner.readback); XCTAssertFalse(owner.busy)
        await owner.load(); XCTAssertEqual(h.transport.requests.count, 1)
    }
    func testHideDuringConfirmPreflightPreventsAnyWrite() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load()
        owner.binding(.name).wrappedValue = "Draft"; await owner.prepare(); let review = try XCTUnwrap(owner.review)
        h.transport.onRead = { owner.disappear() }; await owner.confirm(review)
        XCTAssertTrue(h.transport.writes.isEmpty); XCTAssertNil(h.journal.value)
    }
    func testOldConfirmationCannotConsumeNewReview() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load()
        owner.binding(.name).wrappedValue = "Draft A"; await owner.prepare(); let old = try XCTUnwrap(owner.review)
        owner.cancel(old); owner.binding(.name).wrappedValue = "Draft B"; await owner.prepare(); let fresh = try XCTUnwrap(owner.review)
        owner.cancel(old); await owner.confirm(old); XCTAssertEqual(owner.review?.id, fresh.id); XCTAssertTrue(h.transport.writes.isEmpty)
        await owner.confirm(fresh); XCTAssertEqual(h.transport.writes.count, 1)
    }
    func testReadbackNeverSilentlyDiscardsUnsavedDraftAndOldDiscardCannotTouchNewVisit() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load()
        owner.binding(.name).wrappedValue = "Unsaved"; let before = owner.draft, old = owner.ownerID
        h.transport.info["name"] = .string("Server new"); await owner.load(); XCTAssertEqual(owner.draft, before)
        owner.disappear(); owner.appear(active: true); owner.useReadback(owner: old); XCTAssertEqual(owner.draft, before)
        owner.useReadback(owner: owner.ownerID); XCTAssertEqual(owner.draft?.text(.name), "Server new")
    }
    func testExplicitLocalSaveSurvivesReentryWithoutAnyWriteRequest() async throws {
        let h = try ActivityEditHarness(), first = owner(h); await first.load()
        first.binding(.description).wrappedValue = " Local draft \n"; first.saveLocal(); first.disappear()
        let second = owner(h); XCTAssertEqual(second.draft?.text(.description), " Local draft \n")
        XCTAssertTrue(h.transport.writes.isEmpty)
    }
    func testDefaultOffNormalEditorStillPreservesScopedLocalDraftWithoutRequest() throws {
        let h = try ActivityEditHarness(approved: false); let draft = try h.draft()
        try h.store.save(.init(session: h.session, draft: draft), session: h.session)
        let owner = owner(h); XCTAssertEqual(owner.draft, draft); XCTAssertFalse(owner.readable); XCTAssertFalse(owner.reviewable)
        XCTAssertTrue(h.transport.requests.isEmpty)
    }
    private func deployment() throws -> ReviewedAppDeployment {
        try ReviewedAppDeployment(market: .china, baseURL: "https://activity.example.test",
            approvedBaseURLs: [.china: ["https://activity.example.test"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.activity.edit", realm: "synthetic")
    }
    func testTypedCompositionCompletesReadReviewSaveWithoutOpeningGenericUpdate() async throws {
        let h = try ActivityEditHarness(), deployment = try deployment()
        let session = PublishingSession(namespace: deployment.storageScope.service, accountID: 7, epoch: UUID(), role: "club", region: .china)
        let approval = try OperationEndpointApproval(baseURL: h.configuration.baseURL, namespace: session.namespace, accountID: 7,
            paths: [ActivityEditingService.readPath, ActivityEditingService.updatePath])
        let grants = ActivityEditingGrants(read: approval, update: approval)
        let transport = CompositionHTTPTransport(deployment: deployment, underlying: h.transport)
        transport.current = { .init(epoch: 3, accountID: 7, role: "club", token: "synthetic-activity-token") }
        transport.activityEditingApproval = { _ in grants }
        let credentials = try PublishingCredentials(session: session, token: "synthetic-activity-token")
        let service = ActivityEditingService(configuration: h.configuration, transport: transport, grants: grants,
            drafts: h.store, credentials: { credentials })
        let source = try await service.load(id: 41, session: session)
        var draft = ActivityEditingDraft(source: source); draft.set(.name, "Root update")
        let review = try await service.prepare(draft, session: session); let result = await service.submit(review)
        XCTAssertEqual(result, .acknowledged); XCTAssertEqual(h.transport.writes.count, 1)
        let sent = try XCTUnwrap(h.transport.writes.first)
        do { _ = try await transport.send(sent); XCTFail("Generic update must remain unavailable") } catch {}
        XCTAssertEqual(h.transport.writes.count, 1)
    }
    func testTypedCompositionDefaultSelectorAndRevocationRejectWithoutDispatch() async throws {
        let h = try ActivityEditHarness(), deployment = try deployment()
        let session = PublishingSession(namespace: deployment.storageScope.service, accountID: 7, epoch: UUID(), role: "club", region: .china)
        let approval = try OperationEndpointApproval(baseURL: h.configuration.baseURL, namespace: session.namespace, accountID: 7, paths: [ActivityEditingService.readPath])
        let grants = ActivityEditingGrants(read: approval)
        let transport = CompositionHTTPTransport(deployment: deployment, underlying: h.transport)
        transport.current = { .init(epoch: 3, accountID: 7, role: "club", token: "synthetic-activity-token") }
        let request = try AuthRequestBuilder.makeFormRequest(url: h.configuration.baseURL.appendingPathComponent(ActivityEditingService.readPath), fields: ["id": "41"], token: "synthetic-activity-token")
        do { _ = try await transport.sendActivityEditing(request, activityID: 41, session: session, grants: grants); XCTFail() } catch {}
        XCTAssertTrue(h.transport.requests.isEmpty)
        transport.activityEditingApproval = { _ in grants }
        h.transport.onRead = { transport.activityEditingApproval = { _ in .init() } }
        do { _ = try await transport.sendActivityEditing(request, activityID: 41, session: session, grants: grants); XCTFail() } catch {}
        XCTAssertEqual(h.transport.requests.count, 1)
        do { _ = try await transport.sendActivityEditing(request, activityID: 41, session: session, grants: grants); XCTFail() } catch {}
        XCTAssertEqual(h.transport.requests.count, 1)
    }
    func testTypedCompositionCopiesLiveSelectorAndCannotBorrowNewGrantRevision() async throws {
        let h = try ActivityEditHarness(), deployment = try deployment()
        let session = PublishingSession(namespace: deployment.storageScope.service, accountID: 7, epoch: UUID(), role: "club", region: .china)
        let approval = try OperationEndpointApproval(baseURL: h.configuration.baseURL, namespace: session.namespace, accountID: 7, paths: [ActivityEditingService.readPath])
        let old = ActivityEditingGrants(read: approval), fresh = ActivityEditingGrants(read: approval)
        let transport = CompositionHTTPTransport(deployment: deployment, underlying: h.transport)
        transport.current = { .init(epoch: 3, accountID: 7, role: "club", token: "synthetic-activity-token") }
        transport.activityEditingApproval = { _ in old }
        let copied = transport.replacingUnderlying(h.transport)
        transport.activityEditingApproval = { _ in fresh }
        let request = try AuthRequestBuilder.makeFormRequest(url: h.configuration.baseURL.appendingPathComponent(ActivityEditingService.readPath), fields: ["id": "41"], token: "synthetic-activity-token")
        do { _ = try await copied.sendActivityEditing(request, activityID: 41, session: session, grants: old); XCTFail() } catch {}
        XCTAssertTrue(h.transport.requests.isEmpty)
        _ = try await copied.sendActivityEditing(request, activityID: 41, session: session, grants: fresh)
        XCTAssertEqual(h.transport.requests.count, 1)
    }

    func testUnreadableReplayLockCannotOverwriteOriginalPendingDraftOrAcceptReadback() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load()
        owner.binding(.name).wrappedValue = "Keep exact original"; owner.saveLocal()
        let saved = h.storage.values; await owner.prepare(); let review = try XCTUnwrap(owner.review)
        h.transport.onWrite = { h.journal.failRead = true }; h.transport.loseWrite = true
        await owner.confirm(review); let originalPending = h.storage.values
        XCTAssertEqual(owner.status, "unknown"); XCTAssertFalse(owner.editable)
        owner.binding(.name).wrappedValue = "Wrong overwrite"; owner.saveLocal(); owner.useReadback(owner: owner.ownerID)
        XCTAssertEqual(h.storage.values, originalPending); XCTAssertNotEqual(saved, originalPending)
        let reopened = self.owner(h); XCTAssertFalse(reopened.editable)
        XCTAssertEqual(h.transport.writes.count, 1)
    }

    func testTwoVisibleEditorsStaleLocalSaveCannotReplaceUnknownRequestAndReopenRestoresOriginal() async throws {
        let h = try ActivityEditHarness(), first = owner(h), stale = owner(h)
        await first.load(); await stale.load()
        first.binding(.name).wrappedValue = "Original sent input"
        stale.binding(.name).wrappedValue = "Other unsent local draft"
        let staleDraft = stale.draft; await first.prepare(); let review = try XCTUnwrap(first.review)
        h.transport.loseWrite = true; await first.confirm(review)
        let original = h.storage.values; XCTAssertNil(stale.pending)
        stale.saveLocal()
        XCTAssertEqual(stale.status, "unknown"); XCTAssertEqual(stale.pending?.operationID, review.id)
        XCTAssertEqual(stale.draft, staleDraft); XCTAssertEqual(h.storage.values, original)
        first.disappear(); stale.disappear()
        let reopened = owner(h); XCTAssertEqual(reopened.pending?.operationID, review.id)
        XCTAssertEqual(reopened.draft, review.draft)
        await reopened.load(); XCTAssertEqual(reopened.draft, review.draft)
        XCTAssertEqual(reopened.pending?.operationID, review.id); XCTAssertEqual(h.transport.writes.count, 1)
    }
    func testStaleVisibleEditorWithUnreadableJournalCannotWriteLocalDraft() async throws {
        let h = try ActivityEditHarness(), owner = owner(h); await owner.load()
        owner.binding(.name).wrappedValue = "Preserved before outage"; owner.saveLocal(); let saved = h.storage.values
        owner.binding(.name).wrappedValue = "Only in memory"; h.journal.failRead = true; owner.saveLocal()
        XCTAssertEqual(h.storage.values, saved); XCTAssertEqual(owner.draft?.text(.name), "Only in memory")
        XCTAssertFalse(owner.editable); XCTAssertTrue(h.transport.writes.isEmpty)
    }

}

import XCTest
import Foundation
import SwiftUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Questify

@MainActor private final class ActivityResumeTestStorage: ProjectEditDataStorage {
    var values: [String: Data] = [:]
    var fail = false
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws { if fail { throw PublishModesError.storage }; values[key] = data }
    func remove(_ key: String) throws { values[key] = nil }
}
@MainActor private final class ActivityResumeTestJournal: OperationPendingJournal {
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
@MainActor private final class ActivityResumeTestTransport: HTTPTransport {
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
@MainActor private final class ActivityResumeHarness {
    let configuration = try! APIConfiguration(baseURL: URL(string: "https://activity.example.test")!)
    let session = PublishingSession(namespace: "activity-editor-tests", accountID: 7, epoch: UUID(), role: "club", region: .china)
    var credential: PublishingCredentials?
    let transport = ActivityResumeTestTransport()
    let journal = ActivityResumeTestJournal()
    let storage = ActivityResumeTestStorage()
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

@MainActor final class ActivityEditingForegroundRecoveryTests: XCTestCase {
    private func makeOwner(_ h: ActivityResumeHarness) async -> ActivityEditingController {
        let owner = ActivityEditingController(activityID: 41, session: h.session, service: h.service)
        owner.appear(active: true)
        await owner.load()
        return owner
    }
    func testForegroundDuringDispatchedWriteRestoresOriginalLockBeforeLateAck() async throws {
        let h = try ActivityResumeHarness(), owner = await makeOwner(h)
        owner.binding(.name).wrappedValue = "Original request"
        await owner.prepare()
        let review = try XCTUnwrap(owner.review)
        h.transport.onWrite = {
            owner.setActive(false)
            owner.setActive(true)
            XCTAssertEqual(owner.pending?.operationID, review.id)
            XCTAssertEqual(owner.draft, review.draft)
            XCTAssertEqual(owner.status, "unknown")
            XCTAssertFalse(owner.editable)
            owner.binding(.name).wrappedValue = "Must not replace original"
        }
        await owner.confirm(review)
        XCTAssertEqual(owner.status, "unknown")
        XCTAssertEqual(owner.draft, review.draft)
        XCTAssertEqual(h.journal.value?.operationID, review.id)
        await owner.prepare()
        await owner.confirm(review)
        XCTAssertEqual(h.transport.writes.count, 1)
    }
    func testForegroundBeforeDispatchRetainsDraftWithoutClaimingAcknowledgment() async throws {
        let h = try ActivityResumeHarness(), owner = await makeOwner(h)
        owner.binding(.name).wrappedValue = "Unsent input"
        await owner.prepare()
        let review = try XCTUnwrap(owner.review)
        h.transport.onRead = { owner.setActive(false); owner.setActive(true) }
        await owner.confirm(review)
        XCTAssertEqual(owner.status, "notSent")
        XCTAssertNil(owner.pending)
        XCTAssertEqual(owner.draft, review.draft)
        XCTAssertTrue(owner.editable)
        XCTAssertTrue(h.transport.writes.isEmpty)
    }
    func testUnreadableJournalOnForegroundLocksEditingUntilExplicitRecovery() async throws {
        let h = try ActivityResumeHarness(), owner = await makeOwner(h)
        owner.binding(.name).wrappedValue = "Retain memory"
        let original = owner.draft
        owner.setActive(false)
        h.journal.failRead = true
        owner.setActive(true)
        XCTAssertFalse(owner.editable)
        XCTAssertEqual(owner.status, "unavailable")
        XCTAssertEqual(owner.draft, original)
        owner.saveLocal()
        XCTAssertTrue(h.storage.values.isEmpty)
        h.journal.failRead = false
        await owner.load()
        XCTAssertTrue(owner.editable)
        XCTAssertEqual(owner.draft, original)
        XCTAssertTrue(h.transport.writes.isEmpty)
    }
    func testAccountLossCannotRestoreOrWriteOriginalAccountPending() async throws {
        let h = try ActivityResumeHarness(), owner = await makeOwner(h)
        owner.binding(.name).wrappedValue = "Original account"
        await owner.prepare()
        let review = try XCTUnwrap(owner.review)
        h.transport.onWrite = {
            owner.setActive(false)
            h.credential = nil
            owner.setActive(true)
            XCTAssertFalse(owner.current)
            XCTAssertFalse(owner.editable)
            XCTAssertEqual(owner.binding(.name).wrappedValue, "")
        }
        await owner.confirm(review)
        XCTAssertEqual(h.journal.value?.operationID, review.id)
        await owner.prepare()
        XCTAssertEqual(h.transport.writes.count, 1)
    }
    func testOrdinaryForegroundPreservesUnsavedDraftAndDoesNotReadNetwork() async throws {
        let h = try ActivityResumeHarness(), owner = await makeOwner(h)
        owner.binding(.description).wrappedValue = " Exact unsaved input "
        let original = owner.draft, count = h.transport.requests.count
        owner.setActive(false)
        owner.setActive(true)
        XCTAssertEqual(owner.draft, original)
        XCTAssertTrue(owner.editable)
        XCTAssertEqual(h.transport.requests.count, count)
        owner.disappear()
        owner.setActive(false)
        owner.setActive(true)
        XCTAssertFalse(owner.current)
    }
}

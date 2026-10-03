import XCTest
@testable import QuestifyCore

@MainActor final class ContentDraftJournalSuspensionTests: XCTestCase {
    struct Payload: Codable, Equatable { let title: String }
    private final class Journal: ContentDraftSecureJournal {
        let scope: ContentDraftJournalScope
        var value: ContentDraftPending? { didSet { revision += 1 } }
        private var revision: UInt8 = 0
        private var snapshot: ContentDraftJournalSnapshot? { value.map { .init(value: $0, generation: Data(repeating: revision, count: 32)) } }
        var pause: String?
        var waiting: CheckedContinuation<Void, Never>?
        var reached: (() -> Void)?
        init(_ scope: ContentDraftJournalScope) { self.scope = scope }
        private func suspend(_ operation: String) async {
            if pause == operation {
                await withCheckedContinuation { waiting = $0; reached?() }
            }
        }
        func read() async throws -> ContentDraftJournalSnapshot? { await suspend("read"); return snapshot }
        func insert(_ value: ContentDraftPending) async throws -> ContentDraftJournalSnapshot {
            guard self.value == nil || self.value == value else { throw ContentDraftIssue.storageUnavailable }
            self.value = value; let result = snapshot!; await suspend("insert"); return result
        }
        func replace(_ old: ContentDraftJournalSnapshot, with new: ContentDraftPending) async throws -> ContentDraftJournalSnapshot {
            guard snapshot == old else { throw ContentDraftIssue.storageUnavailable }; value = new; let result = snapshot!; await suspend("replace"); return result
        }
        func clear(matching value: ContentDraftJournalSnapshot) async throws {
            guard snapshot == value else { throw ContentDraftIssue.storageUnavailable }; self.value = nil; await suspend("clear")
        }
        func resume() { pause = nil; let saved = waiting; waiting = nil; saved?.resume() }
    }
    private final class Service: ContentDraftServing {
        var writes = 0
        func restore(id: Int64, identity: ContentDraftIdentity) async throws -> ContentDraftRecord { throw ContentDraftIssue.unavailable }
        func list(type: ContentDraftBusinessType?) async throws -> [ContentDraftRecord] { throw ContentDraftIssue.unavailable }
        func mutate(_ attempt: ContentDraftPreparedDispatch) async throws -> ContentDraftRecord {
            writes += 1
            let payload = attempt.mutation.command.payloadJson!
            let object: [String: Any] = ["id": 19, "ownerMemberId": 7, "businessType": "TOPIC", "clientDraftKey": "synthetic-key",
                "payloadJson": payload, "payloadHash": ContentDraftRecord.hash(payload), "status": "DRAFT", "version": 1, "updatedByDevice": "synthetic-device"]
            return try JSONDecoder().decode(ContentDraftRecord.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }
    private func fixture() throws -> (ContentDraftCoordinator<Payload>, Journal, Service) {
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://fixture.invalid")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "fixture-token"))
        let identity = try ContentDraftIdentity(ownerMemberID: 7, businessType: .topic, clientDraftKey: "synthetic-key")
        let journal = Journal(.init(context: context, identity: identity)), service = Service()
        return (ContentDraftCoordinator(identity: identity, initialPayload: Payload(title: "synthetic"), service: service,
            lease: ContentDraftSessionLease(context: context, current: { context }), journal: journal), journal, service)
    }
    func testLogoutDuringInsertAndReplaceLeavesLockAndZeroHTTP() async throws {
        for operation in ["insert", "replace"] {
            let (model, journal, service) = try fixture()
            await model.initialize(); model.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "synthetic-device")
            journal.pause = operation
            let reached = expectation(description: operation); journal.reached = { reached.fulfill() }
            let task = Task { await model.confirm() }
            await fulfillment(of: [reached], timeout: 2)
            await model.confirm(); XCTAssertEqual(service.writes, 0)
            model.invalidate(); journal.resume(); await task.value
            XCTAssertEqual(service.writes, 0); XCTAssertNotNil(journal.value); XCTAssertEqual(model.phase, .invalidated)
            XCTAssertNil(model.document); XCTAssertNil(model.localPayload)
        }
    }
    func testLogoutDuringInitialReadNeverRestoresUI() async throws {
        let (model, journal, service) = try fixture(); journal.pause = "read"
        let reached = expectation(description: "read"); journal.reached = { reached.fulfill() }
        let task = Task { await model.initialize() }
        await fulfillment(of: [reached], timeout: 2)
        model.invalidate(); journal.resume(); await task.value
        XCTAssertEqual(model.phase, .invalidated); XCTAssertNil(model.localPayload); XCTAssertEqual(service.writes, 0)
    }
    func testLogoutDuringClearNeverRestoresOldReceiptUI() async throws {
        let (model, journal, service) = try fixture()
        await model.initialize(); model.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "synthetic-device")
        journal.pause = "clear"
        let reached = expectation(description: "clear"); journal.reached = { reached.fulfill() }
        let task = Task { await model.confirm() }
        await fulfillment(of: [reached], timeout: 2)
        model.invalidate(); journal.resume(); await task.value
        XCTAssertEqual(service.writes, 1); XCTAssertEqual(model.phase, .invalidated); XCTAssertNil(model.document); XCTAssertNil(model.localPayload)
    }
    func testRetryReadSuspensionBlocksRepeatedTapAndLogout() async throws {
        let (model, journal, service) = try fixture()
        let identity = try ContentDraftIdentity(ownerMemberID: 7, businessType: .topic, clientDraftKey: "synthetic-key")
        journal.value = .init(mutation: try .save(payload: Payload(title: "synthetic"), identity: identity,
            subjectID: nil, deviceID: "synthetic-device", baseline: nil), dispatched: true)
        await model.initialize(); journal.pause = "read"
        let reached = expectation(description: "retry read"); journal.reached = { reached.fulfill() }
        let task = Task { await model.retryExact() }
        await fulfillment(of: [reached], timeout: 2)
        await model.retryExact(); model.invalidate(); journal.resume(); await task.value
        XCTAssertEqual(service.writes, 0); XCTAssertNotNil(journal.value); XCTAssertEqual(model.phase, .invalidated)
    }
}

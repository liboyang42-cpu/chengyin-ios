import XCTest
import SwiftUI
@testable import Questify

private final class RecoveryOwnerTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) { throw URLError(.networkConnectionLost) }
}
@MainActor private final class RecoveryOwnerStorage: ProjectEditDataStorage {
    var values: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws { values[key] = data }
    func remove(_ key: String) throws { values[key] = nil }
}
@MainActor private final class RecoveryOwnerJournal: OperationPendingJournal {
    var value: OperationPendingRecord?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { value?.ownerKey == ownerKey && value?.targetKey == targetKey ? value : nil }
    func write(_ record: OperationPendingRecord) throws { value = record }
    func clear(_ record: OperationPendingRecord) throws { if value == record { value = nil } }
}
@MainActor final class ActivityPublishingRequestRecoveryOwnerTests: XCTestCase {
    private func fixture(terminal: Bool, pending: Bool) throws -> (PublishingSession, PublishingService, PublishingDraftStore, ActivityCreateRequestContract.Submit) {
        let session = PublishingSession(namespace: "owner-recovery-fixture", accountID: 71, epoch: UUID(), role: "club", region: .china)
        let store = PublishingDraftStore(storage: RecoveryOwnerStorage()), journal = RecoveryOwnerJournal()
        let submit = try ActivityCreateRequestContract.Submit(id: UUID(), fields: ["name": .string("Fixture activity")])
        let receipt: ActivityCreateRequestContract.Receipt?
        if terminal {
            let fields: [String: Any] = ["protocolVersion": submit.protocolVersion, "requestId": submit.requestId,
                "payloadSHA256": submit.payloadSHA256, "state": "COMMITTED", "originalResult": ["activityId": 42]]
            receipt = try JSONDecoder().decode(ActivityCreateRequestContract.Receipt.self, from: JSONSerialization.data(withJSONObject: fields))
        } else { receipt = nil }
        try store.saveActivityRequest(.init(ownerKey: session.storageKey, submit: submit, receipt: receipt), session: session, expected: nil)
        if pending { try journal.write(.init(operationID: UUID(uuidString: submit.requestId)!, ownerKey: session.storageKey, targetKey: "publishModes:activity:create")) }
        let credentials = try PublishingCredentials(session: session, token: "synthetic-token")
        let config = try APIConfiguration(baseURL: URL(string: "https://example.test")!)
        let service = PublishingService(configuration: config, transport: RecoveryOwnerTransport(), journal: journal,
            activityRequestStore: store, credentials: { credentials })
        return (session, service, store, submit)
    }
    func testRestoredUnknownLocksNewViewAndEveryReplacementDraft() throws {
        let (session, service, _, _) = try fixture(terminal: false, pending: false)
        let owner = ActivityPublishingSubmissionOwner()
        owner.bind(account: session, draftID: UUID(), draft: .init(), service: service); owner.appeared()
        XCTAssertEqual(owner.outcome, .unknown); XCTAssertNil(owner.begin(allowCovered: false))
        owner.bind(account: session, draftID: UUID(), draft: .init(), service: service)
        XCTAssertEqual(owner.outcome, .unknown); XCTAssertFalse(owner.startAnotherActivity())
    }
    func testCompletedCreateRestoresReceiptAndRequiresExplicitNewActivity() throws {
        let (session, service, store, original) = try fixture(terminal: true, pending: false)
        let owner = ActivityPublishingSubmissionOwner()
        owner.bind(account: session, draftID: UUID(), draft: .init(), service: service); owner.appeared()
        XCTAssertEqual(owner.outcome, .acknowledged); XCTAssertEqual(owner.receipt?.activityID, 42)
        XCTAssertNil(owner.begin(allowCovered: false)); XCTAssertTrue(owner.startAnotherActivity())
        owner.bind(account: session, draftID: UUID(), draft: .init(), service: service)
        XCTAssertNil(owner.outcome); XCTAssertNotNil(owner.begin(allowCovered: false))
        XCTAssertEqual(try store.activityRequest(session: session)?.submit, original)
    }
    func testTerminalReceiptWithRemainingJournalLockCannotStartAnother() throws {
        let (session, service, _, _) = try fixture(terminal: true, pending: true)
        let owner = ActivityPublishingSubmissionOwner()
        owner.bind(account: session, draftID: UUID(), draft: .init(), service: service); owner.appeared()
        XCTAssertEqual(owner.outcome, .unknown); XCTAssertTrue(owner.receipt?.terminal == true)
        XCTAssertFalse(owner.startAnotherActivity()); XCTAssertNil(owner.begin(allowCovered: false))
    }
    func testAccountChangeAndBackgroundRetirePresentationWithoutClearingEvidence() throws {
        let (session, service, store, original) = try fixture(terminal: true, pending: false)
        let owner = ActivityPublishingSubmissionOwner()
        owner.bind(account: session, draftID: UUID(), draft: .init(), service: service); owner.appeared()
        owner.setActive(false); XCTAssertFalse(owner.startAnotherActivity())
        owner.bind(account: nil, draftID: UUID(), draft: .init(), service: nil)
        XCTAssertNil(owner.receipt); XCTAssertNil(owner.outcome)
        XCTAssertEqual(try store.activityRequest(session: session)?.submit, original)
    }
}

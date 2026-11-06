import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent synthetic coverage for the opt-in host. Existing GroupPollTests
/// remains unchanged and continues to specify the nil-sidecar legacy contract.
@MainActor final class GroupPollOptionalRecoveryTests: XCTestCase {
    private let base = URL(string: "https://poll-recovery.example.test/prod-api")!
    private let namespace = "optional-recovery-test"
    private var scope: IMScope { try! .init(identity: .init(accountID: 7, epoch: 1), conversationID: 12) }
    private func sidecar(_ storage: OptionalPollStorage) throws -> GroupPollCreateRecoveryJournal {
        try .init(storage: storage, namespace: namespace, realm: base, accountID: 7, conversationID: 12)
    }
    private func owner(_ client: OptionalPollClient, _ reader: OptionalPollReader, _ journal: OptionalPollJournal,
                       sidecar: GroupPollCreateRecoveryJournal? = nil, reference: GroupPollReference? = nil) throws -> GroupPollCoordinator {
        try .init(scope: scope, reference: reference, client: client, reader: reader, journal: journal,
                  namespace: namespace, realm: base, creationRecovery: sidecar)
    }
    private func unknown(_ owner: GroupPollCoordinator, client: OptionalPollClient) async throws -> GroupPollDraft {
        client.failSend = true
        await owner.reviewCreate(question: "Original", options: ["River", "Park"], deadline: nil)
        await owner.confirm()
        guard case .create(let draft)? = client.mutations.first else { throw APIError.invalidRequest }
        XCTAssertEqual(owner.visiblePhase, .unknown)
        return draft
    }
    func testNilSidecarKeepsLegacyCreationRetryAndMessageReadback() async throws {
        let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal()
        let original = try owner(client, reader, journal)
        let draft = try await unknown(original, client: client)
        XCTAssertTrue(original.canRetryCreation); XCTAssertFalse(original.canRecoverCreationReceipt)
        await original.retryCreationUnchanged()
        XCTAssertEqual(client.mutations, [.create(draft), .create(draft)])
        let reopened = try owner(client, reader, journal)
        XCTAssertEqual(reopened.visiblePhase, .unknown); XCTAssertFalse(reopened.canRetryCreation)
        let detail = try owner(client, reader, journal, reference: GroupPollReference(poll: XCTUnwrap(client.poll)))
        await detail.refresh()
        XCTAssertTrue(journal.records.isEmpty)
        original.resume(); XCTAssertEqual(original.visiblePhase, .idle); XCTAssertTrue(original.canCreate)
    }
    func testSuccessfulOptInConfirmationClearsOnlyItsOriginalLockAndPayload() async throws {
        let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
        let payload = try sidecar(storage), original = try owner(client, reader, journal, sidecar: payload)
        await original.reviewCreate(question: "Original", options: ["River", "Park"], deadline: nil)
        await original.confirm()
        XCTAssertEqual(original.visiblePhase, .acknowledged); XCTAssertEqual(client.mutations.count, 1)
        XCTAssertTrue(journal.records.isEmpty); XCTAssertNil(try payload.restore()); XCTAssertTrue(original.canStartAnother)
    }
    func testSidecarRestoresExactDraftAndRetryBytesWithoutCreatingAnotherKey() async throws {
        let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
        let payload = try sidecar(storage), first = try owner(client, reader, journal, sidecar: payload)
        let draft = try await unknown(first, client: client)
        let bytes = storage.values, locks = journal.records
        let reopened = try owner(client, reader, journal, sidecar: sidecar(storage))
        XCTAssertEqual(reopened.originalCreationDraft, draft); XCTAssertTrue(reopened.canRetryCreation)
        await reopened.retryCreationUnchanged()
        XCTAssertEqual(client.mutations, [.create(draft), .create(draft)])
        XCTAssertEqual(try client.mutations[0].body(), try client.mutations[1].body())
        XCTAssertEqual(storage.values, bytes); XCTAssertEqual(journal.records, locks)
    }
    func testReceiptOnlyGrantRecoversWithoutSENDResultOrCurrentMembershipGrant() async throws {
        let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
        let payload = try sidecar(storage), original = try owner(client, reader, journal, sidecar: payload)
        let draft = try await unknown(original, client: client)
        client.paths = ["api/im/poll/create-receipt"]; reader.isConfigured = false; reader.member = false
        XCTAssertFalse(original.canRead); XCTAssertFalse(original.canRetryCreation); XCTAssertTrue(original.canRecoverCreationReceipt)
        await original.recoverCreationReceipt()
        XCTAssertEqual(original.visiblePhase, .acknowledged); XCTAssertEqual(original.reference?.pollID, 31)
        XCTAssertFalse(original.isMember); XCTAssertFalse(original.canVote); XCTAssertFalse(original.canClose)
        XCTAssertEqual(client.mutations, [.create(draft)]); XCTAssertEqual(client.receiptCalls, 1)
        XCTAssertTrue(journal.records.isEmpty); XCTAssertNil(try payload.restore())
    }
    func testSidecarResultReadDoesNotSettleCreationWithoutOriginalHashReceipt() async throws {
        let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
        let payload = try sidecar(storage), original = try owner(client, reader, journal, sidecar: payload)
        let draft = try await unknown(original, client: client), locks = journal.records
        let detail = try owner(client, reader, journal, sidecar: sidecar(storage), reference: GroupPollReference(poll: XCTUnwrap(client.poll)))
        await detail.refresh()
        XCTAssertFalse(detail.canRecoverCreationReceipt); XCTAssertNil(detail.originalCreationDraft)
        XCTAssertEqual(journal.records, locks); XCTAssertEqual(try payload.restore(), draft)
        original.resume(); XCTAssertEqual(original.visiblePhase, .unknown)
        await original.recoverCreationReceipt(); XCTAssertEqual(original.visiblePhase, .acknowledged)
    }
    func testLegacyKeyOnlyRecoveryNeverInventsDraftOrGrantsRetry() async throws {
        let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
        _ = try await unknown(owner(client, reader, journal), client: client)
        let reopened = try owner(client, reader, journal, sidecar: sidecar(storage))
        XCTAssertNil(reopened.originalCreationDraft); XCTAssertFalse(reopened.canRetryCreation)
        client.paths = ["api/im/poll/create-receipt"]
        await reopened.recoverCreationReceipt()
        XCTAssertEqual(reopened.visiblePhase, .acknowledged); XCTAssertTrue(reopened.recoveredCreationWithoutDraft)
        XCTAssertTrue(journal.records.isEmpty); XCTAssertTrue(storage.values.isEmpty); XCTAssertEqual(client.mutations.count, 1)
    }
    func testNotFoundUnknownAndWrongHashKeepBothOriginalStoresAndNeverSend() async throws {
        for state in [GroupPollOriginalCreateReceipt.State.notFound, .unknown, .applied] {
            let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
            let payload = try sidecar(storage), original = try owner(client, reader, journal, sidecar: payload)
            let draft = try await unknown(original, client: client), locks = journal.records, bytes = storage.values
            client.receiptState = state; client.hashOverride = String(repeating: "0", count: 64)
            await original.recoverCreationReceipt()
            XCTAssertEqual(original.visiblePhase, .unknown); XCTAssertEqual(journal.records, locks); XCTAssertEqual(storage.values, bytes)
            XCTAssertEqual(client.mutations, [.create(draft)]); XCTAssertNil(original.reference)
        }
    }
    func testExpiredStoredDraftRemainsReadableButCannotRetry() throws {
        let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
        let payload = try sidecar(storage)
        let draft = try GroupPollDraft(conversationID: 12, question: "Old", options: ["A", "B"],
                                      deadline: Date(timeIntervalSince1970: 100), now: Date(timeIntervalSince1970: 0))
        try payload.save(draft)
        let ownerKey = [namespace, base.absoluteString, "7"].map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        try journal.write(.init(operationID: XCTUnwrap(UUID(uuidString: draft.clientPollKey)), ownerKey: ownerKey, targetKey: "im.poll.conversation.12.create"))
        let reopened = try owner(client, reader, journal, sidecar: payload)
        XCTAssertEqual(reopened.originalCreationDraft, draft); XCTAssertFalse(reopened.canRetryCreation)
        XCTAssertTrue(reopened.canRecoverCreationReceipt); XCTAssertTrue(client.mutations.isEmpty)
    }
    func testCorruptSidecarFailsClosedAndDoesNotTouchLegacyLock() async throws {
        let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
        let payload = try sidecar(storage), original = try owner(client, reader, journal, sidecar: payload)
        _ = try await unknown(original, client: client); let locks = journal.records
        storage.values[try XCTUnwrap(storage.values.keys.first)] = Data("{}".utf8)
        XCTAssertThrowsError(try owner(client, reader, journal, sidecar: payload))
        XCTAssertEqual(journal.records, locks); XCTAssertEqual(client.mutations.count, 1); XCTAssertEqual(client.receiptCalls, 0)
    }
    func testSynchronousJournalSuspendKeepsUnknownWithoutDispatchForBothModes() async throws {
        for protected in [false, true] {
            let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
            let original = try owner(client, reader, journal, sidecar: protected ? sidecar(storage) : nil)
            await original.reviewCreate(question: "Original", options: ["River", "Park"], deadline: nil)
            journal.afterWrite = { original.suspend() }
            await original.confirm()
            XCTAssertEqual(original.visiblePhase, .unknown); XCTAssertEqual(journal.records.count, 1)
            XCTAssertTrue(client.mutations.isEmpty); XCTAssertTrue(storage.values.isEmpty)
        }
    }
    func testSynchronousSidecarSuspendKeepsExactDraftAndUnknownWithoutDispatch() async throws {
        let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
        let payload = try sidecar(storage), original = try owner(client, reader, journal, sidecar: payload)
        await original.reviewCreate(question: "Original", options: ["River", "Park"], deadline: nil)
        storage.afterWrite = { original.suspend() }
        await original.confirm()
        XCTAssertEqual(original.visiblePhase, .unknown); XCTAssertNotNil(try payload.restore())
        XCTAssertEqual(journal.records.count, 1); XCTAssertTrue(client.mutations.isEmpty)
    }
    func testSourceLossDuringMembershipPreflightCannotWriteOrPersist() async throws {
        let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
        let original = try owner(client, reader, journal, sidecar: sidecar(storage))
        await original.reviewCreate(question: "Original", options: ["River", "Park"], deadline: nil)
        var current = true; reader.beforeRead = { current = false }
        await original.confirm(sourceIsCurrent: { current })
        XCTAssertEqual(original.visiblePhase, .idle); XCTAssertTrue(client.mutations.isEmpty)
        XCTAssertTrue(journal.records.isEmpty); XCTAssertTrue(storage.values.isEmpty)
    }
    func testCancelledReceiptCannotSettleOrReviveAfterReentry() async throws {
        let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
        let payload = try sidecar(storage), original = try owner(client, reader, journal, sidecar: payload)
        _ = try await unknown(original, client: client)
        let receipt = try client.receipt(), locks = journal.records, bytes = storage.values
        let gate = OptionalPollGate<GroupPollOriginalCreateReceipt>(), started = expectation(description: "receipt suspended")
        gate.onStart = { started.fulfill() }; client.receiptOperation = { await gate.wait() }
        let task = Task { await original.recoverCreationReceipt() }
        await fulfillment(of: [started], timeout: 2)
        task.cancel(); original.suspend(); original.resume(); gate.resume(receipt); await task.value
        XCTAssertEqual(original.visiblePhase, .unknown); XCTAssertNil(original.reference)
        XCTAssertEqual(journal.records, locks); XCTAssertEqual(storage.values, bytes); XCTAssertEqual(client.mutations.count, 1)
    }
    func testSourceLossOnReceiptCannotClearEitherStore() async throws {
        let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
        let original = try owner(client, reader, journal, sidecar: sidecar(storage))
        _ = try await unknown(original, client: client)
        let locks = journal.records, bytes = storage.values; var current = true
        client.beforeReceipt = { current = false }
        await original.recoverCreationReceipt(sourceIsCurrent: { current })
        XCTAssertEqual(original.visiblePhase, .unknown); XCTAssertNil(original.reference)
        XCTAssertEqual(journal.records, locks); XCTAssertEqual(storage.values, bytes)
    }
    func testSynchronousRetirementDuringEachSettlementStepNeverPublishesLateSuccess() async throws {
        for retireAtLock in [true, false] {
            let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
            let payload = try sidecar(storage), original = try owner(client, reader, journal, sidecar: payload)
            let draft = try await unknown(original, client: client)
            if retireAtLock { journal.afterClear = { original.suspend() } }
            else { storage.afterRemove = { original.suspend() } }
            await original.recoverCreationReceipt()
            XCTAssertNil(original.reference); XCTAssertNil(original.visiblePoll)
            XCTAssertEqual(client.mutations, [.create(draft)]); XCTAssertTrue(journal.records.isEmpty)
            if retireAtLock {
                XCTAssertEqual(original.visiblePhase, .unknown); XCTAssertEqual(try payload.restore(), draft)
                journal.afterClear = nil
                await original.recoverCreationReceipt()
                XCTAssertEqual(original.visiblePhase, .acknowledged); XCTAssertNil(try payload.restore())
            } else {
                XCTAssertEqual(original.visiblePhase, .idle); XCTAssertNil(try payload.restore())
            }
        }
    }
    func testReviewOnChangeRetirementPreventsMembershipRequest() async throws {
        for protected in [false, true] {
            for withdrawSource in [false, true] {
                let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
                let original = try owner(client, reader, journal, sidecar: protected ? sidecar(storage) : nil)
                var current = true
                original.onChange = {
                    guard original.visiblePhase == .loading else { return }
                    original.onChange = nil
                    if withdrawSource { current = false } else { original.suspend() }
                }
                await original.reviewCreate(question: "Original", options: ["River", "Park"], deadline: nil, sourceIsCurrent: { current })
                XCTAssertEqual(reader.membershipCalls, 0); XCTAssertEqual(client.resultCalls, 0)
                XCTAssertTrue(client.mutations.isEmpty); XCTAssertTrue(journal.records.isEmpty); XCTAssertTrue(storage.values.isEmpty)
                XCTAssertEqual(original.visiblePhase, .idle)
            }
        }
    }
    func testRefreshOnChangeRetirementPreventsResultAndMembershipRequests() async throws {
        for protected in [false, true] {
            for withdrawSource in [false, true] {
                let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
                let draft = try GroupPollDraft(conversationID: 12, question: "Original", options: ["River", "Park"])
                let poll = try JSONDecoder().decode(GroupPoll.self, from: JSONSerialization.data(withJSONObject: optionalPollObject(draft)))
                client.poll = poll
                let detail = try owner(client, reader, journal, sidecar: protected ? sidecar(storage) : nil, reference: GroupPollReference(poll: poll))
                var current = true
                detail.onChange = {
                    guard detail.visiblePhase == .loading else { return }
                    detail.onChange = nil
                    if withdrawSource { current = false } else { detail.suspend() }
                }
                await detail.refresh(sourceIsCurrent: { current })
                XCTAssertEqual(client.resultCalls, 0); XCTAssertEqual(reader.membershipCalls, 0)
                XCTAssertTrue(client.mutations.isEmpty); XCTAssertEqual(detail.visiblePhase, .idle); XCTAssertFalse(detail.isMember)
            }
        }
    }
    func testDispatchOnChangeRetirementPreventsEveryPreflightAndWrite() async throws {
        for protected in [false, true] {
            for creating in [false, true] {
                for withdrawSource in [false, true] {
                    let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
                    let original: GroupPollCoordinator
                    if creating {
                        original = try owner(client, reader, journal, sidecar: protected ? sidecar(storage) : nil)
                        await original.reviewCreate(question: "Original", options: ["River", "Park"], deadline: nil)
                    } else {
                        let draft = try GroupPollDraft(conversationID: 12, question: "Original", options: ["River", "Park"])
                        let poll = try JSONDecoder().decode(GroupPoll.self, from: JSONSerialization.data(withJSONObject: optionalPollObject(draft)))
                        client.poll = poll
                        original = try owner(client, reader, journal, sidecar: protected ? sidecar(storage) : nil, reference: GroupPollReference(poll: poll))
                        await original.refresh(); original.reviewVote(optionID: 51)
                    }
                    client.resultCalls = 0; reader.membershipCalls = 0
                    var current = true
                    original.onChange = {
                        guard original.visiblePhase == .submitting else { return }
                        original.onChange = nil
                        if withdrawSource { current = false } else { original.suspend() }
                    }
                    await original.confirm(sourceIsCurrent: { current })
                    XCTAssertEqual(client.resultCalls, 0); XCTAssertEqual(reader.membershipCalls, 0)
                    XCTAssertTrue(client.mutations.isEmpty); XCTAssertTrue(journal.records.isEmpty); XCTAssertTrue(storage.values.isEmpty)
                    XCTAssertEqual(original.visiblePhase, .idle)
                }
            }
        }
    }
    func testReceiptOnChangeRetirementReadsNothingAndRetainsOriginalStores() async throws {
        for withdrawSource in [false, true] {
            let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
            let original = try owner(client, reader, journal, sidecar: sidecar(storage))
            let draft = try await unknown(original, client: client), locks = journal.records, bytes = storage.values
            reader.membershipCalls = 0
            var current = true
            original.onChange = {
                guard original.visiblePhase == .loading else { return }
                original.onChange = nil
                if withdrawSource { current = false } else { original.suspend() }
            }
            await original.recoverCreationReceipt(sourceIsCurrent: { current })
            XCTAssertEqual(client.receiptCalls, 0); XCTAssertEqual(client.resultCalls, 0); XCTAssertEqual(reader.membershipCalls, 0)
            XCTAssertEqual(client.mutations, [.create(draft)]); XCTAssertEqual(journal.records, locks); XCTAssertEqual(storage.values, bytes)
            XCTAssertEqual(original.visiblePhase, .unknown); XCTAssertNil(original.reference)
        }
    }
    func testRefreshLockClearRetirementDoesNotReadMembershipAfterCallback() async throws {
        for protected in [false, true] {
            for withdrawSource in [false, true] {
                let client = OptionalPollClient(), reader = OptionalPollReader(), journal = OptionalPollJournal(), storage = OptionalPollStorage()
                // A real legacy key-only lock may still be reconciled by its matching result.
                // The empty optional sidecar must preserve that exact compatibility rule.
                let draft = try await unknown(owner(client, reader, journal), client: client)
                let detail = try owner(client, reader, journal, sidecar: protected ? sidecar(storage) : nil,
                                       reference: GroupPollReference(poll: XCTUnwrap(client.poll)))
                client.resultCalls = 0; reader.membershipCalls = 0
                var current = true
                journal.afterClear = {
                    journal.afterClear = nil
                    if withdrawSource { current = false } else { detail.suspend() }
                }
                await detail.refresh(sourceIsCurrent: { current })
                XCTAssertEqual(client.resultCalls, 1); XCTAssertEqual(reader.membershipCalls, 0)
                XCTAssertEqual(client.mutations, [.create(draft)]); XCTAssertTrue(journal.records.isEmpty)
                XCTAssertEqual(detail.visiblePhase, .idle); XCTAssertFalse(detail.isMember)
            }
        }
    }
    func testIndependentReceiptRouteUsesExactGETAndDefaultOff() async throws {
        let transport = OptionalPollTransport(), draft = try GroupPollDraft(conversationID: 12, question: "Original", options: ["River", "Park"])
        let object: [String: Any] = ["source": "original-poll-create-v1", "state": "APPLIED", "conversation_id": "12",
            "creator_member_id": "7", "client_poll_key": draft.clientPollKey, "poll_id": "31", "message_id": "44",
            "request_hash": GroupPollCreateRecoveryJournal.originalRequestHash(draft), "poll": optionalPollObject(draft)]
        transport.bytes = try JSONSerialization.data(withJSONObject: ["code": 200, "data": object])
        let disabled = GroupPollService(configuration: try .init(baseURL: base), transport: transport)
        do { _ = try await disabled.creationReceipt(scope: scope, clientPollKey: draft.clientPollKey, token: "fixture-token"); XCTFail("No implicit grant") } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
        let service = GroupPollService(configuration: try .init(baseURL: base), transport: transport, enabledPaths: ["api/im/poll/create-receipt"])
        let result = try await service.creationReceipt(scope: scope, clientPollKey: draft.clientPollKey, token: "fixture-token")
        XCTAssertEqual(result.state, .applied); XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first), parts = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(parts.path, "/prod-api/api/im/poll/create-receipt")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") }), ["conversation_id": "12", "client_poll_key": draft.clientPollKey])
        XCTAssertNil(request.httpBody); XCTAssertFalse(request.httpShouldHandleCookies)
    }
    func testTypeNineRequiresExactServerOriginAndOriginalTypeFourIdentity() throws {
        func message(sender: Int = 0, type: Int = 9, source: String = "original-poll-result-v1", original: Int = 44) throws -> MessagingMessage {
            let extra = try JSONSerialization.data(withJSONObject: ["source": source, "pollId": 31, "originalMessageId": original, "creatorMemberId": 7])
            return try JSONDecoder().decode(MessagingMessage.self, from: JSONSerialization.data(withJSONObject: ["id": 99, "conversationId": 12,
                "senderId": sender, "status": 0, "msgType": type, "extraJson": String(decoding: extra, as: UTF8.self)]))
        }
        let reference = try XCTUnwrap(message().pollReference)
        XCTAssertEqual(reference.pollID, 31); XCTAssertEqual(reference.messageID, 44); XCTAssertEqual(reference.creatorID, 7)
        XCTAssertNil(try message(type: 3).pollReference)
        XCTAssertNil(try message(sender: 7).pollReference); XCTAssertNil(try message(source: "other").pollReference)
        XCTAssertNil(try message(original: 99).pollReference); XCTAssertNil(try message(original: 0).pollReference)
        for key in ["hangout_81", "hangout_081"] {
            let row = try JSONDecoder().decode(MessagingConversation.self, from: JSONSerialization.data(withJSONObject: ["conversationId": 12, "type": 4, "counterparty": ["bizKey": key]]))
            XCTAssertFalse(row.supportsGroupPolls)
        }
    }
}

private func optionalPollObject(_ draft: GroupPollDraft) -> [String: Any] {
    var row: [String: Any] = ["id": 31, "conversationId": 12, "creatorMemberId": 7, "messageId": 44,
        "clientPollKey": draft.clientPollKey, "question": draft.question, "selectionMode": "SINGLE", "visibility": "PUBLIC", "status": "OPEN", "version": 1,
        "totalVoters": 0, "options": draft.options.enumerated().map { i, text in ["id": 51+i, "pollId": 31, "position": i+1, "content": text, "voteCount": 0] as [String: Any] }]
    if let deadline = draft.deadlineAt { row["deadlineAt"] = deadline }
    return row
}
@MainActor private final class OptionalPollStorage: ProjectEditDataStorage {
    var values: [String: Data] = [:]
    var afterWrite: (() -> Void)?
    var afterRemove: (() -> Void)?
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ value: Data, key: String) throws { values[key] = value; afterWrite?() }
    func remove(_ key: String) throws { values[key] = nil; afterRemove?() }
}
@MainActor private final class OptionalPollJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]
    var afterWrite: (() -> Void)?
    var afterClear: (() -> Void)?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records[ownerKey+targetKey] }
    func write(_ record: OperationPendingRecord) throws { records[record.ownerKey+record.targetKey] = record; afterWrite?() }
    func clear(_ record: OperationPendingRecord) throws { records[record.ownerKey+record.targetKey] = nil; afterClear?() }
}
@MainActor private final class OptionalPollReader: MessagingReading {
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    var isConfigured = true, member = true
    var membershipCalls = 0
    var beforeRead: (() -> Void)?
    func messagingConversations() async throws -> [MessagingConversation] {
        membershipCalls += 1; beforeRead?()
        if !member { return [] }
        return [try JSONDecoder().decode(MessagingConversation.self, from: Data(#"{"conversationId":12,"type":4,"counterparty":{"bizKey":"club_81"}}"#.utf8))]
    }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage { throw APIError.notConfigured }
}
@MainActor private final class OptionalPollClient: GroupPollServing {
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    var paths: Set<String> = ["api/im/poll/create", "api/im/poll/result", "api/im/poll/vote", "api/im/poll/close", "api/im/poll/create-receipt"]
    var failSend = false
    var mutations: [GroupPollMutation] = []
    var poll: GroupPoll?
    var draft: GroupPollDraft?
    var receiptCalls = 0
    var resultCalls = 0
    var receiptState: GroupPollOriginalCreateReceipt.State = .applied
    var hashOverride: String?
    var beforeReceipt: (() -> Void)?
    var receiptOperation: (() async -> GroupPollOriginalCreateReceipt)?
    func permits(_ path: String) -> Bool { paths.contains(path) }
    func result(_ reference: GroupPollReference, expectedIdentity: MessagingReadIdentity) async throws -> GroupPoll { resultCalls += 1; return try XCTUnwrap(poll) }
    func perform(_ mutation: GroupPollMutation, scope: IMScope, reference: GroupPollReference?) async throws -> GroupPoll {
        mutations.append(mutation)
        guard case .create(let original) = mutation else { throw APIError.invalidRequest }
        draft = original; poll = try JSONDecoder().decode(GroupPoll.self, from: JSONSerialization.data(withJSONObject: optionalPollObject(original)))
        if failSend { throw URLError(.timedOut) }
        return try XCTUnwrap(poll)
    }
    func receipt() throws -> GroupPollOriginalCreateReceipt {
        if receiptState != .applied { return .init(state: receiptState, poll: nil, requestHash: nil) }
        let hash: String
        if let hashOverride { hash = hashOverride }
        else { hash = GroupPollCreateRecoveryJournal.originalRequestHash(try XCTUnwrap(draft)) }
        return .init(state: .applied, poll: try XCTUnwrap(poll), requestHash: hash)
    }
    func creationReceipt(scope: IMScope, clientPollKey: String) async throws -> GroupPollOriginalCreateReceipt {
        receiptCalls += 1; beforeReceipt?()
        if let receiptOperation { return await receiptOperation() }
        return try receipt()
    }
}
@MainActor private final class OptionalPollGate<Value> {
    var onStart: (() -> Void)?
    private var continuation: CheckedContinuation<Value, Never>?
    func wait() async -> Value { await withCheckedContinuation { continuation = $0; onStart?() } }
    func resume(_ value: Value) { let saved = continuation; continuation = nil; saved?.resume(returning: value) }
}
private final class OptionalPollTransport: HTTPTransport {
    var bytes = Data()
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (bytes, 200) }
}

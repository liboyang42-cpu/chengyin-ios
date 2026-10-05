import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func pollData(_ overrides: [String: Any] = [:]) throws -> Data {
    var row: [String: Any] = ["id": 31, "conversationId": 12, "creatorMemberId": 7,
        "clientPollKey": "source-key", "question": "Which route?", "selectionMode": "SINGLE", "visibility": "PUBLIC", "status": "OPEN", "version": 1, "messageId": 44,
        "options": [["id": 51, "pollId": 31, "position": 1, "content": "River", "voteCount": 0], ["id": 52, "pollId": 31, "position": 2, "content": "Park", "voteCount": 0]], "totalVoters": 0]
    row.merge(overrides) { _, new in new }; return try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
}
private func poll(_ overrides: [String: Any] = [:]) throws -> GroupPoll { try JSONDecoder().decode(GroupPoll.self, from: pollData(overrides)) }
private func pollMessage() throws -> MessagingMessage {
    try JSONDecoder().decode(MessagingMessage.self, from: Data(#"{"id":44,"conversationId":12,"senderId":7,"status":0,"msgType":4,"content":"[投票]","extraJson":"{\"pollId\":31}"}"#.utf8))
}
private final class PollTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var data = Data(); var status = 200
    var beforeReturn: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); beforeReturn?(); return (data, status) }
    func receipt(_ overrides: [String: Any] = [:]) throws { data = Data("{\"code\":200,\"data\":".utf8) + (try pollData(overrides)) + Data("}".utf8) }
}
@MainActor private final class PollClient: GroupPollServing {
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    var enabled = true
    var current: GroupPoll = try! poll()
    var mutations: [GroupPollMutation] = []
    var resultCalls = 0
    var failure: Error?
    var beforeResult: (() -> Void)?
    var beforeMutation: (() -> Void)?
    func permits(_ path: String) -> Bool { enabled }
    func result(_ reference: GroupPollReference, expectedIdentity: MessagingReadIdentity) async throws -> GroupPoll { resultCalls += 1; beforeResult?(); return current }
    func perform(_ mutation: GroupPollMutation, scope: IMScope, reference: GroupPollReference?) async throws -> GroupPoll {
        mutations.append(mutation); beforeMutation?(); if let failure { throw failure }
        switch mutation {
        case .create(let draft): current = try poll(["clientPollKey": draft.clientPollKey, "question": draft.question, "totalVoters": NSNull()])
        case .vote(_, let option):
            current = try poll(["myOptionId": option, "totalVoters": 1, "options": [["id": 51, "pollId": 31, "position": 1, "content": "River", "voteCount": option == 51 ? 1 : 0], ["id": 52, "pollId": 31, "position": 2, "content": "Park", "voteCount": option == 52 ? 1 : 0]]])
        case .close: current = try poll(["status": "CLOSED", "version": 2])
        }
        return current
    }
}
@MainActor private final class PollReader: MessagingReading, ClubReading {
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    var isConfigured = true
    var member = true
    var groupKey = "club_81"
    var beforeRead: (() -> Void)?
    var isClubConfigured: Bool { isConfigured }
    var clubIdentity: ClubReadIdentity { .init(accountID: identity?.accountID, epoch: identity?.epoch ?? 0) }
    func messagingConversations() async throws -> [MessagingConversation] {
        beforeRead?(); guard member else { return [] }
        return [try JSONDecoder().decode(MessagingConversation.self, from: JSONSerialization.data(withJSONObject: ["conversationId": 12, "type": 4, "counterparty": ["bizKey": groupKey]]))]
    }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage { throw APIError.notConfigured }
    func clubDetail(id: Int) async throws -> ClubRecord { beforeRead?(); return try JSONDecoder().decode(ClubRecord.self, from: JSONSerialization.data(withJSONObject: ["id": id, "isJoined": member])) }
    func clubHome() async throws -> ClubHome { throw APIError.notConfigured }
    func clubOwned() async throws -> [ClubRecord] { [] }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { [] }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw APIError.notConfigured }
}
@MainActor private final class PollJournal: OperationPendingJournal {
    var values: [String: OperationPendingRecord] = [:]
    var fails = false
    var afterWrite: (() -> Void)?
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { if fails { throw APIError.malformedResponse }; return values[ownerKey + targetKey] }
    func write(_ record: OperationPendingRecord) throws { if fails { throw APIError.malformedResponse }; values[record.ownerKey + record.targetKey] = record; afterWrite?() }
    func clear(_ record: OperationPendingRecord) throws { if fails { throw APIError.malformedResponse }; values.removeValue(forKey: record.ownerKey + record.targetKey) }
}
final class GroupPollTests: XCTestCase {
    private let base = URL(string: "https://poll.example.test/prod-api")!
    private func service(_ transport: PollTransport, enabled: Set<String> = ["api/im/poll/create", "api/im/poll/vote", "api/im/poll/close", "api/im/poll/result"]) throws -> GroupPollService {
        try .init(configuration: APIConfiguration(baseURL: base), transport: transport, enabledPaths: enabled)
    }
    @MainActor private func owner(_ client: PollClient, _ reader: PollReader, _ journal: PollJournal, creation: Bool = false) throws -> GroupPollCoordinator {
        try .init(scope: IMScope(identity: client.identity!, conversationID: 12), reference: creation ? nil : XCTUnwrap(pollMessage().pollReference), client: client, reader: reader, journal: journal, namespace: "CN-tests", realm: base)
    }
    func testTypeFourCardUsesDistinctIdentifiersAndRejectsUntrustedKinds() throws {
        let reference = try XCTUnwrap(pollMessage().pollReference)
        XCTAssertEqual(reference.pollID, 31); XCTAssertEqual(reference.conversationID, 12); XCTAssertEqual(reference.messageID, 44)
        for extra in ["{}", "{\"pollId\":true}", "{\"pollId\":0}", "{\"pollId\":\"31\"}"] {
            let data = try JSONSerialization.data(withJSONObject: ["id": 44, "conversationId": 12, "senderId": 7, "status":0,"msgType": 4, "extraJson": extra])
            XCTAssertNil(try JSONDecoder().decode(MessagingMessage.self, from: data).pollReference)
        }
    }
    func testDraftUsesBackendUTF16LimitsAndStableMillisecondDeadline() throws {
        XCTAssertThrowsError(try GroupPollDraft(conversationID: 12, question: String(repeating: "😀", count: 101), options: ["a", "b"]))
        XCTAssertThrowsError(try GroupPollDraft(conversationID: 12, question: "Q", options: ["a"]))
        XCTAssertThrowsError(try GroupPollDraft(conversationID: 12, question: "Q", options: ["a", " "]))
        XCTAssertThrowsError(try GroupPollDraft(conversationID: 12, question: "Q", options: ["a", "b"], deadline: .distantPast))
        let draft = try GroupPollDraft(conversationID: 12, question: " Q ", options: [" a ", "b"], deadline: Date(timeIntervalSince1970: 2000000000), clientPollKey: "stable")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["conversationId", "clientPollKey", "question", "options", "deadlineAt"])
        XCTAssertEqual(json["deadlineAt"] as? Int64, 2000000000000); XCTAssertEqual(draft.question, "Q")
    }
    func testResultRejectsCountsForeignIDsAndUnsupportedModes() throws {
        let invalid: [[String: Any]] = [["totalVoters": 4], ["conversationId": 99], ["messageId": 99], ["creatorMemberId": 99], ["selectionMode": "MULTIPLE"], ["visibility": "ANONYMOUS"], ["myOptionId": 77], ["version": 0]]
        for fields in invalid {
            XCTAssertThrowsError(try poll(fields).validate(reference: XCTUnwrap(pollMessage().pollReference), conversationID: 12, results: true))
        }
        let created = try poll(["totalVoters": NSNull()]); XCTAssertFalse(created.hasResults)
        XCTAssertNoThrow(try created.validate(conversationID: 12, results: false)); XCTAssertThrowsError(try created.validate(conversationID: 12, results: true))
    }
    func testDateDecodesExplicitOffsetAndEpochMillisWithoutLocalTimezoneGuess() throws {
        let numeric = try poll(["deadlineAt": 2000000000000]).deadlineAt
        let iso = try poll(["deadlineAt": "2033-05-18T11:33:20.000+08:00"]).deadlineAt
        XCTAssertEqual(numeric, iso)
        XCTAssertThrowsError(try poll(["deadlineAt": "2033-05-18 11:33:20"]))
    }
    func testResultIsFormPollIDAndCreateVoteCloseAreExactJSON() async throws {
        let transport = PollTransport(); try transport.receipt()
        let api = try service(transport), reference = try XCTUnwrap(pollMessage().pollReference)
        _ = try await api.result(reference, token: "test-token")
        let resultRequest = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(resultRequest.url?.path, "/prod-api/api/im/poll/result")
        XCTAssertEqual(resultRequest.httpMethod, "POST")
        XCTAssertEqual(resultRequest.value(forHTTPHeaderField: "Authorization"), "test-token")
        let contentType = try XCTUnwrap(resultRequest.value(forHTTPHeaderField: "Content-Type"))
        let prefix = "multipart/form-data; boundary="
        XCTAssertTrue(contentType.hasPrefix(prefix))
        let boundary = String(contentType.dropFirst(prefix.count)); XCTAssertFalse(boundary.isEmpty)
        let body = try XCTUnwrap(String(data: try XCTUnwrap(resultRequest.httpBody), encoding: .utf8))
        // The shared source-backed FormData builder is multipart, with one exact poll ID field.
        XCTAssertEqual(body, "--\(boundary)\r\nContent-Disposition: form-data; name=\"poll_id\"\r\n\r\n31\r\n--\(boundary)--\r\n")
        XCTAssertFalse(resultRequest.httpShouldHandleCookies)
        let scope = try IMScope(identity: .init(accountID: 7, epoch: 1), conversationID: 12)
        try transport.receipt(["status": "CLOSED", "version": 2])
        _ = try await api.perform(.close(pollID: 31, expectedVersion: 1), scope: scope, reference: reference, token: "test-token")
        let close = transport.requests[1]
        XCTAssertEqual(close.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: close.httpBody!) as? [String: Int], ["pollId": 31, "expectedVersion": 1])
        let vote = try GroupPollMutation.vote(pollID: 31, optionID: 52).body()
        XCTAssertEqual(try JSONSerialization.jsonObject(with: vote) as? [String: Int], ["pollId": 31, "optionId": 52])
    }
    func testNoGrantNoRequestsAndCreateGrantCannotReadOrVote() async throws {
        let transport = PollTransport(), reference = try XCTUnwrap(pollMessage().pollReference)
        let grants: [Set<String>] = [[], ["api/im/poll/create"]]
        for paths in grants {
            do { _ = try await service(transport, enabled: paths).result(reference, token: "test"); XCTFail() } catch {}
        }
        XCTAssertTrue(transport.requests.isEmpty)
        let route = try BusinessRuntimeRoute.post("api/im/poll/vote")
        XCTAssertTrue(BusinessRuntimeFeature.imPollVote.accepts(route)); XCTAssertFalse(BusinessRuntimeFeature.imPollCreate.accepts(route)); XCTAssertFalse(BusinessRuntimeFeature.imSend.accepts(route))
    }
    func testHTTPRedirectAndWrongConversationNeverAcknowledge() async throws {
        let transport = PollTransport(), ref = try XCTUnwrap(pollMessage().pollReference)
        try transport.receipt(); transport.status = 302
        do { _ = try await service(transport).result(ref, token: "test"); XCTFail() } catch {}
        transport.status = 200; try transport.receipt(["conversationId": 77])
        do { _ = try await service(transport).result(ref, token: "test"); XCTFail() } catch {}
    }
    func testCreateWireReceiptAndStableKeyValidation() async throws {
        let transport = PollTransport(), api = try service(transport)
        let draft = try GroupPollDraft(conversationID: 12, question: "Which route?", options: ["River", "Park"], clientPollKey: "stable-source-key")
        let scope = try IMScope(identity: .init(accountID: 7, epoch: 1), conversationID: 12)
        try transport.receipt(["clientPollKey": draft.clientPollKey, "totalVoters": NSNull()])
        let receipt = try await api.perform(.create(draft), scope: scope, reference: nil, token: "test")
        XCTAssertFalse(receipt.hasResults)
        XCTAssertEqual(transport.requests[0].url?.path, "/prod-api/api/im/poll/create")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["conversationId", "clientPollKey", "question", "options"])
        XCTAssertEqual(body["clientPollKey"] as? String, draft.clientPollKey)
        try transport.receipt(["clientPollKey": "wrong", "totalVoters": NSNull()])
        do { _ = try await api.perform(.create(draft), scope: scope, reference: nil, token: "test"); XCTFail() } catch {}
    }
    func testDuplicateVoteConflictIsNotSuccessAndVoteCannotUseForeignPoll() async throws {
        let transport = PollTransport(), api = try service(transport), reference = try XCTUnwrap(pollMessage().pollReference)
        let scope = try IMScope(identity: .init(accountID: 7, epoch: 1), conversationID: 12)
        transport.data = Data(#"{"code":409,"msg":"already voted"}"#.utf8)
        do { _ = try await api.perform(.vote(pollID: 31, optionID: 51), scope: scope, reference: reference, token: "test"); XCTFail() }
        catch { XCTAssertEqual((error as? MessagingReadFailure)?.code, 409) }
        XCTAssertEqual(transport.requests.count, 1)
        do { _ = try await api.perform(.vote(pollID: 99, optionID: 51), scope: scope, reference: reference, token: "test"); XCTFail() } catch {}
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testResultRejectsDuplicateOptionsAndOverflowTotals() throws {
        let duplicate: [[String: Any]] = [["id":51,"pollId":31,"position":1,"content":"A","voteCount":0],["id":51,"pollId":31,"position":2,"content":"B","voteCount":0]]
        XCTAssertThrowsError(try poll(["options": duplicate]).validate(conversationID: 12, results: true))
        let overflow: [[String: Any]] = [["id":51,"pollId":31,"position":1,"content":"A","voteCount":Int.max],["id":52,"pollId":31,"position":2,"content":"B","voteCount":1]]
        XCTAssertThrowsError(try poll(["options": overflow, "totalVoters": Int.max]).validate(conversationID: 12, results: true))
    }
    @MainActor func testSessionRejectsOldSuccessAndDoesNotExpireNewLogin() async throws {
        let transport = PollTransport(); try transport.receipt()
        var session: GroupPollSession? = try .init(accountID: 7, epoch: 1, token: "test")
        var expired = 0
        let client = GroupPollSessionClient(service: try service(transport), session: { session }, onUnauthorized: { _ in expired += 1 })
        transport.beforeReturn = { session = try? .init(accountID: 7, epoch: 2, token: "new") }
        do { _ = try await client.result(XCTUnwrap(pollMessage().pollReference), expectedIdentity: .init(accountID: 7, epoch: 1)); XCTFail() } catch {}
        XCTAssertEqual(expired, 0)
    }
    @MainActor func testVoteRequiresExplicitReviewConfirmationAndCannotVoteTwice() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(), owner = try owner(client, reader, journal)
        await owner.refresh(); XCTAssertTrue(owner.canVote); XCTAssertTrue(client.mutations.isEmpty)
        owner.reviewVote(optionID: 51); owner.cancelReview(); XCTAssertTrue(client.mutations.isEmpty)
        owner.reviewVote(optionID: 51); await owner.confirm()
        XCTAssertEqual(client.mutations, [.vote(pollID: 31, optionID: 51)])
        XCTAssertEqual(owner.visiblePoll?.myOptionId, 51); XCTAssertFalse(owner.canVote); XCTAssertTrue(journal.values.isEmpty)
        owner.reviewVote(optionID: 52); await owner.confirm(); XCTAssertEqual(client.mutations.count, 1)
    }
    @MainActor func testUnknownVoteLocksAcrossOwnerRecreationAndOpenReadCannotClearIt() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(), first = try owner(client, reader, journal)
        await first.refresh(); client.failure = URLError(.timedOut); first.reviewVote(optionID: 51); await first.confirm()
        XCTAssertEqual(first.visiblePhase, .unknown); first.suspend()
        let second = try owner(client, reader, journal); await second.refresh()
        XCTAssertFalse(second.canVote); XCTAssertEqual(second.visiblePhase, .unknown)
        second.reviewVote(optionID: 52); await second.confirm(); XCTAssertEqual(client.mutations.count, 1)
        client.current = try poll(["status": "CLOSED", "version": 2]); await second.refresh()
        XCTAssertTrue(journal.values.isEmpty); XCTAssertEqual(second.visiblePhase, .idle); XCTAssertFalse(second.canVote)
    }
    @MainActor func testUnknownVoteReadbackUsesServerChoiceWithoutInventingAcknowledgment() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(), owner = try owner(client, reader, journal)
        await owner.refresh(); client.failure = URLError(.timedOut); owner.reviewVote(optionID: 51); await owner.confirm()
        client.current = try poll(["myOptionId": 52, "totalVoters": 1, "options": [["id":51,"pollId":31,"position":1,"content":"River","voteCount":0],["id":52,"pollId":31,"position":2,"content":"Park","voteCount":1]]])
        await owner.refresh(); XCTAssertEqual(owner.visiblePoll?.myOptionId, 52); XCTAssertEqual(owner.visiblePhase, .idle); XCTAssertTrue(journal.values.isEmpty)
    }
    @MainActor func testCloseCreatorAndFreshVersionAreRequired() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(), owner = try owner(client, reader, journal)
        await owner.refresh(); owner.reviewClose(); client.current = try poll(["version": 2]); await owner.confirm()
        XCTAssertEqual(owner.visiblePhase, .rejected); XCTAssertTrue(client.mutations.isEmpty)
        client.identity = .init(accountID: 9, epoch: 1); reader.identity = client.identity
        let other = try self.owner(client, reader, journal); await other.refresh(); XCTAssertFalse(other.canClose)
    }
    @MainActor func testExitMembershipBetweenReviewAndConfirmDoesNotVote() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(), owner = try owner(client, reader, journal)
        await owner.refresh(); owner.reviewVote(optionID: 51); reader.member = false; await owner.confirm()
        XCTAssertTrue(client.mutations.isEmpty); XCTAssertEqual(owner.visiblePhase, .rejected); XCTAssertFalse(owner.canVote)
        await owner.refresh(); XCTAssertNotNil(owner.visiblePoll); XCTAssertFalse(owner.isMember)
    }
    @MainActor func testHangoutGroupDoesNotOfferPollMutations() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(); reader.groupKey = "hangout_81"
        let owner = try owner(client, reader, journal); await owner.refresh(); XCTAssertFalse(owner.canVote)
        let create = try self.owner(client, reader, journal, creation: true)
        await create.reviewCreate(question: "Q", options: ["a", "b"], deadline: nil); XCTAssertEqual(create.visiblePhase, .blocked); XCTAssertTrue(client.mutations.isEmpty)
    }
    @MainActor func testCreateRetriesFrozenBytesOnlyAndPersistsUnknownLock() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(), owner = try owner(client, reader, journal, creation: true)
        client.failure = URLError(.timedOut)
        await owner.reviewCreate(question: "Q", options: ["River", "Park"], deadline: nil); await owner.confirm()
        let first = try XCTUnwrap(client.mutations.first)
        XCTAssertEqual(try first.body(), try first.body())
        XCTAssertFalse(owner.canCreate); XCTAssertTrue(owner.canRetryCreation)
        await owner.reviewCreate(question: "Replacement", options: ["X", "Y"], deadline: nil)
        await owner.retryCreationUnchanged(); XCTAssertEqual(client.mutations, [first, first])
        let reopened = try self.owner(client, reader, journal, creation: true); XCTAssertEqual(reopened.visiblePhase, .unknown); XCTAssertFalse(reopened.canRetryCreation)
    }
    @MainActor func testReopeningMatchingMessageReconcilesCreateAfterRelaunch() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(), create = try owner(client, reader, journal, creation: true)
        client.failure = URLError(.timedOut)
        await create.reviewCreate(question: "Q", options: ["River", "Park"], deadline: nil); await create.confirm()
        guard case .create(let draft) = client.mutations[0] else { return XCTFail() }
        client.current = try poll(["clientPollKey": draft.clientPollKey, "question": draft.question])
        let detail = try owner(client, reader, journal); await detail.refresh(); XCTAssertTrue(journal.values.isEmpty)
        create.resume(); XCTAssertEqual(create.visiblePhase, .idle); XCTAssertTrue(create.canCreate)
    }
    @MainActor func testJournalFailureAndStaleMembershipCompletionDispatchNothing() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(), owner = try owner(client, reader, journal)
        await owner.refresh(); owner.reviewVote(optionID: 51); journal.fails = true; await owner.confirm(); XCTAssertTrue(client.mutations.isEmpty)
        journal.fails = false; await owner.refresh(); owner.reviewVote(optionID: 51)
        reader.beforeRead = { client.identity = .init(accountID: 7, epoch: 2) }; await owner.confirm()
        XCTAssertTrue(client.mutations.isEmpty); XCTAssertNil(owner.visiblePoll)
    }
    @MainActor func testJournalCallbackSuspendRetainsLockWithoutDispatch() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(), owner = try owner(client, reader, journal)
        await owner.refresh(); owner.reviewVote(optionID: 51)
        journal.afterWrite = { owner.suspend() }
        await owner.confirm()
        XCTAssertTrue(client.mutations.isEmpty); XCTAssertEqual(journal.values.count, 1)
        XCTAssertEqual(owner.visiblePhase, .unknown); XCTAssertFalse(owner.canVote)
    }
    @MainActor func testJournalCallbackAccountEpochChangeRetainsLockWithoutDispatch() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(), owner = try owner(client, reader, journal)
        await owner.refresh(); owner.reviewVote(optionID: 51)
        journal.afterWrite = { client.identity = .init(accountID: 7, epoch: 2); reader.identity = client.identity }
        await owner.confirm()
        XCTAssertTrue(client.mutations.isEmpty); XCTAssertEqual(journal.values.count, 1)
        XCTAssertEqual(owner.visiblePhase, .blocked); XCTAssertNil(owner.visiblePoll)
    }
    @MainActor func testJournalCallbackTaskCancellationRetainsLockWithoutDispatch() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(), owner = try owner(client, reader, journal)
        await owner.refresh(); owner.reviewVote(optionID: 51)
        var operation: Task<Void, Never>?
        journal.afterWrite = { operation?.cancel() }
        operation = Task { await owner.confirm() }
        await operation?.value
        XCTAssertTrue(client.mutations.isEmpty); XCTAssertEqual(journal.values.count, 1)
        XCTAssertEqual(owner.visiblePhase, .unknown); XCTAssertFalse(owner.canVote)
    }
    @MainActor func testSuspendDuringPreflightDoesNotDispatchAndUnknownPostDispatchKeepsLock() async throws {
        let client = PollClient(), reader = PollReader(), journal = PollJournal(), owner = try owner(client, reader, journal)
        await owner.refresh(); owner.reviewVote(optionID: 51); reader.beforeRead = { owner.suspend() }; await owner.confirm()
        XCTAssertTrue(client.mutations.isEmpty)
        reader.beforeRead = nil; await owner.refresh(); owner.reviewVote(optionID: 51)
        client.beforeMutation = { owner.suspend() }; await owner.confirm(); XCTAssertEqual(client.mutations.count, 1); XCTAssertFalse(journal.values.isEmpty)
    }
}

@MainActor private final class TestClubChatClient: ClubChatServing {
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    var isConfigured = true
    var requests: [Int] = []
    var fail = false
    var conversationID = 12
    var beforeReturn: (() -> Void)?
    func enter(clubID: Int, expectedIdentity: MessagingReadIdentity) async throws -> Int {
        requests.append(clubID); beforeReturn?(); if fail { throw URLError(.timedOut) }; return conversationID
    }
}
final class ClubChatTests: XCTestCase {
    @MainActor func testDefaultOffAndExactJSONUsesClubIDNotConversationID() async throws {
        let transport = PollTransport(); transport.data = Data(#"{"code":200,"data":{"conversationId":12}}"#.utf8)
        let snapshot = try GroupPollSession(accountID: 7, epoch: 1, token: "test")
        let configuration = try APIConfiguration(baseURL: URL(string: "https://club.example.test/prod-api")!)
        let disabled = ClubChatService(configuration: configuration, transport: transport, session: { snapshot })
        do { _ = try await disabled.enter(clubID: 81, expectedIdentity: snapshot.identity); XCTFail() } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
        let service = ClubChatService(configuration: configuration, transport: transport, enabled: true, session: { snapshot })
        let conversation = try await service.enter(clubID: 81, expectedIdentity: snapshot.identity)
        XCTAssertEqual(conversation, 12)
        XCTAssertEqual(transport.requests[0].url?.path, "/prod-api/api/club/chat")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as? [String: Int], ["id": 81])
        XCTAssertFalse(transport.requests[0].httpShouldHandleCookies)
    }
    @MainActor func testClubEntryVerifiesCurrentMembershipAndMatchingServerConversation() async throws {
        let client = TestClubChatClient(), reader = PollReader()
        let owner = try ClubChatCoordinator(clubID: 81, identity: client.identity!, service: client, clubs: reader, messages: reader)
        XCTAssertTrue(client.requests.isEmpty); await owner.enter()
        guard case .ready(let group) = owner.visiblePhase else { return XCTFail() }
        XCTAssertEqual(group.id, 12); XCTAssertNotEqual(group.id, owner.clubID)
        reader.groupKey = "club_99"; await owner.enter(); XCTAssertEqual(owner.visiblePhase, .unknown)
    }
    @MainActor func testNonMemberCannotBootstrapEvenIfClientEnabled() async throws {
        let client = TestClubChatClient(), reader = PollReader(); reader.member = false
        let owner = try ClubChatCoordinator(clubID: 81, identity: client.identity!, service: client, clubs: reader, messages: reader)
        await owner.enter(); XCTAssertTrue(client.requests.isEmpty); XCTAssertEqual(owner.visiblePhase, .rejected)
    }
    @MainActor func testUnknownRetryAlwaysUsesSameClubAndNoAutomaticRetry() async throws {
        let client = TestClubChatClient(), reader = PollReader(); client.fail = true
        let owner = try ClubChatCoordinator(clubID: 81, identity: client.identity!, service: client, clubs: reader, messages: reader)
        await owner.enter(); XCTAssertEqual(owner.visiblePhase, .unknown); XCTAssertEqual(client.requests, [81])
        client.fail = false; await owner.enter(); XCTAssertEqual(client.requests, [81, 81])
        guard case .ready = owner.visiblePhase else { return XCTFail() }
    }
    @MainActor func testRoleSessionChangeAfterAwaitCannotNavigate() async throws {
        let client = TestClubChatClient(), reader = PollReader()
        let owner = try ClubChatCoordinator(clubID: 81, identity: client.identity!, service: client, clubs: reader, messages: reader)
        client.beforeReturn = { client.identity = nil }; await owner.enter(); XCTAssertEqual(owner.visiblePhase, .stale)
    }
    @MainActor func testClubServiceRejectsStaleSuccessAndMalformedID() async throws {
        let transport = PollTransport(); transport.data = Data(#"{"code":200,"data":{"conversationId":0}}"#.utf8)
        var snapshot: GroupPollSession? = try .init(accountID: 7, epoch: 1, token: "test")
        let service = try ClubChatService(configuration: APIConfiguration(baseURL: URL(string: "https://club.example.test")!), transport: transport, enabled: true, session: { snapshot })
        do { _ = try await service.enter(clubID: 81, expectedIdentity: snapshot!.identity); XCTFail() } catch {}
        transport.data = Data(#"{"code":200,"data":{"conversationId":12}}"#.utf8)
        transport.beforeReturn = { snapshot = try? .init(accountID: 7, epoch: 2, token: "new") }
        do { _ = try await service.enter(clubID: 81, expectedIdentity: .init(accountID: 7, epoch: 1)); XCTFail() } catch {}
    }
}

#if DEBUG
import SwiftUI

/// Synthetic-only in-memory fixture. No transport, shared defaults, accounts or live calls.
@MainActor private final class GroupPollFixtureStore: ObservableObject, GroupPollServing, MessagingReading {
    @Published var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    let scenario: String
    let isConfigured = true
    var mutations = 0
    var owners: [String: GroupPollCoordinator] = [:]
    private let journal = GroupPollFixtureJournal()
    var row: [String: Any] = ["id": 31, "conversationId": 12, "creatorMemberId": 7, "clientPollKey": "fixture",
        "question": "Which route?", "selectionMode": "SINGLE", "visibility": "PUBLIC", "status": "OPEN", "version": 1, "messageId": 44, "totalVoters": 0,
        "options": [["id": 51, "pollId": 31, "position": 1, "content": "River", "voteCount": 0], ["id": 52, "pollId": 31, "position": 2, "content": "Park", "voteCount": 0]]]
    init(scenario: String) { self.scenario = scenario; if scenario == "other" { identity = .init(accountID: 9, epoch: 1) } }
    func permits(_ path: String) -> Bool { scenario != "dormant" }
    func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T { try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value)) }
    func messagingConversations() async throws -> [MessagingConversation] {
        try decode([MessagingConversation].self, [["conversationId": 12, "type": 4, "counterparty": ["nickname": "Fixture club", "bizKey": "club_81"], "lastMsgType": 4]])
    }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage {
        try decode(MessagingPage.self, ["list": [["id": 44, "conversationId": 12, "senderId": 7, "status":0,"msgType": 4, "extraJson": "{\"pollId\":31}"]], "hasMore": false])
    }
    func result(_ reference: GroupPollReference, expectedIdentity: MessagingReadIdentity) async throws -> GroupPoll { try decode(GroupPoll.self, row) }
    func perform(_ mutation: GroupPollMutation, scope: IMScope, reference: GroupPollReference?) async throws -> GroupPoll {
        mutations += 1
        if scenario == "unknown" { throw URLError(.timedOut) }
        switch mutation {
        case .create(let draft):
            row["totalVoters"] = 0; row["myOptionId"] = nil; row["status"] = "OPEN"; row["version"] = 1
            row["clientPollKey"] = draft.clientPollKey; row["question"] = draft.question
            row["deadlineAt"] = draft.deadlineAt; row["options"] = draft.options.enumerated().map { index, text in ["id": 51 + index, "pollId": 31, "position": index + 1, "content": text, "voteCount": 0] as [String: Any] }
            var created = row; created["totalVoters"] = nil
            return try decode(GroupPoll.self, created)
        case .vote(_, let option):
            row["myOptionId"] = option; row["totalVoters"] = 1
            row["options"] = (row["options"] as! [[String: Any]]).map { original in var value = original; value["voteCount"] = value["id"] as? Int == option ? 1 : 0; return value }
        case .close: row["status"] = "CLOSED"; row["version"] = 2
        }
        return try decode(GroupPoll.self, row)
    }
    func owner(_ conversation: Int, _ reference: GroupPollReference?) -> GroupPollCoordinator? {
        guard let identity else { return nil }
        let key = "\(identity.epoch)-\(reference?.pollID ?? 0)"
        if let owner = owners[key] { return owner }
        let owner = try? GroupPollCoordinator(scope: IMScope(identity: identity, conversationID: conversation), reference: reference,
            client: self, reader: self, journal: journal, namespace: "synthetic-only", realm: URL(string: "https://poll.fixture.test")!)
        owners[key] = owner; return owner
    }
}
@MainActor private final class GroupPollFixtureJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records[ownerKey + targetKey] }
    func write(_ record: OperationPendingRecord) throws { records[record.ownerKey + record.targetKey] = record }
    func clear(_ record: OperationPendingRecord) throws { records.removeValue(forKey: record.ownerKey + record.targetKey) }
}
@MainActor struct GroupPollFixtureRoot: View {
    @StateObject private var store: GroupPollFixtureStore
    init(scenario: String) { _store = StateObject(wrappedValue: GroupPollFixtureStore(scenario: scenario)) }
    var body: some View {
        NavigationStack {
            MessagingHomeView(reader: store, expanded: .init(coordinator: { _ in nil }, uploadCoordinator: { _ in nil }, starter: { nil },
                topicReader: TopicSessionReader(service: nil, currentSession: { nil }), pollCoordinator: { store.owner($0, $1) }))
        }.id(store.identity)
    }
}
#endif

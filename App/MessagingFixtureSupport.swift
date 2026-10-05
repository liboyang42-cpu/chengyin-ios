#if DEBUG
import SwiftUI

/// Offline-only, explicitly mounted by root DEBUG routing. No hosts, credentials, real
/// personal records, timers, image loads or shared session access.
enum MessagingFixtureScenario: String {
    case success, empty, error, closed, unauthorized, unconfigured, pagingError, loading
}

@MainActor
final class MessagingFixtureReader: MessagingReading {
    let scenario: MessagingFixtureScenario
    private(set) var epoch: UInt64 = 1
    private(set) var accountID = 9001
    var isConfigured: Bool { scenario != .unconfigured }
    var identity: MessagingReadIdentity? {
        scenario == .unauthorized ? nil : MessagingReadIdentity(accountID: accountID, epoch: epoch)
    }
    init(_ scenario: MessagingFixtureScenario) { self.scenario = scenario }
    func switchAccount() { epoch &+= 1; accountID = accountID == 9001 ? 9002 : 9001 }
    private func prepare() async throws {
        try Task.checkCancellation()
        if scenario == .loading { try await Task.sleep(nanoseconds: 15_000_000_000) }
        if scenario == .error { throw MessagingReadFailure(code: 503, message: "Synthetic service failure") }
        if scenario == .unauthorized { throw APIError.unauthorized }
        if scenario == .unconfigured { throw APIError.notConfigured }
    }
    private func decode<Value: Decodable>(_ type: Value.Type, _ object: Any) throws -> Value {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    func messagingConversations() async throws -> [MessagingConversation] {
        try await prepare()
        if scenario == .empty { return [] }
        let rows: [[String: Any]] = (1...35).map { index in
            ["conversationId": 900 + index, "type": index <= 4 ? index : 1,
             "counterparty": ["id": 8000 + index, "nickname": "Fixture conversation \(index)"],
             "lastMsgType": index == 2 ? 2 : 1,
             "lastMsgText": index == 2 ? "" : "Synthetic preview for account \(accountID)",
             "lastMsgAt": "2026-10-01 10:00:00", "unread": index == 1 ? 3 : 0,
             "muted": index == 4 ? 1 : 0]
        }
        return try decode([MessagingConversation].self, rows)
    }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage {
        try await prepare()
        guard (901...935).contains(conversationID), cursor == 0 || cursor == 42 else { throw APIError.invalidRequest }
        if scenario == .closed { throw MessagingReadFailure(code: 409, errorCode: "HANGOUT_CLOSED") }
        if scenario == .empty { return try decode(MessagingPage.self, ["list": [], "hasMore": false]) }
        if cursor == 42 {
            if scenario == .pagingError { throw MessagingReadFailure(code: 503, message: "Synthetic earlier-page failure") }
            return try decode(MessagingPage.self, ["list": [message(id: 1, conversationID: conversationID,
                text: "Synthetic earlier message", sender: 8001)], "nextCursor": 0, "hasMore": false])
        }
        let generic = #"{"cardType":"generic","title":"Fixture notice","sub":"Synthetic card description","buttons":[{"text":"Fixture action"}],"result":{"taskId":"FIXTURE-TASK","outcome":"Synthetic outcome","reason":"Synthetic reason"}}"#
        let route = #"{"cardType":"route","topicId":7001}"#
        let location = #"{"cardType":"location","name":"Fixture point","address":"Synthetic location","lat":0,"lng":0}"#
        let rows = [
            message(id: 10, conversationID: conversationID, text: "Synthetic received text", sender: 8001),
            message(id: 11, conversationID: conversationID, text: "Synthetic own text for account \(accountID)", sender: accountID),
            message(id: 12, conversationID: conversationID, text: "Synthetic image", sender: 8001, type: 2),
            message(id: 13, conversationID: conversationID, text: "", sender: 0, type: 3, extra: generic),
            message(id: 14, conversationID: conversationID, text: "", sender: 8001, type: 3, extra: route),
            message(id: 15, conversationID: conversationID, text: "", sender: 8001, type: 3, extra: location),
            message(id: 16, conversationID: conversationID, text: "Future message type", sender: 8001, type: 99),
            message(id: 17, conversationID: conversationID, text: "<b>Literal text</b> [fixture](disabled)", sender: 8001)
        ]
        return try decode(MessagingPage.self, ["list": rows, "hasMore": true, "nextCursor": 42])
    }
    private func message(id: Int, conversationID: Int, text: String, sender: Int, type: Int = 1,
                         extra: String = "") -> [String: Any] {
        ["id": id, "conversationId": conversationID, "senderId": sender, "status":0,"msgType": type,
         "content": text, "extraJson": extra, "senderName": "Fixture sender",
         "createTime": "2026-10-01 10:00:00"]
    }
}

@MainActor
struct MessagingFixtureHostView: View {
    private let reader: MessagingFixtureReader
    @State private var revision: UInt64 = 1
    init(scenario: MessagingFixtureScenario = .success) { reader = MessagingFixtureReader(scenario) }
    var body: some View {
        NavigationStack {
            MessagingHomeView(reader: reader)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("messaging.fixture.switch") { reader.switchAccount(); revision = reader.epoch }
                            .accessibilityIdentifier("messaging.fixture.switch")
                    }
                }
        }.id(revision)
    }
}
#endif

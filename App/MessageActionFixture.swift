#if DEBUG
import SwiftUI

@MainActor private final class MessageFixtureStore:MessagingReading,MessageActionWriting {
    let isConfigured=true
    let identity:MessagingReadIdentity? = .init(accountID:9001,epoch:1)
    private var rows:[[String:Any]]=[["id":1,"conversationId":901,"senderId":8001,"msgType":1,"content":"Fixture received message"]]
    private var receipts:[String:MessagingMessage]=[:]
    func messagingConversations() async throws -> [MessagingConversation] { [] }
    func messagingMessages(conversationID:Int,cursor:Int) async throws -> MessagingPage {
        guard conversationID==901,cursor==0 else { throw APIError.invalidRequest }
        return try JSONDecoder().decode(MessagingPage.self,from:JSONSerialization.data(withJSONObject:["list":rows,"hasMore":false]))
    }
    func send(_ intent:MessageTextIntent,expectedIdentity:MessagingReadIdentity) async throws -> MessagingMessage {
        guard expectedIdentity==identity,intent.conversationID==901 else { throw APIError.unauthorized }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--reference-message-unknown") { throw APIError.malformedResponse }
        if args.contains("--reference-message-rejected") { throw MessagingReadFailure(code: 403) }
        if args.contains("--reference-message-pending") { try await Task.sleep(for: .seconds(30)) }
        if let existing=receipts[intent.clientMessageID] { return existing }
        let row:[String:Any]=["id":rows.count+1,"conversationId":901,"senderId":9001,"msgType":1,"content":intent.content]
        let message=try JSONDecoder().decode(MessagingMessage.self,from:JSONSerialization.data(withJSONObject:row))
        rows.append(row);receipts[intent.clientMessageID]=message;return message
    }
}
@MainActor private final class MessageFixtureOwner:ObservableObject {
    let store=MessageFixtureStore()
    lazy var sender=MessageActionCoordinator(accountID:9001,conversationID:901,writer:store)
}
@MainActor struct MessageActionFixtureHost:View {
    @StateObject private var model=MessageFixtureOwner()
    var body:some View {
        NavigationStack { MessagingHistoryView(conversationID:901,reader:model.store,sender:model.sender) }
    }
}
#endif

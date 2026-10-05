import Foundation

public enum MessageSendState:Equatable {
    case idle, sending, outcomeUnknown, rejected, closed
    /// Server receipt, not a read receipt or a claim the recipient saw the message.
    case acknowledged(MessagingMessage)
}

/// One pending text intent per account/conversation. Retain across navigation. No persistence
/// or exactly-once guarantee is claimed; manual retry reuses the same source client_message_id.
@MainActor public final class MessageActionCoordinator {
    public let accountID:Int
    public let conversationID:Int
    private let writer:any MessageActionWriting
    private var state:MessageSendState = .idle
    private var intent:MessageTextIntent?
    private var sendingIdentity:MessagingReadIdentity?
    public var onStateChange:(()->Void)?
    public var isConfigured:Bool { writer.isConfigured }
    public var isCurrentAccount:Bool { writer.identity?.accountID==accountID }
    public var visibleState:MessageSendState { isCurrentAccount ? state : .idle }
    public var pendingText:String? { isCurrentAccount ? intent?.content : nil }
    public var pendingClientMessageID:String? { isCurrentAccount ? intent?.clientMessageID : nil }
    public init(accountID:Int,conversationID:Int,writer:any MessageActionWriting) {
        self.accountID=accountID;self.conversationID=conversationID;self.writer=writer
    }
    /// Host supplies true only after a successful current-account history load, not during
    /// load/error/closed states. Server remains authoritative for permission at send time.
    @discardableResult public func sendNew(_ content:String,conversationReady:Bool,expectedIdentity:MessagingReadIdentity) async -> Bool {
        guard writer.identity==expectedIdentity,conversationReady,isConfigured,isCurrentAccount,accountID>0,conversationID>0,
              state != .sending,state != .outcomeUnknown,state != .closed else { return false }
        guard let newIntent=try? MessageTextIntent(conversationID:conversationID,content:content) else { return false }
        intent=newIntent
        return await dispatch(conversationReady:conversationReady,expectedIdentity:expectedIdentity)
    }
    /// Explicit action only. Never rotate the ID or change text when retrying an existing intent.
    @discardableResult public func retry(conversationReady:Bool,expectedIdentity:MessagingReadIdentity) async -> Bool {
        guard state == .outcomeUnknown || state == .rejected else { return false }
        return await dispatch(conversationReady:conversationReady,expectedIdentity:expectedIdentity)
    }
    private func dispatch(conversationReady:Bool,expectedIdentity:MessagingReadIdentity) async -> Bool {
        guard writer.identity==expectedIdentity,conversationReady,isConfigured,isCurrentAccount,!Task.isCancelled,
              state != .sending,state != .closed,let intent,let identity=writer.identity else { return false }
        state = .sending;sendingIdentity=identity;onStateChange?()
        do {
            let receipt=try await writer.send(intent,expectedIdentity:identity)
            guard !Task.isCancelled,writer.identity==identity else {
                state = .outcomeUnknown;sendingIdentity=nil;onStateChange?();return false
            }
            state = .acknowledged(receipt);sendingIdentity=nil;onStateChange?();return true
        } catch {
            sendingIdentity=nil
            if writer.identity != identity || Task.isCancelled { state = .outcomeUnknown }
            else if let failure=error as? MessagingReadFailure, failure.httpStatus==nil {
                if failure.isClosed { state = .closed }
                else if let code=failure.code,[400,401,403,404].contains(code) { state = .rejected }
                else { state = .outcomeUnknown }
            } else { state = .outcomeUnknown }
            onStateChange?();return false
        }
    }
    /// Hiding a screen does not cancel an already-sent request or throw away the pending intent.
    /// The UI must clear its editable draft on dismissal/account change; this owner retains only
    /// the original submitted text for explicit recovery, in memory and scoped to this account.
    public func sessionChanged() { onStateChange?() }
}

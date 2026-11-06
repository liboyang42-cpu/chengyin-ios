import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mini-program im/list `onRowDelete` and im/chat `onMoreSelect` (举报 / 拉黑 /
/// 解除拉黑 / 隐藏会话). Exact source paths and fields from ApiImController:
/// delete(conversation_id), report(message_id, reason), block/unblock(target_member_id).
public enum IMSafetyAction: Equatable {
    case hide(conversationID: Int)
    case report(conversationID: Int, messageID: Int)
    case block(conversationID: Int, targetMemberID: Int)
    case unblock(conversationID: Int, targetMemberID: Int)

    /// Source sends this fixed literal; there is no reason picker in the chat page.
    public static let reportReason = "用户举报"

    public var conversationID: Int {
        switch self {
        case .hide(let id), .report(let id, _), .block(let id, _), .unblock(let id, _): return id
        }
    }
    public var feature: BusinessRuntimeFeature {
        switch self { case .hide: return .imDelete; case .report: return .imReport; case .block: return .imBlock; case .unblock: return .imUnblock }
    }
    public var path: String {
        switch self { case .hide: return "api/im/delete"; case .report: return "api/im/report"; case .block: return "api/im/block"; case .unblock: return "api/im/unblock" }
    }
    public var fields: [String: String] {
        switch self {
        case .hide(let id): return ["conversation_id": String(id)]
        case .report(_, let message): return ["message_id": String(message), "reason": Self.reportReason]
        case .block(_, let target), .unblock(_, let target): return ["target_member_id": String(target)]
        }
    }
    var isValid: Bool {
        switch self {
        case .hide(let id): return id > 0
        case .report(let id, let message): return id > 0 && message > 0
        case .block(let id, let target), .unblock(let id, let target): return id > 0 && target > 0
        }
    }

    /// Source `doReport`: only the latest server message sent by someone else,
    /// never a pending local row, a system sender (0) or the viewer's own text.
    public static func reportTarget(in messages: [MessagingMessage], accountID: Int) -> MessagingMessage? {
        messages.last { message in
            guard let sender = message.senderID else { return false }
            return message.id > 0 && sender > 0 && sender != accountID
        }
    }
    /// Source `doBlock` rereads /api/im/conversations and accepts only a type-1
    /// row whose counterparty is a positive member other than the viewer.
    public static func blockTarget(in conversations: [MessagingConversation], conversationID: Int, accountID: Int) -> Int? {
        guard let row = conversations.first(where: { $0.id == conversationID }), row.kind == .direct,
              let id = row.counterparty?.id, id > 0, id != accountID else { return nil }
        return id
    }
}

/// Which safety entries a conversation offers (chat `_moreItemsFor`): system
/// notices only offer hide; others offer report, block or unblock, and hide.
public struct IMSafetyMenu: Equatable {
    public enum Item: Equatable { case report, block, unblock, hide }
    public let items: [Item]
    public init(conversation: MessagingConversation?, blockedByMe: Bool?) {
        if conversation?.kind == .system { items = [.hide]; return }
        items = [.report, blockedByMe == true ? .unblock : .block, .hide]
    }
}

/// Composer gate text, in source priority order (chat `loadMessages`).
public enum IMReplyBlock: Equatable {
    case systemNotice, blockedByMe, peerUnavailable
    public static func from(conversation: MessagingConversation?, page blocked: Bool?, blockedByMe: Bool?) -> Self? {
        if conversation?.kind == .system { return .systemNotice }
        guard blocked == true else { return nil }
        return blockedByMe == true ? .blockedByMe : .peerUnavailable
    }
}

/// Read-receipt trigger policy for P033 chat load (`/api/im/read`). Defaults to
/// `.explicitUserActionOnly` (`shouldAutoMarkRead == false`) so opening a chat
/// never dispatches an implicit write unless `.autoOnLoadWhenGranted(imReadGranted: true)`
/// is explicitly configured.
public enum IMReadReceiptTriggerPolicy: Equatable, Sendable {
    case explicitUserActionOnly
    case autoOnLoadWhenGranted(imReadGranted: Bool)

    public static let defaultPolicy: Self = .explicitUserActionOnly

    public var shouldAutoMarkRead: Bool {
        switch self {
        case .explicitUserActionOnly:
            return false
        case .autoOnLoadWhenGranted(let imReadGranted):
            return imReadGranted
        }
    }

    public func shouldAutoMarkRead(unreadCount: Int?) -> Bool {
        guard shouldAutoMarkRead else { return false }
        guard let unreadCount else { return true }
        return unreadCount > 0
    }
}

public struct IMSafetySession: Equatable {
    public let identity: MessagingReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = .init(accountID: accountID, epoch: epoch); self.token = token
    }
}

extension IMSafetySession {
    /// Lends the capsule token to one request without exposing it as a property.
    func withToken<Value>(_ body: (String) async throws -> Value) async rethrows -> Value { try await body(token) }
}

/// Injectable only. Disabled unless the reviewed business runtime grants the
/// exact path; no default host, cookies, redirects or retries.
public struct IMSafetyService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let enabledPaths: Set<String>
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabledPaths: Set<String>) {
        self.configuration = configuration; self.transport = transport; self.enabledPaths = enabledPaths
    }
    public func permits(_ action: IMSafetyAction) -> Bool { enabledPaths.contains(action.path) }
    public func perform(_ action: IMSafetyAction, token: String) async throws {
        guard permits(action) else { throw APIError.notConfigured }
        guard action.isValid, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(action.path),
            fields: action.fields, token: token)
        request.httpShouldHandleCookies = false
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        struct Header: Decodable { let code: Int; let msg: String?; let errorCode: String? }
        guard data.count <= 64 * 1024 else { throw APIError.malformedResponse }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        guard (200..<300).contains(status) else { throw MessagingReadFailure(httpStatus: status, code: header?.code, errorCode: header?.errorCode, message: header?.msg) }
        guard let header else { throw APIError.malformedResponse }
        guard header.code == 200 else { throw MessagingReadFailure(code: header.code, errorCode: header.errorCode, message: header.msg) }
    }
}

@MainActor public protocol IMSafetyWriting: AnyObject {
    var identity: MessagingReadIdentity? { get }
    func permits(_ action: IMSafetyAction) -> Bool
    func perform(_ action: IMSafetyAction, expectedIdentity: MessagingReadIdentity) async throws
}

@MainActor public final class IMSafetyWriter: IMSafetyWriting {
    private let service: IMSafetyService?
    private let session: () -> IMSafetySession?
    private let onUnauthorized: (IMSafetySession) -> Void
    public var identity: MessagingReadIdentity? { session()?.identity }
    public init(service: IMSafetyService? = nil, session: @escaping () -> IMSafetySession?,
                onUnauthorized: @escaping (IMSafetySession) -> Void = { _ in }) {
        self.service = service; self.session = session; self.onUnauthorized = onUnauthorized
    }
    public func permits(_ action: IMSafetyAction) -> Bool { service?.permits(action) == true }
    public func perform(_ action: IMSafetyAction, expectedIdentity: MessagingReadIdentity) async throws {
        guard let service else { throw APIError.notConfigured }
        guard let snapshot = session(), snapshot.identity == expectedIdentity else { throw APIError.unauthorized }
        do {
            try await service.perform(action, token: snapshot.token)
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
        } catch {
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }
            throw error
        }
    }
}

public enum IMSafetyState: Equatable {
    case idle
    case resolving                      // block target reread before review
    case unavailable(String?)           // target/message could not be resolved
    case reviewing(IMSafetyAction)
    case submitting(IMSafetyAction)
    case acknowledged(IMSafetyAction)
    case rejected(IMSafetyAction, message: String?)
    case outcomeUnknown(IMSafetyAction)
    case verifying(IMSafetyAction)
    case notApplied(IMSafetyAction)     // readback shows the change did not land
}

/// One reviewed safety action per conversation scope. Nothing dispatches without
/// an explicit `confirm`; an uncertain outcome is resolved by readback (hide: the
/// row is absent; block/unblock: `blockedByMe`), never by assuming success.
/// Report has no readable state, so its unknown outcome stays unknown and only
/// an explicit, warned retry can resend it.
@MainActor public final class IMSafetyCoordinator {
    public let scope: IMScope
    public let writer: any IMSafetyWriting
    private let reader: any MessagingReading
    public private(set) var requestID = UUID()
    private var state: IMSafetyState = .idle
    public var onChange: (() -> Void)?

    public init(scope: IMScope, writer: any IMSafetyWriting, reader: any MessagingReading) {
        self.scope = scope; self.writer = writer; self.reader = reader
    }
    public var isCurrent: Bool { writer.identity == scope.identity && reader.identity == scope.identity }
    public var visibleState: IMSafetyState { isCurrent ? state : .idle }
    public func permits(_ action: IMSafetyAction) -> Bool { isCurrent && writer.permits(action) && action.conversationID == scope.conversationID }
    private var isBusy: Bool {
        switch state { case .resolving, .submitting, .verifying, .outcomeUnknown: return true; default: return false }
    }

    @discardableResult public func review(_ action: IMSafetyAction) -> Bool {
        guard permits(action), action.isValid, !isBusy else { return false }
        requestID = UUID(); set(.reviewing(action)); return true
    }
    @discardableResult public func reviewReport(messages: [MessagingMessage]) -> Bool {
        guard !isBusy else { return false }
        guard let target = IMSafetyAction.reportTarget(in: messages, accountID: scope.identity.accountID) else {
            set(.unavailable(nil)); return false
        }
        return review(.report(conversationID: scope.conversationID, messageID: target.id))
    }
    /// Block/unblock resolve the peer from a fresh conversation read, like the source.
    public func reviewBlock(unblock: Bool) async {
        // Path/scope probe only; the real target comes from the reread below.
        let probe: IMSafetyAction = unblock ? .unblock(conversationID: scope.conversationID, targetMemberID: 1)
            : .block(conversationID: scope.conversationID, targetMemberID: 1)
        guard permits(probe), !isBusy else { return }
        set(.resolving)
        let identity = scope.identity
        do {
            let rows = try await reader.messagingConversations()
            guard isCurrent, scope.identity == identity, state == .resolving else { return }
            guard let target = IMSafetyAction.blockTarget(in: rows, conversationID: scope.conversationID, accountID: identity.accountID) else {
                set(.unavailable(nil)); return
            }
            requestID = UUID()
            set(.reviewing(unblock ? .unblock(conversationID: scope.conversationID, targetMemberID: target)
                                   : .block(conversationID: scope.conversationID, targetMemberID: target)))
        } catch {
            guard isCurrent, state == .resolving else { return }
            set(.unavailable((error as? MessagingReadFailure)?.message))
        }
    }
    public func cancelReview() {
        switch state { case .reviewing, .unavailable, .rejected, .acknowledged, .notApplied: set(.idle); default: break }
    }
    public func confirm() async {
        guard case .reviewing(let action) = state else { return }
        await dispatch(action)
    }
    /// Explicit resend of the exact reviewed action (same request ID).
    public func retryUnchanged() async {
        switch state {
        case .outcomeUnknown(let action), .rejected(let action, _), .notApplied(let action): await dispatch(action)
        default: return
        }
    }
    /// Uncertain-outcome readback. Report cannot be read back and stays unknown.
    public func verify() async {
        guard case .outcomeUnknown(let action) = state, isCurrent else { return }
        if case .report = action { return }
        set(.verifying(action))
        do {
            let applied: Bool
            switch action {
            case .hide(let id):
                let rows = try await reader.messagingConversations()
                applied = !rows.contains { $0.id == id }
            case .block(let id, _), .unblock(let id, _):
                let page = try await reader.messagingMessages(conversationID: id, cursor: 0)
                guard let byMe = page.blockedByMe else { throw APIError.malformedResponse }
                if case .block = action { applied = byMe } else { applied = !byMe }
            case .report: return
            }
            guard isCurrent, state == .verifying(action) else { return }
            set(applied ? .acknowledged(action) : .notApplied(action))
        } catch {
            guard isCurrent, state == .verifying(action) else { return }
            set(.outcomeUnknown(action))
        }
    }
    private func dispatch(_ action: IMSafetyAction) async {
        guard permits(action), !Task.isCancelled else { return }
        set(.submitting(action))
        do {
            try await writer.perform(action, expectedIdentity: scope.identity)
            guard isCurrent, !Task.isCancelled else { set(.outcomeUnknown(action)); return }
            set(.acknowledged(action))
        } catch {
            if isCurrent, let failure = error as? MessagingReadFailure, failure.httpStatus == nil,
               let code = failure.code, [400, 401, 403, 404].contains(code) {
                set(.rejected(action, message: failure.message))
            } else { set(.outcomeUnknown(action)) }
        }
    }
    private func set(_ next: IMSafetyState) { state = next; onChange?() }
}

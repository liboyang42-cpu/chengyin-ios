import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public protocol NativeChannelNotificationAccess: AnyObject {
    var context: RuntimeDependencyContext { get }
    var isCurrent: Bool { get }
    func retireOperations()
    func allows(_ operation: NativeChannelNotificationOperation, scope: NativeChannelNotificationScope?) -> Bool
    func deliveryLog(query: NativeNotificationDeliveryLogQuery) async throws -> NativeNotificationDeliveryLogPage
    func clubDefault(scope: NativeChannelNotificationScope) async throws -> NativeClubNotificationDefault
    func preferences(scope: NativeChannelNotificationScope?) async throws -> NativeChannelNotificationDirectory
    func submit(_ command: NativeChannelNotificationCommand) async throws -> NativeChannelNotificationReceipt
    func receipt(_ command: NativeChannelNotificationCommand, recovery: NativeChannelNotificationRecovery?) async throws -> NativeChannelNotificationReceipt
    func unreadSummary() async throws -> NativeChannelNotificationUnreadSummary
}

public extension NativeChannelNotificationAccess {
    func deliveryLog(query: NativeNotificationDeliveryLogQuery) async throws -> NativeNotificationDeliveryLogPage {
        throw NativeChannelNotificationError.accessClosed
    }
    func clubDefault(scope: NativeChannelNotificationScope) async throws -> NativeClubNotificationDefault {
        throw NativeChannelNotificationError.accessClosed
    }
    func receipt(_ command: NativeChannelNotificationCommand) async throws -> NativeChannelNotificationReceipt {
        try await receipt(command, recovery: nil)
    }
}

/// The existing host dispatcher supplies final-forward fencing, no redirects and
/// no automatic retries. No generic URLSession/HTTPTransport fallback is provided.
@MainActor public protocol NativeChannelNotificationDispatching {
    func send(_ request: URLRequest, fence: NativeChannelNotificationDispatchFence) async throws -> (Data, Int)
}
@MainActor public final class NativeChannelNotificationDispatchFence {
    private let check: () -> Bool
    public init(_ check: @escaping () -> Bool) { self.check = check }
    public var isCurrent: Bool { check() }
}

/// One original CHANNEL_INDEX read-state row, never a share of the global mention count.
public struct NativeChannelNotificationReadState: Decodable, Equatable {
    public let channelID: String
    public let lastReadMessageID: String?
    public let unread: Int64?
    public let mentionCount: Int64?
    public let readStateAvailable: Int
    enum CodingKeys: String, CodingKey {
        case channelID = "channel_id", lastReadMessageID = "last_read_msg_id", unread
        case mentionCount = "mention_count", readStateAvailable = "read_state_available"
    }
    func validate() throws {
        guard NativeChannelNotificationScope.validID(channelID), [0, 1].contains(readStateAvailable) else { throw NativeChannelNotificationError.malformedResponse }
        if readStateAvailable == 1 {
            guard let unread, unread >= 0, let mentionCount, mentionCount >= 0,
                  let lastReadMessageID, let cursor = Int64(lastReadMessageID), cursor >= 0,
                  String(cursor) == lastReadMessageID else { throw NativeChannelNotificationError.malformedResponse }
        } else {
            guard unread == nil, mentionCount == nil, lastReadMessageID == nil else { throw NativeChannelNotificationError.malformedResponse }
        }
    }
}

public struct NativeChannelNotificationUnreadSummary: Decodable, Equatable {
    public struct Tabs: Decodable, Equatable { public let dm: Int64; public let sys: Int64; public let channel: Int64 }
    public let total: Int64
    public let mentionCount: Int64
    public let hasMention: Int
    public let byTab: Tabs
    /// Trusted only from this authenticated original summary, never from an APNs payload.
    /// Omitted means the generation producer is not enabled; it is NOT generation zero.
    public let badgeGeneration: Int64?
    /// Absent in older producers is unavailable, not an empty/zero per-conversation projection.
    public let byChannel: [NativeChannelNotificationReadState]?
    public let channelScope: String?
    public init(total: Int64, mentionCount: Int64, hasMention: Int, byTab: Tabs, badgeGeneration: Int64? = nil, byChannel: [NativeChannelNotificationReadState]? = nil, channelScope: String? = nil) {
        self.total = total; self.mentionCount = mentionCount; self.hasMention = hasMention; self.byTab = byTab
        self.badgeGeneration = badgeGeneration; self.byChannel = byChannel; self.channelScope = channelScope
    }
    enum CodingKeys: String, CodingKey { case total, mentionCount = "mention_count", hasMention = "has_mention", byTab = "by_tab", badgeGeneration = "badge_generation", byChannel = "by_channel", channelScope = "channel_scope" }
    public func channelState(channelID: String) -> NativeChannelNotificationReadState? {
        guard channelScope == "CHANNEL_INDEX" else { return nil }
        return byChannel?.first { $0.channelID == channelID }
    }
    public func channelState(for conversation: MessagingConversation) -> NativeChannelNotificationReadState? {
        // Join two original projections only after an explicit directory mapping, never by ID coincidence.
        guard [4, 5].contains(conversation.type ?? 0), let context = conversation.directoryContext,
              context.channelID == conversation.id else { return nil }
        return channelState(channelID: String(context.channelID))
    }
    public func validate() throws {
        if let byChannel {
            guard channelScope == "CHANNEL_INDEX", Set(byChannel.map(\.channelID)).count == byChannel.count else { throw NativeChannelNotificationError.malformedResponse }
            try byChannel.forEach { try $0.validate() }
            // Muted/quiet rows can be present while excluded from the global badge. Do not sum rows into totals.
        } else if channelScope != nil { throw NativeChannelNotificationError.malformedResponse }
        guard badgeGeneration.map({ $0 >= 0 }) ?? true,
              total >= 0, mentionCount >= 0, [0, 1].contains(hasMention),
              byTab.dm >= 0, byTab.sys >= 0, byTab.channel >= 0,
              byTab.dm <= total, byTab.sys <= total - byTab.dm,
              byTab.channel == total - byTab.dm - byTab.sys,
              hasMention == (mentionCount > 0 ? 1 : 0) else { throw NativeChannelNotificationError.malformedResponse }
    }
}

/// Only audited endpoints. mute remains the original legacy adapter path; its
/// authority is independently supplied only after the MVC dispatcher is verified.
@MainActor public final class NativeChannelNotificationService: NativeChannelNotificationAccess {
    private let authority: NativeChannelNotificationAuthority
    private let transport: any NativeChannelNotificationDispatching
    private var operationRevision: UInt64 = 0
    public var context: RuntimeDependencyContext { authority.context }
    public var isCurrent: Bool { authority.isCurrent }
    public init(authority: NativeChannelNotificationAuthority, transport: any NativeChannelNotificationDispatching) {
        self.authority = authority; self.transport = transport
    }
    public func retireOperations() { operationRevision &+= 1 }
    public func allows(_ operation: NativeChannelNotificationOperation, scope: NativeChannelNotificationScope?) -> Bool {
        authority.allows(operation, scope: scope)
    }
    public func preferences(scope: NativeChannelNotificationScope?) async throws -> NativeChannelNotificationDirectory {
        let result: NativeChannelNotificationDirectory = try await execute(operation: scope == nil ? .directory : .preference,
            scope: scope, path: "api/im/notify-pref", query: scope.map { [URLQueryItem(name: "scope_type", value: String($0.type)), URLQueryItem(name: "scope_id", value: $0.value)] } ?? [])
        try result.validate(accountID: String(context.session.accountID))
        if let scope { guard result.list.count == 1, result.list[0].scope == scope else { throw NativeChannelNotificationError.malformedResponse } }
        return result
    }
    public func deliveryLog(query: NativeNotificationDeliveryLogQuery) async throws -> NativeNotificationDeliveryLogPage {
        let result: NativeNotificationDeliveryLogPage = try await execute(operation: .deliveryLog, scope: nil,
            path: "api/im/notify-log", query: query.queryItems)
        try result.validate(account: String(context.session.accountID), query: query); return result
    }
    public func clubDefault(scope: NativeChannelNotificationScope) async throws -> NativeClubNotificationDefault {
        guard scope.type == 2 else { throw NativeChannelNotificationError.invalidInput }
        let result: NativeClubNotificationDefault = try await execute(operation: .clubDefaultRead, scope: scope,
            path: "api/club/settings/notify-level", query: [URLQueryItem(name: "clubId", value: scope.value)])
        try result.validate(club: scope.value); return result
    }
    public func submit(_ command: NativeChannelNotificationCommand) async throws -> NativeChannelNotificationReceipt {
        try command.validate()
        let operation: NativeChannelNotificationOperation
        let path: String
        switch command.operation {
        case .mute: operation = .mute; path = "api/im/mute"
        case .ack: operation = .ack; path = "api/im/read"
        case .preference: operation = .save; path = "api/im/notify-pref"
        case .clubDefault: operation = .clubDefaultSave; path = "api/club/settings/notify-level"
        }
        let result: NativeChannelNotificationReceipt = try await execute(operation: operation, scope: command.scope, path: path, body: command.body)
        try result.validate(for: command); return result
    }
    public func receipt(_ command: NativeChannelNotificationCommand, recovery: NativeChannelNotificationRecovery?) async throws -> NativeChannelNotificationReceipt {
        try command.validate()
        try recovery?.validate(for: command)
        let lookup = recovery?.lookupPath ?? "/api/im/notification-requests/" + command.requestID
        let result: NativeChannelNotificationReceipt = try await execute(operation: .receipt, scope: command.scope,
            path: String(lookup.dropFirst()))
        try result.validate(for: command); return result
    }
    public func unreadSummary() async throws -> NativeChannelNotificationUnreadSummary {
        let result: NativeChannelNotificationUnreadSummary = try await execute(operation: .unread, scope: nil, path: "api/im/unread-summary")
        try result.validate(); return result
    }
    private func execute<Value: Decodable>(operation: NativeChannelNotificationOperation, scope: NativeChannelNotificationScope?,
        path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Value {
        guard let revision = authority.revision(operation, scope: scope) else { throw NativeChannelNotificationError.accessClosed }
        let lifecycle = operationRevision
        var parts = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { throw NativeChannelNotificationError.invalidInput }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        try Task.checkCancellation()
        try authority.check(operation, scope: scope, revision: revision)
        let fence = NativeChannelNotificationDispatchFence { [weak self] in
            guard let self, !Task.isCancelled, self.operationRevision == lifecycle else { return false }
            return self.authority.revision(operation, scope: scope) == revision
        }
        let (bytes, httpStatus) = try await transport.send(request, fence: fence)
        try Task.checkCancellation()
        guard fence.isCurrent else { throw NativeChannelNotificationError.accessClosed }
        try authority.check(operation, scope: scope, revision: revision)
        guard bytes.count <= 2 * 1024 * 1024 else { throw NativeChannelNotificationError.malformedResponse }
        let decoder = JSONDecoder()
        let header = try? decoder.decode(Header.self, from: bytes)
        guard (200..<300).contains(httpStatus), header?.code == 200,
              !([NativeChannelNotificationOperation.save, .mute, .ack, .clubDefaultSave].contains(operation) && header?.outcomeKnown == false) else {
            if let header, header.recovery != nil || header.returnPath != nil || header.requestID != nil || header.outcomeKnown != nil {
                throw NativeChannelNotificationError.serverResponse(.init(httpStatus: httpStatus, code: header.code,
                    errorCode: header.errorCode, outcomeKnown: header.outcomeKnown, requestID: header.requestID,
                    returnPath: header.returnPath, recovery: header.recovery))
            }
            throw NativeChannelNotificationError.server(httpStatus: httpStatus, code: header?.code, errorCode: header?.errorCode)
        }
        do { return try decoder.decode(Envelope<Value>.self, from: bytes).data }
        catch { throw NativeChannelNotificationError.malformedResponse }
    }
    private struct Header: Decodable {
        let code: Int
        let errorCode: String?
        let outcomeKnown: Bool?
        let requestID: String?
        let returnPath: String?
        let recovery: NativeChannelNotificationRecovery?
        enum CodingKeys: String, CodingKey { case code, errorCode, returnPath, recovery, outcomeKnown = "outcome_known", requestID = "request_id" }
    }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Narrow consumer of the host's existing source and redirect-denying transport.
/// Owns no grant, session, storage writer, retry policy or generic route allowance.
@MainActor public final class NativeChannelNotificationFinalForward: NativeChannelNotificationDispatching {
    public let authority: NativeChannelNotificationAuthority
    private let sourceFence: NativeChannelNotificationHostSource
    private let journal: NativeChannelNotificationJournal
    private let underlying: any HTTPTransport
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64,
                source: any NativeChannelNotificationAuthorizing,
                journal: NativeChannelNotificationJournal, underlying: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, viewer: @escaping () -> UInt64,
                selected: @escaping () -> (any NativeChannelNotificationAuthorizing)?) throws {
        let sourceFence = NativeChannelNotificationHostSource(context: context, viewerRevision: viewerRevision,
            source: source, current: current, viewer: viewer, selected: selected)
        let authority = try NativeChannelNotificationAuthority(context: context, source: sourceFence)
        guard authority.isCurrent, journal.owner == NativeChannelNotificationJournalOwner(context: context),
              ContentDraftContextFence.matches(current(), context), viewer() == viewerRevision,
              selected().map({ ObjectIdentifier($0) }) == ObjectIdentifier(source) else {
            throw NativeChannelNotificationError.accessClosed
        }
        self.authority = authority; self.sourceFence = sourceFence; self.journal = journal; self.underlying = underlying
    }
    private var isCurrent: Bool { authority.isCurrent }
    private struct Access {
        let operation: NativeChannelNotificationOperation
        let scope: NativeChannelNotificationScope?
        var original: NativeChannelNotificationCommand? = nil
    }
    public func send(_ request: URLRequest, fence: NativeChannelNotificationDispatchFence) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent, let access = try access(request),
              let revision = authority.revision(access.operation, scope: access.scope), fence.isCurrent else {
            throw NativeChannelNotificationError.accessClosed
        }
        // Same persisted original bytes and current operation grant are checked immediately
        // before the sole existing transport call. No re-encoding or automatic retry.
        let response = try await underlying.send(request)
        if response.1 == 401 {
            // A received unauthorized result retires only this captured source, even
            // when cancellation or identity replacement happened during the request.
            // The original source retains retirement across new wrappers/remounts.
            // Never expire a newer shared session or revoke the selected replacement.
            sourceFence.retireReceivedUnauthorized()
            throw NativeChannelNotificationError.accessClosed
        }
        guard !Task.isCancelled, isCurrent, fence.isCurrent,
              authority.revision(access.operation, scope: access.scope) == revision else {
            throw NativeChannelNotificationError.accessClosed
        }
        if let original = access.original, try journal.restore() != original {
            throw NativeChannelNotificationError.pendingCommand
        }
        return response
    }
    private func access(_ request: URLRequest) throws -> Access? {
        let context = authority.context
        guard let url = request.url, request.httpBodyStream == nil,
              url.fragment == nil, url.user == nil, url.password == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }).isSubset(of:
                ["accept", "authorization", "content-type"]) else { return nil }
        func exact(_ path: String, query: [URLQueryItem] = []) -> Bool {
            var c = URLComponents(url: context.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
            if !query.isEmpty { c?.queryItems = query }
            return c?.url?.absoluteString.utf8.elementsEqual(url.absoluteString.utf8) == true
        }
        if request.httpMethod == "GET" {
            guard request.httpBody == nil, request.value(forHTTPHeaderField: "Content-Type") == nil else { return nil }
            if exact("api/im/notify-pref") { return Access(operation: .directory, scope: nil) }
            if exact("api/im/unread-summary") { return Access(operation: .unread, scope: nil) }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let query = try? NativeNotificationDeliveryLogQuery(queryItems: items),
               exact("api/im/notify-log", query: query.queryItems) {
                return Access(operation: .deliveryLog, scope: nil)
            }
            if items.count == 2, items[0].name == "scope_type", items[1].name == "scope_id",
               let typeText = items[0].value, let type = Int(typeText), String(type) == typeText,
               let value = items[1].value, let scope = try? NativeChannelNotificationScope(type: type, value: value),
               exact("api/im/notify-pref", query: [URLQueryItem(name: "scope_type", value: String(scope.type)),
                                                   URLQueryItem(name: "scope_id", value: scope.value)]) {
                return Access(operation: .preference, scope: scope)
            }
            if items.count == 1, items[0].name == "clubId", let club = items[0].value,
               let scope = try? NativeChannelNotificationScope(type: 2, value: club),
               exact("api/club/settings/notify-level", query: [URLQueryItem(name: "clubId", value: club)]) {
                return Access(operation: .clubDefaultRead, scope: scope)
            }
            // A receipt is never inferred from the visible screen's scope or a typed key.
            if let original = try journal.restore(), exact("api/im/notification-requests/" + original.requestID) {
                return Access(operation: .receipt, scope: original.scope, original: original)
            }
            return nil
        }
        guard request.httpMethod == "POST", request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              url.query == nil, let body = request.httpBody, body.count <= 8192,
              let original = try journal.restore(), body == original.body else { return nil }
        switch original.operation {
        case .mute:
            guard exact("api/im/mute") else { return nil }
            return Access(operation: .mute, scope: original.scope, original: original)
        case .ack:
            guard exact("api/im/read") else { return nil }
            return Access(operation: .ack, scope: original.scope, original: original)
        case .clubDefault:
            guard original.scope.type == 2, exact("api/club/settings/notify-level") else { return nil }
            return Access(operation: .clubDefaultSave, scope: original.scope, original: original)
        case .preference:
            guard exact("api/im/notify-pref") else { return nil }
            return Access(operation: .save, scope: original.scope, original: original)
        }
    }
}

/// Read-through fence, not an issuer. Reuses only the supplied source's revisions;
/// retained service projections see host retirement even without another network call.
@MainActor private final class NativeChannelNotificationHostSource: NativeChannelNotificationAuthorizing {
    private let context: RuntimeDependencyContext
    private let viewerRevision: UInt64
    private let source: any NativeChannelNotificationAuthorizing
    private let capturedAuthorizationVersion: UUID?
    private let current: () -> RuntimeDependencyContext?
    private let viewer: () -> UInt64
    private let selected: () -> (any NativeChannelNotificationAuthorizing)?
    private var retired = false
    init(context: RuntimeDependencyContext, viewerRevision: UInt64, source: any NativeChannelNotificationAuthorizing,
         current: @escaping () -> RuntimeDependencyContext?, viewer: @escaping () -> UInt64,
         selected: @escaping () -> (any NativeChannelNotificationAuthorizing)?) {
        self.context = context; self.viewerRevision = viewerRevision; self.source = source
        capturedAuthorizationVersion = source.authorizationVersion
        self.current = current; self.viewer = viewer; self.selected = selected
    }
    private var isCurrent: Bool {
        guard !retired, ContentDraftContextFence.matches(current(), context), viewer() == viewerRevision,
              selected().map({ ObjectIdentifier($0) }) == ObjectIdentifier(source) else {
            retired = true; return false
        }
        return true
    }
    func retireReceivedUnauthorized() {
        guard let capturedAuthorizationVersion else { retired = true; return }
        retireAuthorization(context: context, authorizationVersion: capturedAuthorizationVersion)
    }
    func retireAuthorization(context: RuntimeDependencyContext, authorizationVersion: UUID) {
        guard ContentDraftContextFence.matches(self.context, context),
              capturedAuthorizationVersion == authorizationVersion else { return }
        retired = true
        source.retireAuthorization(context: context, authorizationVersion: authorizationVersion)
    }
    var currentContext: RuntimeDependencyContext? { isCurrent ? source.currentContext : nil }
    var authorizationVersion: UUID? { isCurrent ? source.authorizationVersion : nil }
    func authorizationRevision(for operation: NativeChannelNotificationOperation,
                               scope: NativeChannelNotificationScope?) -> UUID? {
        isCurrent ? source.authorizationRevision(for: operation, scope: scope) : nil
    }
}

import Foundation

/// Exact operation/scope key; no wildcard, role label, scope 0 or synthetic account scope.
public struct NativeChannelNotificationConfigurationKey: Hashable {
    public let operation: NativeChannelNotificationOperation
    public let scope: NativeChannelNotificationScope?
    public init(operation: NativeChannelNotificationOperation, scope: NativeChannelNotificationScope?) throws {
        switch operation {
        case .directory, .unread, .deliveryLog:
            guard scope == nil else { throw NativeChannelNotificationError.invalidInput }
        case .preference, .save, .receipt:
            guard scope != nil else { throw NativeChannelNotificationError.invalidInput }
        case .clubDefaultRead, .clubDefaultSave:
            guard scope?.type == 2 else { throw NativeChannelNotificationError.invalidInput }
        case .mute, .ack:
            guard scope?.type == 1 else { throw NativeChannelNotificationError.invalidInput }
        }
        self.operation = operation; self.scope = scope
    }
}

/// In-process, explicit configuration input from the existing reviewed host owner.
/// It is not Codable, an HTTP/RBAC proof, or an issuer. Revisions are supplied, never
/// generated here. Constructing this value does not install or enable any endpoint.
public struct NativeChannelNotificationConfigurationSnapshot {
    public let context: RuntimeDependencyContext
    public let viewerRevision: UInt64
    public let authorizationVersion: UUID
    public let expiresAt: Date
    public let operations: [NativeChannelNotificationConfigurationKey: UUID]
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64, authorizationVersion: UUID,
                expiresAt: Date, operations: [NativeChannelNotificationConfigurationKey: UUID]) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0, !context.session.namespace.isEmpty,
              AuthRequestBuilder.isValidToken(context.session.token), expiresAt.timeIntervalSince1970.isFinite,
              !operations.isEmpty,
              operations.keys.allSatisfy({ $0.scope.map { $0.belongsToAccount(String(context.session.accountID)) } ?? true }) else {
            throw NativeChannelNotificationError.invalidInput
        }
        self.context = context; self.viewerRevision = viewerRevision; self.authorizationVersion = authorizationVersion
        self.expiresAt = expiresAt; self.operations = operations
    }
    fileprivate func matches(_ other: Self) -> Bool {
        ContentDraftContextFence.matches(context, other.context) && viewerRevision == other.viewerRevision
            && authorizationVersion == other.authorizationVersion && expiresAt == other.expiresAt
            && operations == other.operations
    }
}

/// Concrete Authorizing provider bound to one explicit configuration issuance.
/// This holds no new session/permission store and creates no UUID or grant. The live
/// configuration is read through the original owner's callback on every access.
/// Retain this instance for one issuance; configure the existing Composition selector
/// with source(for:viewerRevision:). A fresh instance requires a fresh reviewed input.
@MainActor public final class NativeChannelNotificationConfiguredSource: NativeChannelNotificationAuthorizing {
    private let captured: NativeChannelNotificationConfigurationSnapshot
    private let current: () -> NativeChannelNotificationConfigurationSnapshot?
    private let now: () -> Date
    private var retired = false
    public init(snapshot: NativeChannelNotificationConfigurationSnapshot,
                current: @escaping () -> NativeChannelNotificationConfigurationSnapshot?,
                now: @escaping () -> Date = Date.init) throws {
        guard snapshot.expiresAt > now(), let live = current(), snapshot.matches(live) else {
            throw NativeChannelNotificationError.accessClosed
        }
        captured = snapshot; self.current = current; self.now = now
    }
    private var live: NativeChannelNotificationConfigurationSnapshot? {
        guard !retired, captured.expiresAt > now(), let value = current(), captured.matches(value) else {
            retired = true; return nil
        }
        return value
    }
    public func source(for context: RuntimeDependencyContext, viewerRevision: UInt64) -> (any NativeChannelNotificationAuthorizing)? {
        guard let live, ContentDraftContextFence.matches(live.context, context), live.viewerRevision == viewerRevision else { return nil }
        return self
    }
    public func retireAuthorization(context: RuntimeDependencyContext, authorizationVersion: UUID) {
        guard ContentDraftContextFence.matches(captured.context, context),
              captured.authorizationVersion == authorizationVersion else { return }
        retired = true
    }
    public var currentContext: RuntimeDependencyContext? { live?.context }
    public var authorizationVersion: UUID? { live?.authorizationVersion }
    public func authorizationRevision(for operation: NativeChannelNotificationOperation,
                                      scope: NativeChannelNotificationScope?) -> UUID? {
        guard let live, let key = try? NativeChannelNotificationConfigurationKey(operation: operation, scope: scope) else { return nil }
        return live.operations[key]
    }
}

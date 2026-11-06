import Foundation

public enum NativeChannelNotificationOperation: Hashable {
    case directory, preference, save, mute, receipt, unread, ack, clubDefaultRead, clubDefaultSave, deliveryLog
}

/// Implemented by the existing session/endpoint authority owner, never by a view.
/// A nonnil revision must come from its real current authorization source and
/// rotate on replacement/revocation. No role-name, login or OS-permission inference.
@MainActor public protocol NativeChannelNotificationAuthorizing: AnyObject {
    var currentContext: RuntimeDependencyContext? { get }
    /// Dedicated source version; not metadataVersion, perm_version or session epoch.
    var authorizationVersion: UUID? { get }
    func authorizationRevision(for operation: NativeChannelNotificationOperation,
                               scope: NativeChannelNotificationScope?) -> UUID?
    /// Received HTTP401 retires only the matching original issuance. Implementations
    /// must preserve that retirement across normal host remounts, and must not retire
    /// a replacement context/version or clear its journal. No default no-op exists.
    func retireAuthorization(context: RuntimeDependencyContext, authorizationVersion: UUID)
}

@MainActor public final class NativeChannelNotificationAuthority {
    public let context: RuntimeDependencyContext
    private let source: any NativeChannelNotificationAuthorizing
    private let capturedAuthorizationVersion: UUID?
    private struct Key: Hashable { let operation: NativeChannelNotificationOperation; let scope: NativeChannelNotificationScope? }
    private var capturedRevisions: [Key: UUID] = [:]
    private var invalidated = false
    public init(context: RuntimeDependencyContext, source: any NativeChannelNotificationAuthorizing) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0,
              !context.session.namespace.isEmpty, AuthRequestBuilder.isValidToken(context.session.token) else {
            throw NativeChannelNotificationError.accessClosed
        }
        self.context = context; self.source = source
        capturedAuthorizationVersion = source.authorizationVersion
    }
    public var isCurrent: Bool {
        guard !invalidated else { return false }
        guard capturedAuthorizationVersion != nil,
              source.authorizationVersion == capturedAuthorizationVersion,
              ContentDraftContextFence.matches(source.currentContext, context),
              capturedRevisions.allSatisfy({ key, revision in
                  source.authorizationRevision(for: key.operation, scope: key.scope) == revision
              }) else {
            // Once this captured authority observes replacement/revocation, it cannot
            // revive cached projections if the source later returns the old values.
            // A freshly authorized flow may still recover the original protected journal.
            invalidated = true
            return false
        }
        return true
    }
    public func revision(_ operation: NativeChannelNotificationOperation, scope: NativeChannelNotificationScope?) -> UUID? {
        guard isCurrent,
              scope.map({ $0.belongsToAccount(String(context.session.accountID)) }) ?? true,
              (operation != .mute && operation != .ack) || scope?.type == 1 else { return nil }
        let key = Key(operation: operation, scope: scope)
        guard let revision = source.authorizationRevision(for: operation, scope: scope) else { return nil }
        if let captured = capturedRevisions[key], captured != revision { invalidated = true; return nil }
        capturedRevisions[key] = revision
        return revision
    }
    public func allows(_ operation: NativeChannelNotificationOperation, scope: NativeChannelNotificationScope?) -> Bool {
        revision(operation, scope: scope) != nil
    }
    public func check(_ operation: NativeChannelNotificationOperation, scope: NativeChannelNotificationScope?, revision: UUID) throws {
        guard self.revision(operation, scope: scope) == revision else { throw NativeChannelNotificationError.accessClosed }
    }
}

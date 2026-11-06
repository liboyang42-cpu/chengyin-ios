import Foundation

/// A retained consumer of one existing authority issuance, not a role/grant issuer.
/// The reviewed configuration owner must retain this instance for that issuance.
/// Every credential and revision is supplied by the original source; none is generated.
@MainActor public final class NativeChannelMessageHostAuthority: NativeChannelMessageAuthorizing {
    public let context: RuntimeDependencyContext
    public let viewerRevision: UInt64
    public let binding: NativeChannelMessageBinding
    private let source: any NativeChannelMessageAuthorizing
    private let current: () -> RuntimeDependencyContext?
    private let viewer: () -> UInt64
    private let selected: () -> (any NativeChannelMessageAuthorizing)?
    private let captured: [NativeChannelMessageCapability: NativeChannelMessageCredentials]
    private var retired = false
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64, binding: NativeChannelMessageBinding,
                source: any NativeChannelMessageAuthorizing, current: @escaping () -> RuntimeDependencyContext?,
                viewer: @escaping () -> UInt64, selected: @escaping () -> (any NativeChannelMessageAuthorizing)?) throws {
        let identity = MessagingReadIdentity(accountID: context.session.accountID, epoch: context.session.epoch)
        guard context.market == .china, context.session.accountID > 0, source.identity == identity,
              ContentDraftContextFence.matches(current(), context), viewer() == viewerRevision,
              selected().map({ ObjectIdentifier($0) }) == ObjectIdentifier(source) else { throw APIError.notConfigured }
        var values: [NativeChannelMessageCapability: NativeChannelMessageCredentials] = [:]
        let capabilities: [NativeChannelMessageCapability] = [.receipt, .mutations, .revisions, .pins, .search, .context]
            + NativeChannelMessageOperation.allCases.map { .mutate($0) }
        for capability in capabilities {
            if let credentials = try? source.credentials(for: capability, binding: binding) {
                guard Self.matches(credentials, context: context, binding: binding) else { throw APIError.notConfigured }
                values[capability] = credentials
            }
        }
        guard values[.receipt] != nil || values[.mutations] != nil else { throw APIError.notConfigured }
        self.context = context; self.viewerRevision = viewerRevision; self.binding = binding
        self.source = source; self.current = current; self.viewer = viewer; self.selected = selected; captured = values
    }
    public var identity: MessagingReadIdentity? {
        guard !retired, ContentDraftContextFence.matches(current(), context), viewer() == viewerRevision,
              source.identity == MessagingReadIdentity(accountID: context.session.accountID, epoch: context.session.epoch),
              selected().map({ ObjectIdentifier($0) }) == ObjectIdentifier(source) else { retired = true; return nil }
        return source.identity
    }
    public func credentials(for capability: NativeChannelMessageCapability,
                            binding: NativeChannelMessageBinding) throws -> NativeChannelMessageCredentials {
        guard identity != nil, Self.sameBinding(self.binding, binding), let original = captured[capability] else { throw APIError.notConfigured }
        guard let live = try? source.credentials(for: capability, binding: binding), Self.same(original, live) else {
            retired = true; throw APIError.notConfigured
        }
        return original
    }
    /// Conditional retirement is retained across normal remounts of this exact issuance.
    /// It never selects or retires a replacement source, and never logs out a shared session.
    public func retireReceivedUnauthorized(_ credentials: NativeChannelMessageCredentials) {
        guard captured.values.contains(where: { Self.same($0, credentials) }) else { return }
        retired = true
    }
    /// Called only when the normal host observed this retained source being replaced.
    /// Screen disappearance alone must not call this or discard receipt recovery.
    public func retireObservedSelection() { retired = true }
    public static func same(_ a: NativeChannelMessageCredentials, _ b: NativeChannelMessageCredentials) -> Bool {
        a.identity == b.identity && sameBinding(a.binding, b.binding)
            && a.namespace.utf8.elementsEqual(b.namespace.utf8)
            && a.baseURL.absoluteString.utf8.elementsEqual(b.baseURL.absoluteString.utf8)
            && a.authorityRevision.utf8.elementsEqual(b.authorityRevision.utf8)
            && a.token.utf8.elementsEqual(b.token.utf8)
    }
    private static func sameBinding(_ a: NativeChannelMessageBinding, _ b: NativeChannelMessageBinding) -> Bool {
        a.sameTarget(as: b) && a.mappingRevision.utf8.elementsEqual(b.mappingRevision.utf8)
    }
    private static func matches(_ value: NativeChannelMessageCredentials, context: RuntimeDependencyContext,
                                binding: NativeChannelMessageBinding) -> Bool {
        value.identity == MessagingReadIdentity(accountID: context.session.accountID, epoch: context.session.epoch)
            && sameBinding(value.binding, binding) && value.namespace.utf8.elementsEqual(context.session.namespace.utf8)
            && value.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8)
            && value.token.utf8.elementsEqual(context.session.token.utf8)
    }
}

import Foundation

/// Read-only composition of the real channel reader with original 8's sole scope contract.
/// The upstream provider must be issued by the native/RBAC/catalogue source owner.
/// This adapter does not construct NativeWebhookBinding, authorizationVersion, events or grants.
@MainActor public final class NativeChannelManagementWebhookScopeAdapter: NativeWebhookScopeProvider {
    private let channels: any NativeChannelManagementIntegrationContextProviding
    private let channelID: NativeChannelManagementID
    private let upstream: (any NativeWebhookScopeProvider)?
    private var capturedChannel: NativeChannelManagementIntegrationContext?
    private var capturedBinding: NativeWebhookBinding?
    private var retired = false
    public init(channels: any NativeChannelManagementIntegrationContextProviding, channelID: NativeChannelManagementID,
                upstream: (any NativeWebhookScopeProvider)? = nil) {
        self.channels = channels; self.channelID = channelID; self.upstream = upstream
    }
    /// Resolves only the existing CLUB/channel scope type; it establishes no native/RBAC authority.
    public static func scope(from channel: NativeChannelManagementIntegrationContext) throws -> NativeWebhookScope {
        guard channel.ownerType == "CLUB", channel.serverPermissionNames.isSuperset(of: ["VIEW_CHANNEL", "READ_HISTORY", "MANAGE_WEBHOOKS"]),
              let owner = NativeWebhookID(rawValue: channel.ownerID.rawValue),
              let id = NativeWebhookID(rawValue: channel.channelID.rawValue) else {
            throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_REAL_CHANNEL_MANAGEMENT_CONTEXT_UNAVAILABLE")
        }
        return NativeWebhookScope(ownerID: owner, channelID: id)
    }
    public func currentContext() async throws -> NativeWebhookContext {
        let channel = try await currentChannel()
        guard let upstream else {
            throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_NATIVE_RBAC_AUTHORIZATION_VERSION_SOURCE_UNAVAILABLE")
        }
        let value = try await upstream.currentContext()
        try await validate(value, channel: channel)
        return value // Original context, original authorizationVersion and original eventCatalogue, unchanged.
    }
    public func revalidate(_ binding: NativeWebhookBinding) async throws -> NativeWebhookContext {
        let channel = try await currentChannel()
        guard let upstream else {
            throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_NATIVE_RBAC_AUTHORIZATION_VERSION_SOURCE_UNAVAILABLE")
        }
        let value = try await upstream.revalidate(binding)
        guard value.binding == binding else { retired = true; throw NativeWebhookClientError.scopeChanged }
        try await validate(value, channel: channel)
        return value
    }
    private func currentChannel() async throws -> NativeChannelManagementIntegrationContext {
        guard !retired else { throw NativeWebhookClientError.scopeChanged }
        let channel: NativeChannelManagementIntegrationContext
        do { channel = try await channels.currentChannelContext(channelID: channelID) }
        catch { retired = true; throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_CURRENT_CHANNEL_SOURCE_UNAVAILABLE") }
        guard channels.contextIsCurrent(channel), channel.channelID == channelID,
              capturedChannel == nil || capturedChannel == channel else {
            retired = true; throw NativeWebhookClientError.scopeChanged
        }
        _ = try Self.scope(from: channel)
        return channel
    }
    private func validate(_ value: NativeWebhookContext, channel: NativeChannelManagementIntegrationContext) async throws {
        let fresh = try await currentChannel()
        guard fresh == channel, channels.contextIsCurrent(channel), value.binding.scope == (try Self.scope(from: channel)),
              value.binding.accountID == String(channel.identity.owner.accountID),
              value.binding.market == RegionalMarket.china.rawValue,
              value.binding.namespace.utf8.elementsEqual(channel.identity.owner.namespace.utf8),
              value.binding.origin.absoluteString.utf8.elementsEqual(channel.identity.owner.baseURL.utf8),
              !value.binding.authorizationVersion.isEmpty,
              capturedBinding == nil || capturedBinding == value.binding else {
            retired = true; throw NativeWebhookClientError.scopeChanged
        }
        // No fallback version or example event catalogue is created, including an empty "available" catalogue.
        if case .available(let revision, let options) = value.eventCatalogue,
           revision.isEmpty || options.isEmpty {
            throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_REGISTERED_EVENT_CATALOGUE_UNAVAILABLE")
        }
        capturedChannel = channel; capturedBinding = value.binding
    }
}

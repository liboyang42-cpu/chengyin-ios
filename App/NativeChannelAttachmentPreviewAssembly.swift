import Foundation

/// The original authenticated descriptor and its credential-free object download
/// are separate channels. Never route an OSS URL through generic API composition.
@MainActor enum NativeChannelAttachmentPreviewAssembly {
    static func make(message: MessagingMessage, configuration: APIConfiguration,
                     factory: BusinessRuntimeFactory,
                     currentFactory: @escaping () -> BusinessRuntimeFactory?,
                     current: @escaping () -> Bool, unauthorized: @escaping () -> Void,
                     mediaTransport: (any HTTPTransport)? = nil) -> NativeChannelAttachmentPreviewFlow? {
        let context = factory.captured
        guard configuration.baseURL == context.baseURL, message.id > 0, message.type == 2,
              let scope = try? IMScope(identity: .init(accountID: context.session.accountID,
                  epoch: context.session.epoch), conversationID: message.conversationID),
              let route = try? BusinessRuntimeRoute(method: "GET", path: "api/im/message/\(message.id)/attachment") else { return nil }
        let issued = factory.routes([.imChannelAttachmentPreview])
        let origins = factory.configuration.imMediaOrigins
        let enabled = issued.contains(route) && !origins.isEmpty &&
            origins.allSatisfy { ObjectCardMediaPolicy.origin($0) == $0 }
        let active: () -> Bool = {
            guard current(), let live = currentFactory(), live.captured == context else { return false }
            // Configuration withdrawal must revoke this retained page even when the
            // account, token and runtime epoch have not changed. Never silently renew.
            return live.routes([.imChannelAttachmentPreview]) == issued && live.configuration.imMediaOrigins == origins
        }
        let media = SocialReaderApprovedMediaTransport(origins: origins, captured: context,
            transport: mediaTransport ?? boundedMediaTransport(enabled: enabled),
            current: { active() ? context : nil })
        return NativeChannelAttachmentPreviewFlow(messageID: message.id, scope: scope, configuration: configuration,
            api: factory.client([.imChannelAttachmentPreview]), media: media, origins: origins, enabled: enabled,
            token: { active() ? context.session.token : nil }, current: active,
            unauthorized: { if active() { unauthorized() } })
    }
    /// Construction is inert. The exact-origin/current adapter above is the only caller.
    static func boundedMediaTransport(enabled: Bool) -> ResponseLimitedHTTPTransport {
        ResponseLimitedHTTPTransport(enabled: enabled, maximumResponseBytes: SocialMessageMediaService.maximumBytes)
    }
}

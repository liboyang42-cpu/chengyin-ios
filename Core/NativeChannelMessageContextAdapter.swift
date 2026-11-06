import Foundation

/// Consumes owner43's exact protocol. The original host must separately supply its
/// actual MessagingConversation projection; this adapter never invents that DTO.
@MainActor public final class NativeChannelMessageContextAdapter {
    private let source: any NativeChannelManagementIntegrationContextProviding
    public init(source: any NativeChannelManagementIntegrationContextProviding) { self.source = source }
    public func binding(channelID: NativeChannelManagementID, conversation: MessagingConversation) async throws -> NativeChannelMessageBinding {
        let context = try await source.currentChannelContext(channelID: channelID)
        guard source.contextIsCurrent(context), context.channelID == channelID, ["CLUB", "TEAM"].contains(context.ownerType),
              let channel = NativeChannelMessageID(rawValue: context.channelID.rawValue),
              let originalConversation = NativeChannelMessageID(rawValue: String(conversation.id)),
              // This equality is checked AFTER reading a true channel and receiving the real
              // original projection; a conversation alone never constructs a channel.
              originalConversation == channel else { throw APIError.notConfigured }
        // Metadata and permission versions remain distinct, and neither is an auth grant.
        let revision = "\(context.sourcePath)|metadata:\(context.metadataVersion.value)|permission:\(context.permissionVersion.value)"
        return try .init(channelID: channel, conversationID: originalConversation, mappingRevision: revision)
    }
}

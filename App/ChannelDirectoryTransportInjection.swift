import Foundation

/// One already selected channel and its space, carried into the directory request.
/// A conversation id is not a channel id. Kind is the guild kind, not a rules version.
struct ChannelDirectorySelection: Equatable {
    let channelID: Int
    let spaceID: Int64
    let kind: Int
}

/// Turns that selection plus the caller's original transport into one directory request.
/// It does not send, does not read a history-read grant, does not call
/// `api/native/spaces/admission`, and does not invent a token, a version, or a grant.
enum ChannelDirectoryTransportInjection {
    static func request(configuration: APIConfiguration, transport: any HTTPTransport, token: String,
                        accountID: Int, epoch: UInt64, channelID: Int, spaceID: Int64, kind: Int) -> ChannelDirectoryAdmissionRequest? {
        request(configuration: configuration, transport: transport, token: token,
                accountID: accountID, epoch: epoch,
                selection: ChannelDirectorySelection(channelID: channelID, spaceID: spaceID, kind: kind))
    }

    static func request(configuration: APIConfiguration, transport: any HTTPTransport, token: String,
                        accountID: Int, epoch: UInt64, selection: ChannelDirectorySelection) -> ChannelDirectoryAdmissionRequest? {
        guard selection.channelID > 0, selection.spaceID > 0, selection.kind == 1 || selection.kind == 3,
              accountID > 0, AuthRequestBuilder.isValidToken(token) else { return nil }
        return ChannelDirectoryAdmissionRequest(
            configuration: configuration, transport: transport, token: token,
            accountID: accountID, epoch: epoch,
            channelID: selection.channelID, spaceID: selection.spaceID, kind: selection.kind)
    }
}

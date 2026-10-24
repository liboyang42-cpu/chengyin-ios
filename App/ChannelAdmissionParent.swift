import Foundation

/// Session transport plus the space being opened. The catalog is read, not supplied.
struct ChannelDirectoryAdmissionRequest {
    let configuration: APIConfiguration
    let transport: any HTTPTransport
    let token: String
    let accountID: Int
    let epoch: UInt64
    let channelID: Int
    let spaceID: Int64
    let kind: Int
}

/// Group management loads the current catalog from the directory detail, then opens the page.
@MainActor enum ChannelAdmissionParent {
    static func page(configuration: APIConfiguration, transport: any HTTPTransport, token: String,
                     accountID: Int, epoch: UInt64, channelID: Int, spaceID: Int64, kind: Int) async throws -> ChannelAdmissionGovernanceView {
        let catalog = try await ChannelDirectoryCatalogProducer.catalog(
            configuration: configuration, transport: transport, token: token,
            channelID: channelID, spaceID: spaceID, kind: kind)
        return try ChannelAdmissionGovernanceEntry.make(
            configuration: configuration, transport: transport, token: token,
            accountID: accountID, epoch: epoch, catalog: catalog, kind: kind, spaceID: spaceID)
    }
}

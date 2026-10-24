import Foundation

/// Opens the received admission page from the same current catalog the factory admits.
/// The transport is the one the caller already holds. This does not read AppSession,
/// does not invent a rules version, and does not send.
enum ChannelAdmissionGovernanceEntry {
    @MainActor static func make(
        configuration: APIConfiguration,
        transport: any HTTPTransport,
        token: String,
        accountID: Int,
        epoch: UInt64,
        catalog: ChannelCatalogEntry,
        kind: Int,
        spaceID: Int64
    ) throws -> ChannelAdmissionGovernanceView {
        guard kind == 1 || kind == 3, spaceID > 0 else { throw ChannelAuthorizationError.invalidCatalog }
        let client = try ChannelAdmissionGovernanceFactory.client(
            configuration: configuration, transport: transport, token: token,
            accountID: accountID, epoch: epoch, catalog: catalog)
        return ChannelAdmissionGovernanceView(client: client, catalog: catalog, kind: kind, spaceID: spaceID)
    }
}

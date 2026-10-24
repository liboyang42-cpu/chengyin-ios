import Foundation

/// Builds the original admission client from an already resolved account and catalog.
/// The consented version is the catalog's published rules version. A stale snapshot
/// is refused. This does not read AppSession, does not invent a version, does not
/// borrow another domain's permission, and does not send by itself.
public enum ChannelAdmissionGovernanceFactory {
    public static func client(
        configuration: APIConfiguration,
        transport: any HTTPTransport,
        token: String,
        accountID: Int,
        epoch: UInt64,
        catalog: ChannelCatalogEntry
    ) throws -> ChannelAdmissionGovernanceClient {
        let identity = try ChannelAccount4Identity(accountID: accountID, epoch: epoch)
        let admission = try ChannelRulesAdmission(
            identity: identity, consentedVersion: catalog.rules.publishedVersion)
        _ = try admission.admit(identity: identity, catalog: catalog)
        return try ChannelAdmissionGovernanceClient(
            configuration: configuration, transport: transport, token: token, admission: admission)
    }
}

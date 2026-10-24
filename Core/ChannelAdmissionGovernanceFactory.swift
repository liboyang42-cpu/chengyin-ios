import Foundation

/// Builds the original admission client from an already resolved account.
/// It does not read AppSession, does not invent an approval, and does not enable writes by itself.
public enum ChannelAdmissionGovernanceFactory {
    public static func client(
        configuration: APIConfiguration,
        transport: any HTTPTransport,
        token: String,
        accountID: Int,
        epoch: UInt64,
        consentedVersion: Int
    ) throws -> ChannelAdmissionGovernanceClient {
        let identity = try ChannelAccount4Identity(accountID: accountID, epoch: epoch)
        let admission = try ChannelRulesAdmission(identity: identity, consentedVersion: consentedVersion)
        return try ChannelAdmissionGovernanceClient(
            configuration: configuration, transport: transport, token: token, admission: admission)
    }
}

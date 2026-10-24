import Foundation

/// Rules-consent gate over existing P04 dual-version CAS. Join is admitted only
/// against the published rules version captured by the catalog snapshot.
public struct ChannelRulesAdmission: Equatable, Sendable {
    public let identity: ChannelAccount4Identity
    public let consentedVersion: Int
    public init(identity: ChannelAccount4Identity, consentedVersion: Int) throws {
        guard consentedVersion > 0 else { throw ChannelAuthorizationError.rulesCASConflict }
        self.identity = identity
        self.consentedVersion = consentedVersion
    }

    /// Pending rules cannot admit a member. A stale expectedVersion is a CAS
    /// conflict against the existing P04 writer, not a missing contract.
    public func admit(identity: ChannelAccount4Identity, catalog: ChannelCatalogEntry) throws -> Int {
        guard identity == self.identity else { throw ChannelAuthorizationError.account4Mismatch }
        let cas = catalog.rules
        guard cas.isCurrent else { throw ChannelAuthorizationError.rulesCASConflict }
        if let pending = cas.pendingVersion, consentedVersion == pending {
            throw ChannelAuthorizationError.rulesCASConflict
        }
        guard consentedVersion == cas.publishedVersion else { throw ChannelAuthorizationError.rulesConsentRequired }
        return cas.publishedVersion
    }
}

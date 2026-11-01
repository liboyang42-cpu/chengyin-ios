import Foundation

/// Qualification loss clears public/private NPC caches so an old draft cannot serve.
@MainActor public final class MerchantNPCQualificationRevoke {
    private var revoked: Set<String> = []
    private var publicCache: [String: MerchantNPCPublishedRevision] = [:]
    private var privateDrafts: [String: MerchantNPCKnowledgeDraft] = [:]
    public init() {}
    public func key(_ scope: MerchantNPCScope) -> String {
        "merchant-npc-qual:\(scope.namespace.utf8.count):\(scope.namespace):account:\(scope.accountID):row:\(scope.merchantRowID.rawValue)"
    }
    public func rememberPrivate(_ draft: MerchantNPCKnowledgeDraft, scope: MerchantNPCScope) {
        guard !isRevoked(scope) else { return }
        privateDrafts[key(scope)] = draft
    }
    public func rememberPublished(_ revision: MerchantNPCPublishedRevision, scope: MerchantNPCScope) {
        guard !isRevoked(scope), revision.scope == scope else { return }
        publicCache[key(scope)] = revision
        privateDrafts[key(scope)] = nil
    }
    public func revoke(_ scope: MerchantNPCScope) {
        let identity = key(scope)
        revoked.insert(identity)
        publicCache[identity] = nil
        privateDrafts[identity] = nil
    }
    public func isRevoked(_ scope: MerchantNPCScope) -> Bool { revoked.contains(key(scope)) }
    public func allowsServing(_ scope: MerchantNPCScope) -> Bool { !isRevoked(scope) }
    public func cachedPublic(_ scope: MerchantNPCScope) -> MerchantNPCPublishedRevision? {
        guard !isRevoked(scope) else { return nil }
        return publicCache[key(scope)]
    }
    public func cachedPrivate(_ scope: MerchantNPCScope) -> MerchantNPCKnowledgeDraft? {
        guard !isRevoked(scope) else { return nil }
        return privateDrafts[key(scope)]
    }
}

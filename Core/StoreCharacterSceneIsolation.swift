import Foundation

/// W04 knowledge isolation for the store character page. Knowledge typed here is store-public
/// fact text: it may reach only the store public NPC scope, never a theme binding, the merchant's
/// private assistant or a creator scope. This helper builds nothing that is sent.
public enum StoreCharacterKnowledgeIsolation {
    public static let dataClass: SceneAIDataClass = .approvedStoreFacts
    public static let scenario: SceneAIScenario = .storePublicNPC
    public static func mayReceive(_ scope: SceneAIScope) -> Bool {
        guard scope.isValid, case .storePublic = scope else { return false }
        return scope.scenario.allowedData.contains(dataClass)
    }
    public static func storePublicScope(merchantID: String, storeID: String) -> SceneAIScope? {
        let scope = SceneAIScope.storePublic(merchantID: merchantID, storeID: storeID)
        return scope.isValid ? scope : nil
    }
    /// Scopes that the source knowledge field must never feed, even for the same merchant.
    public static func excluded(_ scope: SceneAIScope) -> Bool { !mayReceive(scope) }
}

/// W04 scope projection: store public mode vs a server-derived theme binding. The theme binding
/// comes only from the server's session response; a client theme hint is compared, never used.
public struct StoreCharacterSceneProjection: Equatable {
    public enum ThemeBinding: Equatable {
        case notBound
        case bound(isolationKey: String)
        case hintMismatch
    }
    public let storePublicKey: String?
    public let themeBinding: ThemeBinding
    public let storeMode: SceneAIAvailability.Mode
    public let themeMode: SceneAIAvailability.Mode?
    public let knowledgeReachesTheme: Bool
    public init(merchantID: String, storeID: String, serverBinding: ThemeNPCSessionScope?, clientThemeHint: String?,
                availability: SceneAIAvailability = .disabled) {
        let store = StoreCharacterKnowledgeIsolation.storePublicScope(merchantID: merchantID, storeID: storeID)
        storePublicKey = store?.isolationKey
        storeMode = store.map(availability.mode(for:)) ?? .nonGenerative(reasonKey: "sceneAI.unavailable.unsupported")
        if let binding = serverBinding, binding.merchantID == merchantID {
            if binding.agrees(withClientThemeHint: clientThemeHint) {
                let scope = SceneAIScope.themeBinding(binding)
                themeBinding = .bound(isolationKey: scope.isolationKey)
                themeMode = availability.mode(for: scope)
            } else { themeBinding = .hintMismatch; themeMode = nil }
        } else { themeBinding = serverBinding == nil ? .notBound : .hintMismatch; themeMode = nil }
        knowledgeReachesTheme = serverBinding.map { StoreCharacterKnowledgeIsolation.mayReceive(.themeBinding($0)) } ?? false
    }
    /// Two modes of one merchant never share a cache/transcript key.
    public var sharesIsolation: Bool {
        guard let storePublicKey, case .bound(let key) = themeBinding else { return false }
        return key == storePublicKey
    }
}

/// W05 merchant AI draft status: blockers only. No generate, save, submit or publish route exists.
public struct StoreCharacterAIDraftStatus: Equatable {
    public let stage: MerchantAuthoringStage
    public let blockers: [MerchantPublishBlocker]
    public var canPublish: Bool { blockers.isEmpty }
    public init(revision: MerchantAuthoringRevision, gates: MerchantCityNPCParityGates) {
        stage = revision.stage
        // Publishing is never wired from this page, so the capability is off even with the gate on.
        blockers = MerchantAuthoringGuard.publishBlockers(revision, capabilityEnabled: gates.merchantAIDrafts && Self.publishRouteRegistered)
    }
    public static let publishRouteRegistered = false
}

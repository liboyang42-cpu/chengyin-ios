import Foundation

/// Reform plan v9 §7–8 / W04.0–W04.4, W04.8. Client contract only: the server derives the
/// principal, scenario and theme/release/run/binding from held participation. Nothing here
/// authorizes a request; it refuses to send, cache or display anything whose scope is not exact.
/// No host, provider, model name, prompt or credential lives in this file.
public enum SceneAIScenario: String, CaseIterable, Sendable {
    case platformBackoffice = "PLATFORM_BACKOFFICE"
    case creatorPlayer = "CREATOR_PLAYER"
    case merchantPrivateAssistant = "MERCHANT_PRIVATE_ASSISTANT"
    case storePublicNPC = "STORE_PUBLIC_NPC"
    case themeDirectorNPC = "THEME_DIRECTOR_NPC"

    /// Only bizTypes already registered in the backend AiSceneRouter. An unregistered bizType is
    /// served by a mock fallback there, so an empty set means the App must not send at all.
    public var registeredBizTypes: Set<String> {
        switch self {
        case .platformBackoffice: return []
        case .creatorPlayer: return ["theme_draft", "node_generate", "chapter_overview", "template_fill", "club_design"]
        case .merchantPrivateAssistant: return ["merchant_plan", "merchant_task_suggest", "merchant_insight"]
        case .storePublicNPC: return ["merchant_npc_chat"]
        case .themeDirectorNPC: return ["npc_chat"]
        }
    }
    /// Back-office AI is staff tooling; the App has no entry for it.
    public var availableInApp: Bool { self != .platformBackoffice }
    /// The minimum data classes this scenario may receive (§7 table). Advisory for the client's
    /// own request assembly; the server's projection/ACL is the enforcement point.
    public var allowedData: Set<SceneAIDataClass> {
        switch self {
        case .platformBackoffice: return []
        case .creatorPlayer: return [.licensedPlayLibrary, .ownDrafts]
        case .merchantPrivateAssistant: return [.approvedStoreFacts, .privateStoreOperations]
        case .storePublicNPC: return [.approvedStoreFacts]
        case .themeDirectorNPC: return [.approvedStoreFacts, .currentRunState, .unlockedClues, .approvedBranches]
        }
    }
    public var forbiddenData: Set<SceneAIDataClass> { Set(SceneAIDataClass.allCases).subtracting(allowedData) }
}

public enum SceneAIDataClass: String, CaseIterable, Sendable {
    case licensedPlayLibrary = "LICENSED_PLAY_LIBRARY"
    case ownDrafts = "OWN_DRAFTS"
    case othersPrivateDrafts = "OTHERS_PRIVATE_DRAFTS"
    case unpurchasedAnswers = "UNPURCHASED_ANSWERS"
    case approvedStoreFacts = "APPROVED_STORE_FACTS"
    /// Sales, staff, customers, layout and process: merchant-private assistant only.
    case privateStoreOperations = "PRIVATE_STORE_OPERATIONS"
    case merchantPriceFloor = "MERCHANT_PRICE_FLOOR"
    case currentRunState = "CURRENT_RUN_STATE"
    case unlockedClues = "UNLOCKED_CLUES"
    case lockedCluesAndEndings = "LOCKED_CLUES_AND_ENDINGS"
    case approvedBranches = "APPROVED_BRANCHES"
    case otherThemeContent = "OTHER_THEME_CONTENT"
    case otherPlayerMemory = "OTHER_PLAYER_MEMORY"
    case backofficeDrafts = "BACKOFFICE_DRAFTS"
}

/// Theme binding scope (W04.1). Every field comes from the server's session/open response;
/// a client-held theme ID is only compared, never used to build this value.
public struct ThemeNPCSessionScope: Hashable, Sendable {
    public enum Actor: String, Sendable { case player = "PLAYER", team = "TEAM" }
    public let actorType: Actor
    public let actorID: String
    public let merchantID: String
    public let themeID: String
    public let releaseID: String
    public let runID: String
    public let bindingID: String
    public init?(actorType: Actor, actorID: String, merchantID: String, themeID: String, releaseID: String, runID: String, bindingID: String) {
        guard [actorID, merchantID, themeID, releaseID, runID, bindingID].allSatisfy(SceneAIScope.validComponent) else { return nil }
        self.actorType = actorType; self.actorID = actorID; self.merchantID = merchantID
        self.themeID = themeID; self.releaseID = releaseID; self.runID = runID; self.bindingID = bindingID
    }
    /// Consistency check only. A matching hint does not grant access; a mismatch fails closed.
    public func agrees(withClientThemeHint hint: String?, releaseHint: String? = nil) -> Bool {
        (hint == nil || hint == themeID) && (releaseHint == nil || releaseHint == releaseID)
    }
}

/// One isolation scope per scenario (W04.0). Caches, transcripts and memory are keyed by
/// `isolationKey`, so two themes of the same merchant or a store's public and private modes
/// can never share an entry.
public enum SceneAIScope: Hashable, Sendable {
    case creator(accountID: String)
    case merchantPrivate(merchantID: String, storeID: String, operatorID: String)
    case storePublic(merchantID: String, storeID: String)
    case themeBinding(ThemeNPCSessionScope)

    public var scenario: SceneAIScenario {
        switch self {
        case .creator: return .creatorPlayer
        case .merchantPrivate: return .merchantPrivateAssistant
        case .storePublic: return .storePublicNPC
        case .themeBinding: return .themeDirectorNPC
        }
    }
    public var isValid: Bool {
        switch self {
        case .creator(let account): return Self.validComponent(account)
        case .merchantPrivate(let merchant, let store, let op): return [merchant, store, op].allSatisfy(Self.validComponent)
        case .storePublic(let merchant, let store): return [merchant, store].allSatisfy(Self.validComponent)
        case .themeBinding: return true
        }
    }
    /// Length-prefixed so that no component value can collide with a separator.
    public var isolationKey: String {
        let parts: [String]
        switch self {
        case .creator(let account): parts = [account]
        case .merchantPrivate(let merchant, let store, let op): parts = [merchant, store, op]
        case .storePublic(let merchant, let store): parts = [merchant, store]
        case .themeBinding(let s): parts = [s.actorType.rawValue, s.actorID, s.merchantID, s.themeID, s.releaseID, s.runID, s.bindingID]
        }
        return ([scenario.rawValue] + parts).map { "\($0.utf8.count):\($0)" }.joined()
    }
    static func validComponent(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.trimmingCharacters(in: .whitespacesAndNewlines) == value
    }
}

/// Server echo attached to every AI reply (W04.8 audit linkage). A reply is shown only when its
/// echoed scope is the exact scope the request was sent for and every version field is present.
public struct SceneAIReplyEcho: Equatable, Sendable {
    public let scenario: SceneAIScenario
    public let isolationKey: String
    public let traceID: String
    public let policyVersion: String
    public let promptVersion: String
    public let releaseID: String?
    public init(scenario: SceneAIScenario, isolationKey: String, traceID: String, policyVersion: String, promptVersion: String, releaseID: String?) {
        self.scenario = scenario; self.isolationKey = isolationKey; self.traceID = traceID
        self.policyVersion = policyVersion; self.promptVersion = promptVersion; self.releaseID = releaseID
    }
}

public enum SceneAIReplyDecision: Equatable, Sendable {
    case display
    case discardScopeMismatch
    case discardMissingAudit
}

/// Global and per-theme kill switches (W04.8). Default is non-generative everywhere.
public struct SceneAIAvailability: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case generative
        /// Approved fixed copy or rule-based hints; the main line stays completable.
        case nonGenerative(reasonKey: String)
    }
    public var globalGenerationEnabled = false
    public var disabledThemeIDs: Set<String> = []
    public var enabledScenarios: Set<SceneAIScenario> = []
    /// Streaming would display unreviewed text before the safety decision; kept off.
    public let allowsStreamingDisplay = false
    public init() {}
    public static let disabled = SceneAIAvailability()

    public func mode(for scope: SceneAIScope) -> Mode {
        guard scope.isValid, scope.scenario.availableInApp, !scope.scenario.registeredBizTypes.isEmpty else {
            return .nonGenerative(reasonKey: "sceneAI.unavailable.unsupported")
        }
        guard globalGenerationEnabled else { return .nonGenerative(reasonKey: "sceneAI.unavailable.global") }
        guard enabledScenarios.contains(scope.scenario) else { return .nonGenerative(reasonKey: "sceneAI.unavailable.scenario") }
        if case .themeBinding(let s) = scope, disabledThemeIDs.contains(s.themeID) {
            return .nonGenerative(reasonKey: "sceneAI.unavailable.theme")
        }
        return .generative
    }

    public static func decide(_ echo: SceneAIReplyEcho, sentFor scope: SceneAIScope) -> SceneAIReplyDecision {
        guard echo.scenario == scope.scenario, echo.isolationKey == scope.isolationKey else { return .discardScopeMismatch }
        if case .themeBinding(let s) = scope, echo.releaseID != s.releaseID { return .discardScopeMismatch }
        guard [echo.traceID, echo.policyVersion, echo.promptVersion].allSatisfy({ !$0.isEmpty }) else { return .discardMissingAudit }
        return .display
    }
}

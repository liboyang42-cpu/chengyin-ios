import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Routes of hengyin `ApiMerchantAuthoringController` (`cursor/w05-j-merchant-authoring`).
/// Generation goes through that job contract so the server can call the existing gateway.
/// This client does not call a model, write stock, or send an approval conclusion.
public enum MerchantAuthoringRoute: String, CaseIterable, Sendable {
    case jobs = "api/merchant/authoring/jobs"
    case cancelJob = "api/merchant/authoring/jobs/cancel"
    case drafts = "api/merchant/authoring/drafts"
    case releases = "api/merchant/authoring/releases"
    case publicRead = "api/merchant/authoring/public"
    case environment = "api/merchant/authoring/environment"
    case mainLine = "api/merchant/authoring/main-line"
    public static let backendController = "ApiMerchantAuthoringController"
    public static let backendBranch = "cursor/w05-j-merchant-authoring"
    public static func draft(_ id: String, suffix: String = "") -> String? {
        guard id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { return nil }
        return "api/merchant/authoring/drafts/\(id)" + suffix
    }
    public static func withdraw(_ id: String) -> String? {
        guard id.range(of: "^[0-9]{1,18}$", options: .regularExpression) != nil else { return nil }
        return "api/merchant/authoring/releases/\(id)/withdraw"
    }
}

public struct MerchantAuthoringOwner: Equatable, Hashable, Sendable {
    public let accountID: String
    public let merchantID: String
    public let storeID: String
    public let permissionRevision: UInt64
    public init(accountID: String, merchantID: String, storeID: String, permissionRevision: UInt64) {
        self.accountID = accountID; self.merchantID = merchantID; self.storeID = storeID; self.permissionRevision = permissionRevision
    }
    public var key: String { "\(accountID.utf8.count):\(accountID)\u{1f}\(merchantID.utf8.count):\(merchantID)\u{1f}\(storeID.utf8.count):\(storeID)\u{1f}\(permissionRevision)" }
}

public struct MerchantAuthoringSession: Equatable, Sendable {
    public let namespace: String
    public let accountID: Int
    public let credential: String
    public let owner: MerchantAuthoringOwner
    public let storeIDs: Set<String>
    public let themeIDs: Set<String>
    public init(namespace: String, accountID: Int, credential: String, owner: MerchantAuthoringOwner, storeIDs: Set<String>, themeIDs: Set<String>) {
        self.namespace = namespace; self.accountID = accountID; self.credential = credential
        self.owner = owner; self.storeIDs = storeIDs; self.themeIDs = themeIDs
    }
}

/// Unapproved model, cost, concurrency, templates, reviewer permissions, environment provider,
/// fallback and visibility stay nil and fail closed. No numeric product default is filled in.
public struct MerchantAuthoringPolicy: Equatable, Sendable {
    public var modelID: String?
    public var costCapMinor: Int?
    public var concurrencyCap: Int?
    public var approvedTemplateIDs: Set<String>
    public var approvedRewardRuleIDs: Set<String>
    public var merchantReviewerPermission: String?
    public var themeReviewerPermission: String?
    public var environmentProviderID: String?
    public var fallbackBranchID: String?
    public var visibility: String?
    public init() { approvedTemplateIDs = []; approvedRewardRuleIDs = [] }
    public static let unset = MerchantAuthoringPolicy()

    public var generationConfigured: Bool {
        let model = modelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !model.isEmpty, let costCapMinor, costCapMinor >= 0, let concurrencyCap, concurrencyCap > 0,
              !approvedTemplateIDs.isEmpty, approvedTemplateIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return false }
        return true
    }
    public var publishConfigured: Bool {
        generationConfigured && !(merchantReviewerPermission ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(themeReviewerPermission ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(visibility ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public var environmentConfigured: Bool {
        !(environmentProviderID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(fallbackBranchID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct MerchantAuthoringDraftSummary: Equatable, Sendable, Identifiable {
    public let draftID: String
    public let version: Int
    public let stage: MerchantAuthoringStage
    public let storeID: String
    public var id: String { draftID }
    public init(draftID: String, version: Int, stage: MerchantAuthoringStage, storeID: String) {
        self.draftID = draftID; self.version = version; self.stage = stage; self.storeID = storeID
    }
}

public struct MerchantAuthoringDraftInput: Equatable, Sendable {
    public var canonicalPlot: String
    public var allowedVariables: [String]
    public var approvedBranches: [String]
    public var serverActionRules: [String]
    public static let rejectedEffects: Set<String> = ["NEW_ROUTE", "TIME_LIMIT", "CASH", "PRIZE", "STOCK_PROMISE"]
    public init(canonicalPlot: String, allowedVariables: [String], approvedBranches: [String], serverActionRules: [String]) {
        self.canonicalPlot = canonicalPlot; self.allowedVariables = allowedVariables
        self.approvedBranches = approvedBranches; self.serverActionRules = serverActionRules
    }
    public func blocked(_ effects: [String]) -> [String] { effects.filter { Self.rejectedEffects.contains($0) } }
}

public enum MerchantAuthoringRefusal: Error, Equatable, Sendable {
    case policyUnset, endpointNotApproved(String), capabilityDisabled, jobConflict, unauthorized
    case stale, versionConflict, rejectedEffect, incompleteDraft, malformed, notSent
}

public enum MerchantAuthoringOutcome: Equatable, Sendable {
    case refused(MerchantAuthoringRefusal)
    case unknown(String)
    case cancelled(String)
    case stale
    case revision(MerchantAuthoringRevision, releaseID: String?)
    case drafts([MerchantAuthoringDraftSummary])
    case review(merchantFactsConfirmed: Bool, themeApproved: Bool)
    case release(ShopNPCPublicRead)
    /// Server job view. UNKNOWN is not a publish. CANCELLED carries no published release.
    case job(outcome: String, draftID: String?, errorCode: String?)
}

public enum MerchantAuthoringWire {
    public static let stripped = ["approved", "merchantFactsApproval", "themeContentApproval", "stage"]
    public static func data(_ fields: [String: Any]) throws -> Data {
        guard let clean = strip(fields) as? [String: Any], JSONSerialization.isValidJSONObject(clean) else { throw APIError.invalidRequest }
        return try JSONSerialization.data(withJSONObject: clean)
    }
    private static func strip(_ value: Any) -> Any {
        if var clean = value as? [String: Any] {
            for key in stripped { clean.removeValue(forKey: key) }
            for (key, item) in clean { clean[key] = strip(item) }
            return clean
        }
        if let items = value as? [Any] { return items.map(strip) }
        return value
    }
}

public enum MerchantAuthoringReadback {
    /// A content change cannot come back still approved, published, or carrying the previous evidence.
    public static func acceptsSave(old: MerchantAuthoringRevision, new: MerchantAuthoringRevision, contentChanged: Bool) -> Bool {
        guard MerchantAuthoringGuard.acceptsReadback(old: old, new: new) else { return false }
        guard contentChanged else { return true }
        guard new.merchantFactsApproval == nil, new.themeContentApproval == nil else { return false }
        return [.draft, .changesRequired, .validated, .failed].contains(new.stage)
    }
}

public enum MerchantAuthoringEnvironment {
    /// No provider approval: do not invent weather. Only an already-approved store-fact branch can be considered.
    public static func select(policy: MerchantAuthoringPolicy, proposedBranchID: String?, branches: [ApprovedBranch],
                               snapshot: EnvironmentSnapshot?, serverNow: Date, storeFactBranchID: String?) -> EnvironmentBranchDecision {
        guard policy.environmentConfigured else {
            guard let storeFactBranchID, branches.filter({ $0.branchID == storeFactBranchID }).count == 1 else { return .noBranchAvailable }
            let facts = branches.filter { $0.branchID == storeFactBranchID }
            return EnvironmentBranchSelector.decide(proposedBranchID: storeFactBranchID, branches: facts, snapshot: nil, serverNow: serverNow)
        }
        return EnvironmentBranchSelector.decide(proposedBranchID: proposedBranchID, branches: branches, snapshot: snapshot, serverNow: serverNow)
    }
}

@MainActor public final class MerchantAuthoringService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let approval: OperationEndpointApproval?
    private let journal: any MerchantAuthoringJobJournal
    public let policy: MerchantAuthoringPolicy
    public let gates: MerchantAICommerceGates
    private let session: () -> MerchantAuthoringSession?
    public init(configuration: APIConfiguration, transport: any HTTPTransport, approval: OperationEndpointApproval? = nil,
                journal: any MerchantAuthoringJobJournal, policy: MerchantAuthoringPolicy = .unset,
                gates: MerchantAICommerceGates = .disabled, session: @escaping () -> MerchantAuthoringSession?) {
        self.configuration = configuration; self.transport = transport; self.approval = approval
        self.journal = journal; self.policy = policy; self.gates = gates; self.session = session
    }

    public func restoredJob(owner: MerchantAuthoringOwner) -> MerchantAuthoringJobRecord? {
        guard session()?.owner == owner else { return nil }
        return try? journal.pendingUnknown(ownerKey: owner.key)
    }

    public func listDrafts(owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard authorized(owner) else { return .refused(.unauthorized) }
        guard allows(MerchantAuthoringRoute.drafts.rawValue) else { return .refused(.endpointNotApproved(MerchantAuthoringRoute.drafts.rawValue)) }
        do {
            let (data, status) = try await send("GET", path: MerchantAuthoringRoute.drafts.rawValue, query: [:], fields: nil, owner: owner)
            guard session()?.owner == owner else { return .stale }
            guard (200..<300).contains(status) else { return .refused(.malformed) }
            return .drafts(try Self.drafts(data, merchantID: owner.merchantID))
        } catch { return .refused(.malformed) }
    }

    public func createDraft(requestID: UUID, templateID: String, themeID: String?, skuID: String?, scene: String, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard authorized(owner, themeID: themeID), policy.generationConfigured, policy.approvedTemplateIDs.contains(templateID) else {
            return authorized(owner, themeID: themeID) ? .refused(.policyUnset) : .refused(.unauthorized)
        }
        let fingerprint = MerchantAuthoringFingerprint.make([owner.merchantID, owner.storeID, templateID, themeID ?? "", skuID ?? "", scene, MerchantAuthoringIntent.create.rawValue])
        return await mutate(MerchantAuthoringRoute.drafts.rawValue, intent: .create, requestID: requestID, fingerprint: fingerprint, draftID: requestID.uuidString, owner: owner, fields: requestFields(requestID, templateID: templateID, themeID: themeID, skuID: skuID, scene: scene, draftID: nil), accept: { data in
            .revision(try Self.draftRevision(data, owner: owner), releaseID: nil)
        })
    }

    public func generate(requestID: UUID, draftID: String, templateID: String, themeID: String?, prompt: String, effects: [String], scene: String, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard authorized(owner, themeID: themeID) else { return .refused(.unauthorized) }
        guard policy.generationConfigured, policy.approvedTemplateIDs.contains(templateID), policy.modelID != nil, policy.costCapMinor != nil else { return .refused(.policyUnset) }
        guard MerchantAuthoringDraftInput(canonicalPlot: "", allowedVariables: [], approvedBranches: [], serverActionRules: []).blocked(effects).isEmpty else { return .refused(.rejectedEffect) }
        let fingerprint = MerchantAuthoringFingerprint.make([owner.merchantID, draftID, templateID, themeID ?? "", prompt, scene, MerchantAuthoringIntent.generate.rawValue])
        return await mutate(MerchantAuthoringRoute.jobs.rawValue, intent: .generate, requestID: requestID, fingerprint: fingerprint, draftID: draftID, owner: owner, fields: requestFields(requestID, templateID: templateID, themeID: themeID, skuID: nil, scene: scene, draftID: draftID), accept: Self.acceptJob)
    }

    public func query(requestID: UUID, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard let record = try? journal.lookup(ownerKey: owner.key, requestID: requestID.uuidString) else { return .unknown(requestID.uuidString) }
        return await replay(record, owner: owner)
    }

    public func cancel(requestID: UUID, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard authorized(owner) else { return .refused(.unauthorized) }
        guard (try? journal.cancel(ownerKey: owner.key, requestID: requestID.uuidString)) != nil else { return .refused(.notSent) }
        if allows(MerchantAuthoringRoute.cancelJob.rawValue) {
            _ = try? await send("POST", path: MerchantAuthoringRoute.cancelJob.rawValue, query: [:], fields: ["requestId": requestID.uuidString], owner: owner)
        }
        return .cancelled(requestID.uuidString)
    }

    public func save(requestID: UUID, old: MerchantAuthoringRevision, input: MerchantAuthoringDraftInput, game: InStoreGameDraft, scene: String, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard authorized(owner) else { return .refused(.unauthorized) }
        guard input.blocked(input.serverActionRules).isEmpty else { return .refused(.rejectedEffect) }
        if scene == "IN_STORE_GAME", !game.missingFields(approvedTemplates: policy.approvedTemplateIDs, approvedRewardRules: policy.approvedRewardRuleIDs).isEmpty { return .refused(.incompleteDraft) }
        guard let path = MerchantAuthoringRoute.draft(old.draftID) else { return .refused(.malformed) }
        let fingerprint = MerchantAuthoringFingerprint.make([old.draftID, String(old.version), input.canonicalPlot, input.allowedVariables.joined(separator: ","), input.approvedBranches.joined(separator: ","), scene, MerchantAuthoringIntent.save.rawValue])
        let fields: [String: Any] = ["expectedVersion": old.version, "body": saveBody(input, game: game, scene: scene)]
        return await mutate(path, intent: .save, requestID: requestID, fingerprint: fingerprint, draftID: old.draftID, owner: owner, fields: fields, accept: { data in
            let revision = try Self.draftRevision(data, owner: owner)
            guard MerchantAuthoringReadback.acceptsSave(old: old, new: revision, contentChanged: true) else { throw MerchantAuthoringRefusal.versionConflict }
            return .revision(revision, releaseID: nil)
        })
    }

    public func reviewStatus(draftID: String, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard authorized(owner), let path = MerchantAuthoringRoute.draft(draftID, suffix: "/review") else { return .refused(.unauthorized) }
        guard allows(path) else { return .refused(.endpointNotApproved(path)) }
        do {
            let (data, status) = try await send("GET", path: path, query: [:], fields: nil, owner: owner)
            guard (200..<300).contains(status), session()?.owner == owner else { return .stale }
            let row = try Self.object(data)
            let facts = row["merchantFact"]?.object?["outcome"]?.text == "APPROVED"
            let theme = row["themeContent"]?.object?["outcome"]?.text == "APPROVED"
            return .review(merchantFactsConfirmed: facts, themeApproved: theme)
        } catch { return .refused(.malformed) }
    }

    public func publish(requestID: UUID, revision: MerchantAuthoringRevision, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard authorized(owner) else { return .refused(.unauthorized) }
        guard policy.publishConfigured, gates.merchantAuthoringPublish else {
            return gates.merchantAuthoringPublish ? .refused(.policyUnset) : .refused(.capabilityDisabled)
        }
        let fingerprint = MerchantAuthoringFingerprint.make([revision.draftID, String(revision.version), owner.merchantID, MerchantAuthoringIntent.publish.rawValue])
        let fields: [String: Any] = ["requestId": requestID.uuidString, "draftId": revision.draftID, "version": revision.version]
        return await mutate(MerchantAuthoringRoute.releases.rawValue, intent: .publish, requestID: requestID, fingerprint: fingerprint, draftID: revision.draftID, owner: owner, fields: fields, accept: Self.acceptRelease)
    }

    public func readRevision(draftID: String, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard authorized(owner), let path = MerchantAuthoringRoute.draft(draftID) else { return .unknown(draftID) }
        guard allows(path) else { return .unknown(draftID) }
        do {
            let (data, status) = try await send("GET", path: path, query: [:], fields: nil, owner: owner)
            guard (200..<300).contains(status), session()?.owner == owner else { return .stale }
            return .revision(try Self.draftRevision(data, owner: owner), releaseID: nil)
        } catch { return .unknown(draftID) }
    }

    public func readPublic(merchantID: String, themeID: String?, releaseID: String?, runID: String?, binding: String, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard authorized(owner), !binding.isEmpty, let merchant = Int(merchantID) else { return .refused(.notSent) }
        guard allows(MerchantAuthoringRoute.publicRead.rawValue) else { return .refused(.endpointNotApproved(MerchantAuthoringRoute.publicRead.rawValue)) }
        var query = ["merchantId": String(merchant), "binding": binding]
        if let themeID, let theme = Int(themeID) { query["themeId"] = String(theme) }
        if let releaseID, Int(releaseID) != nil { query["releaseId"] = releaseID }
        if let runID, !runID.isEmpty { query["runId"] = runID }
        do {
            let (data, status) = try await send("GET", path: MerchantAuthoringRoute.publicRead.rawValue, query: query, fields: nil, owner: owner)
            guard (200..<300).contains(status), session()?.owner == owner else { return .stale }
            return try Self.publicRead(data)
        } catch { return .refused(.malformed) }
    }

    public func mainLine(merchantID: String, themeID: String?, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard authorized(owner), let merchant = Int(merchantID) else { return .refused(.notSent) }
        guard allows(MerchantAuthoringRoute.mainLine.rawValue) else { return .refused(.endpointNotApproved(MerchantAuthoringRoute.mainLine.rawValue)) }
        var query = ["merchantId": String(merchant)]
        if let themeID, let theme = Int(themeID) { query["themeId"] = String(theme) }
        do {
            let (data, status) = try await send("GET", path: MerchantAuthoringRoute.mainLine.rawValue, query: query, fields: nil, owner: owner)
            guard (200..<300).contains(status), session()?.owner == owner else { return .stale }
            return try Self.publicRead(data)
        } catch { return .refused(.malformed) }
    }

    /// Server environment row. No local weather is invented; an unapproved route is not called.
    public func environment(releaseID: String, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard authorized(owner), Int(releaseID) != nil else { return .refused(.notSent) }
        guard policy.environmentConfigured else { return .refused(.policyUnset) }
        guard allows(MerchantAuthoringRoute.environment.rawValue) else { return .refused(.endpointNotApproved(MerchantAuthoringRoute.environment.rawValue)) }
        do {
            let (data, status) = try await send("GET", path: MerchantAuthoringRoute.environment.rawValue, query: ["releaseId": releaseID], fields: nil, owner: owner)
            guard (200..<300).contains(status), session()?.owner == owner else { return .stale }
            let row = try Self.object(data)
            let provider = row["provider"]?.text ?? ""
            guard !provider.isEmpty else { return .refused(.policyUnset) }
            return .job(outcome: row["action"]?.text ?? "NONE", draftID: releaseID, errorCode: row["branch"]?.text)
        } catch { return .refused(.malformed) }
    }

    public func noteReadback(requestID: UUID, owner: MerchantAuthoringOwner) -> Bool {
        guard session()?.owner == owner else { return false }
        return (try? journal.acknowledge(ownerKey: owner.key, requestID: requestID.uuidString)) != nil
    }

    private func mutate(_ path: String, intent: MerchantAuthoringIntent, requestID: UUID, fingerprint: String, draftID: String, owner: MerchantAuthoringOwner, fields: [String: Any], accept: (Data) throws -> MerchantAuthoringOutcome) async -> MerchantAuthoringOutcome {
        let id = requestID.uuidString
        guard allows(path) else { return .refused(.endpointNotApproved(path)) }
        if intent == .generate, (try? journal.lookup(ownerKey: owner.key, requestID: id)) == nil {
            guard let cap = policy.concurrencyCap, let count = try? journal.unknownCount(ownerKey: owner.key), count < cap else { return .refused(.policyUnset) }
        }
        let claim: MerchantAuthoringClaim
        do { claim = try journal.claim(ownerKey: owner.key, requestID: id, fingerprint: fingerprint, draftID: draftID, storeID: owner.storeID, intent: intent) }
        catch { return .refused(.jobConflict) }
        if !claim.fresh { return await replay(claim.record, owner: owner) }
        do {
            let (data, status) = try await send("POST", path: path, query: [:], fields: fields, owner: owner)
            guard session()?.owner == owner else { return .stale }
            if (try? journal.lookup(ownerKey: owner.key, requestID: id))?.state == .cancelled { return .cancelled(id) }
            if status == 202 { return .unknown(id) }
            if status == 409 { return .refused(.versionConflict) }
            let outcome = try accept(data)
            if case .unknown = outcome { return .unknown(id) }
            if case .job(let name, _, _) = outcome, name == "UNKNOWN" { return .unknown(id) }
            try journal.acknowledge(ownerKey: owner.key, requestID: id)
            return outcome
        } catch let refusal as MerchantAuthoringRefusal {
            return refusal == .versionConflict || refusal == .malformed ? .refused(refusal) : .unknown(id)
        } catch { return .unknown(id) }
    }

    private func replay(_ record: MerchantAuthoringJobRecord, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        if record.state == .cancelled { return .cancelled(record.requestID) }
        switch record.intent {
        case .generate: return await readJob(record, owner: owner)
        case .create: return .unknown(record.requestID)
        case .save: return await readRevision(draftID: record.draftID, owner: owner)
        case .publish: return await findRelease(record.requestID, owner: owner)
        }
    }

    private func readJob(_ record: MerchantAuthoringJobRecord, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard allows(MerchantAuthoringRoute.jobs.rawValue) else { return .unknown(record.requestID) }
        do {
            let (data, status) = try await send("GET", path: MerchantAuthoringRoute.jobs.rawValue, query: ["requestId": record.requestID], fields: nil, owner: owner)
            guard session()?.owner == owner else { return .unknown(record.requestID) }
            if status == 202 || status == 404 { return .unknown(record.requestID) }
            if (try? journal.lookup(ownerKey: owner.key, requestID: record.requestID))?.state == .cancelled { return .cancelled(record.requestID) }
            let outcome = try Self.acceptJob(data)
            if case .unknown = outcome { return .unknown(record.requestID) }
            if case .job(let name, _, _) = outcome, name == "UNKNOWN" || name == "CANCELLED" { return name == "CANCELLED" ? .cancelled(record.requestID) : .unknown(record.requestID) }
            try? journal.acknowledge(ownerKey: owner.key, requestID: record.requestID)
            return outcome
        } catch { return .unknown(record.requestID) }
    }

    private func findRelease(_ requestID: String, owner: MerchantAuthoringOwner) async -> MerchantAuthoringOutcome {
        guard allows(MerchantAuthoringRoute.releases.rawValue) else { return .unknown(requestID) }
        do {
            let (data, status) = try await send("GET", path: MerchantAuthoringRoute.releases.rawValue, query: ["requestId": requestID], fields: nil, owner: owner)
            guard (200..<300).contains(status), session()?.owner == owner else { return .unknown(requestID) }
            return try Self.acceptRelease(data)
        } catch { return .unknown(requestID) }
    }

    private func send(_ method: String, path: String, query: [String: String], fields: [String: Any]?, owner: MerchantAuthoringOwner) async throws -> (Data, Int) {
        guard let session = session(), session.owner == owner, session.storeIDs.contains(owner.storeID) else { throw MerchantAuthoringRefusal.unauthorized }
        guard !path.contains("?"), !path.contains("..") else { throw MerchantAuthoringRefusal.malformed }
        let body = try MerchantAuthoringWire.data(fields ?? [:])
        var request = try OperationAdapterHTTP.json(configuration: configuration, path: path, body: body, token: session.credential)
        request.httpMethod = method
        if method == "GET" { request.httpBody = nil }
        if !query.isEmpty, let url = request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
            request.url = parts.url
        }
        return try await transport.send(request)
    }

    private func allows(_ path: String) -> Bool {
        guard let approval, let session = session(), path.hasPrefix("api/"), !path.contains("?"), !path.contains("..") else { return false }
        return approval.allows(configuration: configuration, namespace: session.namespace, accountID: session.accountID, path: path)
    }

    private func authorized(_ owner: MerchantAuthoringOwner, themeID: String? = nil) -> Bool {
        guard let session = session(), session.owner == owner, session.storeIDs.contains(owner.storeID) else { return false }
        if let themeID, !session.themeIDs.contains(themeID) { return false }
        return true
    }

    private func requestFields(_ requestID: UUID, templateID: String, themeID: String?, skuID: String?, scene: String, draftID: String?) -> [String: Any] {
        var fields: [String: Any] = ["requestId": requestID.uuidString, "templateId": templateID]
        if let draftID { fields["draftId"] = draftID }
        if !scene.isEmpty { fields["scene"] = scene }
        if let themeID, let theme = Int(themeID) { fields["themeId"] = theme }
        if let skuID, let sku = Int(skuID) { fields["skuId"] = sku }
        return fields
    }

    private func saveBody(_ input: MerchantAuthoringDraftInput, game: InStoreGameDraft, scene: String) -> [String: Any] {
        var body: [String: Any] = ["canonical_plot": input.canonicalPlot, "allowed_variables": input.allowedVariables, "approved_branches": input.approvedBranches]
        var rules: [String: String] = [:]
        if let exit = game.failureExit, !exit.isEmpty { rules["fail_exit"] = exit }
        if let offline = game.offlineFallback, !offline.isEmpty { rules["offline_alternative"] = offline }
        if !rules.isEmpty { body["server_action_rules"] = rules }
        guard scene == "IN_STORE_GAME" else { return body }
        if let minutes = game.durationMinutes { body["duration_minutes"] = minutes }
        if let headcount = game.maxParticipants { body["headcount"] = headcount }
        if let segment = game.businessHoursText { body["business_segment"] = segment }
        if let staff = game.needsStaff { body["staff_need"] = staff ? "required" : "none" }
        if let noise = game.noiseAndFilmingLimits { body["noise_limit"] = noise; body["photo_limit"] = noise }
        if let access = game.accessibleAlternative { body["accessibility_alternative"] = access }
        if let exit = game.failureExit { body["fail_exit"] = exit }
        if let offline = game.offlineFallback { body["offline_alternative"] = offline }
        switch game.reward {
        case .approvedRule(let id)?: body["reward_rule_ref"] = id
        case .noReward?: body["reward_rule_ref"] = "none"
        case nil: break
        }
        return body
    }

    private static func drafts(_ data: Data, merchantID: String) throws -> [MerchantAuthoringDraftSummary] {
        let row = try object(data)
        _ = row["publishSucceeded"]
        guard let rows = row["drafts"]?.array else { throw MerchantAuthoringRefusal.malformed }
        return try rows.map { value in
            guard let item = value.object, let id = item["draftId"]?.text, let version = item["currentVersion"]?.integer, version >= 0,
                  let merchant = Self.text(item["merchantId"]), merchant == merchantID else { throw MerchantAuthoringRefusal.malformed }
            let stage: MerchantAuthoringStage = item["publishOutcome"]?.text == "PUBLISHED" ? .published : item["publishOutcome"]?.text == "WITHDRAWN" ? .withdrawn : .draft
            return MerchantAuthoringDraftSummary(draftID: id, version: version, stage: stage, storeID: merchant)
        }
    }

    private static func draftRevision(_ data: Data, owner: MerchantAuthoringOwner) throws -> MerchantAuthoringRevision {
        let row = try object(data)
        guard let draftID = row["draftId"]?.text, let version = row["currentVersion"]?.integer ?? row["version"]?.integer, version >= 0 else { throw MerchantAuthoringRefusal.malformed }
        let hash = row["bodyHash"]?.text ?? ""
        let theme = text(row["themeId"]) != nil
        let stage: MerchantAuthoringStage = version == 0 ? .factsReady : .draft
        return MerchantAuthoringRevision(draftID: draftID, version: version, stage: stage, authorID: owner.accountID, contentHash: hash,
                                          touchesThemeContent: theme, merchantFactsApproval: nil, themeContentApproval: nil)
    }

    private static func acceptJob(_ data: Data) throws -> MerchantAuthoringOutcome {
        let row = try object(data)
        let outcome = row["outcome"]?.text ?? "UNKNOWN"
        if outcome == "UNKNOWN" { return .unknown("") }
        if outcome == "CANCELLED" { return .cancelled(row["requestId"]?.text ?? "") }
        return .job(outcome: outcome, draftID: row["draftId"]?.text, errorCode: row["errorCode"]?.text)
    }

    private static func acceptRelease(_ data: Data) throws -> MerchantAuthoringOutcome {
        let row = try object(data)
        let outcome = row["outcome"]?.text ?? ""
        guard outcome == "PUBLISHED" || outcome == "WITHDRAWN", let release = text(row["releaseId"]) else {
            if outcome == "UNKNOWN" { return .unknown("") }
            throw MerchantAuthoringRefusal.malformed
        }
        let facts = stringFacts(row["facts"])
        if outcome == "PUBLISHED", let read = ShopNPCPublicRead(releaseID: release, stage: .published, facts: facts) { return .release(read) }
        return .job(outcome: outcome, draftID: row["draftId"]?.text, errorCode: nil)
    }

    private static func publicRead(_ data: Data) throws -> MerchantAuthoringOutcome {
        let row = try object(data)
        guard row["outcome"]?.text == "PUBLISHED", let release = text(row["releaseId"]),
              let read = ShopNPCPublicRead(releaseID: release, stage: .published, facts: stringFacts(row["facts"])) else { return .refused(.malformed) }
        return .release(read)
    }

    private static func object(_ data: Data) throws -> [String: ProjectEditJSON] {
        let body = try OperationAdapterHTTP.envelope(data)
        if body["code"]?.integer == 202 { throw MerchantAuthoringRefusal.notSent }
        guard let row = body["data"]?.object else { throw MerchantAuthoringRefusal.malformed }
        return row
    }

    private static func text(_ value: ProjectEditJSON?) -> String? {
        if let text = value?.text, !text.isEmpty { return text }
        if let number = value?.integer { return String(number) }
        return nil
    }

    private static func stringFacts(_ value: ProjectEditJSON?) -> [String: String] {
        guard let row = value?.object else { return [:] }
        var facts: [String: String] = [:]
        for (key, item) in row {
            if let text = item.text { facts[key] = text }
            else if let number = item.integer { facts[key] = String(number) }
            else if let values = item.array?.compactMap(\.text) { facts[key] = values.joined(separator: ",") }
        }
        return facts
    }
}

import Foundation
import Observation

/// Workbench flow for one store: list or new draft, generate, cancel, save, review, publish, read back, preview, return.
/// Switching account, store or permission revision drops private content and ignores older replies.
@MainActor @Observable public final class MerchantAuthoringCoordinator {
    public enum Phase: Equatable, Sendable {
        case list, drafting, generating, unknown, editing, review, publishConfirm, readBack, preview, returned, cancelled
    }

    public private(set) var phase: Phase = .list
    public private(set) var epoch: UInt64 = 0
    public private(set) var owner: MerchantAuthoringOwner
    public private(set) var drafts: [MerchantAuthoringDraftSummary] = []
    public private(set) var revision: MerchantAuthoringRevision?
    public private(set) var reviewFacts = false
    public private(set) var reviewTheme = false
    public private(set) var publicRead: ShopNPCPublicRead?
    public private(set) var themeDecision: SceneAIReplyDecision?
    public private(set) var refusal: MerchantAuthoringRefusal?
    public private(set) var requestID: UUID?
    public private(set) var releaseID: String?
    public var templateID = ""
    public var themeID = ""
    public var prompt = ""
    public var plot = ""
    public var variablesText = ""
    public var branchesText = ""
    public var rulesText = ""
    public var durationText = ""
    public var participantsText = ""
    public var businessHours = ""
    public var needsStaff: Bool?
    public var noise = ""
    public var accessible = ""
    public var offline = ""
    public var failureExit = ""
    public var rewardRuleID = ""
    public var reward: InStoreGameDraft.Reward?
    public var skuID = ""
    public var scene = ""
    public var binding = ""
    public private(set) var statusNote: String?
    public var catalog: [CanonicalSKUFact] = []
    /// AI failure does not block the existing theme main line.
    public var themeMainLineBlocked: Bool { false }

    private let service: MerchantAuthoringService
    private var saveID: UUID?
    private var publishID: UUID?
    private var inflight: UUID?
    private var inflightIntent: MerchantAuthoringIntent?

    public init(service: MerchantAuthoringService, owner: MerchantAuthoringOwner) {
        self.service = service
        self.owner = owner
        if let job = service.restoredJob(owner: owner) { remember(job) }
    }

    public func visibleRevision(for owner: MerchantAuthoringOwner) -> MerchantAuthoringRevision? {
        guard self.owner == owner else { return nil }
        return revision
    }

    public func adopt(_ owner: MerchantAuthoringOwner) {
        guard self.owner != owner else { return }
        epoch &+= 1
        clearPrivate()
        self.owner = owner
        if let job = service.restoredJob(owner: owner) { remember(job) } else { phase = .list }
    }

    public func restore(_ owner: MerchantAuthoringOwner) { adopt(owner) }

    public func reload() async {
        let snap = mark()
        let outcome = await service.listDrafts(owner: owner)
        guard live(snap) else { return }
        if case .drafts(let rows) = outcome { drafts = rows.filter { $0.storeID == owner.merchantID }; refusal = nil; phase = .list }
        else if case .refused(let reason) = outcome { refusal = reason }
    }

    public func beginNew() async {
        guard phase == .list || phase == .returned else { return }
        let snap = mark()
        let id = UUID()
        requestID = id
        inflight = id
        inflightIntent = .create
        let outcome = await service.createDraft(requestID: id, templateID: templateID, themeID: themeID.nilIfEmpty, skuID: skuID.nilIfEmpty, scene: scene, owner: owner)
        guard live(snap) else { return }
        switch outcome {
        case .revision(let revision, let release):
            self.revision = revision
            releaseID = release
            refusal = nil
            phase = .drafting
        case .unknown:
            phase = .unknown
        case .refused(let reason):
            requestID = nil
            inflight = nil
            refusal = reason
        case .cancelled:
            phase = .cancelled
        case .stale:
            break
        default:
            refusal = .malformed
        }
    }

    public func generate(effects: [String] = []) async {
        let snap = mark()
        if phase == .unknown { await queryOriginal(); return }
        guard phase == .drafting, let revision else { return }
        if requestID == nil { requestID = UUID() }
        guard let requestID else { return }
        inflight = requestID
        inflightIntent = .generate
        phase = .generating
        let outcome = await service.generate(requestID: requestID, draftID: revision.draftID, templateID: templateID, themeID: themeID.nilIfEmpty, prompt: prompt, effects: effects, scene: scene, owner: owner)
        guard live(snap) else { return }
        switch outcome {
        case .cancelled:
            phase = .cancelled
        case .revision(let revision, let release):
            self.revision = revision
            if let release { releaseID = release }
            refusal = nil
            phase = .editing
        case .job(let name, let draftID, let errorCode):
            if name == "SUCCEEDED", let draftID { await openDraft(draftID, snap: snap) }
            else { statusNote = errorCode; phase = name == "FAILED" ? .drafting : .unknown }
        case .unknown:
            phase = .unknown
        case .refused(let reason):
            refusal = reason
            phase = reason == .jobConflict ? .unknown : .drafting
        case .stale:
            break
        default:
            phase = .unknown
        }
    }

    public func cancel() async {
        let snap = mark()
        guard let id = inflight ?? requestID else { phase = .cancelled; return }
        let outcome = await service.cancel(requestID: id, owner: owner)
        guard live(snap) else { return }
        if case .revision = outcome { return }
        phase = .cancelled
    }

    public func save() async {
        guard phase == .editing, let old = revision else { return }
        if saveID == nil { saveID = UUID() }
        guard let saveID else { return }
        let snap = mark()
        inflight = saveID
        inflightIntent = .save
        let outcome = await service.save(requestID: saveID, old: old, input: draftInput, game: gameDraft, scene: scene, owner: owner)
        guard live(snap) else { return }
        switch outcome {
        case .revision(let new, let release):
            guard MerchantAuthoringReadback.acceptsSave(old: old, new: new, contentChanged: true) else { refusal = .versionConflict; phase = .unknown; return }
            revision = new
            if let release { releaseID = release }
            _ = service.noteReadback(requestID: saveID, owner: owner)
            self.saveID = nil
            refusal = nil
        case .unknown:
            phase = .unknown
        case .cancelled:
            phase = .cancelled
        case .refused(let reason):
            refusal = reason
            if reason == .jobConflict || reason == .versionConflict { phase = .unknown }
        case .stale:
            break
        default:
            break
        }
    }

    public func loadReview() async {
        guard let revision else { return }
        let snap = mark()
        let outcome = await service.reviewStatus(draftID: revision.draftID, owner: owner)
        guard live(snap) else { return }
        if case .review(let facts, let theme) = outcome { reviewFacts = facts; reviewTheme = theme; phase = .review; refusal = nil }
        else if case .refused(let reason) = outcome { refusal = reason }
    }

    public func confirmPublish() async {
        guard phase == .publishConfirm, let revision else { return }
        if publishID == nil { publishID = UUID() }
        guard let publishID else { return }
        let snap = mark()
        inflight = publishID
        inflightIntent = .publish
        let outcome = await service.publish(requestID: publishID, revision: revision, owner: owner)
        guard live(snap) else { return }
        applyPublish(outcome, old: revision, requestID: publishID)
    }

    public func readBack() async {
        guard let revision else { return }
        let snap = mark()
        let outcome = await service.readRevision(draftID: revision.draftID, owner: owner)
        guard live(snap) else { return }
        if case .revision(let new, let release) = outcome, MerchantAuthoringGuard.acceptsReadback(old: revision, new: new) {
            self.revision = new
            if let release { releaseID = release }
            phase = .readBack
            refusal = nil
        } else { phase = .unknown }
    }

    public func queryOriginal() async {
        let snap = mark()
        guard phase == .unknown, let inflight else { return }
        let intent = inflightIntent
        let outcome = await service.query(requestID: inflight, owner: owner)
        guard live(snap) else { return }
        switch intent {
        case .publish:
            applyPublish(outcome, old: revision, requestID: inflight)
        case .save:
            guard let old = revision, case .revision(let new, let release) = outcome, MerchantAuthoringReadback.acceptsSave(old: old, new: new, contentChanged: true) else { phase = .unknown; return }
            self.revision = new
            if let release { releaseID = release }
            _ = service.noteReadback(requestID: inflight, owner: owner)
            phase = .editing
        default:
            if case .job(let name, let draftID, _) = outcome, name == "SUCCEEDED", let draftID {
                await openDraft(draftID, snap: snap)
                return
            }
            guard case .revision(let new, let release) = outcome else { phase = .unknown; return }
            self.revision = new
            if let release { releaseID = release }
            _ = service.noteReadback(requestID: inflight, owner: owner)
            phase = .editing
        }
    }

    private func openDraft(_ draftID: String, snap: (UInt64, MerchantAuthoringOwner)) async {
        let read = await service.readRevision(draftID: draftID, owner: owner)
        guard live(snap) else { return }
        if case .revision(let revision, let release) = read {
            self.revision = revision
            if let release { releaseID = release }
            refusal = nil
            phase = .editing
        } else { phase = .unknown }
    }

    public func previewPublic() async {
        guard let releaseID, !binding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { refusal = .notSent; publicRead = nil; return }
        let snap = mark()
        let outcome = await service.readPublic(merchantID: owner.merchantID, themeID: themeID.nilIfEmpty, releaseID: releaseID, runID: nil, binding: binding, owner: owner)
        guard live(snap) else { return }
        if case .release(let read) = outcome {
            publicRead = read
            phase = .preview
            refusal = nil
            let environment = await service.environment(releaseID: read.releaseID, owner: owner)
            guard live(snap) else { return }
            if case .job(_, _, let branch) = environment { statusNote = branch }
            else if case .refused(let reason) = environment { refusal = reason }
        } else { publicRead = nil; if case .refused(let reason) = outcome { refusal = reason } }
    }

    public func openMainLine() async {
        let snap = mark()
        let outcome = await service.mainLine(merchantID: owner.merchantID, themeID: themeID.nilIfEmpty, owner: owner)
        guard live(snap) else { return }
        if case .release(let read) = outcome { publicRead = read; phase = .preview }
        else if case .refused(let reason) = outcome { refusal = reason }
    }

    public func previewTheme(scope: SceneAIScope, echo: SceneAIReplyEcho) -> SceneAIReplyDecision {
        guard let publicRead, case .themeBinding(let binding) = scope, binding.releaseID == publicRead.releaseID else {
            themeDecision = .discardScopeMismatch
            return .discardScopeMismatch
        }
        let decision = SceneAIAvailability.decide(echo, sentFor: scope)
        themeDecision = decision
        return decision
    }

    public func publicClasses(_ classes: Set<SceneAIDataClass>) -> Set<SceneAIDataClass> {
        let stage: MerchantAuthoringStage = publicRead == nil ? (revision?.stage ?? .draft) : .published
        return SceneAIScenario.storePublicNPC.publicReleaseData(classes, releaseStage: stage)
    }

    public func finish() async {
        let snap = mark()
        publicRead = nil
        themeDecision = nil
        phase = .returned
        await reload()
        guard live(snap) else { return }
    }

    public func showPublishConfirm() {
        guard phase == .review || phase == .editing, revision != nil else { return }
        phase = .publishConfirm
    }

    public var presentation: MerchantInStoreGameAuthoringPresentation? {
        guard let revision else { return nil }
        return MerchantInStoreGameAuthoringPresentation(revision: revision, gameDraft: gameDraft, approvedTemplates: service.policy.approvedTemplateIDs,
                                                         approvedRewardRules: service.policy.approvedRewardRuleIDs, productDraft: productDraft ?? Self.placeholderProduct(owner),
                                                         catalog: catalog, requestID: publishID ?? requestID ?? UUID(), gates: service.gates)
    }

    private func applyPublish(_ outcome: MerchantAuthoringOutcome, old: MerchantAuthoringRevision?, requestID: UUID) {
        switch outcome {
        case .release(let read):
            publicRead = read
            releaseID = read.releaseID
            _ = service.noteReadback(requestID: requestID, owner: owner)
            phase = .readBack
            refusal = nil
        case .job(let name, _, _):
            guard name == "PUBLISHED" || name == "WITHDRAWN" else { phase = .unknown; return }
            _ = service.noteReadback(requestID: requestID, owner: owner)
            phase = .readBack
            refusal = nil
        case .revision(let new, let release):
            if let old, !MerchantAuthoringGuard.acceptsReadback(old: old, new: new) { refusal = .versionConflict; phase = .unknown; return }
            guard new.stage == .published || new.stage == .withdrawn else { phase = .unknown; return }
            revision = new
            if let release { releaseID = release }
            _ = service.noteReadback(requestID: requestID, owner: owner)
            phase = .readBack
            refusal = nil
        case .cancelled:
            phase = .cancelled
        case .unknown:
            phase = .unknown
        case .refused(let reason):
            refusal = reason
        default:
            phase = .unknown
        }
    }

    private func remember(_ job: MerchantAuthoringJobRecord) {
        guard let id = UUID(uuidString: job.requestID) else { return }
        inflight = id
        inflightIntent = job.intent
        switch job.intent {
        case .save: saveID = id
        case .publish: publishID = id
        case .create, .generate: requestID = id
        }
        phase = .unknown
    }

    private func clearPrivate() {
        revision = nil
        drafts = []
        publicRead = nil
        themeDecision = nil
        refusal = nil
        requestID = nil
        releaseID = nil
        saveID = nil
        publishID = nil
        inflight = nil
        inflightIntent = nil
        reviewFacts = false
        reviewTheme = false
        templateID = ""
        themeID = ""
        prompt = ""
        plot = ""
        variablesText = ""
        branchesText = ""
        rulesText = ""
        durationText = ""
        participantsText = ""
        businessHours = ""
        needsStaff = nil
        noise = ""
        accessible = ""
        offline = ""
        failureExit = ""
        rewardRuleID = ""
        reward = nil
        skuID = ""
        scene = ""
        binding = ""
        statusNote = nil
        catalog = []
    }

    private func mark() -> (UInt64, MerchantAuthoringOwner) { (epoch, owner) }
    private func live(_ snap: (UInt64, MerchantAuthoringOwner)) -> Bool { snap.0 == epoch && snap.1 == owner }

    private var draftInput: MerchantAuthoringDraftInput {
        MerchantAuthoringDraftInput(canonicalPlot: plot, allowedVariables: split(variablesText), approvedBranches: split(branchesText), serverActionRules: split(rulesText))
    }
    private var gameDraft: InStoreGameDraft {
        var game = InStoreGameDraft()
        game.interactionTemplateID = templateID.nilIfEmpty
        game.durationMinutes = Int(durationText.trimmingCharacters(in: .whitespaces))
        game.maxParticipants = Int(participantsText.trimmingCharacters(in: .whitespaces))
        game.businessHoursText = businessHours.nilIfEmpty
        game.needsStaff = needsStaff
        game.noiseAndFilmingLimits = noise.nilIfEmpty
        game.accessibleAlternative = accessible.nilIfEmpty
        game.offlineFallback = offline.nilIfEmpty
        game.failureExit = failureExit.nilIfEmpty
        game.reward = reward
        return game
    }
    private var productDraft: MerchantProductDraft? {
        guard let skuID = skuID.nilIfEmpty else { return nil }
        return MerchantProductDraft(merchantID: owner.merchantID, source: .canonical(skuID: skuID), claimedPriceMinor: nil, claimedDiscountText: nil, createsThemeInventoryCopy: false)
    }
    private func split(_ text: String) -> [String] { text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private static func placeholderProduct(_ owner: MerchantAuthoringOwner) -> MerchantProductDraft {
        MerchantProductDraft(merchantID: owner.merchantID, source: .manual(confirmedByPerson: false, hasPrice: false, hasFulfilment: false, hasStockRule: false, hasRefundTerms: false),
                             claimedPriceMinor: nil, claimedDiscountText: nil, createsThemeInventoryCopy: false)
    }
}

private extension String {
    var nilIfEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

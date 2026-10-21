import Foundation

/// Transport effects for C9, supplied by the C7-owned shared-service adapter.
/// This module owns no network client and never rewrites the shared services.
///
/// Adapter contract:
/// - Reads return raw row arrays (`MerchantContentValue` arrays) from the real endpoints.
/// - `sendInvite` performs exactly one invite dispatch. It must throw
///   `ChapterReplacementInvitationFailure.unknown` for any lost/ambiguous response and a
///   different `ChapterReplacementInvitationFailure` only for a definitive rejection.
///   There is no `requestId`, so no adapter may auto-retry the invite.
/// Minimal original-target identity. No message body, token, or archive id.
public struct ChapterReplacementInvitationIntent: Codable, Equatable, Sendable {
    public let topicID: Int
    public let actorAccountID: Int
    public let merchantMemberID: Int
    public let chapterID: Int
    public let replacementOfOfferID: Int
    public let scope: ChapterReplacementInvitationScope

    public init(plan: ChapterReplacementInvitationPlan) {
        topicID = plan.topicID
        actorAccountID = plan.actorAccountID
        merchantMemberID = plan.candidate.merchantMemberID
        chapterID = plan.candidate.chapterID
        replacementOfOfferID = plan.candidate.replacementOfOfferID
        scope = plan.scope
    }
}

public protocol ChapterReplacementInvitationIntentStoring: AnyObject {
    func load() throws -> ChapterReplacementInvitationIntent?
    func save(_ intent: ChapterReplacementInvitationIntent) throws
    func clear(_ intent: ChapterReplacementInvitationIntent) throws
}

/// In-process lock shared by a recreated screen. Tests pass their own instance.
public final class ChapterReplacementInvitationMemoryIntents: ChapterReplacementInvitationIntentStoring {
    public static let process = ChapterReplacementInvitationMemoryIntents()
    private var value: ChapterReplacementInvitationIntent?
    public init() {}
    public func load() throws -> ChapterReplacementInvitationIntent? { value }
    public func save(_ intent: ChapterReplacementInvitationIntent) throws { value = intent }
    public func clear(_ intent: ChapterReplacementInvitationIntent) throws { if value == intent { value = nil } }
}

/// One JSON file. A new process reads the same path. Unreadable bytes stay locked.
public final class ChapterReplacementInvitationFileIntents: ChapterReplacementInvitationIntentStoring {
    private let fileURL: URL?
    public init(directory: URL?) {
        fileURL = directory?.appendingPathComponent("chapter-replacement-intent.json")
    }
    public static func live() -> ChapterReplacementInvitationFileIntents {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Questify/c9-replacement-intent", isDirectory: true)
        return ChapterReplacementInvitationFileIntents(directory: directory)
    }
    public func load() throws -> ChapterReplacementInvitationIntent? {
        guard let fileURL else { throw ChapterReplacementInvitationFailure.unknown }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do { return try JSONDecoder().decode(ChapterReplacementInvitationIntent.self, from: Data(contentsOf: fileURL)) }
        catch { throw ChapterReplacementInvitationFailure.unknown }
    }
    public func save(_ intent: ChapterReplacementInvitationIntent) throws {
        guard let fileURL else { throw ChapterReplacementInvitationFailure.unknown }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(intent).write(to: fileURL, options: .atomic)
        } catch { throw ChapterReplacementInvitationFailure.unknown }
    }
    public func clear(_ intent: ChapterReplacementInvitationIntent) throws {
        guard let fileURL, try load() == intent else { return }
        do { try FileManager.default.removeItem(at: fileURL) } catch { throw ChapterReplacementInvitationFailure.unknown }
    }
}

extension ChapterReplacementInvitationPlan {
    static func restored(_ intent: ChapterReplacementInvitationIntent) -> ChapterReplacementInvitationPlan {
        let vacancy = ChapterReplacementInvitationVacancy(lockedOfferID: intent.replacementOfOfferID, topicID: intent.topicID, chapterID: intent.chapterID)
        let candidate = ChapterReplacementInvitationCandidate(merchantMemberID: intent.merchantMemberID, chapterID: intent.chapterID, replacementOfOfferID: intent.replacementOfOfferID)
        return ChapterReplacementInvitationPlan(topicID: intent.topicID, vacancy: vacancy, candidate: candidate,
                                                scope: intent.scope, actorAccountID: intent.actorAccountID, message: nil)
    }
}

public struct ChapterReplacementInvitationEffects {
    public var loadVacancyRows: (Int) async throws -> [MerchantContentValue]
    public var loadCandidateRows: (ChapterReplacementInvitationInvitableRequest) async throws -> [MerchantContentValue]
    public var loadExistingRows: (Int, ChapterReplacementInvitationScope) async throws -> [MerchantContentValue]
    public var sendInvite: (ChapterReplacementInvitationPlan) async throws -> Void
    public var loadOwnerListRows: (ChapterReplacementInvitationOwnerListRequest) async throws -> [MerchantContentValue]
    public var loadOwnerMineRows: (ChapterReplacementInvitationOwnerMineRequest) async throws -> [MerchantContentValue]

    public init(loadVacancyRows: @escaping (Int) async throws -> [MerchantContentValue],
                loadCandidateRows: @escaping (ChapterReplacementInvitationInvitableRequest) async throws -> [MerchantContentValue],
                loadExistingRows: @escaping (Int, ChapterReplacementInvitationScope) async throws -> [MerchantContentValue],
                sendInvite: @escaping (ChapterReplacementInvitationPlan) async throws -> Void,
                loadOwnerListRows: @escaping (ChapterReplacementInvitationOwnerListRequest) async throws -> [MerchantContentValue],
                loadOwnerMineRows: @escaping (ChapterReplacementInvitationOwnerMineRequest) async throws -> [MerchantContentValue]) {
        self.loadVacancyRows = loadVacancyRows
        self.loadCandidateRows = loadCandidateRows
        self.loadExistingRows = loadExistingRows
        self.sendInvite = sendInvite
        self.loadOwnerListRows = loadOwnerListRows
        self.loadOwnerMineRows = loadOwnerMineRows
    }
}

@MainActor
public final class ChapterReplacementInvitationCoordinator {
    public enum Phase: Equatable {
        case idle, loadingVacancies, loadingCandidates, ready
        case reviewing(ChapterReplacementInvitationPlan)
        case sending(ChapterReplacementInvitationPlan)
        /// Response was lost or readback has not proved the tuple yet. The only
        /// permitted next step is `verifyUnknown()`; sending again is impossible here.
        case unknown(ChapterReplacementInvitationPlan)
        case verified(ChapterReplacementInvitationVerified)
        case failed(ChapterReplacementInvitationFailure)
    }

    private let effects: ChapterReplacementInvitationEffects
    private let intents: any ChapterReplacementInvitationIntentStoring
    /// Corrupt or missing durable storage. Stays set so a later load cannot unlock a send.
    private var blocked = false
    public private(set) var phase: Phase = .idle
    public private(set) var topicID: Int?
    public private(set) var actorAccountID: Int?
    public private(set) var vacancies: [ChapterReplacementInvitationVacancy] = []
    public private(set) var candidates: [ChapterReplacementInvitationCandidate] = []
    public private(set) var selectedVacancy: ChapterReplacementInvitationVacancy?
    public private(set) var sendAttempts = 0
    private var generation = 0

    public init(effects: ChapterReplacementInvitationEffects, intents: any ChapterReplacementInvitationIntentStoring = ChapterReplacementInvitationFileIntents.live()) {
        self.effects = effects
        self.intents = intents
    }

    public var impact: ChapterReplacementInvitationImpact? {
        if case .reviewing(let plan) = phase { return ChapterReplacementInvitationImpact(plan: plan) }
        return nil
    }

    /// Starting a (new) topic or switching account retires every selection and plan.
    public func begin(topicID: Int, actorAccountID: Int) {
        guard topicID > 0, actorAccountID > 0 else { phase = .failed(.invalid); return }
        if blocked { phase = .failed(.unknown); return }
        do {
            if let intent = try intents.load() {
                // Refresh, a new screen, or a new process must not drop an unresolved write.
                self.topicID = intent.topicID
                self.actorAccountID = intent.actorAccountID
                phase = .unknown(ChapterReplacementInvitationPlan.restored(intent))
                return
            }
        } catch {
            blocked = true
            phase = .failed(.unknown)
            return
        }
        if self.topicID == topicID, self.actorAccountID == actorAccountID, phase != .idle { return }
        generation += 1
        self.topicID = topicID; self.actorAccountID = actorAccountID
        vacancies = []; candidates = []; selectedVacancy = nil
        phase = .idle
    }

    public func loadVacancies() async {
        if blocked { phase = .failed(.unknown); return }
        guard let topicID, actorAccountID != nil else { phase = .failed(.noSelection); return }
        if case .sending = phase { return }
        if case .unknown = phase { return }
        let ticket = generation
        phase = .loadingVacancies
        do {
            let rows = try await effects.loadVacancyRows(topicID)
            guard ticket == generation, self.topicID == topicID else { return }
            vacancies = ChapterReplacementInvitationVacancy.vacancies(rows: rows)
                .filter { $0.topicID == topicID }
            candidates = []; selectedVacancy = nil
            phase = .ready
        } catch {
            guard ticket == generation else { return }
            phase = .failed((error as? ChapterReplacementInvitationFailure) ?? .unknown)
        }
    }

    /// Location is optional: `nil` coordinates (permission refused) still query by topic.
    public func loadCandidates(for vacancy: ChapterReplacementInvitationVacancy,
                               coordinates: ChapterReplacementInvitationCoordinates? = nil) async {
        if blocked { phase = .failed(.unknown); return }
        guard let topicID, actorAccountID != nil else { phase = .failed(.noSelection); return }
        if case .sending = phase { return }
        if case .unknown = phase { return }
        guard vacancy.topicID == topicID, vacancies.contains(vacancy) else { phase = .failed(.candidateMismatch); return }
        let ticket = generation
        selectedVacancy = vacancy
        phase = .loadingCandidates
        do {
            let request = try ChapterReplacementInvitationInvitableRequest(topicID: topicID, coordinates: coordinates)
            let rows = try await effects.loadCandidateRows(request)
            guard ticket == generation, self.topicID == topicID, selectedVacancy == vacancy else { return }
            candidates = ChapterReplacementInvitationCandidate.candidates(rows: rows, vacancy: vacancy)
            phase = .ready
        } catch {
            guard ticket == generation else { return }
            phase = .failed((error as? ChapterReplacementInvitationFailure) ?? .unknown)
        }
    }

    /// Builds the frozen review plan from fresh existing-application rows.
    public func prepare(candidate: ChapterReplacementInvitationCandidate,
                        scope: ChapterReplacementInvitationScope,
                        merchantAccess: MerchantAccess?,
                        publisherProof: ChapterReplacementInvitationPublisherProof?,
                        message: String = "") async {
        if blocked { phase = .failed(.unknown); return }
        if case .sending = phase { return }
        if case .unknown = phase { return }
        // No approved fresh publisher read was injected. Do not invent one.
        guard let publisherProof else { phase = .failed(.notTopicPublisher); return }
        guard let topicID, let actorAccountID, let vacancy = selectedVacancy else { phase = .failed(.noSelection); return }
        guard candidates.contains(candidate) else { phase = .failed(.candidateMismatch); return }
        let ticket = generation
        do {
            let rows = try await effects.loadExistingRows(topicID, scope)
            guard ticket == generation, self.topicID == topicID, self.actorAccountID == actorAccountID else { return }
            let plan = try ChapterReplacementInvitationPlan.make(
                topicID: topicID, scope: scope, actorAccountID: actorAccountID,
                merchantAccess: merchantAccess, publisherProof: publisherProof,
                vacancy: vacancy, candidate: candidate,
                existing: ChapterReplacementInvitationExisting.existing(rows: rows), message: message)
            phase = .reviewing(plan)
        } catch {
            guard ticket == generation else { return }
            phase = .failed((error as? ChapterReplacementInvitationFailure) ?? .unknown)
        }
    }

    public func cancelReview() {
        if case .reviewing = phase { phase = .ready }
    }

    /// Dispatches the frozen plan exactly once, then proves the result by exact-tuple
    /// readback on both owner legs before refreshing the vacancy list.
    public func confirmSend() async {
        if blocked { phase = .failed(.unknown); return }
        guard case .reviewing(let plan) = phase else { return }
        guard let topicID, let actorAccountID else { phase = .failed(.noSelection); return }
        do { try plan.validateCurrent(topicID: topicID, actorAccountID: actorAccountID) }
        catch { phase = .failed(.staleTopic); return }
        let ticket = generation
        let intent = ChapterReplacementInvitationIntent(plan: plan)
        phase = .sending(plan)
        // Persist before the request leaves. A crash mid-flight stays locked and cannot send twice.
        do { try intents.save(intent) } catch {
            guard ticket == generation else { return }
            phase = .failed(.unknown)
            return
        }
        sendAttempts += 1
        do {
            try await effects.sendInvite(plan)
        } catch {
            guard ticket == generation else { return }
            // A definitive adapter rejection is reported; anything ambiguous is UNKNOWN.
            if let failure = error as? ChapterReplacementInvitationFailure, failure != .unknown {
                do { try intents.clear(intent) } catch { phase = .unknown(plan); return }
                phase = .failed(failure)
            } else {
                phase = .unknown(plan)
            }
            return
        }
        guard ticket == generation, self.topicID == topicID else { return }
        await verify(plan: plan, ticket: ticket, refreshVacanciesOnSuccess: true)
    }

    /// UNKNOWN recovery: read-only exact-tuple verification. Never sends again.
    /// Safe to call repeatedly, including after a late server-side fill.
    public func verifyUnknown() async {
        guard case .unknown(let plan) = phase else { return }
        await verify(plan: plan, ticket: generation, refreshVacanciesOnSuccess: true)
    }

    private func verify(plan: ChapterReplacementInvitationPlan, ticket: Int, refreshVacanciesOnSuccess: Bool) async {
        do {
            let list = try await effects.loadOwnerListRows(
                ChapterReplacementInvitationOwnerListRequest(topicID: plan.topicID, scope: plan.scope))
            let mine = try await effects.loadOwnerMineRows(
                ChapterReplacementInvitationOwnerMineRequest(scope: plan.scope))
            guard ticket == generation, topicID == plan.topicID, actorAccountID == plan.actorAccountID else { return }
            let verified = try ChapterReplacementInvitationReadback.verify(ownerList: list, ownerMine: mine, plan: plan)
            do { try intents.clear(ChapterReplacementInvitationIntent(plan: plan)) } catch {
                guard ticket == generation else { return }
                phase = .unknown(plan)
                return
            }
            phase = .verified(verified)
            if refreshVacanciesOnSuccess { await loadVacanciesKeepingSelection() }
        } catch ChapterReplacementInvitationFailure.notFound {
            guard ticket == generation else { return }
            phase = .unknown(plan)
        } catch {
            guard ticket == generation else { return }
            let failure = (error as? ChapterReplacementInvitationFailure) ?? .unknown
            // A mismatched/duplicate readback still proves something landed; stay in
            // UNKNOWN (no resend) instead of offering another dispatch.
            phase = (failure == .stateMismatch || failure == .duplicateReadback) ? .unknown(plan) : .failed(failure)
        }
    }

    private func loadVacanciesKeepingSelection() async {
        guard let topicID else { return }
        let ticket = generation
        if let rows = try? await effects.loadVacancyRows(topicID), ticket == generation, self.topicID == topicID {
            vacancies = ChapterReplacementInvitationVacancy.vacancies(rows: rows).filter { $0.topicID == topicID }
            if let selectedVacancy, !vacancies.contains(selectedVacancy) {
                self.selectedVacancy = nil; candidates = []
            }
        }
    }
}

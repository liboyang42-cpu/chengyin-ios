import Foundation
import Observation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Opaque, one-shot durable dispatch. Only this coordinator file can construct or retire it.
@MainActor final class PlayPreparedDispatch {
    let request: URLRequest
    let baseURL: URL
    let capability: PlayExperienceCapability
    private enum Proof {
        case completion(any PlayCompletionRecoveryStore, PlayCompletionRecoverySnapshot)
        case paused(any PlayPausedStorage, PlayPausedStorageSnapshot)
    }
    private let proof: Proof
    private let key: String
    private let isCurrent: () -> Bool
    private var started = false
    private var retired = false
    fileprivate init(service: PlayExperienceService, scope: PlaySessionScope, session: PlayExperienceSession,
                     completion: PlayCompletionRecoverySnapshot, store: any PlayCompletionRecoveryStore, isCurrent: @escaping () -> Bool) throws {
        guard completion.value.state == .dispatching, completion.value.intent.owner.matches(session), completion.value.intent.gameplayMode != nil else { throw PlayExperienceError.persistenceUnavailable }
        let intent = completion.value.intent
        request = try service.completionRequest(scope: scope, nodeID: intent.nodeID, evidence: intent.evidence,
            advance: intent.advance, token: session.token, boundary: intent.id.uuidString)
        baseURL = service.configuration.baseURL; capability = .classicCompletion; proof = .completion(store, completion)
        key = PlayRunStorageKey.make(session: session, scope: scope); self.isCurrent = isCurrent
    }
    fileprivate init(service: PlayExperienceService, scope: PlaySessionScope, session: PlayExperienceSession,
                     paused: PlayPausedStorageSnapshot, store: any PlayPausedStorage, isCurrent: @escaping () -> Bool) throws {
        guard let value = paused.value, value.owner.matches(session) else { throw PlayExperienceError.persistenceUnavailable }
        request = try service.pausedRequest(scope: scope, record: value.record, savedAt: value.record?.savedAt ?? value.tombstone, token: session.token)
        baseURL = service.configuration.baseURL; capability = .runPersistence; proof = .paused(store, paused)
        key = PlayRunStorageKey.make(session: session, scope: scope); self.isCurrent = isCurrent
    }
    fileprivate func retire() { retired = true }
    func consume(request: URLRequest, transport: any HTTPTransport) async throws {
        guard !started, !retired, request == self.request else { throw PlayExperienceError.persistenceUnavailable }
        started = true; try checkLifetime()
        switch proof {
        case .completion(let store, let expected):
            guard transport is PlayRecoveryRecordingTransport || (store as? PlayDurableRecovery)?.permitsSystemDispatch(to: baseURL) == true,
                  try await store.read(key) == expected else { throw PlayExperienceError.persistenceUnavailable }
        case .paused(let store, let expected):
            guard transport is PlayRecoveryRecordingTransport || (store as? PlayDurableRecovery)?.permitsSystemDispatch(to: baseURL) == true,
                  try await store.read(key: key) == expected else { throw PlayExperienceError.persistenceUnavailable }
        }
        try checkLifetime()
    }
    func checkLifetime() throws {
        guard started, !retired, isCurrent(), !retired else { throw PlayExperienceError.staleSession }
        try Task.checkCancellation()
    }
}

/// An ephemeral command belongs to the exact rendered read, not just a node ID.
/// It cannot be constructed by a view, persisted, or reused after a refresh.
public struct PlayInteractionContext: Equatable {
    fileprivate let owner: UUID
    fileprivate let session: PlayExperienceSession
    fileprivate let generation: UInt64
    fileprivate let mode: PlayGameplayMode
    var authoritativeMode: PlayGameplayMode { mode }
    var lifetimeIdentity: String { "\(owner.uuidString):\(generation):\(mode.rawValue)" }
}

public struct PlayCompletionReview: Equatable {
    public let nodeID: Int
    public let evidence: PlayCompletionEvidence
    public let advance: PlayRouteAdvance?
    let session: PlayExperienceSession
    let generation: UInt64
    let routeSessionID: Int?
    let gameplayMode: PlayGameplayMode?
    let id: UUID
    init(nodeID: Int, evidence: PlayCompletionEvidence, advance: PlayRouteAdvance?, session: PlayExperienceSession, generation: UInt64, routeSessionID: Int?, id: UUID = UUID(), gameplayMode: PlayGameplayMode? = nil) {
        self.nodeID = nodeID; self.evidence = evidence; self.advance = advance; self.session = session
        self.generation = generation; self.routeSessionID = routeSessionID; self.id = id; self.gameplayMode = gameplayMode
    }
}
/// Independent of the existing linear-answer reader. A successful write invalidates the
/// snapshot; only authoritative readback changes progress. No hidden write retries.
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayExperienceCoordinator {
    public let scope: PlaySessionScope
    private var storedSnapshot: PlaySnapshot?
    /// Every display read rechecks the caller's live session/approval lease.
    public private(set) var snapshot: PlaySnapshot? {
        get { loadedSession != nil && loadedSession == currentSession() ? storedSnapshot : nil }
        set { storedSnapshot = newValue }
    }
    public private(set) var extras: [Int: PlayNodeExtras] = [:]
    public private(set) var chapterStories: [Int: ChapterStoryDocument] = [:]
    public private(set) var storyVariables: [String: PlayWireValue] = [:]
    public private(set) var storyVoices: [String: PlayWireValue] = [:]
    public private(set) var storyThoughts: [PlayWireValue] = []
    public private(set) var thoughtSyncPhase: ChapterThoughtSyncPhase = .idle
    public private(set) var pendingThoughtKeys: Set<String> = []
    private var thoughtClaimSessionID: Int?
    private var thoughtSyncInFlight = false
    private var thoughtSyncNonce = UUID()
    public private(set) var phase: Phase = .idle
    public private(set) var issue: PlayExperienceError?
    public private(set) var reward: PlayWireValue?
    public private(set) var hint: PlayHintReceipt?
    public private(set) var ending: PlayEndingDocument?
    public private(set) var leaderboard: PlayCompanionLeaderboard?
    public private(set) var lead: PlayLeadProgress?
    public private(set) var clock = PlayRunClock()
    public private(set) var remoteRunSaveFailed = false
    public private(set) var unresolved = false
    public private(set) var leaderOutcomeUnknown = false
    public enum Phase: String { case idle, loading, ready, reviewing, submitting, needsReadback, unknown, failed }
    private let service: PlayExperienceService
    private let currentSession: () -> PlayExperienceSession?
    private let recovery: any PlayCompletionRecoveryStore
    private let pausedStorage: any PlayPausedStorage
    private let onUnauthorized: (PlayExperienceSession) -> Void
    private var cachedCompletion: PlayCompletionRecoverySnapshot?
    private var retryReadbackVerified = false
    private var pausedLease: PlayPausedStorageSnapshot?
    private var pausedOwner: PlayExperienceSession?
    private var completionAttempt: PlayPreparedDispatch?
    private var runAttempt: PlayPreparedDispatch?
    private var completionTask: Task<PlayWireValue, Error>?
    private var completionTaskID = UUID()
    private var runTask: Task<Void, Error>?
    private var runTaskID = UUID()
    private var runStorageBusy = false
    public private(set) var localRecoveryFailed = false
    private var loadedSession: PlayExperienceSession?
    private var authorityOwner: PlayExperienceSession?
    private var authorityMode: PlayGameplayMode?
    private var unknownLeaderKeys: Set<String> = []
    @ObservationIgnored private var issuedInteractionLifetime: PlayInteractionLifetime?
    private let interactionOwner = UUID()
    private var generation: UInt64 = 0
    private var advancedReadyNodeIDs: Set<Int> = []
    private var hintUnknownNodes: Set<Int> = []
    private var unknownHintRequests: [String: [Int: Int]] = [:]
    public var identity: String? {
        currentSession().map { PlayRunStorageKey.make(session: $0, scope: scope) + ":" + String($0.epoch) }
    }
    public var hasModeRecoveryBlock: Bool {
        guard let mode = gameplayMode, let pending = cachedCompletion?.value else { return false }
        return pending.intent.gameplayMode != mode
    }
    public var available: Bool { service.enabled.contains(.reads) }
    public var gameplayMode: PlayGameplayMode? { PlayGameplayMode(serverValue: snapshot?.result.mode) }
    public var interactionContext: PlayInteractionContext? {
        guard phase == .ready, let session = loadedSession, session == currentSession(),
              let mode = gameplayMode else { return nil }
        return .init(owner: interactionOwner, session: session, generation: generation, mode: mode)
    }
    public func makeInteractionLifetime() -> PlayInteractionLifetime? {
        guard let context = interactionContext else { return nil }
        if let issuedInteractionLifetime, issuedInteractionLifetime.identity == context.lifetimeIdentity { return issuedInteractionLifetime }
        let request = generation
        let lifetime = PlayInteractionLifetime(context: context,
            current: { [weak self] in self?.interactionContext },
            onRetired: { [weak self] in self?.retireChildRead(generation: request) })
        issuedInteractionLifetime = lifetime
        return lifetime
    }
    private func retireChildRead(generation request: UInt64) {
        guard generation == request else { return }
        generation &+= 1; loadedSession = nil; snapshot = nil; extras = [:]
        reward = nil; hint = nil; ending = nil; leaderboard = nil; lead = nil; advancedReadyNodeIDs = []
        // Keep durable completion/pause records and pending thought keys intact.
        // Nothing about a changed mode proves an earlier mutation's outcome.
        thoughtSyncNonce = UUID(); thoughtSyncInFlight = false
        runAttempt?.retire(); runAttempt = nil; runTask?.cancel(); runTask = nil; runTaskID = UUID()
        pausedLease = nil; pausedOwner = nil; clock.restore(nil)
        issue = .staleSession; phase = .needsReadback
    }
    private func accepts(_ context: PlayInteractionContext?) -> Bool {
        guard let context, let current = interactionContext else { return false }
        return context == current
    }
    /// Read authority only; audio never grants gameplay completion authority.
    public var hasCurrentMediaSnapshot: Bool {
        snapshot != nil && loadedSession != nil && loadedSession == currentSession() && (phase == .ready || phase == .unknown)
    }
    /// A read-only projection must not enable completion, hint or leader controls.
    public var canWrite: Bool { !service.enabled.isDisjoint(with: [.classicCompletion, .hints, .leader, .thoughtClaims]) && phase == .ready && !unresolved && !thoughtSyncInFlight && pendingThoughtKeys.isEmpty && loadedSession != nil && loadedSession == currentSession() }
    /// Run state and durable pause records require their own reviewed capability.
    public var canManageRun: Bool { gameplayMode == .cityOrientation && service.enabled.contains(.runPersistence) && hasCurrentMediaSnapshot && !localRecoveryFailed && pausedLease?.value?.pendingRemote != true }
    public init(scope: PlaySessionScope, service: PlayExperienceService, recovery: any PlayCompletionRecoveryStore,
                pausedStorage: any PlayPausedStorage, currentSession: @escaping () -> PlayExperienceSession?,
                onUnauthorized: @escaping (PlayExperienceSession) -> Void = { _ in }) {
        self.scope = scope; self.service = service; self.recovery = recovery; self.pausedStorage = pausedStorage
        self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    public func load() async {
        guard phase != .submitting else { return }
        generation &+= 1; let request = generation
        phase = .loading; issue = nil; snapshot = nil; extras = [:]; cachedCompletion = nil; retryReadbackVerified = false
        guard let session = currentSession(), scope.isValid else { phase = .failed; issue = .staleSession; return }
        if authorityOwner != session {
            reward = nil; hint = nil; ending = nil; leaderboard = nil; lead = nil
            advancedReadyNodeIDs = []
            hintUnknownNodes = Set((unknownHintRequests[PlayRunStorageKey.make(session: session, scope: scope)] ?? [:]).keys)
            leaderOutcomeUnknown = unknownLeaderKeys.contains(PlayRunStorageKey.make(session: session, scope: scope))
            authorityOwner = session
            chapterStories = [:]; storyVariables = [:]; storyVoices = [:]; storyThoughts = []
            pendingThoughtKeys = []; thoughtClaimSessionID = nil; thoughtSyncInFlight = false; thoughtSyncPhase = .idle; thoughtSyncNonce = UUID()
        }
        loadedSession = nil
        do {
            let key = PlayRunStorageKey.make(session: session, scope: scope)
            var pending = try await recovery.read(key)
            try check(session, request)
            if let pending { guard pending.value.intent.owner.matches(session) else { throw PlayExperienceError.persistenceUnavailable } }
            let document = try await service.nodes(scope: scope, token: session.token)
            try check(session, request)
            let route = document.base.routeState?.isBranch == true ? try await service.route(scope: scope, token: session.token) : nil
            try check(session, request)
            let snapshot = try PlaySnapshot(scope: scope, result: document.base, authority: route)
            if let captured = pending, landed(captured.value.intent, snapshot: snapshot) {
                try await recovery.clear(captured, key: key)
                try check(session, request); pending = nil
            }
            cachedCompletion = pending; retryReadbackVerified = true
            var hintRequests = unknownHintRequests[key] ?? [:]
            for (nodeID, level) in hintRequests {
                guard let detail = document.extras[nodeID] else { continue }
                if level == -1, detail.hintLocked == false, detail.hint1?.isEmpty == false || detail.hint2?.isEmpty == false { hintRequests.removeValue(forKey: nodeID) }
                else if level >= 1, (detail.puzzleHintLevel ?? 0) >= level, !detail.usedHints.isEmpty { hintRequests.removeValue(forKey: nodeID) }
            }
            unknownHintRequests[key] = hintRequests; hintUnknownNodes = Set(hintRequests.keys)
            unresolved = pending != nil || !hintUnknownNodes.isEmpty || leaderOutcomeUnknown
            let mode = PlayGameplayMode(serverValue: snapshot.result.mode)
            if authorityMode != mode {
                reward = nil; hint = nil; ending = nil; leaderboard = nil; lead = nil
                advancedReadyNodeIDs = []
            }
            authorityMode = mode
            self.snapshot = snapshot; extras = document.extras; loadedSession = session
            if mode != .cityOrientation {
                // Discard only in-memory orientation state. Free exploration does
                // not read, clear or rewrite its durable pause records.
                runAttempt?.retire(); runAttempt = nil; runTask?.cancel(); runTask = nil; runTaskID = UUID()
                pausedLease = nil; pausedOwner = nil; clock.restore(nil)
                remoteRunSaveFailed = false; localRecoveryFailed = false
            }
            chapterStories = document.chapterStories
            storyVariables.merge(document.storyVariables) { _, new in new }
            storyVoices.merge(document.storyVoices) { _, new in new }
            storyThoughts = snapshot.route?.thoughts ?? document.storyThoughts
            if let previous = thoughtClaimSessionID, let current = snapshot.route?.sessionID, previous != current {
                pendingThoughtKeys = []; thoughtClaimSessionID = nil; thoughtSyncPhase = .idle
            }
            if !pendingThoughtKeys.isEmpty {
                pendingThoughtKeys.subtract(storyThoughts.compactMap { $0["key"].text })
                thoughtSyncPhase = pendingThoughtKeys.isEmpty ? .synced : .needsReadback
                unresolved = unresolved || !pendingThoughtKeys.isEmpty
            }
            phase = unresolved ? .unknown : .ready
        } catch { fail(error, session: session, generation: request) }
    }
    public func claimVisibleThoughts(chapterID: Int) async {
        guard service.enabled.contains(.thoughtClaims) else { thoughtSyncPhase = .disabled; return }
        guard canWrite, hasCurrentMediaSnapshot, let snapshot, snapshot.availability == .active,
              let chapter = chapterStories[chapterID], let topicID = snapshot.result.topicID,
              let routeSessionID = snapshot.route?.sessionID, let version = snapshot.route?.version,
              let session = loadedSession, session == currentSession(), !thoughtSyncInFlight, pendingThoughtKeys.isEmpty else { return }
        let claims = ChapterStoryProjection.claimableThoughtKeys(chapter: chapter, snapshot: snapshot, thoughts: storyThoughts)
        guard !claims.isEmpty else { return }
        let nonce = UUID(); thoughtSyncNonce = nonce; thoughtSyncInFlight = true
        let request = generation
        pendingThoughtKeys = Set(claims); thoughtClaimSessionID = routeSessionID; thoughtSyncPhase = .syncing
        defer { if thoughtSyncNonce == nonce { thoughtSyncInFlight = false } }
        do {
            _ = try await service.syncChapterThoughts(scope: scope, topicID: topicID, claims: claims,
                sessionID: routeSessionID, previousVersion: version, token: session.token)
            try check(session, request)
            thoughtSyncPhase = .needsReadback
            await load() // Only a fresh nodes + route read projects names and completion facts.
        } catch {
            guard thoughtSyncNonce == nonce, currentSession() == session else { return }
            if error as? PlayExperienceError == .unauthorized { onUnauthorized(session); invalidate(); return }
            // No implicit retry after a possibly committed claim. Reopening must read first.
            thoughtSyncPhase = pendingThoughtKeys.isEmpty ? .synced : .needsReadback
            unresolved = unresolved || !pendingThoughtKeys.isEmpty
        }
    }
    /// Called only from an accepted advanced state, never a local timer or preview.
    public func acceptAdvanced(_ state: PlayAdvancedState, context: PlayInteractionContext? = nil) throws {
        guard accepts(context), loadedSession == currentSession(), let snapshot,
              state.nodeID > 0, snapshot.visibleNodes.contains(where: { $0.id == state.nodeID }),
              state.topicID == snapshot.result.topicID, state.readyForBase else { throw PlayExperienceError.invalidAction }
        switch scope {
        case .activity(let id): guard state.activityID == id else { throw PlayExperienceError.invalidAction }
        case .topic: guard state.activityID == 0 else { throw PlayExperienceError.invalidAction }
        }
        advancedReadyNodeIDs.insert(state.nodeID)
    }
    /// UI/provider callbacks must present the authority captured when offered.
    public func review(nodeID: Int, evidence: PlayCompletionEvidence, context: PlayInteractionContext?) throws -> PlayCompletionReview {
        guard accepts(context) else { throw PlayExperienceError.staleSession }
        return try review(nodeID: nodeID, evidence: evidence)
    }
    public func review(nodeID: Int, evidence: PlayCompletionEvidence) throws -> PlayCompletionReview {
        guard service.enabled.contains(.classicCompletion), canWrite, let session = loadedSession, let snapshot,
              snapshot.availability == .active,
              let node = snapshot.visibleNodes.first(where: { $0.id == nodeID }),
              !snapshot.isDone(node), !snapshot.isLocked(node), node.done == false else { throw PlayExperienceError.invalidAction }
        let task: PlayNodeTask
        if gameplayMode == .freeExploration {
            guard let merchantTask = FreeExplorationPresentation.evidenceTask(for: node, in: snapshot) else { throw PlayExperienceError.unsupported }
            task = merchantTask
        } else {
            guard gameplayMode == .cityOrientation else { throw PlayExperienceError.unsupported }
            guard !node.hasAdvancedPrerequisite || advancedReadyNodeIDs.contains(nodeID) else { throw PlayExperienceError.invalidAction }
            task = PlayNodeTask.resolve(mode: snapshot.result.mode, node: node)
        }
        switch (task, evidence) {
        case (.answer, .answer(let text)):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  node.validationMethod != 3 || node.options?[text] != nil else { throw PlayExperienceError.invalidAction }
            guard (node.needScan != true && node.needGPS != true) || node.arrived == true else { throw PlayExperienceError.invalidAction }
        case (.scan, .scan), (.merchantScan, .scan), (.photo, .photo), (.merchantPhoto, .photo), (.arrive, .location): break
        case (.sensor, .sensor(let type, let payload)):
            guard type == node.sensorType, type == "still", let config = try? PlayStillnessConfiguration(raw: extras[nodeID]?.sensorConfig ?? .null),
                  payload.keys.sorted() == ["heldSec"], payload["heldSec"]?.integer == config.durationSeconds else { throw PlayExperienceError.invalidAction }
        default: throw PlayExperienceError.unsupported
        }
        let advance: PlayRouteAdvance?
        if snapshot.route?.isBranch == true {
            guard let version = snapshot.route?.version else { throw PlayExperienceError.invalidAction }
            advance = try PlayRouteAdvance(actionID: UUID().uuidString, expectedVersion: version)
        } else { advance = nil }
        phase = .reviewing
        return PlayCompletionReview(nodeID: nodeID, evidence: evidence, advance: advance, session: session, generation: generation, routeSessionID: snapshot.route?.sessionID, gameplayMode: gameplayMode)
    }
    public func cancelReview() { if phase == .reviewing { phase = .ready } }
    public func submit(_ review: PlayCompletionReview) async {
        guard service.enabled.contains(.classicCompletion), review.gameplayMode == gameplayMode, gameplayMode != nil, phase == .reviewing, review.session == currentSession(), review.session == loadedSession,
              review.generation == generation, !unresolved else { return }
        await dispatch(review)
    }
    private func dispatch(_ review: PlayCompletionReview, recovering: PlayCompletionRecoverySnapshot? = nil) async {
        let session = review.session, request = generation, key = PlayRunStorageKey.make(session: review.session, scope: scope)
        // Fence synchronously before any storage suspension. Other viewers are fenced by CAS.
        unresolved = true; phase = .submitting; reward = nil; retryReadbackVerified = false
        var ticket: PlayCompletionRecoverySnapshot?
        var sent = false
        do {
            let prepared: PlayCompletionRecoverySnapshot
            if let recovering { prepared = recovering }
            else { prepared = try await recovery.prepare(.init(review: review), key: key) }
            ticket = prepared; try check(session, request)
            let dispatched = try await recovery.transition(prepared, to: .dispatching, key: key)
            ticket = dispatched; cachedCompletion = dispatched; try check(session, request)
            sent = true
            let attempt = try PlayPreparedDispatch(service: service, scope: scope, session: session, completion: dispatched, store: recovery,
                isCurrent: { [weak self] in guard let self else { return false }; return self.generation == request && self.currentSession() == session })
            completionAttempt = attempt
            let taskID = UUID(); completionTaskID = taskID
            let service = self.service
            let task = Task { try await service.dispatch(attempt) }
            completionTask = task
            defer { attempt.retire(); if completionTaskID == taskID { completionTask = nil; completionAttempt = nil } }
            let receipt = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try check(session, request)
            guard receipt["nodeId"].tolerantInteger == review.nodeID else { throw PlayExperienceError.malformed }
            let acknowledged = try await recovery.transition(dispatched, to: .acknowledged, key: key)
            ticket = acknowledged; try check(session, request); cachedCompletion = acknowledged
            reward = receipt; phase = .needsReadback; await load()
        } catch {
            guard generation == request else { return }
            guard currentSession() == session else { invalidate(); return }
            // A storage error is never converted into an empty bucket or a safe-to-send state.
            if error as? PlayExperienceError == .persistenceUnavailable {
                localRecoveryFailed = true; issue = .persistenceUnavailable; phase = .unknown; return
            }
            if let ticket, sent {
                do {
                    switch error {
                    case PlayExperienceError.disabled:
                        if recovering == nil || recovering?.value.state == .prepared {
                            try await recovery.clear(ticket, key: key)
                            try check(session, request); cachedCompletion = nil; unresolved = false
                        } else {
                            // Disabled retry cannot establish the outcome of the original write.
                            let unknown = try await recovery.transition(ticket, to: .unknown, key: key)
                            try check(session, request); cachedCompletion = unknown
                        }
                    default:
                        // Generic business errors (including 4xx/5xx envelope codes) do not
                        // establish no commit. Keep the exact intent until matching readback.
                        let unknown = try await recovery.transition(ticket, to: .unknown, key: key)
                        try check(session, request); cachedCompletion = unknown
                    }
                } catch {
                    guard currentSession() == session, generation == request else { return }
                    localRecoveryFailed = true; issue = .persistenceUnavailable; phase = .unknown; return
                }
            }
            if case PlayExperienceError.rejected(let code, _) = error, code == 409 {
                phase = .needsReadback; await load(); return
            }
            fail(error, session: session, generation: request)
            if unresolved { phase = .unknown }
        }
    }
    /// Only a verified readback offers replay. The dispatch CAS rechecks its exact generation.
    public var canRetryExactBranch: Bool {
        guard gameplayMode == .cityOrientation, service.enabled.contains(.classicCompletion), phase == .unknown, retryReadbackVerified, hintUnknownNodes.isEmpty, !leaderOutcomeUnknown,
              let session = loadedSession, session == currentSession(), let snapshot,
              let pending = cachedCompletion?.value, pending.intent.gameplayMode == gameplayMode, let advance = pending.intent.advance,
              !pending.requestAcknowledged, pending.intent.owner.matches(session),
              pending.state != .dispatching || pending.dispatchProcess != recovery.processID,
              snapshot.route?.sessionID == pending.intent.routeSessionID,
              snapshot.route?.version == advance.expectedVersion,
              snapshot.route?.nodeStates[pending.intent.nodeID] == "PLAYABLE" else { return false }
        return true
    }
    public func retryExactBranchAfterReadback() async {
        guard canRetryExactBranch, let session = loadedSession, let pending = cachedCompletion,
              let review = try? pending.value.intent.review(session: session, generation: generation) else { return }
        await dispatch(review, recovering: pending)
    }
    public func requestHint(nodeID: Int, level: Int?, context: PlayInteractionContext? = nil) async {
        // Puzzle scoring is orientation-only. Generic template hints have their
        // own source authority and are not reclassified by entry scope.
        guard accepts(context), level == nil || gameplayMode == .cityOrientation,
              service.enabled.contains(.hints), canWrite, !hintUnknownNodes.contains(nodeID), let session = loadedSession,
              let node = snapshot?.visibleNodes.first(where: { $0.id == nodeID }), snapshot?.isLocked(node) == false else { return }
        let request = generation; phase = .submitting; hintUnknownNodes.insert(nodeID)
        let hintKey = PlayRunStorageKey.make(session: session, scope: scope)
        unknownHintRequests[hintKey, default: [:]][nodeID] = level ?? -1
        do {
            let receipt = try await service.hint(scope: scope, nodeID: nodeID, level: level, token: session.token)
            try check(session, request); hint = receipt; hintUnknownNodes.remove(nodeID); unknownHintRequests[hintKey]?.removeValue(forKey: nodeID); phase = .needsReadback; await load()
        } catch {
            if case PlayExperienceError.rejected = error { hintUnknownNodes.remove(nodeID); unknownHintRequests[hintKey]?.removeValue(forKey: nodeID) }
            if case PlayExperienceError.disabled = error { hintUnknownNodes.remove(nodeID); unknownHintRequests[hintKey]?.removeValue(forKey: nodeID) }
            unresolved = !hintUnknownNodes.isEmpty
            fail(error, session: session, generation: request)
        }
    }
    /// Free exploration reads its own ending only after authoritative redemption.
    /// No orientation leaderboard or completion command is inferred from card count.
    public func loadFreeExplorationEnding() async {
        guard gameplayMode == .freeExploration, hasCurrentMediaSnapshot, let snapshot,
              FreeExplorationPresentation(snapshot: snapshot)?.isFullyRedeemed == true,
              let session = loadedSession, session == currentSession(), phase != .submitting else { return }
        let request = generation
        do { let value = try await service.ending(scope: scope, token: session.token); try check(session, request); ending = value }
        catch { fail(error, session: session, generation: request) }
    }
    public func loadEndingAndLeaderboard() async {
        guard gameplayMode == .cityOrientation, let session = loadedSession, session == currentSession(), phase != .submitting else { return }
        let request = generation
        do {
            let ending = try await service.ending(scope: scope, token: session.token); try check(session, request); self.ending = ending
            let board = try await service.leaderboard(scope: scope, token: session.token); try check(session, request)
            guard board.me.id == session.accountID else { throw PlayExperienceError.malformed }; leaderboard = board
        } catch { fail(error, session: session, generation: request) }
    }
    public func loadLead(context: PlayInteractionContext? = nil) async {
        // The source's club lead tools are mode-independent, but a queued
        // request from an earlier render must not acquire a new mode's lease.
        guard accepts(context), case .activity(let activity) = scope, let session = currentSession(), phase != .submitting else { return }
        let request = generation
        do { let result = try await service.teamProgress(activityID: activity, token: session.token); try check(session, request); lead = result }
        catch { fail(error, session: session, generation: request) }
    }
    public func performLead(_ action: PlayLeadAction, text: String? = nil, context: PlayInteractionContext? = nil) async {
        guard accepts(context), service.enabled.contains(.leader), canWrite, !leaderOutcomeUnknown, let session = loadedSession, case .activity(let activity) = scope,
              lead?.allows(action, accountID: session.accountID) == true else { return }
        let request = generation; phase = .submitting; leaderOutcomeUnknown = true
        let leaderKey = PlayRunStorageKey.make(session: session, scope: scope); unknownLeaderKeys.insert(leaderKey)
        do {
            try await service.lead(activityID: activity, action: action, text: text, token: session.token)
            try check(session, request); leaderOutcomeUnknown = false; unknownLeaderKeys.remove(leaderKey); phase = .needsReadback
            await load(); await loadLead(context: interactionContext)
        } catch {
            if case PlayExperienceError.rejected = error { leaderOutcomeUnknown = false; unknownLeaderKeys.remove(leaderKey) }
            if case PlayExperienceError.disabled = error { leaderOutcomeUnknown = false; unknownLeaderKeys.remove(leaderKey) }
            fail(error, session: session, generation: request)
        }
    }
    public func restoreRun() async {
        guard gameplayMode == .cityOrientation, hasCurrentMediaSnapshot,
              service.enabled.contains(.runPersistence), let session = loadedSession, session == currentSession(), !runStorageBusy else { return }
        runStorageBusy = true; defer { runStorageBusy = false }
        let request = generation, key = PlayRunStorageKey.make(session: session, scope: scope)
        await reconcileRun(session: session, request: request, key: key)
    }
    private func reconcileRun(session: PlayExperienceSession, request: UInt64, key: String) async {
        do {
            let local = try await pausedStorage.read(key: key); try check(session, request)
            if let value = local.value { guard value.owner.matches(session) else { throw PlayExperienceError.persistenceUnavailable } }
            // Network read failure may retain a verified local record; local failures never fall back.
            let remote: PlayPausedRead?
            do { remote = try await service.readPaused(scope: scope, token: session.token) }
            catch {
                try check(session, request)
                if error as? PlayExperienceError == .unauthorized { onUnauthorized(session); invalidate(); return }
                remote = nil
            }
            try check(session, request)
            let tombstone = max(local.value?.tombstone ?? 0, remote?.endedAt ?? 0)
            let candidate = PlayPausedRecord.reconcile(local: local.value?.record, remote: remote)
            let reconciled = candidate.flatMap { $0.savedAt > tombstone ? $0 : nil }
            let remoteConfirms: Bool
            if let old = local.value, old.pendingRemote {
                if let record = old.record { remoteConfirms = remote?.record == record || (remote?.endedAt ?? 0) >= record.savedAt }
                else { remoteConfirms = (remote?.endedAt ?? 0) >= old.tombstone && old.tombstone > 0 }
            } else { remoteConfirms = true }
            // Settle the exact pending operation first, then apply newer authoritative facts.
            // Each step is generation-CAS; a crash between them still retains safe local state.
            var lease = local
            if let old = local.value, old.pendingRemote, remoteConfirms {
                let settled = try PlayPausedSnapshot(owner: old.owner, record: old.record, tombstone: old.tombstone)
                lease = try await pausedStorage.write(settled, replacing: lease, key: key); try check(session, request)
            }
            let value: PlayPausedSnapshot
            if let old = lease.value, old.pendingRemote { value = old }
            else { value = try .init(owner: .init(session: session), record: reconciled, tombstone: tombstone) }
            if value != lease.value { lease = try await pausedStorage.write(value, replacing: lease, key: key); try check(session, request) }
            pausedLease = lease; pausedOwner = session
            clock.restore(value.record); localRecoveryFailed = false
            remoteRunSaveFailed = value.pendingRemote
        } catch {
            guard currentSession() == session, generation == request else { return }
            localRecoveryFailed = true; issue = .persistenceUnavailable; clock.restore(nil); pausedLease = nil; pausedOwner = nil
        }
    }
    public func startRun(now: TimeInterval) {
        guard canManageRun, let loadedSession, currentSession() == loadedSession, pausedOwner == loadedSession, pausedLease != nil, pausedLease?.value?.pendingRemote != true, !runStorageBusy, !localRecoveryFailed else { return }
        try? clock.start(monotonicNow: now)
    }
    public func pauseRun(now: TimeInterval, savedAt: Int64) async {
        guard canManageRun, let session = loadedSession, currentSession() == session, pausedOwner == session, let old = pausedLease, old.value?.pendingRemote != true, !runStorageBusy,
              let record = try? clock.pause(monotonicNow: now, savedAt: savedAt) else { return }
        runStorageBusy = true; defer { runStorageBusy = false }
        let request = generation, key = PlayRunStorageKey.make(session: session, scope: scope)
        do {
            try check(session, request)
            let value = try PlayPausedSnapshot(owner: .init(session: session), record: record, tombstone: old.value?.tombstone ?? 0, pendingRemote: true)
            let saved = try await pausedStorage.write(value, replacing: old, key: key); try check(session, request)
            pausedLease = saved; localRecoveryFailed = false
        } catch {
            guard currentSession() == session, generation == request else { return }
            localRecoveryFailed = true; remoteRunSaveFailed = true; issue = .persistenceUnavailable; return
        }
        do {
            guard let saved = pausedLease else { throw PlayExperienceError.persistenceUnavailable }
            let attempt = try PlayPreparedDispatch(service: service, scope: scope, session: session, paused: saved, store: pausedStorage,
                isCurrent: { [weak self] in guard let self else { return false }; return self.generation == request && self.currentSession() == session })
            runAttempt = attempt
            let service = self.service, taskID = UUID(); runTaskID = taskID
            let task = Task { _ = try await service.dispatch(attempt) }; runTask = task
            defer { attempt.retire(); if runTaskID == taskID { runTask = nil; runAttempt = nil } }
            try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try check(session, request); await reconcileRun(session: session, request: request, key: key)
        }
        catch {
            guard currentSession() == session, generation == request else { return }
            if error as? PlayExperienceError == .unauthorized { onUnauthorized(session); invalidate(); return }
            remoteRunSaveFailed = true
        }
    }
    /// One atomic local tombstone replaces the record before the dormant remote clear.
    public func endRun(now: TimeInterval, savedAt: Int64) async {
        guard canManageRun, let session = loadedSession, currentSession() == session, pausedOwner == session, let old = pausedLease, old.value?.pendingRemote != true, savedAt > 0, !runStorageBusy else { return }
        runStorageBusy = true; defer { runStorageBusy = false }
        let request = generation, key = PlayRunStorageKey.make(session: session, scope: scope)
        do {
            try check(session, request)
            let value = try PlayPausedSnapshot(owner: .init(session: session), record: nil, tombstone: max(savedAt, old.value?.tombstone ?? 0), pendingRemote: true)
            let saved = try await pausedStorage.write(value, replacing: old, key: key); try check(session, request)
            pausedLease = saved; clock.end(monotonicNow: now); localRecoveryFailed = false
        } catch {
            guard currentSession() == session, generation == request else { return }
            localRecoveryFailed = true; remoteRunSaveFailed = true; issue = .persistenceUnavailable; return
        }
        do {
            guard let saved = pausedLease else { throw PlayExperienceError.persistenceUnavailable }
            let attempt = try PlayPreparedDispatch(service: service, scope: scope, session: session, paused: saved, store: pausedStorage,
                isCurrent: { [weak self] in guard let self else { return false }; return self.generation == request && self.currentSession() == session })
            runAttempt = attempt
            let service = self.service, taskID = UUID(); runTaskID = taskID
            let task = Task { _ = try await service.dispatch(attempt) }; runTask = task
            defer { attempt.retire(); if runTaskID == taskID { runTask = nil; runAttempt = nil } }
            try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try check(session, request); await reconcileRun(session: session, request: request, key: key)
        }
        catch {
            guard currentSession() == session, generation == request else { return }
            if error as? PlayExperienceError == .unauthorized { onUnauthorized(session); invalidate(); return }
            remoteRunSaveFailed = true
        }
    }
    public func invalidate() {
        completionAttempt?.retire(); completionAttempt = nil; runAttempt?.retire(); runAttempt = nil
        completionTask?.cancel(); completionTask = nil; completionTaskID = UUID()
        runTask?.cancel(); runTask = nil; runTaskID = UUID()
        pausedLease = nil; pausedOwner = nil; retryReadbackVerified = false
        thoughtSyncNonce = UUID(); thoughtSyncInFlight = false; pendingThoughtKeys = []; thoughtClaimSessionID = nil; thoughtSyncPhase = .idle
        chapterStories = [:]; storyVariables = [:]; storyVoices = [:]; storyThoughts = []
        generation &+= 1; loadedSession = nil; authorityMode = nil; snapshot = nil; extras = [:]; reward = nil; hint = nil; cachedCompletion = nil
        ending = nil; leaderboard = nil; lead = nil; advancedReadyNodeIDs = []; clock.restore(nil); phase = .idle
    }
    private func landed(_ review: PlayCompletionIntent, snapshot: PlaySnapshot) -> Bool {
        // Legacy records without mode stay unresolved; another mode's same node
        // ID and arrival bit cannot establish the result of the earlier write.
        guard let mode = review.gameplayMode, mode == PlayGameplayMode(serverValue: snapshot.result.mode) else { return false }
        if let routeSessionID = review.routeSessionID, snapshot.route?.sessionID != routeSessionID { return false }
        guard let node = snapshot.visibleNodes.first(where: { $0.id == review.nodeID }) else { return false }
        if snapshot.result.mode == 2 {
            switch review.evidence { case .scan: return node.arrived == true; case .photo: return node.selfReported == true; default: return false }
        }
        return snapshot.isDone(node)
    }
    private func check(_ session: PlayExperienceSession, _ request: UInt64) throws {
        guard !Task.isCancelled, currentSession() == session, generation == request else { throw PlayExperienceError.staleSession }
    }
    private func fail(_ error: Error, session: PlayExperienceSession, generation request: UInt64) {
        guard generation == request else { return }
        guard currentSession() == session else { invalidate(); return }
        if error is CancellationError { issue = .unknownResult }
        else { issue = error as? PlayExperienceError ?? .unknownResult }
        if issue == .unauthorized { onUnauthorized(session); invalidate(); return }
        phase = unresolved ? .unknown : .failed
    }
}

import Foundation
import Observation

public struct PlayCompletionReview: Equatable {
    public let nodeID: Int
    public let evidence: PlayCompletionEvidence
    public let advance: PlayRouteAdvance?
    let session: PlayExperienceSession
    let generation: UInt64
    let routeSessionID: Int?
}
public struct PlayPendingCompletion: Equatable {
    public let review: PlayCompletionReview
    public let requestAcknowledged: Bool
}
@MainActor public protocol PlayCompletionRecoveryStore: AnyObject {
    func read(_ key: String) throws -> PlayPendingCompletion?
    func write(_ pending: PlayPendingCompletion?, key: String) throws
}
@MainActor public final class PlayMemoryCompletionRecovery: PlayCompletionRecoveryStore {
    private var values: [String: PlayPendingCompletion] = [:]
    public init() {}
    public func read(_ key: String) throws -> PlayPendingCompletion? { values[key] }
    public func write(_ pending: PlayPendingCompletion?, key: String) throws { values[key] = pending }
}

/// Independent of the existing linear-answer reader. A successful write invalidates the
/// snapshot; only authoritative readback changes progress. No hidden write retries.
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayExperienceCoordinator {
    public let scope: PlaySessionScope
    public private(set) var snapshot: PlaySnapshot?
    public private(set) var extras: [Int: PlayNodeExtras] = [:]
    public private(set) var chapterStories: [Int: ChapterStoryDocument] = [:]
    public private(set) var storyVariables: [String: PlayWireValue] = [:]
    public private(set) var storyVoices: [String: PlayWireValue] = [:]
    public private(set) var storyThoughts: [PlayWireValue] = []
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
    private var loadedSession: PlayExperienceSession?
    private var authorityOwner: PlayExperienceSession?
    private var unknownLeaderKeys: Set<String> = []
    private var generation: UInt64 = 0
    private var advancedReadyNodeIDs: Set<Int> = []
    private var hintUnknownNodes: Set<Int> = []
    private var unknownHintRequests: [String: [Int: Int]] = [:]
    public var identity: String? {
        currentSession().map { PlayRunStorageKey.make(session: $0, scope: scope) + ":" + String($0.epoch) }
    }
    public var available: Bool { service.enabled.contains(.reads) }
    /// Read authority only; audio never grants gameplay completion authority.
    public var hasCurrentMediaSnapshot: Bool {
        snapshot != nil && loadedSession != nil && loadedSession == currentSession() && (phase == .ready || phase == .unknown)
    }
    public var canWrite: Bool { phase == .ready && !unresolved && loadedSession != nil && loadedSession == currentSession() }
    public init(scope: PlaySessionScope, service: PlayExperienceService, recovery: any PlayCompletionRecoveryStore,
                pausedStorage: any PlayPausedStorage, currentSession: @escaping () -> PlayExperienceSession?,
                onUnauthorized: @escaping (PlayExperienceSession) -> Void = { _ in }) {
        self.scope = scope; self.service = service; self.recovery = recovery; self.pausedStorage = pausedStorage
        self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    public func load() async {
        guard phase != .submitting else { return }
        generation &+= 1; let request = generation
        phase = .loading; issue = nil; snapshot = nil; extras = [:]
        guard let session = currentSession(), scope.isValid else { phase = .failed; issue = .staleSession; return }
        if authorityOwner != session {
            reward = nil; hint = nil; ending = nil; leaderboard = nil; lead = nil
            advancedReadyNodeIDs = []
            hintUnknownNodes = Set((unknownHintRequests[PlayRunStorageKey.make(session: session, scope: scope)] ?? [:]).keys)
            leaderOutcomeUnknown = unknownLeaderKeys.contains(PlayRunStorageKey.make(session: session, scope: scope))
            authorityOwner = session
            chapterStories = [:]; storyVariables = [:]; storyVoices = [:]; storyThoughts = []
        }
        loadedSession = nil
        do {
            let document = try await service.nodes(scope: scope, token: session.token)
            try check(session, request)
            let route = document.base.routeState?.isBranch == true ? try await service.route(scope: scope, token: session.token) : nil
            try check(session, request)
            let snapshot = try PlaySnapshot(scope: scope, result: document.base, authority: route)
            let key = PlayRunStorageKey.make(session: session, scope: scope)
            if let pending = try recovery.read(key), landed(pending.review, snapshot: snapshot) {
                try recovery.write(nil, key: key)
            }
            var hintRequests = unknownHintRequests[key] ?? [:]
            for (nodeID, level) in hintRequests {
                guard let detail = document.extras[nodeID] else { continue }
                if level == -1, detail.hintLocked == false, detail.hint1?.isEmpty == false || detail.hint2?.isEmpty == false { hintRequests.removeValue(forKey: nodeID) }
                else if level >= 1, (detail.puzzleHintLevel ?? 0) >= level, !detail.usedHints.isEmpty { hintRequests.removeValue(forKey: nodeID) }
            }
            unknownHintRequests[key] = hintRequests; hintUnknownNodes = Set(hintRequests.keys)
            unresolved = try recovery.read(key) != nil || !hintUnknownNodes.isEmpty || leaderOutcomeUnknown
            self.snapshot = snapshot; extras = document.extras; loadedSession = session
            chapterStories = document.chapterStories
            storyVariables.merge(document.storyVariables) { _, new in new }
            storyVoices.merge(document.storyVoices) { _, new in new }
            storyThoughts = snapshot.route?.thoughts ?? document.storyThoughts
            phase = unresolved ? .unknown : .ready
        } catch { fail(error, session: session, generation: request) }
    }
    /// Called only from an accepted advanced state, never a local timer or preview.
    public func acceptAdvanced(_ state: PlayAdvancedState) throws {
        guard loadedSession == currentSession(), let snapshot,
              state.nodeID > 0, snapshot.visibleNodes.contains(where: { $0.id == state.nodeID }),
              state.topicID == snapshot.result.topicID, state.readyForBase else { throw PlayExperienceError.invalidAction }
        switch scope {
        case .activity(let id): guard state.activityID == id else { throw PlayExperienceError.invalidAction }
        case .topic: guard state.activityID == 0 else { throw PlayExperienceError.invalidAction }
        }
        advancedReadyNodeIDs.insert(state.nodeID)
    }
    public func review(nodeID: Int, evidence: PlayCompletionEvidence) throws -> PlayCompletionReview {
        guard canWrite, let session = loadedSession, let snapshot,
              snapshot.availability == .active,
              let node = snapshot.visibleNodes.first(where: { $0.id == nodeID }),
              !snapshot.isDone(node), !snapshot.isLocked(node), node.done == false else { throw PlayExperienceError.invalidAction }
        guard !node.hasAdvancedPrerequisite || advancedReadyNodeIDs.contains(nodeID) else { throw PlayExperienceError.invalidAction }
        let task = PlayNodeTask.resolve(mode: snapshot.result.mode, node: node)
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
        return PlayCompletionReview(nodeID: nodeID, evidence: evidence, advance: advance, session: session, generation: generation, routeSessionID: snapshot.route?.sessionID)
    }
    public func cancelReview() { if phase == .reviewing { phase = .ready } }
    public func submit(_ review: PlayCompletionReview) async {
        guard phase == .reviewing, review.session == currentSession(), review.session == loadedSession,
              review.generation == generation, !unresolved else { return }
        await dispatch(review)
    }
    private func dispatch(_ review: PlayCompletionReview) async {
        let session = review.session, request = generation, key = PlayRunStorageKey.make(session: review.session, scope: scope)
        do {
            // Store BEFORE sending, so storage failure cannot cause an untracked write.
            try recovery.write(.init(review: review, requestAcknowledged: false), key: key)
            unresolved = true; phase = .submitting; reward = nil
            let receipt = try await service.complete(scope: scope, nodeID: review.nodeID, evidence: review.evidence, advance: review.advance, token: session.token)
            try check(session, request)
            guard receipt["nodeId"].tolerantInteger == review.nodeID else { throw PlayExperienceError.malformed }
            try recovery.write(.init(review: review, requestAcknowledged: true), key: key)
            reward = receipt; phase = .needsReadback; await load()
        } catch {
            guard generation == request else { return }
            guard currentSession() == session else { invalidate(); return }
            if case PlayExperienceError.rejected(let code, _) = error {
                try? recovery.write(nil, key: key); unresolved = false
                if code == 409 { phase = .needsReadback; await load(); return }
            }
            if case PlayExperienceError.disabled = error { try? recovery.write(nil, key: key); unresolved = false }
            fail(error, session: session, generation: request)
            if unresolved { phase = .unknown }
        }
    }
    /// Branch replay preserves BOTH original token fields and payload. Read first. A
    /// changed route version/session or completed node cannot generate a fresh action.
    public var canRetryExactBranch: Bool {
        guard phase == .unknown, hintUnknownNodes.isEmpty, !leaderOutcomeUnknown, let session = loadedSession, session == currentSession(), let snapshot else { return false }
        let key = PlayRunStorageKey.make(session: session, scope: scope)
        guard let pending = try? recovery.read(key), let advance = pending.review.advance, !pending.requestAcknowledged,
              pending.review.session == session, snapshot.route?.sessionID == pending.review.routeSessionID,
              snapshot.route?.version == advance.expectedVersion, snapshot.route?.nodeStates[pending.review.nodeID] == "PLAYABLE" else { return false }
        return true
    }
    public func retryExactBranchAfterReadback() async {
        guard canRetryExactBranch, let session = loadedSession, let snapshot else { return }
        let key = PlayRunStorageKey.make(session: session, scope: scope)
        guard let pending = try? recovery.read(key), let advance = pending.review.advance,
              !pending.requestAcknowledged, pending.review.session == session,
              snapshot.route?.sessionID == pending.review.routeSessionID, snapshot.route?.version == advance.expectedVersion,
              snapshot.route?.nodeStates[pending.review.nodeID] == "PLAYABLE" else { return }
        await dispatch(pending.review)
    }
    public func requestHint(nodeID: Int, level: Int?) async {
        guard canWrite, !hintUnknownNodes.contains(nodeID), let session = loadedSession,
              let node = snapshot?.visibleNodes.first(where: { $0.id == nodeID }), snapshot?.isLocked(node) == false else { return }
        let request = generation; phase = .submitting; hintUnknownNodes.insert(nodeID)
        let hintKey = PlayRunStorageKey.make(session: session, scope: scope)
        unknownHintRequests[hintKey, default: [:]][nodeID] = level ?? -1
        do {
            hint = try await service.hint(scope: scope, nodeID: nodeID, level: level, token: session.token)
            try check(session, request); hintUnknownNodes.remove(nodeID); unknownHintRequests[hintKey]?.removeValue(forKey: nodeID); phase = .needsReadback; await load()
        } catch {
            if case PlayExperienceError.rejected = error { hintUnknownNodes.remove(nodeID); unknownHintRequests[hintKey]?.removeValue(forKey: nodeID) }
            if case PlayExperienceError.disabled = error { hintUnknownNodes.remove(nodeID); unknownHintRequests[hintKey]?.removeValue(forKey: nodeID) }
            unresolved = !hintUnknownNodes.isEmpty
            fail(error, session: session, generation: request)
        }
    }
    public func loadEndingAndLeaderboard() async {
        guard let session = loadedSession, session == currentSession(), phase != .submitting else { return }
        let request = generation
        do {
            let ending = try await service.ending(scope: scope, token: session.token); try check(session, request); self.ending = ending
            let board = try await service.leaderboard(scope: scope, token: session.token); try check(session, request)
            guard board.me.id == session.accountID else { throw PlayExperienceError.malformed }; leaderboard = board
        } catch { fail(error, session: session, generation: request) }
    }
    public func loadLead() async {
        guard case .activity(let activity) = scope, let session = currentSession(), phase != .submitting else { return }
        let request = generation
        do { let result = try await service.teamProgress(activityID: activity, token: session.token); try check(session, request); lead = result }
        catch { fail(error, session: session, generation: request) }
    }
    public func performLead(_ action: PlayLeadAction, text: String? = nil) async {
        guard canWrite, !leaderOutcomeUnknown, let session = loadedSession, case .activity(let activity) = scope,
              lead?.allows(action, accountID: session.accountID) == true else { return }
        let request = generation; phase = .submitting; leaderOutcomeUnknown = true
        let leaderKey = PlayRunStorageKey.make(session: session, scope: scope); unknownLeaderKeys.insert(leaderKey)
        do {
            try await service.lead(activityID: activity, action: action, text: text, token: session.token)
            try check(session, request); leaderOutcomeUnknown = false; unknownLeaderKeys.remove(leaderKey); phase = .needsReadback
            await load(); await loadLead()
        } catch {
            if case PlayExperienceError.rejected = error { leaderOutcomeUnknown = false; unknownLeaderKeys.remove(leaderKey) }
            if case PlayExperienceError.disabled = error { leaderOutcomeUnknown = false; unknownLeaderKeys.remove(leaderKey) }
            fail(error, session: session, generation: request)
        }
    }
    public func restoreRun() async {
        guard let session = currentSession() else { return }
        let request = generation, key = PlayRunStorageKey.make(session: session, scope: scope)
        let local = try? pausedStorage.read(key: key)
        let remote = try? await service.readPaused(scope: scope, token: session.token)
        guard currentSession() == session, request == generation else { return }
        let tombstone = (try? pausedStorage.tombstone(key: key)) ?? 0
        let candidate = PlayPausedRecord.reconcile(local: local, remote: remote)
        let reconciled = candidate.flatMap { $0.savedAt > tombstone ? $0 : nil }
        clock.restore(reconciled); try? pausedStorage.write(reconciled, key: key)
    }
    public func startRun(now: TimeInterval) { guard currentSession() == loadedSession else { return }; try? clock.start(monotonicNow: now) }
    public func pauseRun(now: TimeInterval, savedAt: Int64) async {
        guard let session = loadedSession, currentSession() == session,
              let record = try? clock.pause(monotonicNow: now, savedAt: savedAt) else { return }
        let request = generation, key = PlayRunStorageKey.make(session: session, scope: scope)
        do { try pausedStorage.write(record, key: key) } catch { remoteRunSaveFailed = true }
        do { try await service.savePaused(scope: scope, record: record, token: session.token); try check(session, request); remoteRunSaveFailed = false }
        catch { if currentSession() == session { remoteRunSaveFailed = true } }
    }
    /// Ending the local run does not declare route completion or grant rewards.
    public func endRun(now: TimeInterval, savedAt: Int64) async {
        guard let session = loadedSession, currentSession() == session, savedAt > 0 else { return }
        clock.end(monotonicNow: now); let key = PlayRunStorageKey.make(session: session, scope: scope)
        try? pausedStorage.writeTombstone(savedAt, key: key)
        try? pausedStorage.write(nil, key: key)
        do { try await service.clearPaused(scope: scope, savedAt: savedAt, token: session.token) }
        catch { if currentSession() == session { remoteRunSaveFailed = true } }
    }
    public func invalidate() {
        chapterStories = [:]; storyVariables = [:]; storyVoices = [:]; storyThoughts = []
        generation &+= 1; loadedSession = nil; snapshot = nil; extras = [:]; reward = nil; hint = nil
        ending = nil; leaderboard = nil; lead = nil; advancedReadyNodeIDs = []; clock.restore(nil); phase = .idle
    }
    private func landed(_ review: PlayCompletionReview, snapshot: PlaySnapshot) -> Bool {
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

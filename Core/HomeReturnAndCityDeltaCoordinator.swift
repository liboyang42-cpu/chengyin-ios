import Foundation

/// Reform plan v9 §28 (W19.3–W19.6) and §29–35 (W20.1–W20.4, W20.11–W20.16):
/// pure client-side coordination for private-base return/restore preflight and
/// resident CITY action/delta state machines. Performs no I/O, defines no policy
/// defaults, and never exports private-home location values.
public struct HomeReturnFailurePresentation: Error, Equatable, CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    public let failure: HomeReturnFailure
    public let scope: HomeResourceScope

    public init(failure: HomeReturnFailure, scope: HomeResourceScope) {
        self.failure = failure
        self.scope = scope
    }

    /// Whether the user can retry immediately without changing OS settings or waiting on cooldown.
    public var retryableNow: Bool {
        failure.retryableNow
    }

    /// Cooldown wait duration reported by the server when `failure` is `.cooldown`.
    public var retryAfterSeconds: Int? {
        if case .cooldown(let seconds) = failure {
            return seconds
        }
        return nil
    }

    /// True when the user must enable location services or grant permission before checking again.
    public var requiresSettingsAction: Bool {
        switch failure {
        case .locationOff, .permissionDenied:
            return true
        default:
            return false
        }
    }

    public var description: String { "HomeReturnFailurePresentation[redacted]" }
    public var debugDescription: String { description }
}

public enum HomeReturnRestorePhase: Equatable, CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    case disabled
    case idle
    case preflightReady(HomeReturnCheck)
    case proofVerified(HomeReturnProof)
    case restoring(HomeRestoreRequest)
    case restored(current: Int64, maximum: Int64, accountVersion: Int64, scope: HomeResourceScope)
    case failed(HomeReturnFailurePresentation)

    public var description: String { "HomeReturnRestorePhase[redacted]" }
    public var debugDescription: String { description }
}

@MainActor public final class HomeReturnRestoreCoordinator: CustomStringConvertible, CustomDebugStringConvertible {
    public let capabilities: ReformWorldCapabilities
    public private(set) var phase: HomeReturnRestorePhase
    public private(set) var activeCheck: HomeReturnCheck?
    public private(set) var verifiedProof: HomeReturnProof?
    public private(set) var pendingRequest: HomeRestoreRequest?
    public private(set) var lastFailure: HomeReturnFailurePresentation?

    public init(capabilities: ReformWorldCapabilities = .disabled) {
        self.capabilities = capabilities
        self.phase = capabilities.allows(.homeReturnRestore) ? .idle : .disabled
    }

    /// Parses and validates an explicit resource scope (`GLOBAL`, `RUN`, or `THEME`).
    /// Never accepts an "all games" wildcard scope.
    public static func makeResourceScope(
        scopeType: String,
        scopeId: String? = nil,
        resourceType: String
    ) throws -> HomeResourceScope {
        let normalized = scopeType.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let scope: HomeResourceScope
        switch normalized {
        case "GLOBAL":
            guard scopeId == nil else { throw HomeReturnFailure.invalid }
            scope = .global(resourceType: resourceType)
        case "RUN":
            guard let scopeId else { throw HomeReturnFailure.invalid }
            scope = .run(runId: scopeId, resourceType: resourceType)
        case "THEME":
            guard let scopeId else { throw HomeReturnFailure.invalid }
            scope = .theme(themeId: scopeId, resourceType: resourceType)
        default:
            throw HomeReturnFailure.invalid
        }
        try scope.validate()
        return scope
    }

    @discardableResult
    public func evaluatePreflight(
        home: PrivateHomeSnapshot?,
        status: HomeReturnLocationStatus,
        policy: HomeReturnPolicy?,
        scope: HomeResourceScope,
        now: Date,
        requestId: String = UUID().uuidString
    ) -> Result<HomeReturnCheck, HomeReturnFailurePresentation> {
        guard capabilities.allows(.homeReturnRestore), let policy else {
            return recordFailure(.disabled, scope: scope)
        }
        do {
            let check = try HomeReturnCheck.preflight(
                home: home,
                status: status,
                policy: policy,
                scope: scope,
                now: now,
                requestId: requestId
            )
            activeCheck = check
            verifiedProof = nil
            pendingRequest = nil
            lastFailure = nil
            phase = .preflightReady(check)
            return .success(check)
        } catch let error as HomeReturnFailure {
            return recordFailure(error, scope: scope)
        } catch {
            return recordFailure(.invalid, scope: scope)
        }
    }

    @discardableResult
    public func acceptProof(
        proofId: String,
        homeVersion: Int64,
        scope: HomeResourceScope,
        expiresAtMillis: Int64
    ) throws -> HomeReturnProof {
        guard capabilities.allows(.homeReturnRestore) else {
            _ = recordFailure(.disabled, scope: scope)
            throw HomeReturnFailure.disabled
        }
        guard let check = activeCheck else {
            _ = recordFailure(.invalid, scope: scope)
            throw HomeReturnFailure.invalid
        }
        do {
            let proof = try HomeReturnProof(
                proofId: proofId,
                homeVersion: homeVersion,
                scope: scope,
                expiresAtMillis: expiresAtMillis,
                for: check
            )
            verifiedProof = proof
            lastFailure = nil
            phase = .proofVerified(proof)
            return proof
        } catch let error as HomeReturnFailure {
            _ = recordFailure(error, scope: check.scope)
            throw error
        }
    }

    @discardableResult
    public func beginRestore(
        currentHomeVersion: Int64,
        expectedAccountVersion: Int64,
        deviceNow: Date,
        serverOffset: TimeInterval = 0,
        requestId: String = UUID().uuidString
    ) throws -> HomeRestoreRequest {
        let fallbackScope = verifiedProof?.scope ?? activeCheck?.scope ?? .global(resourceType: "unknown")
        guard capabilities.allows(.homeReturnRestore) else {
            _ = recordFailure(.disabled, scope: fallbackScope)
            throw HomeReturnFailure.disabled
        }
        if let existing = pendingRequest {
            guard existing.requestId == requestId,
                  existing.homeVersion == currentHomeVersion,
                  existing.expectedAccountVersion == expectedAccountVersion
            else {
                _ = recordFailure(.invalid, scope: existing.scope)
                throw HomeReturnFailure.invalid
            }
            lastFailure = nil
            phase = .restoring(existing)
            return existing
        }
        guard let proof = verifiedProof else {
            _ = recordFailure(.invalid, scope: fallbackScope)
            throw HomeReturnFailure.invalid
        }
        do {
            let request = try HomeRestoreRequest(
                proof: proof,
                currentHomeVersion: currentHomeVersion,
                expectedAccountVersion: expectedAccountVersion,
                deviceNow: deviceNow,
                serverOffset: serverOffset,
                requestId: requestId
            )
            pendingRequest = request
            lastFailure = nil
            phase = .restoring(request)
            return request
        } catch let error as HomeReturnFailure {
            _ = recordFailure(error, scope: proof.scope)
            throw error
        }
    }

    @discardableResult
    public func resolveRestore(_ receipt: HomeRestoreReceipt?) throws -> HomeReturnRestorePhase {
        guard let request = pendingRequest else {
            throw HomeReturnFailure.invalid
        }
        guard let receipt else {
            let presentation = HomeReturnFailurePresentation(failure: .unknown, scope: request.scope)
            lastFailure = presentation
            phase = .failed(presentation)
            return phase
        }
        do {
            try receipt.validate(for: request)
        } catch let error as HomeReturnFailure {
            _ = recordFailure(error, scope: request.scope)
            throw error
        }
        pendingRequest = nil
        if let failure = receipt.failure {
            if failure == .homeChanged || failure == .proofExpired {
                verifiedProof = nil
                activeCheck = nil
            }
            let presentation = HomeReturnFailurePresentation(failure: failure, scope: request.scope)
            lastFailure = presentation
            phase = .failed(presentation)
            return phase
        }
        verifiedProof = nil
        activeCheck = nil
        lastFailure = nil
        phase = .restored(
            current: receipt.current,
            maximum: receipt.maximum,
            accountVersion: receipt.accountVersion,
            scope: request.scope
        )
        return phase
    }

    private func recordFailure(
        _ failure: HomeReturnFailure,
        scope: HomeResourceScope
    ) -> Result<HomeReturnCheck, HomeReturnFailurePresentation> {
        let presentation = HomeReturnFailurePresentation(failure: failure, scope: scope)
        lastFailure = presentation
        phase = .failed(presentation)
        return .failure(presentation)
    }

    public nonisolated var description: String { "HomeReturnRestoreCoordinator[redacted]" }
    public nonisolated var debugDescription: String { description }
}

public enum CityCoordinatorPhase: Equatable, Sendable {
    case disabled
    case idle
    case awaitingQuoteConfirmation(CityActionQuote)
    case inFlight(CityActionIntent)
    case settled(CityPendingAction.Outcome)
    case snapshotRequired
}

@MainActor public final class CityActionAndDeltaCoordinator {
    public let capabilities: ReformWorldCapabilities
    public private(set) var board: CityReadBoard
    public private(set) var lifecycle: CityBoardLifecycle
    public private(set) var participation: CityParticipation?
    public private(set) var pendingAction: CityPendingAction
    public private(set) var deltaStream: CityDeltaStream
    public private(set) var pendingQuote: CityActionQuote?
    public private(set) var confirmedConsent: CityPayerConsent?
    public private(set) var challengeStates: [String: CityChallengeState] = [:]
    public private(set) var needsSnapshotReload: Bool = false
    public private(set) var lastAppliedDeltas: [CityDelta] = []
    public private(set) var phase: CityCoordinatorPhase

    public init(
        board: CityReadBoard,
        lifecycle: CityBoardLifecycle,
        participation: CityParticipation?,
        initialSequence: Int64 = 0,
        capabilities: ReformWorldCapabilities = .disabled
    ) throws {
        guard board.lifecycle == lifecycle.rawValue else {
            throw CityActionIssue.invalid
        }
        let cursor = try CityStreamCursor(board: board, sequence: initialSequence)
        self.capabilities = capabilities
        self.board = board
        self.lifecycle = lifecycle
        self.participation = participation
        self.pendingAction = CityPendingAction()
        self.deltaStream = CityDeltaStream(cursor: cursor)
        self.phase = capabilities.allows(.cityActions) ? .idle : .disabled
    }

    /// True only when city actions are enabled, the board is OPEN, the member is joined,
    /// no action is currently in flight, and the delta stream has not flagged a snapshot gap.
    public var canAcceptNewActions: Bool {
        capabilities.allows(.cityActions)
            && lifecycle.acceptsNewActions
            && board.lifecycle == "OPEN"
            && participation != nil
            && pendingAction.intent == nil
            && !needsSnapshotReload
    }

    public func stageQuote(_ quote: CityActionQuote) throws {
        guard capabilities.allows(.cityActions) else { throw CityActionIssue.disabled }
        guard lifecycle.acceptsNewActions, board.lifecycle == "OPEN" else { throw CityActionIssue.boardNotOpen }
        guard participation != nil else { throw CityActionIssue.notJoined }
        guard pendingAction.intent == nil else { throw CityActionIssue.busy }
        try quote.validate()
        guard quote.boardId == board.boardId else { throw CityActionIssue.invalid }
        pendingQuote = quote
        confirmedConsent = nil
        phase = .awaitingQuoteConfirmation(quote)
    }

    @discardableResult
    public func confirmQuote(
        confirmingMemberId: String,
        confirmed: Bool,
        deviceNow: Date,
        serverOffset: TimeInterval = 0
    ) throws -> CityPayerConsent {
        guard capabilities.allows(.cityActions) else { throw CityActionIssue.disabled }
        guard let quote = pendingQuote else { throw CityActionIssue.unconfirmed }
        let consent = try CityPayerConsent(
            quote: quote,
            confirmingMemberId: confirmingMemberId,
            confirmed: confirmed,
            deviceNow: deviceNow,
            serverOffset: serverOffset
        )
        confirmedConsent = consent
        return consent
    }

    @discardableResult
    public func beginAction(
        kind: CityActionKind,
        targetId: String,
        roundSeq: Int64,
        expectedVersion: Int64? = nil,
        requestId: String = UUID().uuidString
    ) throws -> CityActionIntent {
        guard capabilities.allows(.cityActions) else { throw CityActionIssue.disabled }
        let version = expectedVersion ?? deltaStream.cursor.boardVersion
        let consent: CityPayerConsent?
        if kind.requiresQuote {
            if let inFlight = pendingAction.intent, inFlight.requestId == requestId {
                consent = inFlight.consent
            } else {
                guard let quote = pendingQuote,
                      let confirmed = confirmedConsent,
                      quote.quoteId == confirmed.quoteId,
                      quote.quoteVersion == confirmed.quoteVersion,
                      quote.action == kind.rawValue,
                      quote.targetId == targetId
                else {
                    throw CityActionIssue.unconfirmed
                }
                consent = confirmed
            }
        } else {
            guard confirmedConsent == nil, pendingQuote == nil else {
                throw CityActionIssue.invalid
            }
            consent = nil
        }

        let intent = try CityActionIntent(
            kind: kind,
            board: board,
            lifecycle: lifecycle,
            participation: participation,
            targetId: targetId,
            roundSeq: roundSeq,
            expectedVersion: version,
            consent: consent,
            requestId: requestId
        )
        try pendingAction.begin(intent, capabilities: capabilities)
        phase = .inFlight(intent)
        return intent
    }

    @discardableResult
    public func retryInFlight() throws -> CityActionIntent {
        guard let intent = pendingAction.intent else {
            throw CityActionIssue.illegalTransition
        }
        try pendingAction.begin(intent, capabilities: capabilities)
        phase = .inFlight(intent)
        return intent
    }

    @discardableResult
    public func resolveAction(_ receipt: CityActionReceipt?) throws -> CityPendingAction.Outcome {
        let outcome = try pendingAction.resolve(receipt)
        if outcome == .unknown {
            if let current = pendingAction.intent {
                phase = .inFlight(current)
            }
            return .unknown
        }
        pendingQuote = nil
        confirmedConsent = nil
        if case .refresh = outcome {
            needsSnapshotReload = true
        }
        phase = .settled(outcome)
        return outcome
    }

    @discardableResult
    public func ingestDeltas(_ page: [CityDelta]) -> CityDeltaStream.Result {
        let result = deltaStream.ingest(page)
        switch result {
        case .applied(let deltas):
            lastAppliedDeltas = deltas
            needsSnapshotReload = false
        case .unchanged:
            lastAppliedDeltas = []
        case .snapshotRequired:
            lastAppliedDeltas = []
            needsSnapshotReload = true
            if pendingAction.intent == nil && capabilities.allows(.cityActions) {
                phase = .snapshotRequired
            }
        }
        return result
    }

    @discardableResult
    public func applySnapshot(
        board newBoard: CityReadBoard,
        lifecycle newLifecycle: CityBoardLifecycle,
        participation newParticipation: CityParticipation?,
        sequence: Int64
    ) throws -> Bool {
        guard newBoard.lifecycle == newLifecycle.rawValue else {
            throw CityActionIssue.invalid
        }
        let cursor = try CityStreamCursor(board: newBoard, sequence: sequence)
        guard deltaStream.reset(to: cursor) else {
            return false
        }
        board = newBoard
        lifecycle = newLifecycle
        participation = newParticipation
        needsSnapshotReload = false
        lastAppliedDeltas = []
        if pendingAction.intent == nil && capabilities.allows(.cityActions) {
            phase = .idle
        }
        return true
    }

    public func advanceChallenge(challengeId: String, to next: CityChallengeState) throws {
        guard ReformWire.id(challengeId) else { throw CityActionIssue.invalid }
        if let current = challengeStates[challengeId] {
            guard current.canAdvance(to: next) else { throw CityActionIssue.illegalTransition }
        } else {
            guard next == .offered else { throw CityActionIssue.illegalTransition }
        }
        challengeStates[challengeId] = next
    }
}

/// Top-level coordinator keeping W19 private-home return/restore and W20 resident CITY
/// action/delta state machines side by side without sharing state or exporting location fixes.
@MainActor public final class HomeReturnAndCityDeltaCoordinator: CustomStringConvertible, CustomDebugStringConvertible {
    public let capabilities: ReformWorldCapabilities
    public let homeReturn: HomeReturnRestoreCoordinator
    public private(set) var city: CityActionAndDeltaCoordinator?

    public init(
        capabilities: ReformWorldCapabilities = .disabled,
        city: CityActionAndDeltaCoordinator? = nil
    ) {
        self.capabilities = capabilities
        self.homeReturn = HomeReturnRestoreCoordinator(capabilities: capabilities)
        self.city = city
    }

    @discardableResult
    public func configureCity(
        board: CityReadBoard,
        lifecycle: CityBoardLifecycle,
        participation: CityParticipation?,
        initialSequence: Int64 = 0
    ) throws -> CityActionAndDeltaCoordinator {
        let coordinator = try CityActionAndDeltaCoordinator(
            board: board,
            lifecycle: lifecycle,
            participation: participation,
            initialSequence: initialSequence,
            capabilities: capabilities
        )
        self.city = coordinator
        return coordinator
    }

    public nonisolated var description: String { "HomeReturnAndCityDeltaCoordinator[redacted]" }
    public nonisolated var debugDescription: String { description }
}

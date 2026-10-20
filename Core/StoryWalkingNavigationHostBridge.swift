import Foundation

/// Reform plan v9 §23 (W15.1, W15.2, W15.6) & §12.5 / §22 (W14.6, MV25–MV28).
/// Host bridge coordinating `StoryNavigationSequence` authority readbacks with walking navigation
/// stop transitions + arrival-opens-verification gating, and `PersonalFogLedger` confirmed/predicted
/// cells with roam map overlay projection while keeping `PersonalFogFeature.revealSyncEnabled == false`.
public enum StoryNavigationTransition: Equatable {
    case startedStop(WalkingTargetReference)
    case advancedStop(from: WalkingTargetReference, to: WalkingTargetReference)
    case unchanged(WalkingTargetReference)
    case holdingVerification(WalkingTargetReference)
    case clearedStop
    case completedMission
}

public struct StoryWalkingNavigationHostBridge: Equatable {
    public private(set) var sequence: StoryNavigationSequence
    public private(set) var activeWalkingStop: WalkingTargetReference?
    public private(set) var activeEntrance: PlaceNavigationEntrance?
    public private(set) var stopTransitionCount: Int = 0

    public init(missionID: Int) throws {
        self.sequence = try StoryNavigationSequence(missionID: missionID)
    }

    public var missionID: Int {
        sequence.missionID
    }

    public var phase: StoryNavigationSequence.Phase {
        sequence.phase
    }

    /// Applies an authority route-state readback and computes the walking coordinator transition.
    /// Never advances stops locally without a newer authority revision.
    @discardableResult
    public mutating func ingestAuthorityReadback(
        _ readback: StoryRouteStateReadback,
        entrances: [PlaceNavigationEntrance] = []
    ) throws -> StoryNavigationTransition {
        let previousStop = activeWalkingStop ?? pendingVerificationStop
        try sequence.apply(readback)

        switch sequence.phase {
        case .finished:
            activeWalkingStop = nil
            activeEntrance = nil
            return .completedMission
        case .noNavigableStop, .awaitingAuthority:
            activeWalkingStop = nil
            activeEntrance = nil
            return .clearedStop
        case .verificationAvailable(let stop), .verificationSubmitted(let stop):
            activeWalkingStop = nil
            return .holdingVerification(stop)
        case .navigating(let nextStop):
            activeWalkingStop = nextStop
            activeEntrance = Self.firstNavigableEntrance(from: entrances)
            if let previousStop {
                if previousStop == nextStop {
                    return .unchanged(nextStop)
                }
                stopTransitionCount += 1
                return .advancedStop(from: previousStop, to: nextStop)
            } else {
                stopTransitionCount += 1
                return .startedStop(nextStop)
            }
        }
    }

    /// Records that the walking coordinator reached near-destination for `reference`.
    /// Arrival only opens the verification entry and halts active walking guidance; it never
    /// completes the stop or advances to a subsequent stop.
    @discardableResult
    public mutating func recordWalkingArrival(for reference: WalkingTargetReference) -> Bool {
        sequence.reachedNearDestination(reference)
        if case .verificationAvailable(let current) = sequence.phase, current == reference {
            activeWalkingStop = nil
            return true
        }
        return false
    }

    /// Records that the player submitted verification (answer / photo / QR) for `reference`.
    /// Completion remains pending until the next authority readback.
    @discardableResult
    public mutating func recordVerificationSubmitted(for reference: WalkingTargetReference) -> Bool {
        sequence.submittedVerification(reference)
        if case .verificationSubmitted(let current) = sequence.phase, current == reference {
            activeWalkingStop = nil
            return true
        }
        return false
    }

    public func canOpenVerification(for reference: WalkingTargetReference) -> Bool {
        if case .verificationAvailable(let current) = sequence.phase {
            return current == reference
        }
        return false
    }

    public static func firstNavigableEntrance(from entrances: [PlaceNavigationEntrance]) -> PlaceNavigationEntrance? {
        entrances.first(where: \.isNavigable)
    }

    private var pendingVerificationStop: WalkingTargetReference? {
        switch sequence.phase {
        case .verificationAvailable(let stop), .verificationSubmitted(let stop):
            return stop
        default:
            return nil
        }
    }
}

/// Read-only projection of `PersonalFogLedger` state for roam map overlay rendering (W14.6 / MV25–MV28).
/// Keeps server-confirmed cells distinct from local display-only predictions and rolled-back cells.
public struct PersonalFogRoamOverlayProjection: Equatable {
    public let ownerScope: String
    public let confirmedTileCodes: [String]
    public let pendingPredictedTileCodes: [String]
    public let rolledBackTileCodes: [String]
    public let readCursor: Int
    public let revealSyncEnabled: Bool

    public var visibleRevealedTileCodes: [String] {
        Array(Set(confirmedTileCodes).union(pendingPredictedTileCodes)).sorted()
    }
}

public struct PersonalFogRoamHostCoordinator: Equatable {
    public private(set) var ledger: PersonalFogLedger
    public let samplePolicy: PersonalFogSamplePolicy

    public init(ownerScope: String, samplePolicy: PersonalFogSamplePolicy) throws {
        self.ledger = try PersonalFogLedger(ownerScope: ownerScope)
        self.samplePolicy = samplePolicy
    }

    public var overlayProjection: PersonalFogRoamOverlayProjection {
        PersonalFogRoamOverlayProjection(
            ownerScope: ledger.ownerScope,
            confirmedTileCodes: ledger.confirmed.map(\.code).sorted(),
            pendingPredictedTileCodes: ledger.pending.map(\.code).sorted(),
            rolledBackTileCodes: ledger.lastRejected.map(\.code).sorted(),
            readCursor: ledger.readCursor,
            revealSyncEnabled: PersonalFogFeature.revealSyncEnabled
        )
    }

    @discardableResult
    public mutating func ingestServerTilePage(
        owner: String,
        cells: [String],
        nextCursor: Int,
        grid: FogGridVersion = .legacyRoamTile
    ) throws -> PersonalFogRoamOverlayProjection {
        try ledger.applyServerPage(owner: owner, cells: cells, nextCursor: nextCursor, grid: grid)
        return overlayProjection
    }

    @discardableResult
    public mutating func recordForegroundFix(
        tileCode: String,
        fix: RoamDeviceFix,
        now: Date,
        grid: FogGridVersion = .legacyRoamTile
    ) throws -> PersonalFogRoamOverlayProjection {
        let cell = try FogCell(grid: grid, code: tileCode)
        try ledger.predict(cell, fix: fix, policy: samplePolicy, now: now)
        return overlayProjection
    }

    /// Requests the next bounded reveal sync batch. Respects `PersonalFogFeature.revealSyncEnabled == false`
    /// by throwing `PersonalFogFailure.featureDisabled` until backend contract approval.
    public mutating func attemptRevealSyncBatch(key: UUID = UUID()) throws -> PersonalFogLedger.Batch? {
        try ledger.nextBatch(policy: samplePolicy, key: key)
    }

    /// Contract-level batch preparation for offline verification of MV27/MV25 rollback behavior.
    mutating func prepareContractBatch(key: UUID = UUID()) -> PersonalFogLedger.Batch? {
        ledger.nextBatchForContract(policy: samplePolicy, key: key)
    }

    @discardableResult
    public mutating func applyBatchVerdict(
        key: UUID,
        acceptedCodes: [String],
        rejectedCodes: [String],
        grid: FogGridVersion = .legacyRoamTile
    ) throws -> PersonalFogRoamOverlayProjection {
        let accepted = Set(try acceptedCodes.map { try FogCell(grid: grid, code: $0) })
        let rejected = Set(try rejectedCodes.map { try FogCell(grid: grid, code: $0) })
        ledger.acknowledge(key, accepted: accepted, rejected: rejected)
        return overlayProjection
    }
}

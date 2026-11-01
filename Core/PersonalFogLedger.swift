import Foundation

/// Reform plan v9 §12.5 (MV25–MV28) / W14.6. Personal fog only: no team or stranger sharing.
/// Confirmed cells come from the owner-scoped server read (`api/roam/tiles/page`); local
/// predictions are display-only until the server confirms them. Exploration memory is
/// never presence proof, ownership or reward evidence.
public enum PersonalFogFeature {
    /// The reveal write path (grid version, batch idempotency) is not a reviewed contract yet.
    public static let revealSyncEnabled = false
}

public struct FogGridVersion: Hashable, Codable {
    public let id: String
    /// The existing roam tile string grid (geohash alphabet). New grids must be added explicitly.
    public static let legacyRoamTile = FogGridVersion(id: "roam-tile-legacy")
    public func isValidCell(_ code: String) -> Bool {
        self == .legacyRoamTile && RoamExperienceMath.isValidTile(code)
    }
}

public struct FogCell: Hashable, Codable, Comparable {
    public let grid: FogGridVersion
    public let code: String
    public init(grid: FogGridVersion, code: String) throws {
        guard grid.isValidCell(code) else { throw PersonalFogFailure.invalidCell }
        self.grid = grid; self.code = code
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { (lhs.grid.id, lhs.code) < (rhs.grid.id, rhs.code) }
}

public enum PersonalFogFailure: Error, Equatable { case invalidCell, ownerMismatch, featureDisabled, unqualifiedSample, cursorRegression }

/// Thresholds are required inputs: the plan marks accuracy/speed/batch values as configurable, untested candidates (MV27).
public struct PersonalFogSamplePolicy: Equatable {
    public let maxAccuracyMeters: Double
    public let maxAge: TimeInterval
    /// ApiRoamController.splitTiles(tiles, 500): the server silently truncates beyond 500 cells per /reveal.
    public static let serverRevealBatchCap = 500
    public let maxBatch: Int
    public init(maxAccuracyMeters: Double, maxAge: TimeInterval, maxBatch: Int) throws {
        guard maxAccuracyMeters.isFinite, maxAccuracyMeters > 0, maxAge.isFinite, maxAge > 0, (1...PersonalFogSamplePolicy.serverRevealBatchCap).contains(maxBatch) else {
            throw PersonalFogFailure.unqualifiedSample
        }
        self.maxAccuracyMeters = maxAccuracyMeters; self.maxAge = maxAge; self.maxBatch = maxBatch
    }
}

public struct PersonalFogLedger: Equatable {
    public struct Batch: Equatable {
        public let idempotencyKey: UUID
        public let cells: [FogCell]
    }
    public enum CellState: Equatable { case confirmed, pendingSync, hidden }
    public let ownerScope: String
    public private(set) var confirmed: Set<FogCell> = []
    public private(set) var pending: Set<FogCell> = []
    public private(set) var inFlight: Batch?
    public private(set) var readCursor = 0
    public private(set) var lastRejected: Set<FogCell> = []
    public init(ownerScope: String) throws {
        guard !ownerScope.isEmpty, ownerScope.count <= 256 else { throw PersonalFogFailure.ownerMismatch }
        self.ownerScope = ownerScope
    }

    /// Union-merge one server page for this owner. Cursors move forward only; a page from a
    /// different owner scope is rejected rather than merged (MV26 account isolation).
    public mutating func applyServerPage(owner: String, cells: [String], nextCursor: Int, grid: FogGridVersion = .legacyRoamTile) throws {
        guard owner == ownerScope else { throw PersonalFogFailure.ownerMismatch }
        guard nextCursor >= readCursor else { throw PersonalFogFailure.cursorRegression }
        let parsed = try cells.map { try FogCell(grid: grid, code: $0) }
        confirmed.formUnion(parsed); pending.subtract(parsed); readCursor = nextCursor
    }

    /// Records a local prediction from an already-authorized, qualified foreground fix.
    /// Low accuracy, stale or future-dated samples are not predicted (no silent cheating verdict either).
    public mutating func predict(_ cell: FogCell, fix: RoamDeviceFix, policy: PersonalFogSamplePolicy, now: Date) throws {
        guard fix.accuracyMeters <= policy.maxAccuracyMeters, now.timeIntervalSince(fix.measuredAt) <= policy.maxAge,
              fix.measuredAt.timeIntervalSince(now) <= 5 else { throw PersonalFogFailure.unqualifiedSample }
        if !confirmed.contains(cell) { pending.insert(cell) }
    }

    /// Next bounded batch. After a lost response the in-flight batch is resent with the same key (MV27).
    public mutating func nextBatch(policy: PersonalFogSamplePolicy, key: UUID = UUID()) throws -> Batch? {
        guard PersonalFogFeature.revealSyncEnabled else { throw PersonalFogFailure.featureDisabled }
        return nextBatchForContract(policy: policy, key: key)
    }
    mutating func nextBatchForContract(policy: PersonalFogSamplePolicy, key: UUID) -> Batch? {
        if let inFlight { return inFlight }
        let cells = Array(pending.sorted().prefix(policy.maxBatch))
        guard !cells.isEmpty else { return nil }
        let batch = Batch(idempotencyKey: key, cells: cells); inFlight = batch; return batch
    }

    /// Server verdict for the in-flight batch. Rejected predictions roll back visibly (MV25).
    public mutating func acknowledge(_ key: UUID, accepted: Set<FogCell>, rejected: Set<FogCell>) {
        guard let batch = inFlight, batch.idempotencyKey == key else { return }
        let sent = Set(batch.cells)
        let ok = accepted.intersection(sent), no = rejected.intersection(sent).subtracting(ok)
        confirmed.formUnion(ok); pending.subtract(ok.union(no)); lastRejected = no; inFlight = nil
    }
    public func state(of cell: FogCell) -> CellState {
        confirmed.contains(cell) ? .confirmed : pending.contains(cell) ? .pendingSync : .hidden
    }
    public var pendingCount: Int { pending.count }

    /// Sign-out purge: drops every local cell, prediction, in-flight batch and cursor so the
    /// next account (or a reinstall) rebuilds only from its own server pages.
    public mutating func purgeForSignOut() {
        confirmed = []; pending = []; inFlight = nil; readCursor = 0; lastRejected = []
    }
}

import Foundation

/// In-memory only. Full replacement snapshots, tombstones, scope generation and monotonic leases.
public struct PersonalLocationShareReceiverProjection {
    public struct Visible: Identifiable, Equatable {
        public var id: String { grant.grantId }
        public let grant: PersonalLocationShareGrant
        public let observation: PersonalLocationShareObservation
        public let deadlineUptime: TimeInterval
        public let staleUptime: TimeInterval
        public func isStale(at uptime: TimeInterval) -> Bool { observation.stale || uptime >= staleUptime }
    }
    public struct Ticket: Equatable { fileprivate let generation: UInt64; fileprivate let serial: UInt64 }
    private let recipientId: Int64
    public private(set) var visible: [String: Visible] = [:]
    public private(set) var cursor: Int64 = 0
    public private(set) var refreshAfterMs: Int64?
    public private(set) var policyIdentity: String?
    private var tombstones: [String: Int64] = [:]
    private var identities: [String: (owner: Int64, recipient: Int64)] = [:]
    private var versions: [String: Int64] = [:]
    private var lastServerNowMs: Int64 = 0
    private var generation: UInt64 = 0
    private var serial: UInt64 = 0
    public init(recipientId: Int64) { self.recipientId = recipientId }
    public mutating func beginRead() -> Ticket { serial &+= 1; return Ticket(generation: generation, serial: serial) }
    public mutating func clear() {
        generation &+= 1; visible.removeAll(); refreshAfterMs = nil; policyIdentity = nil
        // Tombstones and identity history survive disconnects for this account scope.
    }
    public mutating func expire(at uptime: TimeInterval) {
        visible = visible.filter { uptime < $0.value.deadlineUptime }
    }
    public var nextDeadline: TimeInterval? { visible.values.map(\.deadlineUptime).min() }
    @discardableResult public mutating func apply(_ snapshot: PersonalLocationShareSnapshot, ticket: Ticket,
                                                 uptime: TimeInterval) throws -> Bool {
        guard ticket.generation == generation, ticket.serial == serial else { return false }
        guard recipientId > 0, snapshot.recipientId == recipientId, snapshot.serverNowMs > 0, snapshot.serverNowMs >= lastServerNowMs,
              snapshot.cursor >= cursor, snapshot.refreshAfterMs > 0, snapshot.staleAfterMs > 0,
              snapshot.displayLeaseUntilMs >= snapshot.serverNowMs,
              !snapshot.policyId.isEmpty, snapshot.policyVersion > 0, !snapshot.policyDigest.isEmpty,
              Set(snapshot.entries.map { $0.grant.grantId }).count == snapshot.entries.count else {
            clear(); throw PersonalLocationShareFailure.invalidContract
        }
        var replacement: [String: Visible] = [:]
        for entry in snapshot.entries {
            let grant = entry.grant
            guard grant.structurallyValid, grant.recipientId == recipientId, grant.watermark <= snapshot.cursor,
                  grant.policyId == snapshot.policyId, grant.policyVersion == snapshot.policyVersion,
                  grant.policyDigest == snapshot.policyDigest else { clear(); throw PersonalLocationShareFailure.invalidContract }
            if let identity = identities[grant.grantId], identity.owner != grant.ownerId || identity.recipient != grant.recipientId {
                clear(); throw PersonalLocationShareFailure.invalidContract
            }
            identities[grant.grantId] = (grant.ownerId, grant.recipientId)
            guard tombstones[grant.grantId] == nil else { continue } // A revoked grant is never revived.
            guard grant.version >= (versions[grant.grantId] ?? 0) else { continue }
            versions[grant.grantId] = grant.version
            guard grant.status == .active else { tombstones[grant.grantId] = grant.watermark; continue }
            let end = min(snapshot.displayLeaseUntilMs, min(grant.expiresAtMs, grant.ownerLeaseUntilMs))
            guard end > snapshot.serverNowMs, let observation = entry.observation else { continue }
            guard observation.matches(grant, serverNowMs: snapshot.serverNowMs) else { clear(); throw PersonalLocationShareFailure.invalidContract }
            let remainingFresh = max(0, snapshot.staleAfterMs - (snapshot.serverNowMs - observation.observedAtMs))
            replacement[grant.grantId] = Visible(grant: grant, observation: observation,
                deadlineUptime: uptime + Double(end - snapshot.serverNowMs) / 1000,
                staleUptime: uptime + Double(remainingFresh) / 1000)
        }
        // Absence is authoritative: do not preserve coordinates or allow a late old snapshot to restore them.
        let presentGrantIds = Set(snapshot.entries.map { $0.grant.grantId })
        for removed in Set(visible.keys).subtracting(presentGrantIds) { tombstones[removed] = snapshot.cursor }
        visible = replacement; cursor = snapshot.cursor; lastServerNowMs = snapshot.serverNowMs; refreshAfterMs = snapshot.refreshAfterMs
        policyIdentity = "\(snapshot.policyId):\(snapshot.policyVersion):\(snapshot.policyDigest)"
        return true
    }
    /// Returns true if an authoritative replacement snapshot is required.
    public mutating func apply(_ batch: PersonalLocationShareEventBatch) throws -> Bool {
        guard batch.recipientId == recipientId, batch.serverNowMs > 0, batch.cursor >= 0,
              batch.refreshAfterMs > 0 else { clear(); throw PersonalLocationShareFailure.invalidContract }
        // Invalidate outstanding snapshot responses before touching visible data.
        serial &+= 1
        if batch.resetRequired { clear(); cursor = batch.cursor; lastServerNowMs = batch.serverNowMs; return true }
        guard batch.cursor >= cursor, batch.serverNowMs >= lastServerNowMs else { clear(); throw PersonalLocationShareFailure.invalidContract }
        var last = cursor
        for event in batch.events {
            guard UUID(uuidString: event.grantId) != nil, event.version > 0,
                  event.watermark > last, event.watermark <= batch.cursor else { clear(); throw PersonalLocationShareFailure.invalidContract }
            last = event.watermark
            if event.kind == .invalidated {
                tombstones[event.grantId] = max(tombstones[event.grantId] ?? 0, event.watermark)
                visible.removeValue(forKey: event.grantId)
            }
            versions[event.grantId] = max(versions[event.grantId] ?? 0, event.version)
        }
        cursor = batch.cursor; lastServerNowMs = batch.serverNowMs; refreshAfterMs = batch.refreshAfterMs
        return !batch.events.isEmpty
    }
}

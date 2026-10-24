import Foundation

/// Independent side-quest: discover compliant place → accept capacity hold →
/// GPS/QR/photo/AR or approved alternative → complete/fail/exit → original record recover.
/// Fog tiles and simulated coordinates are never presence.
public enum SideQuestFailure: Error, Equatable {
    case waitingSource(capability: String)
    case notCompliant
    case hiddenCoordinateShipped
    case capacityUnavailable
    case holdRequired
    case proofRequired
    case fakeGPSRejected
    case fogIsNotPresence
    case notHeld
    case alreadyTerminal
    case originalRecordUnknown
    case staleHold
    public var isWaitingSource: Bool {
        if case .waitingSource = self { return true }
        return false
    }
}

public enum SideQuestPhase: String, Equatable, Sendable {
    case idle, discovered, holdAccepted, proofPending, completed, failed, exited, recovered, waitingSource
}

public enum SideQuestProofKind: String, Equatable, Sendable {
    case gps, qr, photo, ar, approvedAlternative
}

public enum SideQuestTerminal: String, Equatable, Sendable {
    case completed, failed, exited
}

/// Device-attested proof only. Simulated GPS and fog tiles cannot be constructed.
public struct SideQuestProof: Equatable, Sendable {
    public let kind: SideQuestProofKind
    public let attested: Bool
    public init?(kind: SideQuestProofKind, attested: Bool, simulated: Bool = false, fogTileKey: String? = nil,
                 approvalAuthority: String? = nil) {
        guard !simulated, fogTileKey == nil else { return nil }
        if kind == .gps { guard attested else { return nil } }
        if kind == .approvedAlternative {
            guard attested, let approvalAuthority, !approvalAuthority.isEmpty else { return nil }
            self.kind = kind; self.attested = true; return
        }
        guard attested else { return nil }
        self.kind = kind; self.attested = true
    }
}

public struct SideQuestPlace: Equatable, Sendable {
    public let placeID: Int
    public let questID: Int
    public let compliant: Bool
    public let capacity: Int
    public let hiddenCoordinateShipped: Bool
    public init?(placeID: Int, questID: Int, compliant: Bool, capacity: Int, hiddenCoordinateShipped: Bool) {
        guard placeID > 0, questID > 0, capacity >= 0, capacity <= 10_000 else { return nil }
        self.placeID = placeID; self.questID = questID; self.compliant = compliant
        self.capacity = capacity; self.hiddenCoordinateShipped = hiddenCoordinateShipped
    }
}

/// Capacity hold identity is the original request, not a current projection.
public struct SideQuestCapacityHold: Equatable, Sendable {
    public let holdID: String
    public let originalRequestID: String
    public let placeID: Int
    public let questID: Int
    public let seats: Int
}

public struct SideQuestOriginalRecord: Equatable, Sendable {
    public let originalRequestID: String
    public let terminal: SideQuestTerminal
    public let proofKind: SideQuestProofKind?
}

public protocol SideQuestPlaceCapacitySourcing {
    func reserve(originalRequestID: String, placeID: Int, seats: Int) -> Bool
    func release(originalRequestID: String)
}

public struct SideQuestAcceptHold {
    public static let placeCapacitySource = "sideQuest.placeCapacitySource"
    public private(set) var phase: SideQuestPhase = .idle
    public private(set) var place: SideQuestPlace?
    public private(set) var hold: SideQuestCapacityHold?
    public private(set) var proof: SideQuestProof?
    public private(set) var original: SideQuestOriginalRecord?
    public private(set) var failure: SideQuestFailure?
    private let capacitySource: (any SideQuestPlaceCapacitySourcing)?
    public init(capacitySource: (any SideQuestPlaceCapacitySourcing)? = nil) {
        self.capacitySource = capacitySource
    }
    public mutating func discover(_ place: SideQuestPlace) throws {
        if original != nil { throw fail(.alreadyTerminal) }
        guard place.compliant else { throw fail(.notCompliant) }
        guard !place.hiddenCoordinateShipped else { throw fail(.hiddenCoordinateShipped) }
        guard place.capacity > 0 else { throw fail(.capacityUnavailable) }
        self.place = place
        hold = nil
        proof = nil
        original = nil
        phase = .discovered
        failure = nil
    }
    public mutating func acceptHold(holdID: String, originalRequestID: String?, seats: Int = 1) throws {
        let requestID = originalRequestID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = hold {
            guard existing.originalRequestID == requestID, existing.holdID == holdID else {
                throw fail(.staleHold)
            }
            return
        }
        guard phase == .discovered, let place else { throw fail(.notCompliant) }
        guard let requestID, !requestID.isEmpty, requestID.count <= 64 else { throw fail(.capacityUnavailable) }
        guard !holdID.isEmpty, holdID.count <= 64, seats > 0, seats <= place.capacity else {
            throw fail(.capacityUnavailable)
        }
        guard let capacitySource else {
            throw SideQuestFailure.waitingSource(capability: Self.placeCapacitySource)
        }
        guard capacitySource.reserve(originalRequestID: requestID, placeID: place.placeID, seats: seats) else {
            throw fail(.capacityUnavailable)
        }
        hold = SideQuestCapacityHold(holdID: holdID, originalRequestID: requestID,
                                     placeID: place.placeID, questID: place.questID, seats: seats)
        phase = .holdAccepted
        failure = nil
    }
    public mutating func submitProof(_ proof: SideQuestProof) throws {
        guard phase == .holdAccepted || phase == .proofPending, hold != nil else { throw fail(.holdRequired) }
        self.proof = proof
        phase = .proofPending
        failure = nil
    }
    public mutating func rejectSimulatedGPS() throws -> Never {
        throw fail(.fakeGPSRejected)
    }
    public mutating func rejectFogAsPresence() throws -> Never {
        throw fail(.fogIsNotPresence)
    }
    public mutating func complete() throws {
        try finish(.completed)
    }
    public mutating func failQuest() throws {
        try finish(.failed)
    }
    public mutating func exit() throws {
        guard phase == .holdAccepted || phase == .proofPending || phase == .discovered else {
            throw fail(.alreadyTerminal)
        }
        try finish(.exited, proofRequired: false)
    }
    /// Recover the original request. UNKNOWN does not invent a new request.
    public mutating func recoverOriginal(originalRequestID: String) throws -> SideQuestOriginalRecord {
        guard let original else { throw fail(.originalRecordUnknown) }
        guard original.originalRequestID == originalRequestID else { throw fail(.staleHold) }
        phase = .recovered
        failure = nil
        return original
    }
    public mutating func commitScoringWriter() throws -> Never {
        throw fail(.waitingSource(capability: OfflinePackSourceInventory.t41ScoringWriter))
    }
    private mutating func finish(_ terminal: SideQuestTerminal, proofRequired: Bool = true) throws {
        guard phase == .holdAccepted || phase == .proofPending else { throw fail(.holdRequired) }
        guard let hold else { throw fail(.notHeld) }
        if proofRequired {
            guard proof != nil else { throw fail(.proofRequired) }
        }
        original = SideQuestOriginalRecord(originalRequestID: hold.originalRequestID,
                                           terminal: terminal, proofKind: proof?.kind)
        capacitySource?.release(originalRequestID: hold.originalRequestID)
        switch terminal {
        case .completed: phase = .completed
        case .failed: phase = .failed
        case .exited: phase = .exited
        }
        failure = nil
    }
    @discardableResult
    private mutating func fail(_ error: SideQuestFailure) -> SideQuestFailure {
        failure = error
        if error.isWaitingSource { phase = .waitingSource }
        return error
    }
}

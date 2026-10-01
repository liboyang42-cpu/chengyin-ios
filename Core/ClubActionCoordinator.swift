import Foundation

public struct ClubActionConfirmation: Equatable {
    public let id: UUID
    public let clubID: Int
    public let clubName: String
    public let identity: ClubReadIdentity
    public let action: ClubAction
    fileprivate init(club: ClubRecord, identity: ClubReadIdentity, action: ClubAction, id: UUID) {
        self.id = id; clubID = club.id; clubName = club.name; self.identity = identity; self.action = action
    }
}
public enum ClubActionState: Equatable {
    case idle, checking, awaitingConfirmation, submitting, notSent
    case acknowledged(ClubActionReceipt)
    case rejected(ClubActionResponseFailure)
    case outcomeUnknown(ClubActionIssue)
    public var preventsNewAction: Bool {
        switch self {
        case .checking, .awaitingConfirmation, .submitting, .outcomeUnknown: return true
        default: return false
        }
    }
}
public enum ClubActionReadback: Equatable { case idle, loading, received(ClubRecord), unavailable }
public enum ClubActionBlock: Error, Equatable {
    case unavailable, signedOut, accountChanged, invalidClub, pendingOperation
    case eligibilityChanged, cancelledBeforeDispatch, staleConfirmation, noReadback, readbackInProgress
}
public enum ClubActionResult: Equatable { case applied, ignoredStale, blocked(ClubActionBlock) }

/// Keep this coordinator with the session owner and inject it into all club details.
/// Unknown outcomes keep a per-account/per-club lock across navigation and epoch changes.
/// Neither readback nor a new confirmation automatically replays an uncertain request.
@MainActor
public final class ClubActionCoordinator {
    private let writer: any ClubActionWriting
    private let reader: any ClubReading
    private let onMembershipChanged: (Int) -> Void
    private struct Key: Hashable { let accountID: Int; let clubID: Int }
    private struct Record {
        let id: UUID
        let identity: ClubReadIdentity
        let ownerID: UUID?
        var state: ClubActionState
        var readback: ClubActionReadback = .idle
        var readIdentity: ClubReadIdentity?
        var readOwnerID: UUID?
        var readGeneration: UInt64 = 0
    }
    private var records: [Key: Record] = [:]
    public init(writer: any ClubActionWriting, reader: any ClubReading,
                onMembershipChanged: @escaping (Int) -> Void = { _ in }) {
        self.writer = writer; self.reader = reader; self.onMembershipChanged = onMembershipChanged
    }
    public var isConfigured: Bool { writer.isConfigured && reader.isClubConfigured }
    public var identity: ClubReadIdentity? {
        guard let identity = writer.identity, identity.isSignedIn, identity == reader.clubIdentity else { return nil }
        return identity
    }
    public var viewerIsMerchant: Bool { writer.viewerIsMerchant }
    private func key(clubID: Int, identity: ClubReadIdentity) -> Key? {
        identity.accountID.map { Key(accountID: $0, clubID: clubID) }
    }
    public func state(clubID: Int) -> ClubActionState {
        synchronizeSession()
        guard let identity, let key = key(clubID: clubID, identity: identity) else { return .idle }
        return records[key]?.state ?? .idle
    }
    public func readback(clubID: Int) -> ClubActionReadback {
        guard let identity, let key = key(clubID: clubID, identity: identity),
              let record = records[key], record.readIdentity == identity else { return .idle }
        return record.readback
    }
    public func synchronizeSession() {
        let current = identity
        for key in Array(records.keys) {
            guard let record = records[key] else { continue }
            if record.identity != current {
                switch record.state {
                case .submitting, .outcomeUnknown: records[key]?.state = .outcomeUnknown(.accountChanged)
                default: records[key] = nil; continue
                }
            }
            if record.readIdentity != current {
                records[key]?.readback = .idle; records[key]?.readIdentity = nil; records[key]?.readOwnerID = nil
                records[key]?.readGeneration &+= 1
            }
        }
    }
    /// Read a fresh detail before showing the confirmation. A stale join button cannot
    /// silently turn into Leave (or a direct join into an application).
    public func prepare(clubID: Int, action: ClubAction, expectedIdentity: ClubReadIdentity, ownerID: UUID? = nil) async throws -> ClubActionConfirmation {
        synchronizeSession()
        guard isConfigured else { throw ClubActionBlock.unavailable }
        guard let identity, let key = key(clubID: clubID, identity: identity) else { throw ClubActionBlock.signedOut }
        guard identity == expectedIdentity else { throw ClubActionBlock.accountChanged }
        guard clubID > 0 else { throw ClubActionBlock.invalidClub }
        guard !state(clubID: clubID).preventsNewAction, readback(clubID: clubID) != .loading else { throw ClubActionBlock.pendingOperation }
        guard !Task.isCancelled else { throw ClubActionBlock.cancelledBeforeDispatch }
        let id = UUID()
        records[key] = Record(id: id, identity: identity, ownerID: ownerID, state: .checking)
        do {
            let club = try await reader.clubDetail(id: clubID)
            guard self.identity == identity else { throw ClubActionBlock.accountChanged }
            guard !Task.isCancelled, records[key]?.id == id, records[key]?.state == .checking else {
                throw ClubActionBlock.cancelledBeforeDispatch
            }
            guard club.id == clubID else { throw ClubActionBlock.invalidClub }
            guard ClubActionAvailability.resolve(club, viewerIsMerchant: writer.viewerIsMerchant) == .available(action) else {
                throw ClubActionBlock.eligibilityChanged
            }
            records[key]?.state = .awaitingConfirmation
            return ClubActionConfirmation(club: club, identity: identity, action: action, id: id)
        } catch {
            if records[key]?.id == id, records[key]?.state == .checking { records[key] = nil }
            throw error
        }
    }
    public func cancel(_ confirmation: ClubActionConfirmation) {
        guard let key = key(clubID: confirmation.clubID, identity: confirmation.identity),
              records[key]?.id == confirmation.id, records[key]?.state == .awaitingConfirmation else { return }
        records[key] = nil
    }
    @discardableResult
    public func confirm(_ confirmation: ClubActionConfirmation, onReadbackStarted: () -> Void = {}) async -> ClubActionResult {
        guard let key = key(clubID: confirmation.clubID, identity: confirmation.identity),
              records[key]?.id == confirmation.id, records[key]?.state == .awaitingConfirmation else { return .blocked(.staleConfirmation) }
        guard identity == confirmation.identity else { cancel(confirmation); return .blocked(.accountChanged) }
        guard !Task.isCancelled else { cancel(confirmation); return .blocked(.cancelledBeforeDispatch) }
        records[key]?.state = .submitting
        let next: ClubActionState
        do {
            let receipt = try await writer.perform(confirmation.action, clubID: confirmation.clubID, expectedIdentity: confirmation.identity)
            next = Task.isCancelled ? .outcomeUnknown(.cancelled) : .acknowledged(receipt)
        } catch let error as ClubActionWriteError {
            switch error {
            case .notSent, .cancelledBeforeDispatch, .eligibilityChanged, .preflightFailed: next = .notSent
            case .rejected(let failure): next = .rejected(failure)
            case .outcomeUnknown(let issue): next = .outcomeUnknown(issue)
            }
        } catch { next = .outcomeUnknown(error is CancellationError ? .cancelled : .transport) }
        guard records[key]?.id == confirmation.id else { return .ignoredStale }
        guard records[key]?.state == .submitting else {
            // A writer-proven no-send or definite rejection can clear an interrupted
            // record, including auth expiry synchronized by the session owner. No old
            // receipt is exposed and nothing is replayed.
            switch next { case .notSent, .rejected: records[key] = nil; default: break }
            return .ignoredStale
        }
        guard identity == confirmation.identity else {
            // A definite no-send/rejection needs no uncertainty lock. Other outcomes
            // stay locked, and no old response is exposed to the replacement account.
            switch next {
            case .notSent, .rejected: records[key] = nil
            default: records[key]?.state = .outcomeUnknown(.accountChanged)
            }
            return .ignoredStale
        }
        records[key]?.state = next
        if case .acknowledged = next {
            onMembershipChanged(confirmation.clubID)
            _ = await readBack(clubID: confirmation.clubID, ownerID: records[key]?.ownerID, onStarted: onReadbackStarted)
        }
        return .applied
    }
    /// Mark local interruption conservatively. This is not a server cancellation.
    public func leaveScreen(clubID: Int, expectedIdentity: ClubReadIdentity, ownerID: UUID? = nil) {
        guard let key = key(clubID: clubID, identity: expectedIdentity), let record = records[key] else { return }
        if record.identity == expectedIdentity, record.ownerID == ownerID {
            switch record.state {
            case .checking, .awaitingConfirmation: records[key] = nil; return
            case .submitting: records[key]?.state = .outcomeUnknown(.cancelled)
            default: break
            }
        }
        // An older screen must not cancel a newer screen's current readback.
        if record.readIdentity == expectedIdentity, record.readOwnerID == ownerID {
            records[key]?.readGeneration &+= 1
            records[key]?.readback = .idle; records[key]?.readIdentity = nil; records[key]?.readOwnerID = nil
        }
    }
    /// One read only. The returned membership is displayed as a current server snapshot,
    /// not proof that an uncertain write succeeded/failed. The uncertainty lock remains.
    @discardableResult
    public func readBack(clubID: Int, ownerID: UUID? = nil, onStarted: () -> Void = {}) async -> ClubActionResult {
        synchronizeSession()
        guard let identity, let key = key(clubID: clubID, identity: identity), var record = records[key] else { return .blocked(.noReadback) }
        switch record.state { case .acknowledged, .outcomeUnknown: break; default: return .blocked(.noReadback) }
        guard record.readback != .loading else { return .blocked(.readbackInProgress) }
        guard !Task.isCancelled else { return .blocked(.cancelledBeforeDispatch) }
        record.readGeneration &+= 1
        let generation = record.readGeneration
        record.readIdentity = identity; record.readOwnerID = ownerID; record.readback = .loading; records[key] = record
        // A screen can use this exact read-start boundary to order the result against
        // its ordinary refreshes. This notification never authorizes a mutation.
        onStarted()
        let result: ClubActionReadback
        do {
            let club = try await reader.clubDetail(id: clubID)
            guard club.id == clubID else { throw APIError.malformedResponse }
            result = .received(club)
        } catch { result = .unavailable }
        guard self.identity == identity, !Task.isCancelled, records[key]?.id == record.id,
              records[key]?.readGeneration == generation else {
            if records[key]?.id == record.id, records[key]?.readGeneration == generation { records[key]?.readback = .idle; records[key]?.readIdentity = nil; records[key]?.readOwnerID = nil }
            return .ignoredStale
        }
        records[key]?.readback = result
        return .applied
    }
}

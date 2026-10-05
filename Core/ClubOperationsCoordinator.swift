import Foundation

public struct ClubOperationsReview: Equatable, Identifiable {
    public let id: UUID
    public let target: ClubOperationsTarget
    public let identity: ClubReadIdentity
    public let command: ClubOperationsCommand
    public let snapshot: ClubOperationsSnapshot
    fileprivate let ownerID: UUID
}
public enum ClubOperationsState: Equatable {
    case idle, preparing, reviewing, preflighting, submitting
    case notSent, acknowledged(ClubOperationsReceipt), rejected(ClubActionResponseFailure), outcomeUnknown(ClubActionIssue)
    public var locksForm: Bool {
        switch self { case .preparing, .reviewing, .preflighting, .submitting, .outcomeUnknown: return true; default: return false }
    }
}
public enum ClubOperationsReadback: Equatable { case idle, loading, received(ClubOperationsSnapshot), unavailable }

/// Retain in the session owner, never in the destination screen. Unknown writes lock
/// this account/target across navigation and credential epochs; reads never unlock them.
/// The access adapter persists minimal unresolved intents across process restart.
@MainActor public final class ClubOperationsCoordinator {
    private let access: any ClubOperationsAccess
    private struct Key: Hashable { let accountID: Int; let target: ClubOperationsTarget }
    private struct Record {
        let id: UUID
        let identity: ClubReadIdentity
        let ownerID: UUID
        var state: ClubOperationsState
        var readback: ClubOperationsReadback = .idle
        var readGeneration: UInt64 = 0
        var readIdentity: ClubReadIdentity?
        var readOwnerID: UUID?
    }
    private var records: [Key: Record] = [:]
    public init(access: any ClubOperationsAccess) { self.access = access }
    public var identity: ClubReadIdentity? { access.identity }
    public var writeAvailability: ClubOperationsWriteAvailability { access.writeAvailability }
    private func key(_ target: ClubOperationsTarget, _ identity: ClubReadIdentity) -> Key? {
        guard let id = identity.accountID, id > 0 else { return nil }; return .init(accountID: id, target: target)
    }
    public func synchronizeSession() {
        for key in Array(records.keys) {
            guard let record = records[key] else { continue }
            if record.identity != identity {
                switch record.state {
                case .submitting, .outcomeUnknown: records[key]?.state = .outcomeUnknown(.accountChanged)
                default: records[key] = nil; continue
                }
            }
            if record.readIdentity != identity {
                records[key]?.readGeneration &+= 1; records[key]?.readback = .idle
                records[key]?.readIdentity = nil; records[key]?.readOwnerID = nil
            }
        }
    }
    public func state(target: ClubOperationsTarget) -> ClubOperationsState {
        synchronizeSession()
        guard let identity, let key = key(target, identity) else { return .idle }
        let current = records[key]?.state ?? .idle
        if !current.locksForm && access.hasPending(target: target) { return .outcomeUnknown(.transport) }
        return current
    }
    public func readback(target: ClubOperationsTarget) -> ClubOperationsReadback {
        guard let identity, let key = key(target, identity), let record = records[key], record.readIdentity == identity else { return .idle }
        return record.readback
    }
    public func prepare(_ command: ClubOperationsCommand, target: ClubOperationsTarget, expectedIdentity: ClubReadIdentity, ownerID: UUID) async throws -> ClubOperationsReview {
        synchronizeSession()
        guard access.isConfigured else { throw ClubOperationsBlock.unavailable }
        guard identity == expectedIdentity, let key = key(target, expectedIdentity) else { throw ClubOperationsBlock.signedOut }
        guard !state(target: target).locksForm, readback(target: target) != .loading else { throw ClubOperationsBlock.pending }
        try Task.checkCancellation()
        let id = UUID()
        records[key] = .init(id: id, identity: expectedIdentity, ownerID: ownerID, state: .preparing)
        do {
            let snapshot = try await access.snapshot(target: target)
            guard identity == expectedIdentity, records[key]?.id == id, records[key]?.state == .preparing, !Task.isCancelled else { throw ClubOperationsBlock.cancelled }
            guard snapshot.target == target else { throw ClubOperationsBlock.changed }
            try command.validate(snapshot: snapshot, identity: expectedIdentity)
            records[key]?.state = .reviewing
            return .init(id: id, target: target, identity: expectedIdentity, command: command, snapshot: snapshot, ownerID: ownerID)
        } catch {
            if records[key]?.id == id, records[key]?.state == .preparing { records[key] = nil }
            throw error
        }
    }
    public func cancel(_ review: ClubOperationsReview) {
        guard let key = key(review.target, review.identity), records[key]?.id == review.id, records[key]?.state == .reviewing else { return }
        records[key] = nil
    }
    public func confirm(_ review: ClubOperationsReview) async {
        guard let key = key(review.target, review.identity), records[key]?.id == review.id, records[key]?.state == .reviewing else { return }
        guard identity == review.identity, !Task.isCancelled else { records[key] = nil; return }
        // The UI cannot turn an unverified live adapter into a writer.
        guard access.writeAvailability == .syntheticOnly || access.writeAvailability == .approved else { records[key]?.state = .notSent; return }
        records[key]?.state = .preflighting
        do {
            let fresh = try await access.snapshot(target: review.target)
            guard identity == review.identity, records[key]?.id == review.id, records[key]?.state == .preflighting, !Task.isCancelled else {
                if records[key]?.id == review.id, records[key]?.state == .preflighting { records[key] = nil }
                return
            }
            guard fresh.target == review.target else { throw ClubOperationsBlock.changed }
            try review.command.validate(snapshot: fresh, identity: review.identity)
        } catch {
            if records[key]?.id == review.id, records[key]?.state == .preflighting { records[key]?.state = .notSent }
            return
        }
        guard identity == review.identity, records[key]?.id == review.id, records[key]?.state == .preflighting, !Task.isCancelled else {
                if records[key]?.id == review.id, records[key]?.state == .preflighting { records[key] = nil }
                return
            }
        records[key]?.state = .submitting
        let next: ClubOperationsState
        do {
            let receipt = try await access.perform(review.command, target: review.target, expectedIdentity: review.identity)
            next = Task.isCancelled ? .outcomeUnknown(.cancelled) : .acknowledged(receipt)
        } catch let error as ClubActionWriteError {
            switch error {
            case .notSent, .preflightFailed, .eligibilityChanged, .cancelledBeforeDispatch: next = .notSent
            case .rejected(let failure): next = .rejected(failure)
            case .outcomeUnknown(let issue): next = .outcomeUnknown(issue)
            }
        } catch { next = .outcomeUnknown(error is CancellationError ? .cancelled : .transport) }
        guard records[key]?.id == review.id else { return }
        guard identity == review.identity, records[key]?.state == .submitting else {
            switch next {
            case .notSent, .rejected: records[key] = nil
            default: records[key]?.state = .outcomeUnknown(identity == review.identity ? .cancelled : .accountChanged)
            }
            return
        }
        records[key]?.state = next
        if case .acknowledged = next { await readBack(target: review.target, ownerID: review.ownerID) }
    }
    public func leaveScreen(target: ClubOperationsTarget, expectedIdentity: ClubReadIdentity, ownerID: UUID) {
        guard let key = key(target, expectedIdentity), let record = records[key] else { return }
        if record.identity == expectedIdentity, record.ownerID == ownerID {
            switch record.state {
            case .preparing, .reviewing, .preflighting: records[key] = nil; return
            case .submitting: records[key]?.state = .outcomeUnknown(.cancelled)
            default: break
            }
        }
        if record.readIdentity == expectedIdentity, record.readOwnerID == ownerID {
            records[key]?.readGeneration &+= 1; records[key]?.readback = .idle
            records[key]?.readIdentity = nil; records[key]?.readOwnerID = nil
        }
    }
    public func readBack(target: ClubOperationsTarget, ownerID: UUID) async {
        synchronizeSession()
        guard let identity, let key = key(target, identity), var record = records[key], record.readback != .loading else { return }
        switch record.state { case .acknowledged, .outcomeUnknown: break; default: return }
        guard !Task.isCancelled else { return }
        record.readGeneration &+= 1; let run = record.readGeneration
        record.readback = .loading; record.readIdentity = identity; record.readOwnerID = ownerID; records[key] = record
        let next: ClubOperationsReadback
        do {
            let snapshot = try await access.snapshot(target: target)
            guard snapshot.target == target else { throw APIError.malformedResponse }
            next = .received(snapshot)
        } catch { next = .unavailable }
        guard self.identity == identity, !Task.isCancelled, records[key]?.id == record.id, records[key]?.readGeneration == run else {
            if records[key]?.id == record.id, records[key]?.readGeneration == run { records[key]?.readback = .idle }
            return
        }
        records[key]?.readback = next
    }
}

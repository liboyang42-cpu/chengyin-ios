import Foundation

public struct ParticipantConfirmation: Equatable {
    public let id: UUID
    public let identity: ProfileReadIdentity
    public let mutation: ParticipantMutation
    // Only prepare() creates confirmations after validation and session checks.
    fileprivate init(identity: ProfileReadIdentity, mutation: ParticipantMutation) {
        id = UUID(); self.identity = identity; self.mutation = mutation
    }
}

public enum ParticipantMutationState: Equatable {
    case idle, awaitingConfirmation, submitting, succeeded, notSent
    case rejected(ParticipantResponseFailure)
    case outcomeUnknown(ParticipantIssue)
    public var preventsNewMutation: Bool {
        switch self {
        case .awaitingConfirmation, .submitting, .outcomeUnknown: return true
        default: return false
        }
    }
}

public enum ParticipantReadback: Equatable {
    case list([ProfileParticipant])
    case detail(ProfileParticipant)
}

public enum ParticipantReadbackState: Equatable {
    case idle, loading
    /// A snapshot for user review only; it never proves a timeout did not mutate data.
    case received(ParticipantReadback)
    case unavailable
}

public enum ParticipantCoordinatorBlock: Error, Equatable {
    case unavailable, signedOut, accountChanged, invalidForm, pendingOperation
    case confirmationNoLongerValid, cancelledBeforeDispatch, noUncertainOutcome, readbackInProgress
}

public enum ParticipantCoordinatorAction: Equatable {
    case applied, ignoredStale
    case blocked(ParticipantCoordinatorBlock)
}

/// Retain one coordinator in the account/session owner across list, detail and sheet
/// navigation. Do not recreate it on each form appearance: unresolved mutations lock that
/// account across dismissal/relogin. An injected journal persists only the unresolved
/// operation lock across restart, never a contact payload, token or automatic replay.
/// Only an explicit same-owner original-create retry uses fixed58 idempotency. Different
/// accounts never see each other's snapshots; edit/delete remain read-only when unknown.
@MainActor
public final class ParticipantMutationCoordinator {
    private let writer: any ParticipantWriting
    private let reader: any ProfileReading
    private let onParticipantsChanged: () -> Void
    private var records: [Int: Record] = [:]
    private let pendingJournal: (any OperationPendingJournal)?
    private let pendingOwner: () -> String?
    private var activePendingOwner: String?
    private var journalUnavailable = false

    private enum ReadbackTarget { case list, detail(Int) }
    private struct Record {
        let id: UUID
        let originalIdentity: ProfileReadIdentity
        let target: ReadbackTarget
        var state: ParticipantMutationState
        var readback: ParticipantReadbackState = .idle
        var readbackIdentity: ProfileReadIdentity?
        var readGeneration: UInt64 = 0
        var writeGeneration: UInt64 = 0
        var savedParticipant: ProfileParticipant?
        var pending: OperationPendingRecord?
        var restored = false
    }

    public init(writer: any ParticipantWriting, reader: any ProfileReading,
                pendingJournal: (any OperationPendingJournal)? = nil,
                pendingOwner: @escaping () -> String? = { nil },
                onParticipantsChanged: @escaping () -> Void = {}) {
        self.writer = writer; self.reader = reader; self.onParticipantsChanged = onParticipantsChanged
        self.pendingJournal = pendingJournal; self.pendingOwner = pendingOwner
    }

    public var identity: ProfileReadIdentity? {
        guard writer.identity == reader.identity else { return nil }
        return writer.identity
    }
    public var isConfigured: Bool { writer.isConfigured && reader.isConfigured }
    public var state: ParticipantMutationState {
        synchronizeSession()
        guard let identity else { return .idle }
        if journalUnavailable { return .outcomeUnknown(.transport) }
        return records[identity.accountID]?.state ?? .idle
    }
    public var readbackState: ParticipantReadbackState {
        guard let identity, let record = records[identity.accountID], record.readbackIdentity == identity else { return .idle }
        return record.readback
    }
    public var savedParticipant: ProfileParticipant? {
        guard let identity, let record = records[identity.accountID], record.originalIdentity == identity,
              record.state == .succeeded else { return nil }
        return record.savedParticipant
    }
    public var canPrepare: Bool { isConfigured && identity != nil && !state.preventsNewMutation }

    /// Call on session changes as well as screen entry. Confirmation and read snapshots
    /// are scoped to an epoch; only the PII-free unresolved-operation lock survives it.
    public func synchronizeSession() {
        let current = identity
        restorePending(for: current)
        for account in Array(records.keys) {
            guard let record = records[account] else { continue }
            if record.originalIdentity != current {
                if record.state == .awaitingConfirmation { records[account] = nil; continue }
                if record.state == .submitting {
                    records[account]?.writeGeneration &+= 1
                    records[account]?.state = .outcomeUnknown(.accountChanged)
                }
                records[account]?.savedParticipant = nil
            }
            if record.readbackIdentity != current {
                records[account]?.readback = .idle
                records[account]?.readbackIdentity = nil
                records[account]?.readGeneration &+= 1
            }
        }
    }

    // Storage scope is supplied by the session host, not inferred from a row or token.
    // No epoch is persisted: a new process must see the same owner's unresolved lock.
    private func restorePending(for identity: ProfileReadIdentity?) {
        guard let journal = pendingJournal else { return }
        guard let identity, let owner = pendingOwner(), !owner.isEmpty else {
            journalUnavailable = identity != nil
            return
        }
        if activePendingOwner != owner {
            records.removeAll() // Never expose a same-number account from another realm.
            activePendingOwner = owner
        }
        do {
            let pending = try journal.pending(ownerKey: owner, targetKey: "profile.participants")
            journalUnavailable = false
            guard let pending else { return }
            guard pending.ownerKey == owner, pending.targetKey == "profile.participants",
                  pending.acknowledgedSteps == 0 else { journalUnavailable = true; return }
            if let record = records[identity.accountID], record.id == pending.operationID,
               record.pending == pending { return }
            // Restore the original operation ID but not a confirmation or retry payload.
            // List inspection is safe for every mutation; it never resolves the lock.
            records[identity.accountID] = Record(id: pending.operationID, originalIdentity: identity,
                target: .list, state: .outcomeUnknown(.transport), pending: pending, restored: true)
        } catch { journalUnavailable = true }
    }
    private func persistBeforeDispatch(_ confirmation: ParticipantConfirmation) throws {
        guard let journal = pendingJournal else { return }
        guard !journalUnavailable, let owner = pendingOwner(), owner == activePendingOwner else {
            throw ParticipantCoordinatorBlock.unavailable
        }
        let pending = OperationPendingRecord(operationID: confirmation.id, ownerKey: owner,
            targetKey: "profile.participants", acknowledgedSteps: 0)
        // A failed/uncertain local write never permits a network dispatch.
        try journal.write(pending)
        guard try journal.pending(ownerKey: owner, targetKey: "profile.participants") == pending else {
            throw ParticipantCoordinatorBlock.unavailable
        }
        records[confirmation.identity.accountID]?.pending = pending
    }
    private func clearPending(_ record: Record) -> Bool {
        guard let journal = pendingJournal, let pending = record.pending else { return true }
        do {
            try journal.clear(pending)
            guard try journal.pending(ownerKey: pending.ownerKey, targetKey: pending.targetKey) == nil else { return false }
            return true
        } catch { return false }
    }

    public func prepare(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) throws -> ParticipantConfirmation {
        synchronizeSession()
        guard isConfigured else { throw ParticipantCoordinatorBlock.unavailable }
        guard let identity else { throw ParticipantCoordinatorBlock.signedOut }
        guard identity == expectedIdentity else { throw ParticipantCoordinatorBlock.accountChanged }
        guard !state.preventsNewMutation else { throw ParticipantCoordinatorBlock.pendingOperation }
        guard !Task.isCancelled else { throw ParticipantCoordinatorBlock.cancelledBeforeDispatch }
        do { _ = try mutation.fields() } catch { throw ParticipantCoordinatorBlock.invalidForm }
        let confirmation = ParticipantConfirmation(identity: identity, mutation: mutation)
        let target: ReadbackTarget
        switch mutation {
        case .save(let draft): target = draft.id.map(ReadbackTarget.detail) ?? .list
        case .delete: target = .list
        case .setDefault(let id): target = .detail(id)
        }
        records[identity.accountID] = Record(id: confirmation.id, originalIdentity: identity,
                                             target: target, state: .awaitingConfirmation)
        return confirmation
    }

    /// Cancel only the still-unsubmitted confirmation that belongs to this screen.
    public func cancelConfirmation(_ confirmation: ParticipantConfirmation) {
        guard let record = records[confirmation.identity.accountID], record.id == confirmation.id,
              record.state == .awaitingConfirmation else { return }
        records[confirmation.identity.accountID] = nil
    }

    /// Invoke exclusively from the user's explicit confirmation action. A frozen intent,
    /// not later text-field edits, is submitted. Repeated taps cannot send it twice.
    @discardableResult
    public func confirm(_ confirmation: ParticipantConfirmation) async -> ParticipantCoordinatorAction {
        // Preserve the original pre-dispatch accountChanged result before synchronization
        // retires the matching unsubmitted confirmation.
        if let record = records[confirmation.identity.accountID], record.id == confirmation.id,
           record.state == .awaitingConfirmation, identity != confirmation.identity {
            cancelConfirmation(confirmation)
            synchronizeSession()
            return .blocked(.accountChanged)
        }
        synchronizeSession()
        guard !journalUnavailable else { return .blocked(.unavailable) }
        let account = confirmation.identity.accountID
        guard let record = records[account], record.id == confirmation.id,
              record.state == .awaitingConfirmation else { return .blocked(.confirmationNoLongerValid) }
        guard identity == confirmation.identity else {
            cancelConfirmation(confirmation)
            return .blocked(.accountChanged)
        }
        guard !Task.isCancelled else {
            cancelConfirmation(confirmation)
            return .blocked(.cancelledBeforeDispatch)
        }
        do { try persistBeforeDispatch(confirmation) }
        catch {
            records[account]?.state = .notSent
            synchronizeSession()
            return .blocked(.unavailable)
        }
        records[account]?.writeGeneration &+= 1
        let attempt = records[account]?.writeGeneration
        records[account]?.state = .submitting
        let nextState: ParticipantMutationState
        var saved: ProfileParticipant?
        do {
            let row = try await writer.performReturningParticipant(confirmation.mutation, requestID: confirmation.id, expectedIdentity: confirmation.identity)
            guard !Task.isCancelled else { throw ParticipantWriteError.outcomeUnknown(.cancelled) }
            if let original = ParticipantOriginalCreateRetry(confirmation: confirmation), !original.accepts(row) {
                throw ParticipantWriteError.outcomeUnknown(.malformedResponse)
            }
            saved = row
            nextState = Task.isCancelled ? .outcomeUnknown(.cancelled) : .succeeded
        } catch let failure as ParticipantWriteError {
            switch failure {
            case .notSent, .cancelledBeforeDispatch: nextState = .notSent
            case .rejected(let response): nextState = .rejected(response)
            case .outcomeUnknown(let issue): nextState = .outcomeUnknown(issue)
            }
        } catch {
            nextState = .outcomeUnknown(error is CancellationError ? .cancelled : .transport)
        }
        guard records[account]?.id == confirmation.id, records[account]?.writeGeneration == attempt,
              records[account]?.state == .submitting else { return .ignoredStale }
        guard identity == confirmation.identity else {
            // Even a discarded success is not permission to silently send again.
            switch nextState {
            case .notSent, .rejected:
                let cleared = records[account].map { clearPending($0) } == true
                records[account]?.state = cleared ? nextState : .outcomeUnknown(.transport)
            default: records[account]?.state = .outcomeUnknown(.accountChanged)
            }
            return .ignoredStale
        }
        switch nextState {
        case .succeeded, .notSent, .rejected:
            guard let completed = records[account], clearPending(completed) else {
                records[account]?.state = .outcomeUnknown(.transport)
                return .applied
            }
        default: break
        }
        records[account]?.state = nextState
        if nextState == .succeeded { records[account]?.savedParticipant = saved; onParticipantsChanged() }
        return .applied
    }

    /// Exact original create only. No `prepare`, new UUID, payload rebuild, alternate
    /// writer, automatic replay or edit/delete retry is reachable from this action.
    public func canRetryOriginalCreate(_ original: ParticipantOriginalCreateRetry) -> Bool {
        synchronizeSession()
        guard isConfigured, identity == original.identity,
              let record = records[original.identity.accountID], record.id == original.requestID,
              record.originalIdentity == original.identity, !record.restored, !journalUnavailable,
              case .outcomeUnknown = record.state, record.readback != .loading else { return false }
        return true
    }
    @discardableResult
    public func retryOriginalCreate(_ original: ParticipantOriginalCreateRetry) async -> ParticipantCoordinatorAction {
        guard canRetryOriginalCreate(original) else { return .blocked(.confirmationNoLongerValid) }
        guard !Task.isCancelled else { return .blocked(.cancelledBeforeDispatch) }
        let confirmation = original.confirmation, account = original.identity.accountID
        do { try persistBeforeDispatch(confirmation) }
        catch { return .blocked(.unavailable) }
        records[account]?.writeGeneration &+= 1
        let attempt = records[account]?.writeGeneration
        records[account]?.state = .submitting
        records[account]?.readGeneration &+= 1
        records[account]?.readback = .idle; records[account]?.readbackIdentity = nil
        records[account]?.savedParticipant = nil
        let nextState: ParticipantMutationState
        var saved: ProfileParticipant?
        do {
            let row = try await writer.performReturningParticipant(confirmation.mutation,
                requestID: confirmation.id, expectedIdentity: confirmation.identity)
            guard !Task.isCancelled else { throw ParticipantWriteError.outcomeUnknown(.cancelled) }
            guard original.accepts(row) else { throw ParticipantWriteError.outcomeUnknown(.malformedResponse) }
            saved = row
            nextState = Task.isCancelled ? .outcomeUnknown(.cancelled) : .succeeded
        } catch let failure as ParticipantWriteError {
            // Failure of this retry cannot prove the first dispatched request failed.
            // In particular a new 401/notSent is NOT permission to mint another UUID.
            switch failure {
            case .notSent, .cancelledBeforeDispatch: nextState = .outcomeUnknown(.transport)
            case .rejected(let response): nextState = .outcomeUnknown(.response(response))
            case .outcomeUnknown(let issue): nextState = .outcomeUnknown(issue)
            }
        } catch { nextState = .outcomeUnknown(error is CancellationError ? .cancelled : .transport) }
        guard records[account]?.id == confirmation.id, records[account]?.writeGeneration == attempt,
              records[account]?.state == .submitting else { return .ignoredStale }
        guard identity == confirmation.identity, !Task.isCancelled else {
            records[account]?.state = .outcomeUnknown(.accountChanged)
            records[account]?.savedParticipant = nil
            return .ignoredStale
        }
        if nextState == .succeeded {
            guard let completed = records[account], clearPending(completed) else {
                records[account]?.state = .outcomeUnknown(.transport)
                return .applied
            }
        }
        records[account]?.state = nextState
        if nextState == .succeeded {
            records[account]?.savedParticipant = saved
            onParticipantsChanged()
        }
        return .applied
    }

    /// Local dismissal cannot undo a server write. A late response cannot unlock a locally
    /// interrupted request. The HTTP task itself is never represented as server cancellation.
    public func leaveScreen(confirmation: ParticipantConfirmation?) {
        guard let confirmation, records[confirmation.identity.accountID]?.id == confirmation.id else { return }
        cancelConfirmation(confirmation)
        if records[confirmation.identity.accountID]?.state == .submitting {
            records[confirmation.identity.accountID]?.writeGeneration &+= 1
            records[confirmation.identity.accountID]?.savedParticipant = nil
            records[confirmation.identity.accountID]?.state = .outcomeUnknown(.cancelled)
        }
    }

    /// Dismissing a readback clears its PII snapshot and invalidates late read completion,
    /// without removing the mutation lock. A stale screen cannot cancel a newer epoch's read.
    public func discardReadback(expectedIdentity: ProfileReadIdentity) {
        guard records[expectedIdentity.accountID]?.readbackIdentity == expectedIdentity else { return }
        records[expectedIdentity.accountID]?.readGeneration &+= 1
        records[expectedIdentity.accountID]?.readback = .idle
        records[expectedIdentity.accountID]?.readbackIdentity = nil
    }

    /// Exactly one explicit read; no mutation, polling, automatic retry, or unlocking.
    /// A list read has no request-ID proof, and /list completeness is unverified.
    /// Users can inspect the returned rows, but absence/matching names cannot prove outcome.
    @discardableResult
    public func readBackUncertainOutcome() async -> ParticipantCoordinatorAction {
        synchronizeSession()
        guard let identity else { return .blocked(.signedOut) }
        guard !journalUnavailable else { return .blocked(.unavailable) }
        guard var record = records[identity.accountID], case .outcomeUnknown = record.state else {
            return .blocked(.noUncertainOutcome)
        }
        guard record.readback != .loading else { return .blocked(.readbackInProgress) }
        guard !Task.isCancelled else { return .blocked(.cancelledBeforeDispatch) }
        record.readGeneration &+= 1
        let generation = record.readGeneration
        record.readback = .loading; record.readbackIdentity = identity
        records[identity.accountID] = record
        let result: ParticipantReadbackState
        do {
            switch record.target {
            case .list: result = .received(.list(try await reader.profileParticipants()))
            case .detail(let id):
                let detail = try await reader.profileParticipant(id: id)
                guard detail.id == id else { throw APIError.malformedResponse }
                result = .received(.detail(detail))
            }
        } catch { result = .unavailable }
        guard self.identity == identity, !Task.isCancelled,
              records[identity.accountID]?.id == record.id,
              records[identity.accountID]?.readGeneration == generation else {
            if records[identity.accountID]?.id == record.id,
               records[identity.accountID]?.readbackIdentity == identity,
               records[identity.accountID]?.readGeneration == generation {
                records[identity.accountID]?.readback = .idle
            }
            return .ignoredStale
        }
        records[identity.accountID]?.readback = result
        return .applied
    }
}

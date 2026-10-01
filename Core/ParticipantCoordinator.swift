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
/// account in memory, even after dismissal/relogin. No persistence, automatic replay, retry,
/// or claim of backend idempotency. Different accounts never see each other's snapshots.
@MainActor
public final class ParticipantMutationCoordinator {
    private let writer: any ParticipantWriting
    private let reader: any ProfileReading
    private let onParticipantsChanged: () -> Void
    private var records: [Int: Record] = [:]

    private enum ReadbackTarget { case list, detail(Int) }
    private struct Record {
        let id: UUID
        let originalIdentity: ProfileReadIdentity
        let target: ReadbackTarget
        var state: ParticipantMutationState
        var readback: ParticipantReadbackState = .idle
        var readbackIdentity: ProfileReadIdentity?
        var readGeneration: UInt64 = 0
    }

    public init(writer: any ParticipantWriting, reader: any ProfileReading,
                onParticipantsChanged: @escaping () -> Void = {}) {
        self.writer = writer; self.reader = reader; self.onParticipantsChanged = onParticipantsChanged
    }

    public var identity: ProfileReadIdentity? {
        guard writer.identity == reader.identity else { return nil }
        return writer.identity
    }
    public var isConfigured: Bool { writer.isConfigured && reader.isConfigured }
    public var state: ParticipantMutationState {
        synchronizeSession()
        guard let identity else { return .idle }
        return records[identity.accountID]?.state ?? .idle
    }
    public var readbackState: ParticipantReadbackState {
        guard let identity, let record = records[identity.accountID], record.readbackIdentity == identity else { return .idle }
        return record.readback
    }
    public var canPrepare: Bool { isConfigured && identity != nil && !state.preventsNewMutation }

    /// Call on session changes as well as screen entry. Confirmation and read snapshots
    /// are scoped to an epoch; only the PII-free unresolved-operation lock survives it.
    public func synchronizeSession() {
        let current = identity
        for account in Array(records.keys) {
            guard let record = records[account] else { continue }
            if record.originalIdentity != current {
                if record.state == .awaitingConfirmation { records[account] = nil; continue }
                if record.state == .submitting { records[account]?.state = .outcomeUnknown(.accountChanged) }
            }
            if record.readbackIdentity != current {
                records[account]?.readback = .idle
                records[account]?.readbackIdentity = nil
                records[account]?.readGeneration &+= 1
            }
        }
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
        records[account]?.state = .submitting
        let nextState: ParticipantMutationState
        do {
            try await writer.perform(confirmation.mutation, expectedIdentity: confirmation.identity)
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
        guard records[account]?.id == confirmation.id, records[account]?.state == .submitting else { return .ignoredStale }
        guard identity == confirmation.identity else {
            // Even a discarded success is not permission to silently send again.
            switch nextState {
            case .notSent, .rejected: records[account]?.state = nextState
            default: records[account]?.state = .outcomeUnknown(.accountChanged)
            }
            return .ignoredStale
        }
        records[account]?.state = nextState
        if nextState == .succeeded { onParticipantsChanged() }
        return .applied
    }

    /// Local dismissal cannot undo a server write. A late response cannot unlock a locally
    /// interrupted request. The HTTP task itself is never represented as server cancellation.
    public func leaveScreen(confirmation: ParticipantConfirmation?) {
        guard let confirmation, records[confirmation.identity.accountID]?.id == confirmation.id else { return }
        cancelConfirmation(confirmation)
        if records[confirmation.identity.accountID]?.state == .submitting {
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
    /// A create has no source-guaranteed returned ID, and /list completeness is unverified.
    /// Users can inspect the returned rows, but absence/matching names cannot prove outcome.
    @discardableResult
    public func readBackUncertainOutcome() async -> ParticipantCoordinatorAction {
        synchronizeSession()
        guard let identity else { return .blocked(.signedOut) }
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
            if records[identity.accountID]?.readGeneration == generation {
                records[identity.accountID]?.readback = .idle
            }
            return .ignoredStale
        }
        records[identity.accountID]?.readback = result
        return .applied
    }
}

import Foundation
import Observation

public enum NativeChannelMessageMutationState: Equatable {
    case idle, saving, dispatching, checking, unknown, persistenceFailed, accessClosed
    case applied(redacted: Bool), rejected(code: String)
}

@MainActor @Observable public final class NativeChannelMessageCoordinator {
    public let client: any NativeChannelMessageAccess
    public let search: NativeChannelMessageSearch
    public let pins: NativeChannelMessagePins
    public let editRecallReadback: NativeChannelMessageEditRecallReadback
    public private(set) var state: NativeChannelMessageMutationState = .idle
    public private(set) var original: NativeChannelMessageCommand?
    public private(set) var projection = NativeChannelMessageProjection()
    public var draft = ""
    public private(set) var draftMessageID: NativeChannelMessageID?
    public private(set) var historyReady = false
    public private(set) var lastFailure: NativeChannelMessageFailure?
    public private(set) var busy = false
    public private(set) var historyRefreshFailed = false
    private let journal: any NativeChannelMessageMutationRecording
    private let expected: MessagingReadIdentity?
    private var generation = 0
    private var active = false
    private var activating = false
    private var rejectionAfterLookup = false
    /// Existing history host re-reads/replaces its projection; result versions are never cached as history.
    @ObservationIgnored private let refreshOriginalHistory: () async throws -> Void
    @ObservationIgnored private let invalidateOriginalMessage: (NativeChannelMessageID) -> Void
    public init(client: any NativeChannelMessageAccess, journal: any NativeChannelMessageMutationRecording,
                invalidateOriginalMessage: @escaping (NativeChannelMessageID) -> Void,
                refreshOriginalHistory: @escaping () async throws -> Void) throws {
        guard journal.scope.binding.sameTarget(as: client.binding) else { throw APIError.invalidConfiguration }
        self.client = client; self.journal = journal; self.refreshOriginalHistory = refreshOriginalHistory
        self.invalidateOriginalMessage = invalidateOriginalMessage
        expected = client.identity; search = .init(client: client); pins = .init(client: client)
        editRecallReadback = .init(client: client)
    }
    public var isCurrent: Bool { active && expected != nil && client.identity == expected }
    public var canStart: Bool { isCurrent && historyReady && !busy && original == nil }
    public func canDisplay(_ row: NativeChannelMessageSnapshot) -> Bool {
        isCurrent && historyReady && client.allows(.mutations) && row.conversationID == client.binding.conversationID
            && (row.status != 0 || !projection.withheld.contains(row.id)) && row.version >= projection.versions[row.id, default: 0]
    }
    public func prepareEdit(_ row: NativeChannelMessageSnapshot) {
        guard canStart else { return }
        if draftMessageID != row.id { draftMessageID = row.id; draft = row.content ?? "" }
    }
    public func activate() async {
        guard !activating, !busy else { return }
        activating = true
        defer { activating = false }
        active = true; generation += 1; historyReady = false; state = .idle
        do {
            original = try journal.restore()
            if let original { draft = original.content ?? draft; draftMessageID = original.messageID; state = .unknown; await recover() }
            await refreshHistory(run: generation)
        } catch { state = .persistenceFailed }
    }
    public func retire() {
        active = false; generation += 1; busy = false; state = .accessClosed
        client.retireOperations()
        original = nil; draft = ""; draftMessageID = nil; historyReady = false; lastFailure = nil; rejectionAfterLookup = false
        search.retire(); pins.retire(); pins.retireAppliedReadback(); projection.retire()
        editRecallReadback.retire()
    }
    public func submit(_ command: NativeChannelMessageCommand) async {
        guard canStart, command.binding == client.binding, client.allows(.mutate(command.operation)) else { return }
        if command.operation == .edit || command.operation == .recall || command.operation == .sort
            || command.operation == .pin || command.operation == .unpin {
            guard client.allows(.receipt) else { return }
        }
        let lease: UUID
        do { lease = try journal.acquire() } catch { state = .persistenceFailed; return }
        defer { journal.release(lease) }
        busy = true; let run = generation
        defer { if generation == run { busy = false } }
        state = .saving; lastFailure = nil; rejectionAfterLookup = false
        do {
            try journal.saveBeforeDispatch(command); original = command
            if command.operation == .edit || command.operation == .recall { editRecallReadback.retire() }
            if command.operation == .edit { draft = command.content ?? draft }
        } catch { state = .persistenceFailed; return }
        state = .dispatching
        do {
            let result = try await client.mutate(command)
            guard current(run) else { return }
            try result.verify(command)
            if command.operation == .edit || command.operation == .recall {
                // The write ACK lacks request_id. Only the original saved UUID receipt
                // may settle this request; NOT_FOUND/PENDING/failed lookup stays UNKNOWN.
                await lookup(command, run: run)
                return
            }
            if command.operation == .pin || command.operation == .unpin || command.operation == .sort {
                // PIN_SORT also returns only updated/sort_nos, never request_id.
                // Confirm the saved original UUID through the existing receipt reader
                // before independently refreshing the current pins. A matching current
                // order is not proof that this original request was applied.
                await lookup(command, run: run)
                return
            }
            try journal.settle(command); original = nil; state = .applied(redacted: false)
            // Retire older content before refresh; never turn a local delete into recall success.
            if let messageID = command.messageID { invalidateOriginalMessage(messageID) }
            await refreshOriginalReadSurfaces(after: command)
            if current(run) { await refreshHistory(run: run) }
        } catch {
            guard current(run) else { return }
            lastFailure = error as? NativeChannelMessageFailure
            await lookup(command, run: run) // All failure paths use the original receipt, never resend.
        }
    }
    public func recover() async {
        guard isCurrent, !busy else { return }
        let lease: UUID
        do { lease = try journal.acquire() } catch { return }
        defer { journal.release(lease) }
        busy = true; let run = generation
        defer { if generation == run { busy = false } }
        do {
            guard let command = try journal.restore() else { original = nil; state = .idle; return }
            original = command; draft = command.content ?? draft
            await lookup(command, run: run)
        } catch { if current(run) { state = .persistenceFailed } }
    }
    private func lookup(_ command: NativeChannelMessageCommand, run: Int) async {
        state = .checking
        do {
            let receipt = try await client.receipt(command)
            guard current(run) else { return }
            if try receipt.verify(command) {
                try journal.settle(command); original = nil; state = .applied(redacted: receipt.result_redacted == true)
                if let messageID = command.messageID { invalidateOriginalMessage(messageID) }
                if receipt.result_redacted == true { historyReady = false; projection.retire(); search.retire(); pins.retire(); pins.retireAppliedReadback() }
                else {
                    if command.operation == .edit || command.operation == .recall {
                        await editRecallReadback.observeApplied(command, receipt: receipt)
                        guard current(run) else { return }
                    }
                    await refreshOriginalReadSurfaces(after: command)
                    if current(run) { await refreshHistory(run: run) }
                }
                if receipt.result_redacted == true { editRecallReadback.retire() }
            } else if receipt.state == "NOT_FOUND", let failure = lastFailure, failure.definiteRejection {
                rejectionAfterLookup = true; state = .rejected(code: failure.errorCode!)
                // CAS conflict refreshes the current source but preserves the user's draft.
                if failure.versionConflict { await refreshHistory(run: run) }
            } else { state = .unknown }
        } catch { if current(run) { state = .unknown } }
    }
    /// User acknowledges a proved HTTP4xx rejection AFTER original lookup. Never available for UNKNOWN.
    public func acknowledgeRejected() {
        guard isCurrent, !busy, rejectionAfterLookup, case .rejected = state, let original else { return }
        do { try journal.settle(original); self.original = nil; state = .idle; rejectionAfterLookup = false }
        catch { state = .persistenceFailed }
    }
    public func replacedHistory(cursor: String, contract: String, cacheAction: String, rows: [NativeChannelMessageSnapshot]) throws {
        guard isCurrent else { throw APIError.notConfigured }
        try projection.replacedHistory(mutationCursor: cursor, syncContract: contract, legacyCacheAction: cacheAction,
                                       snapshots: rows, binding: client.binding)
        historyReady = true
    }
    public func synchronizeMutations() async throws {
        guard isCurrent, let cursor = projection.mutationCursor else { throw APIError.notConfigured }
        let run = generation, page = try await client.mutations(after: cursor)
        guard current(run), projection.mutationCursor == cursor else { throw CancellationError() }
        try projection.consume(page, binding: client.binding)
        for change in page.list { invalidateOriginalMessage(change.message_id) }
        // Search results are also original message bodies. Retire their old generation
        // before any suspension, then use the original search reader, never mutation text.
        if !page.list.isEmpty {
            pins.invalidateOriginalRows()
            await search.refreshOriginalQuery()
            await pins.refreshIfActive()
            guard current(run) else { throw CancellationError() }
            try await refreshOriginalHistory()
        }
    }
    private func refreshOriginalReadSurfaces(after command: NativeChannelMessageCommand) async {
        pins.invalidateOriginalRows()
        if command.operation == .edit || command.operation == .recall {
            await search.refreshOriginalQuery()
        }
        if command.operation == .pin || command.operation == .unpin {
            await pins.observeApplied(command)
        } else { await pins.refreshIfActive() }
    }
    private func current(_ run: Int) -> Bool { generation == run && isCurrent && !Task.isCancelled }
    public func refreshHistory() async { if isCurrent { await refreshHistory(run: generation) } }
    private func refreshHistory(run: Int) async {
        do { try await refreshOriginalHistory(); if current(run) { historyRefreshFailed = false } }
        catch { if current(run) { historyRefreshFailed = true } }
    }
}

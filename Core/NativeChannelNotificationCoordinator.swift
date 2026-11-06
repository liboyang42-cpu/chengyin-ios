import Foundation
import Observation

public enum NativeChannelNotificationState: Equatable {
    case idle, loading, ready, saving, checkingReceipt, outcomeUnknown, pending, applied
    case appliedRedacted, refreshFailed, persistenceFailed, accessClosed
    case failed(NativeChannelNotificationError)
}

/// One account/deployment journal, shared by all settings screens. Every uncertain
/// write keeps its exact original key/body. Appearance and foreground only read.
@MainActor @Observable public final class NativeChannelNotificationCoordinator {
    /// Payload-free invalidation only; the app must reread its current independent unread grant.
    public static let originalUnreadPolicyCommitted = Notification.Name("native.original-im-unread-policy-committed.v1")
    public let scope: NativeChannelNotificationScope?
    public let sharedClubDefaultMode: Bool
    private let client: any NativeChannelNotificationAccess
    private let journal: NativeChannelNotificationJournal
    private var unreadRecoveryOnly = false
    private var active = false
    private var generation: UInt64 = 0
    private var busy = false
    private var storedDirectory: NativeChannelNotificationDirectory?
    private var storedClubDefault: NativeClubNotificationDefault?
    private var storedDefaultRejection: String?
    private var storedReceipt: NativeChannelNotificationReceipt?
    private var storedUnread: NativeChannelNotificationUnreadSummary?
    private var command: NativeChannelNotificationCommand?
    private var serverContext: NativeChannelNotificationServerFailure?
    private var storedFailure: NativeChannelNotificationError?
    public private(set) var state: NativeChannelNotificationState = .idle
    public private(set) var unreadIssue = false
    public var lastFailure: NativeChannelNotificationError? { isCurrent ? storedFailure : nil }
    /// Preserved separately from lookup_path. The native host owns any navigation.
    public var recoveryReturnPath: String? { isCurrent ? (serverContext?.returnPath ?? serverContext?.recovery?.returnPath) : nil }
    @ObservationIgnored public var onUnreadSummary: ((NativeChannelNotificationUnreadSummary) -> Void)?
    public init(client: any NativeChannelNotificationAccess, journal: NativeChannelNotificationJournal,
                scope: NativeChannelNotificationScope?, sharedClubDefault: Bool = false) throws {
        guard (!sharedClubDefault || scope?.type == 2),
              journal.owner == NativeChannelNotificationJournalOwner(context: client.context),
              scope.map({ $0.belongsToAccount(String(client.context.session.accountID)) }) ?? true else {
            throw NativeChannelNotificationError.accessClosed
        }
        self.client = client; self.journal = journal; self.scope = scope; sharedClubDefaultMode = sharedClubDefault
    }
    public var isCurrent: Bool { active && client.isCurrent }
    public var canRead: Bool { isCurrent && client.allows(sharedClubDefaultMode ? .clubDefaultRead : (scope == nil ? .directory : .preference), scope: scope) }
    public var clubDefault: NativeClubNotificationDefault? { sharedClubDefaultMode && canRead ? storedClubDefault : nil }
    public var sharedDefaultRejection: String? { isCurrent ? storedDefaultRejection : nil }
    public var canSaveClubDefault: Bool { sharedClubDefaultMode && !unreadRecoveryOnly && canRead && clubDefault != nil && !busy && command == nil && state != .persistenceFailed && client.allows(.clubDefaultSave, scope: scope) }
    public var directory: NativeChannelNotificationDirectory? { canRead ? storedDirectory : nil }
    public var accountDefaultScope: NativeChannelNotificationScope? {
        guard let row = directory?.defaults.preference,
              row.scope.value == String(client.context.session.accountID) else { return nil }
        return row.scope
    }
    public var preference: NativeChannelNotificationPreference? { scope.flatMap { target in directory?.list.first { $0.scope == target } } }
    public var receipt: NativeChannelNotificationReceipt? {
        guard isCurrent, let command, client.allows(.receipt, scope: command.scope) else { return nil }
        return storedReceipt
    }
    public var unread: NativeChannelNotificationUnreadSummary? { isCurrent && client.allows(.unread, scope: nil) ? storedUnread : nil }
    public var pendingRequestID: String? { isCurrent ? command?.requestID : nil }
    public var isBusy: Bool { busy }
    public var canSave: Bool { !sharedClubDefaultMode && !unreadRecoveryOnly && canRead && preference != nil && !busy && command == nil && state != .persistenceFailed && client.allows(.save, scope: scope) }
    public var canMute: Bool { !unreadRecoveryOnly && canRead && scope?.type == 1 && !busy && command == nil && state != .persistenceFailed && client.allows(.mute, scope: scope) }
    /// ACK uses its own grant. A mute or preference grant does not enable it.
    public var canAck: Bool { !unreadRecoveryOnly && isCurrent && scope?.type == 1 && !busy && command == nil && state != .persistenceFailed && client.allows(.ack, scope: scope) }
    public var canCheckReceipt: Bool { !unreadRecoveryOnly && isCurrent && !busy && command.map { client.allows(.receipt, scope: $0.scope) } == true }

    /// Host calls on logout/revocation, background, identity or approval change.
    /// Persisted original intent remains in protected storage for its original owner.
    public func deactivate() {
        client.retireOperations()
        active = false; generation &+= 1; busy = false
        storedDirectory = nil; storedClubDefault = nil; storedDefaultRejection = nil; storedReceipt = nil; storedUnread = nil; command = nil
        unreadIssue = false; storedFailure = nil; serverContext = nil; state = .accessClosed
    }
    public func activate() async {
        guard !Task.isCancelled else { return }
        if unreadRecoveryOnly { deactivate(); unreadRecoveryOnly = false }
        guard !active else { return }
        active = true; generation &+= 1
        await refresh()
    }
    /// Normal foreground unread recovery. No preference read, ACK, token registration,
    /// original write retry or OS prompt is implied by this independent read grant.
    public func activateUnreadRecovery() async {
        guard !Task.isCancelled else { return }
        if active && !unreadRecoveryOnly { deactivate() }
        unreadRecoveryOnly = true
        if !active { active = true; generation &+= 1 }
        await refreshUnreadRecovery()
    }
    public func refreshUnreadRecovery() async {
        guard !Task.isCancelled, unreadRecoveryOnly, isCurrent, !busy else { return }
        guard client.allows(.unread, scope: nil) else {
            storedUnread = nil; unreadIssue = true; state = .accessClosed; return
        }
        let ticket = generation; busy = true; state = .loading; storedUnread = nil; unreadIssue = false
        defer { if ticket == generation { busy = false } }
        await refreshUnread(ticket: ticket)
        guard current(ticket) else { return }
        state = unreadIssue ? .refreshFailed : .ready
    }
    public func refresh() async {
        guard !Task.isCancelled else { return }
        if unreadRecoveryOnly { await refreshUnreadRecovery(); return }
        guard isCurrent, !busy, let lease = journal.acquire() else { return }
        let ticket = generation; busy = true
        // An original receipt/current read is not evidence that the last visible
        // projection is still current. Keep the protected command, not old rows.
        storedDirectory = nil; storedClubDefault = nil; storedReceipt = nil; storedUnread = nil
        defer { journal.release(lease); if ticket == generation { busy = false } }
        do {
            command = try journal.restore()
            serverContext = try command.flatMap { try journal.failureContext(for: $0) }
        }
        catch { state = .persistenceFailed; return }
        if let original = command {
            state = .checkingReceipt
            do {
                let result = try await client.receipt(original, recovery: serverContext?.recovery)
                guard current(ticket) else { return }
                try result.validate(for: original)
                if result.status == "APPLIED" {
                    try settle(original, receipt: result)
                    if result.resultRedacted == true { return }
                    if original.operation == .ack { await refreshUnread(ticket: ticket); return }
                } else if result.status == "REJECTED" {
                    try settleRejected(original, receipt: result)
                    if result.resultRedacted == true { return }
                } else { storedReceipt = result; state = result.status == "PENDING" ? .pending : .outcomeUnknown }
            } catch {
                guard current(ticket) else { return }
                handle(error, uncertain: true, preserveRecovery: true)
                if state == .accessClosed || state == .persistenceFailed { return }
            }
        } else { state = .loading }
        await readCurrent(ticket: ticket, afterApplied: state == .applied)
    }
    public func saveClubDefault(level: NativeChannelNotificationLevel, expectedVersion: Int64) async {
        guard canSaveClubDefault, let row = clubDefault else { return }
        guard row.version == expectedVersion else {
            storedFailure = .server(httpStatus: 409, code: 409, errorCode: "CLUB_DEFAULT_VERSION_CONFLICT")
            state = .failed(storedFailure!); return
        }
        do { await dispatchNew(try .init(clubDefault: row, level: level)) }
        catch { state = .failed(.invalidInput) }
    }
    public func save(_ draft: NativeChannelNotificationDraft, expectedVersion: Int64) async {
        guard canSave, let preference else { return }
        guard preference.version == expectedVersion else {
            storedFailure = .server(httpStatus: 409, code: 409, errorCode: "PREFERENCE_VERSION_CONFLICT")
            state = .failed(storedFailure!); return
        }
        do { await dispatchNew(try .init(preference: preference, draft: draft)) }
        catch { state = .failed(.invalidInput) }
    }
    public func mute(minutes: Int) async {
        guard canMute, let scope else { return }
        do { await dispatchNew(try .init(scope: scope, minutes: minutes)) }
        catch { state = .failed(.invalidInput) }
    }
    /// Explicit read cursor. Persists through the original journal before POST api/im/read.
    public func acknowledge(lastMessageID: Int64) async {
        guard canAck, let scope, let channel = Int64(scope.value), channel > 0 else { return }
        do { await dispatchNew(try .init(ackChannelID: channel, lastMessageID: lastMessageID)) }
        catch { state = .failed(.invalidInput) }
    }
    private func dispatchNew(_ intent: NativeChannelNotificationCommand) async {
        guard !Task.isCancelled, isCurrent, !busy, let lease = journal.acquire() else { return }
        let ticket = generation; busy = true
        defer { journal.release(lease); if ticket == generation { busy = false } }
        do { try journal.persist(intent); command = intent }
        catch { state = .persistenceFailed; return } // absolutely no dispatch on storage failure
        state = .saving
        storedFailure = nil; storedDefaultRejection = nil; serverContext = nil
        do {
            let result = try await client.submit(intent)
            guard current(ticket) else { return }
            try result.validate(for: intent)
            if result.status == "APPLIED" {
                try settle(intent, receipt: result)
                if result.resultRedacted != true { await refreshAfterApply(intent, ticket: ticket) }
            } else if result.status == "REJECTED" {
                try settleRejected(intent, receipt: result)
                if result.resultRedacted != true { await readCurrent(ticket: ticket, afterApplied: false) }
            } else { storedReceipt = result; state = result.status == "PENDING" ? .pending : .outcomeUnknown }
        } catch {
            guard current(ticket) else { return }
            handle(error, uncertain: true, preserveRecovery: true)
            // Every failed write is left journaled. The next action reads the
            // original receipt, including business/CAS errors and malformed 200s.
        }
    }
    public func checkReceipt() async { await refresh() }
    /// Explicit user retry first re-reads the original receipt. A PENDING or failed
    /// read does not dispatch. NOT_FOUND stays unknown, but can replay exact bytes.
    public func retryOriginal() async {
        guard !Task.isCancelled, canCheckReceipt, let original = command, let lease = journal.acquire() else { return }
        let ticket = generation; busy = true
        defer { journal.release(lease); if ticket == generation { busy = false } }
        state = .checkingReceipt
        do {
            let observed = try await client.receipt(original, recovery: serverContext?.recovery)
            guard current(ticket) else { return }
            try observed.validate(for: original)
            if observed.status == "APPLIED" {
                try settle(original, receipt: observed)
                if observed.resultRedacted != true { await refreshAfterApply(original, ticket: ticket) }
                return
            }
            if observed.status == "REJECTED" {
                try settleRejected(original, receipt: observed)
                if observed.resultRedacted != true { await readCurrent(ticket: ticket, afterApplied: false) }
                return
            }
            storedReceipt = observed
            let mayReplay: Bool
            switch original.operation {
            case .clubDefault:
                mayReplay = false // UNKNOWN / NOT_FOUND never authorize resending this shared policy write.
            case .ack:
                mayReplay = observed.status != "PENDING" && observed.resumeWithSameRequest == true && client.allows(.ack, scope: original.scope)
            case .mute:
                mayReplay = observed.status == "NOT_FOUND" && client.allows(.mute, scope: original.scope)
            case .preference:
                mayReplay = observed.status == "NOT_FOUND" && client.allows(.save, scope: original.scope)
            }
            guard mayReplay else { state = original.operation == .clubDefault && observed.status != "PENDING" ? .outcomeUnknown : .pending; return }
            state = .saving
            let result = try await client.submit(original)
            guard current(ticket) else { return }
            try result.validate(for: original)
            if result.status == "APPLIED" {
                try settle(original, receipt: result)
                if result.resultRedacted != true { await refreshAfterApply(original, ticket: ticket) }
            } else { storedReceipt = result; state = result.status == "PENDING" ? .pending : .outcomeUnknown }
        } catch { if current(ticket) { handle(error, uncertain: true, preserveRecovery: true) } }
    }
    private func settle(_ intent: NativeChannelNotificationCommand, receipt: NativeChannelNotificationReceipt) throws {
        do { try journal.settle(intent) }
        catch { state = .persistenceFailed; throw NativeChannelNotificationError.persistenceFailed }
        // Never use immutable historical preference fields as the current state.
        storedReceipt = nil; command = nil; storedDirectory = nil; storedClubDefault = nil; storedDefaultRejection = nil; storedFailure = nil; serverContext = nil
        if receipt.resultRedacted == true { storedUnread = nil; state = .appliedRedacted }
        else {
            state = .applied
            if intent.operation == .ack { NativePushAttemptReader.signalOriginalReadCommitted() }
            else { NotificationCenter.default.post(name: Self.originalUnreadPolicyCommitted, object: nil) }
        }
    }
    private func settleRejected(_ intent: NativeChannelNotificationCommand, receipt: NativeChannelNotificationReceipt) throws {
        guard intent.operation == .clubDefault, receipt.status == "REJECTED" else { throw NativeChannelNotificationError.malformedResponse }
        try receipt.validate(for: intent)
        do { try journal.settle(intent) }
        catch { state = .persistenceFailed; throw NativeChannelNotificationError.persistenceFailed }
        // Only the writer's terminal, pre-mutation receipt can clear this command.
        // Neither a transport error nor a missing request is a rejection.
        command = nil; storedReceipt = nil; serverContext = nil; storedFailure = nil
        storedDirectory = nil; storedClubDefault = nil
        storedDefaultRejection = receipt.resultRedacted == true ? "REJECTED" : receipt.result?.rejectionCode
        state = receipt.resultRedacted == true ? .accessClosed : .ready
    }
    private func readCurrent(ticket: UInt64, afterApplied: Bool) async {
        guard current(ticket), canRead else {
            storedDirectory = nil; storedClubDefault = nil; state = .accessClosed
            if current(ticket) && !sharedClubDefaultMode { await refreshUnread(ticket: ticket) }
            return
        }
        storedDirectory = nil; storedClubDefault = nil
        do {
            if sharedClubDefaultMode, let scope {
                let result = try await client.clubDefault(scope: scope)
                guard current(ticket), canRead else { storedClubDefault = nil; return }
                try result.validate(club: scope.value); storedClubDefault = result; storedDirectory = nil
            } else {
                let result = try await client.preferences(scope: scope)
                guard current(ticket), canRead else { storedDirectory = nil; return }
                try result.validate(accountID: String(client.context.session.accountID))
                storedDirectory = result; storedClubDefault = nil
            }
            if command == nil { state = afterApplied ? .applied : .ready }
        } catch {
            guard current(ticket) else { return }
            storedDirectory = nil; storedClubDefault = nil
            if afterApplied { state = .refreshFailed } else { handle(error, uncertain: command != nil) }
        }
        if !sharedClubDefaultMode { await refreshUnread(ticket: ticket) }
    }
    /// ACK success is the original receipt. Settings are a different permission.
    /// Missing preference access must not replace .applied with .accessClosed.
    private func refreshAfterApply(_ intent: NativeChannelNotificationCommand, ticket: UInt64) async {
        if intent.operation == .ack { await refreshUnread(ticket: ticket); return }
        await readCurrent(ticket: ticket, afterApplied: true)
    }
    private func refreshUnread(ticket: UInt64) async {
        // Independent frontend unread truth, even when OS notifications are denied.
        guard current(ticket), client.allows(.unread, scope: nil) else { storedUnread = nil; return }
        do {
            let summary = try await client.unreadSummary()
            guard current(ticket), client.allows(.unread, scope: nil) else { return }
            storedUnread = summary; unreadIssue = false; onUnreadSummary?(summary)
        } catch { if current(ticket) { storedUnread = nil; unreadIssue = true } }
    }
    private func current(_ ticket: UInt64) -> Bool {
        guard ticket == generation else { return false }
        guard isCurrent else {
            // A terminal authority loss belongs only to this still-current lifecycle.
            // Retire local projections via the original path; protected original bytes stay.
            if active && !client.isCurrent { deactivate() }
            return false
        }
        guard !Task.isCancelled else {
            // Cancellation is not a negative receipt and never settles/replaces
            // the original bytes. Only this still-current lifecycle may clear UI.
            storedDirectory = nil; storedClubDefault = nil; storedReceipt = nil; storedUnread = nil
            if command != nil { state = .outcomeUnknown }
            else { state = state == .applied ? .refreshFailed : .idle }
            return false
        }
        return true
    }
    private func handle(_ error: Error, uncertain: Bool, preserveRecovery: Bool = false) {
        if let failure = error as? NativeChannelNotificationError {
            storedFailure = failure
            if preserveRecovery, let details = failure.serverDetails, let command,
               details.recovery != nil || details.returnPath != nil || details.requestID != nil || details.outcomeKnown != nil {
                do { try details.validate(for: command) }
                catch { storedFailure = .malformedResponse; state = .outcomeUnknown; return }
                do { try journal.rememberFailure(details, for: command); serverContext = details }
                catch { state = .persistenceFailed; return }
            }
            if failure == .persistenceFailed { state = .persistenceFailed; return }
            if failure == .accessClosed { clearForDenial(); return }
            if let details = failure.serverDetails,
               details.errorCode == "HANGOUT_CLOSED" || details.errorCode == "IM_CONVERSATION_CLOSED"
                || details.returnPath == "/subpackageB/pages/im/list/index"
                || details.recovery?.returnPath == "/subpackageB/pages/im/list/index" {
                // The preserved original closed-conversation branch can travel
                // inside an OUTCOME_UNKNOWN/500 envelope. Hide current data while
                // retaining the original command and independent receipt recovery.
                clearForDenial(); return
            }
            if let details = failure.serverDetails,
               [401, 403, 404].contains(details.httpStatus) || details.code.map({ [401, 403, 404].contains($0) }) == true { clearForDenial(); return }
            state = uncertain ? .outcomeUnknown : .failed(failure)
        } else { state = uncertain ? .outcomeUnknown : .failed(.malformedResponse) }
    }
    private func clearForDenial() { storedDirectory = nil; storedClubDefault = nil; storedDefaultRejection = nil; storedReceipt = nil; storedUnread = nil; state = .accessClosed }
}

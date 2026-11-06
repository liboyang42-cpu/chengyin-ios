import Foundation
import Observation

@available(macOS 14.0, *)
@MainActor @Observable public final class PrivateHomeCoordinator {
    public enum Phase: String { case disabled, idle, loading, ready, review, sending, unknown, blocked, invalidated }
    public private(set) var phase: Phase = .idle
    public private(set) var home: PrivateHomeSnapshot?
    public private(set) var review: PrivateHomeMutation?
    public private(set) var decision: PrivateHomeReceipt.Decision?
    public private(set) var issue: PrivateHomeIssue?
    private var pending: PrivateHomeMutation?
    private let service: any PrivateHomeServing
    private let journal: (any PrivateHomeSecureJournaling)?
    private let owner: PlayExperienceSession
    private let current: () -> PlayExperienceSession?
    private let enabled: Bool
    private var generation = UUID()
    private var journalLoaded = false
    // Validated current reads and matching terminal receipts establish a version floor.
    // Keep the floor for this owner instance; no private point or new durable record is stored.
    private var minimumHomeVersion: Int64?
    private var settlingTicket: UUID?
    private var pauseAfterSettlement = false
    public init(service: any PrivateHomeServing, journal: (any PrivateHomeSecureJournaling)? = nil,
                owner: PlayExperienceSession, enabled: Bool = false, current: @escaping () -> PlayExperienceSession?) {
        self.service = service; self.journal = journal; self.owner = owner; self.enabled = enabled; self.current = current
        if !enabled { phase = .disabled }
    }
    public var canEdit: Bool { enabled && current() == owner && phase == .ready && home != nil && pending == nil && journalLoaded && journal != nil }
    public var canRetry: Bool { enabled && current() == owner && phase == .unknown && pending != nil }
    public var canConfirm: Bool { enabled && current() == owner && phase == .review && review != nil }
    public var isBusy: Bool { phase == .loading || phase == .sending }
    private func gate() -> Bool {
        guard enabled else { phase = .disabled; return false }
        guard current() == owner else { invalidate(); return false }
        return phase != .invalidated
    }
    /// Logout/account/realm/token revision must call this; confidential durable lock remains scoped in journal.
    public func invalidate() {
        generation = UUID(); home = nil; review = nil; pending = nil; decision = nil; issue = .staleSession
        journalLoaded = false; minimumHomeVersion = nil; settlingTicket = nil; pauseAfterSettlement = false; phase = .invalidated
    }
    public func load() async {
        guard gate(), !isBusy, phase != .review else { return }
        let ticket = generation
        phase = .loading
        do {
            if let journal {
                guard journal.scope == PrivateHomeJournalScope(owner: owner) else { throw PrivateHomeIssue.storageUnavailable }
                let stored = try await journal.read(); try stored?.validate()
                guard ticket == generation, gate() else { return }
                guard journal.scope == PrivateHomeJournalScope(owner: owner) else { throw PrivateHomeIssue.storageUnavailable }
                // A missing/replaced slot is not a receipt for the known original command.
                // Preserve that UNKNOWN identity; never unlock or adopt another request from a GET.
                guard pending == nil || stored == pending else { throw PrivateHomeIssue.storageUnavailable }
                pending = stored; journalLoaded = true
            }
        } catch {
            guard ticket == generation, gate() else { return }
            journalLoaded = false; issue = .storageUnavailable
            phase = pending == nil ? .blocked : .unknown; return
        }
        phase = .loading
        do {
            let value = try await service.load(); try value.validate()
            guard ticket == generation, gate() else { return }
            guard minimumHomeVersion.map({ value.version >= $0 }) ?? true else {
                home = nil; throw PrivateHomeIssue.unavailable
            }
            minimumHomeVersion = max(minimumHomeVersion ?? value.version, value.version)
            home = value; issue = nil; phase = pending == nil ? .ready : .unknown
        } catch {
            guard ticket == generation, gate() else { return }
            issue = pending == nil ? .unavailable : .unknownOutcome
            phase = pending == nil ? .blocked : .unknown
        }
    }
    public func prepareSet(label: String, point: PrivateHomePoint) {
        guard canEdit, let home else { return }
        do { review = try PrivateHomeMutation(expectedVersion: home.version, label: label, point: point); issue = nil; phase = .review }
        catch { issue = .invalid }
    }
    public func prepareDelete() {
        guard canEdit, let home, home.status == .active else { return }
        do { review = try PrivateHomeMutation(expectedVersion: home.version); issue = nil; phase = .review }
        catch { issue = .invalid }
    }
    /// Navigation/background cancels undispatched work, never an already-possible server write.
    /// The original identity remains locked until durable recovery and its matching receipt.
    public func cancelReview() {
        if phase == .review { review = nil; phase = .ready; return }
        guard phase == .sending else { return }
        if settlingTicket == generation {
            // The matching receipt is already validated and its conditional clear may have
            // happened. Let only that operation settle, then require an explicit current read.
            pauseAfterSettlement = true; return
        }
        generation = UUID()
        pending = pending ?? review
        review = nil; decision = nil; journalLoaded = false
        issue = pending == nil ? .storageUnavailable : .unknownOutcome
        phase = pending == nil ? .blocked : .unknown
    }
    private func commandIsCurrent(_ ticket: UUID) -> Bool {
        guard ticket == generation, gate() else { return false }
        guard !Task.isCancelled else { cancelReview(); return false }
        return true
    }
    public func confirm() async {
        guard canConfirm, !Task.isCancelled, let review, let journal else { return }
        let ticket = generation; phase = .sending; decision = nil; pauseAfterSettlement = false
        do {
            // Atomic secure persistence is mandatory, even for DELETE. Ambiguous save blocks all new work.
            try await journal.save(review)
            guard commandIsCurrent(ticket) else { return }
            pending = review; self.review = nil
        } catch {
            guard commandIsCurrent(ticket) else { return }
            // The storage error does not prove an empty slot. Retain this original
            // identity so an explicit refresh cannot adopt a replacement or unlock it.
            // Keep the initial blocked presentation; recovery still rechecks the durable slot.
            pending = review; self.review = nil; journalLoaded = false
            issue = .storageUnavailable; phase = .blocked; return
        }
        await dispatchPending()
    }
    public func retryExact() async { guard canRetry, !Task.isCancelled else { return }; await dispatchPending() }
    private func dispatchPending() async {
        guard gate(), let mutation = pending, let journal else { return }
        guard !Task.isCancelled else { cancelReview(); return }
        let ticket = generation; phase = .sending; decision = nil; pauseAfterSettlement = false
        do {
            // A cached pending value is not authority to replay. Recheck the durable slot on every dispatch.
            guard journal.scope == PrivateHomeJournalScope(owner: owner) else { throw PrivateHomeIssue.storageUnavailable }
            let stored = try await journal.read(); try stored?.validate()
            guard commandIsCurrent(ticket) else { return }
            guard journal.scope == PrivateHomeJournalScope(owner: owner), stored == mutation else { throw PrivateHomeIssue.storageUnavailable }
        } catch {
            guard commandIsCurrent(ticket) else { return }
            issue = .storageUnavailable; phase = .unknown; return
        }
        do {
            guard commandIsCurrent(ticket) else { return }
            let receipt = try await service.mutate(mutation); try receipt.validate(for: mutation)
            guard commandIsCurrent(ticket) else { return }
            // GET cannot prove a request's outcome. Only its matching receipt unlocks the journal.
            try await clearOriginal(mutation, journal: journal, ticket: ticket)
            guard ticket == generation, gate() else { return }
            pending = nil; review = nil; home = nil; decision = receipt.decision; phase = .idle
            minimumHomeVersion = max(minimumHomeVersion ?? 0, receipt.version)
            if pauseAfterSettlement || Task.isCancelled {
                pauseAfterSettlement = false; journalLoaded = false; issue = .unavailable; phase = .blocked
                return // Known terminal result, no automatic GET after leaving the foreground.
            }
            await load() // VERSION_CONFLICT fetches fresh version, requires a NEW explicit review.
        } catch {
            guard commandIsCurrent(ticket) else { return }
            review = nil; issue = .unknownOutcome; phase = .unknown
        }
    }
    private func clearOriginal(_ mutation: PrivateHomeMutation, journal: any PrivateHomeSecureJournaling,
                               ticket: UUID) async throws {
        settlingTicket = ticket
        defer { if settlingTicket == ticket { settlingTicket = nil } }
        try await journal.clear(matching: mutation)
    }
}

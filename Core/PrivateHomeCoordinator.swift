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
        journalLoaded = false; phase = .invalidated
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
                pending = stored; journalLoaded = true
            }
        } catch {
            guard ticket == generation, gate() else { return }
            issue = .storageUnavailable; phase = .blocked; return
        }
        phase = .loading
        do {
            let value = try await service.load(); try value.validate()
            guard ticket == generation, gate() else { return }
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
    public func cancelReview() { guard phase == .review else { return }; review = nil; phase = .ready }
    public func confirm() async {
        guard canConfirm, let review, let journal else { return }
        let ticket = generation; phase = .sending
        do {
            // Atomic secure persistence is mandatory, even for DELETE. Ambiguous save blocks all new work.
            try await journal.save(review)
            guard ticket == generation, gate() else { return }
            pending = review; self.review = nil
        } catch {
            guard ticket == generation, gate() else { return }
            self.review = nil; issue = .storageUnavailable; phase = .blocked; return
        }
        await dispatchPending()
    }
    public func retryExact() async { guard canRetry else { return }; await dispatchPending() }
    private func dispatchPending() async {
        guard gate(), let mutation = pending, let journal else { return }
        let ticket = generation; phase = .sending
        do {
            // A cached pending value is not authority to replay. Recheck the durable slot on every dispatch.
            guard journal.scope == PrivateHomeJournalScope(owner: owner) else { throw PrivateHomeIssue.storageUnavailable }
            let stored = try await journal.read(); try stored?.validate()
            guard ticket == generation, gate() else { return }
            guard journal.scope == PrivateHomeJournalScope(owner: owner), stored == mutation else { throw PrivateHomeIssue.storageUnavailable }
        } catch {
            guard ticket == generation, gate() else { return }
            issue = .storageUnavailable; phase = .unknown; return
        }
        do {
            let receipt = try await service.mutate(mutation); try receipt.validate(for: mutation)
            guard ticket == generation, gate() else { return }
            // GET cannot prove a request's outcome. Only its matching receipt unlocks the journal.
            try await journal.clear(matching: mutation)
            guard ticket == generation, gate() else { return }
            pending = nil; review = nil; home = nil; decision = receipt.decision; phase = .idle
            await load() // VERSION_CONFLICT fetches fresh version, requires a NEW explicit review.
        } catch {
            guard ticket == generation, gate() else { return }
            review = nil; issue = .unknownOutcome; phase = .unknown
        }
    }
}

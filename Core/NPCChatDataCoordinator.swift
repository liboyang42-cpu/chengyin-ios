import Foundation

/// Private chat text stays in memory while this explicitly opened screen is
/// active. No automatic foreground reload, retries, persistence or third-party sharing.
/// Optional log deletion (BK-EXISTING) is OFF unless a host injects both the
/// deleter and its separate approval; it needs an explicit destructive confirmation.
@MainActor public final class NPCChatDataCoordinator {
    public enum Phase: Equatable { case idle, loading, loaded, unavailable }
    /// `deleted`/`unknown` describe the log-deletion request only, never full erasure.
    public enum Deletion: Equatable { case idle, confirming, deleting, deleted(count: Int), unknown, failed(NPCChatDataFailure) }
    public private(set) var phase: Phase = .idle
    public private(set) var failure: NPCChatDataFailure?
    public private(set) var deletion: Deletion = .idle
    public var onChange: (() -> Void)?
    public var currentSession: ComplianceSession? { current() }
    private let current: () -> ComplianceSession?
    private let available: (ComplianceSession) -> Bool
    private let read: (ComplianceSession) async throws -> NPCChatData
    private let deletionAvailable: (ComplianceSession) -> Bool
    private let deleteLogs: ((ComplianceSession) async throws -> NPCChatLogDeletionOutcome)?
    private var confirmation: (session: ComplianceSession, generation: UUID)?
    private var stored: NPCChatData?
    private var loadedSession: ComplianceSession?
    private var generation = UUID()
    private var visible = false
    private var active = false
    public init(current: @escaping () -> ComplianceSession?, available: @escaping (ComplianceSession) -> Bool,
                read: @escaping (ComplianceSession) async throws -> NPCChatData,
                deletionAvailable: @escaping (ComplianceSession) -> Bool = { _ in false },
                deleteLogs: ((ComplianceSession) async throws -> NPCChatLogDeletionOutcome)? = nil) {
        self.current = current; self.available = available; self.read = read
        self.deletionAvailable = deletionAvailable; self.deleteLogs = deleteLogs
    }
    public var data: NPCChatData? {
        guard active, visible, let loadedSession, current() == loadedSession, available(loadedSession) else { return nil }
        return stored
    }
    public var canLoad: Bool {
        guard active, visible, phase != .loading, deletion != .deleting, let session = current(), session.valid else { return false }
        return available(session)
    }
    /// Offered only over records already read for this exact session, so the
    /// person has seen what the server currently returns before deleting it.
    public var canRequestDeletion: Bool {
        guard deleteLogs != nil, phase == .loaded, data != nil, deletion != .deleting,
              let session = current(), session.valid, session == loadedSession else { return false }
        return deletionAvailable(session)
    }
    public func appear(active: Bool) {
        clear(); visible = true; self.active = active; updateAvailability(); onChange?()
    }
    public func suspend() { clear(); active = false; onChange?() }
    /// Foregrounding may expose an explicit reload button, never stored text or a request.
    public func foreground() { guard visible else { return }; active = true; updateAvailability(); onChange?() }
    public func sessionChanged() { clear(); updateAvailability(); onChange?() }
    public func invalidate() { clear(); visible = false; active = false; onChange?() }
    public func load() async {
        guard canLoad, let session = current() else { updateAvailability(); onChange?(); return }
        // A visible deletion result survives its own readback; a pending confirmation does not.
        clearRead(); if deletion == .confirming { deletion = .idle; confirmation = nil }
        let operation = generation
        phase = .loading; onChange?()
        do {
            let value = try await read(session)
            guard generation == operation else { return }
            guard !Task.isCancelled, visible, active, current() == session, available(session) else { sessionChanged(); return }
            guard value.ownerAccountID == session.accountID else { throw NPCChatDataFailure.malformed }
            stored = value; loadedSession = session; phase = .loaded; failure = nil
        } catch {
            guard generation == operation else { return }
            guard !Task.isCancelled, visible, active, current() == session else { sessionChanged(); return }
            stored = nil; loadedSession = nil; phase = .unavailable
            failure = error as? NPCChatDataFailure ?? .failed
        }
        onChange?()
    }
    public func requestDeletion() {
        guard canRequestDeletion, deletion != .confirming, let session = current() else { return }
        confirmation = (session, generation); deletion = .confirming; onChange?()
    }
    public func cancelDeletion() {
        guard deletion == .confirming else { return }
        confirmation = nil; deletion = .idle; onChange?()
    }
    /// Sends at most once per confirmation. Close, background, account/epoch or
    /// approval change before the response retires it; a late response is ignored.
    /// Either outcome clears the shown records and reads back once, because only
    /// the export can show what remains (including logs written by a late reply).
    public func confirmDeletion() async {
        guard deletion == .confirming, let pending = confirmation, let deleteLogs else { return }
        confirmation = nil
        guard pending.generation == generation, current() == pending.session, canRequestDeletion else {
            deletion = .idle; onChange?(); return
        }
        let session = pending.session, operation = generation
        deletion = .deleting; onChange?()
        let outcome: NPCChatLogDeletionOutcome
        do { outcome = try await deleteLogs(session) }
        catch {
            guard generation == operation else { return }
            guard !Task.isCancelled, visible, active, current() == session else { sessionChanged(); return }
            deletion = .failed(error as? NPCChatDataFailure ?? .failed); onChange?(); return
        }
        guard generation == operation else { return }
        guard !Task.isCancelled, visible, active, current() == session else { sessionChanged(); return }
        clearRead()
        switch outcome {
        case .deleted(let count): deletion = .deleted(count: count)
        case .unknown: deletion = .unknown
        }
        onChange?()
        await load()
    }
    private func updateAvailability() {
        guard visible, active else { return }
        guard let session = current(), session.valid else { phase = .unavailable; failure = .signedOut; return }
        if !available(session) { phase = .unavailable; failure = .unavailable }
    }
    private func clear() { clearRead(); deletion = .idle; confirmation = nil }
    private func clearRead() {
        generation = UUID(); stored = nil; loadedSession = nil; phase = .idle; failure = nil
    }
}

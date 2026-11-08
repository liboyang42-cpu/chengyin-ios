import Foundation

/// A restart reader with no action/start API and no answer payload. The host must
/// finish loading this barrier before offering a new start or answer submission.
@MainActor public final class PlayQATextRestartRecovery {
    private let journal: any PlayQATextRestartJournal
    private let reader: any PlayQATextReceiptReading
    private let currentSession: () -> PlayExperienceSession?
    public private(set) var snapshot: PlayQATextRestartSnapshot?
    public private(set) var phase = "unloaded"
    private var acceptedView: PlayWireValue?
    private var acceptedOwner: PlayExperienceSession?
    private var loadedOwner: PlayExperienceSession?
    public init(journal: any PlayQATextRestartJournal, reader: any PlayQATextReceiptReading,
                currentSession: @escaping () -> PlayExperienceSession?) {
        self.journal = journal; self.reader = reader; self.currentSession = currentSession
    }
    public var blocksNewAction: Bool {
        guard loadedOwner != nil, loadedOwner == currentSession() else { return true }
        return phase != "empty" && phase != "resolved"
    }
    public var resolvedView: PlayWireValue? {
        guard phase == "resolved", acceptedOwner == currentSession(), acceptedOwner != nil else { return nil }
        return acceptedView
    }
    private func owner() throws -> PlayExperienceSession {
        guard let session = currentSession(), journal.context.owner.matches(session) else { throw PlayExperienceError.staleSession }
        return session
    }
    private func check(_ session: PlayExperienceSession) throws {
        guard currentSession() == session else { throw PlayExperienceError.staleSession }
        try Task.checkCancellation()
    }
    public func load() async {
        guard ["unloaded", "unavailable"].contains(phase) else { return }
        acceptedView = nil; acceptedOwner = nil; loadedOwner = nil; phase = "loading"
        do {
            let session = try owner(), value = try await journal.read()
            try check(session)
            if let value { try value.value.validate(context: journal.context) }
            snapshot = value; loadedOwner = session; phase = value == nil ? "empty" : "unknown"
        } catch {
            phase = (try? owner()) == nil ? "stale" : "unavailable"
        }
    }
    /// Only the return of this completed durable reservation may precede the
    /// original first POST. Any existing reservation blocks, including the same
    /// key. There is no "prepared means unsent" assumption across a crash.
    @discardableResult public func reserve(_ pending: PlayAdvancedPending, qa: PlayWireValue) async throws -> PlayQATextRestartSnapshot {
        guard ["empty", "resolved"].contains(phase), snapshot == nil else { throw PlayExperienceError.persistenceUnavailable }
        let session = try owner()
        guard loadedOwner == session else { throw PlayExperienceError.staleSession }
        let record = try PlayQATextRestartRecord(pending: pending, qa: qa, context: journal.context)
        acceptedView = nil; acceptedOwner = nil; phase = "loading"
        do {
            let value = try await journal.reserve(record)
            snapshot = value
            try value.value.validate(context: journal.context)
            guard value.value == record else { throw PlayExperienceError.persistenceUnavailable }
            try check(session)
            phase = "unknown"; return value
        } catch {
            phase = (try? owner()) == nil ? "stale" : "unavailable"
            throw error
        }
    }
    public func reconcile() async {
        guard phase == "unknown", let original = snapshot else { return }
        acceptedView = nil; acceptedOwner = nil; phase = "reading"
        let session: PlayExperienceSession
        let receipt: PlayQATextActionReceipt
        do {
            session = try owner()
            try original.value.validate(context: journal.context)
            receipt = try await reader.qaTextReceipt(original.value.request, token: session.token)
            try check(session)
            guard receipt.request == original.value.request else { throw PlayExperienceError.malformed }
        } catch {
            phase = PlayQATextActionReceipt.failurePhase(error, ownerIsCurrent: (try? owner()) != nil)
            return
        }
        do {
            // CAS clear follows matched original receipt proof. Failure does not
            // expose the result or unlock a new action. A later load may finish
            // the existing encrypted clear tombstone, without replaying a POST.
            try await journal.clear(original)
            try check(session)
            snapshot = nil; loadedOwner = session; acceptedOwner = session; acceptedView = receipt.view; phase = "resolved"
        } catch {
            phase = currentSession() == session ? "unavailable" : "stale"
        }
    }
    /// Internal bridge for the coordinator's ORIGINAL awaited action response.
    /// The caller must first run advancedAction's response binding and validate
    /// the same captured owner/generation. Generic state/version reads and the
    /// restart path must never call this method. This acknowledges transport;
    /// it does not interpret the server's answer verdict.
    func acknowledgeOriginalReply(_ request: PlayQATextReceiptRequest, owner session: PlayExperienceSession) async throws {
        guard phase == "unknown", let original = snapshot, original.value.request == request,
              loadedOwner == session, currentSession() == session else { throw PlayExperienceError.staleSession }
        try original.value.validate(context: journal.context)
        phase = "reading"
        do {
            try await journal.clear(original)
            try check(session)
            snapshot = nil; acceptedView = nil; acceptedOwner = nil; phase = "empty"
        } catch {
            phase = currentSession() == session ? "unavailable" : "stale"
            throw error
        }
    }
}

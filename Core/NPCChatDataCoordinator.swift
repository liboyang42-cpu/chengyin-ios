import Foundation

/// Private chat text stays in memory while this explicitly opened screen is
/// active. No automatic foreground reload, retries, persistence or third-party sharing.
@MainActor public final class NPCChatDataCoordinator {
    public enum Phase: Equatable { case idle, loading, loaded, unavailable }
    public private(set) var phase: Phase = .idle
    public private(set) var failure: NPCChatDataFailure?
    public var onChange: (() -> Void)?
    public var currentSession: ComplianceSession? { current() }
    private let current: () -> ComplianceSession?
    private let available: (ComplianceSession) -> Bool
    private let read: (ComplianceSession) async throws -> NPCChatData
    private var stored: NPCChatData?
    private var loadedSession: ComplianceSession?
    private var generation = UUID()
    private var visible = false
    private var active = false
    public init(current: @escaping () -> ComplianceSession?, available: @escaping (ComplianceSession) -> Bool,
                read: @escaping (ComplianceSession) async throws -> NPCChatData) {
        self.current = current; self.available = available; self.read = read
    }
    public var data: NPCChatData? {
        guard active, visible, let loadedSession, current() == loadedSession, available(loadedSession) else { return nil }
        return stored
    }
    public var canLoad: Bool {
        guard active, visible, phase != .loading, let session = current(), session.valid else { return false }
        return available(session)
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
        clear(); let operation = generation
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
    private func updateAvailability() {
        guard visible, active else { return }
        guard let session = current(), session.valid else { phase = .unavailable; failure = .signedOut; return }
        if !available(session) { phase = .unavailable; failure = .unavailable }
    }
    private func clear() {
        generation = UUID(); stored = nil; loadedSession = nil; phase = .idle; failure = nil
    }
}

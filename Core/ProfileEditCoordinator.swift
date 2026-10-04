import Foundation

public struct ProfileEditConfirmation: Identifiable, Equatable {
    public let id: UUID
    public let payload: ProfileEditPayload
    fileprivate let snapshot: ProfileEditSnapshot
    fileprivate let session: ProfileEditSession
}
/// Retain in AppSession, not the navigation destination. Unknown writes remain locked even
/// through navigation and same-account reauthentication. Reconciliation never repeats a POST.
@MainActor
public final class ProfileEditCoordinator {
    private let service: (any ProfileEditServing)?
    private let currentSession: () -> ProfileEditSession?
    private let onUnauthorized: (ProfileEditSession) -> Void
    private let onSaved: () -> Void
    private var session: ProfileEditSession?
    private var generation = 0
    private struct PendingWrite {
        let payload: ProfileEditPayload
        // A matching read does not establish that a timed-out POST has finished.
        // Only a terminal successful acknowledgment permits reconciliation to unlock.
        var acknowledged: Bool = false
    }
    private var pending: [Int: PendingWrite] = [:]
    public private(set) var snapshot: ProfileEditSnapshot?
    public private(set) var confirmation: ProfileEditConfirmation?
    public private(set) var isBusy = false
    public private(set) var messageKey: String?
    public private(set) var remoteMessage: String?
    public var identity: ProfileReadIdentity? { currentSession()?.identity }
    public var viewerRevision: UInt64? { currentSession()?.viewerRevision }
    public var isConfigured: Bool { service != nil }
    public var isLocked: Bool { currentSession().map { pending[$0.identity.accountID] != nil } ?? false }
    public init(service: (any ProfileEditServing)?, currentSession: @escaping () -> ProfileEditSession?,
                onUnauthorized: @escaping (ProfileEditSession) -> Void = { _ in }, onSaved: @escaping () -> Void = {}) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized; self.onSaved = onSaved
    }
    public func synchronizeSession() {
        guard currentSession() != session else { return }
        generation += 1; session = currentSession(); snapshot = nil; confirmation = nil
        isBusy = false; messageKey = nil; remoteMessage = nil
    }
    public func leaveScreen() { confirmation = nil }
    private func active(_ expected: ProfileEditSession, _ request: Int) -> Bool {
        generation == request && currentSession() == expected && !Task.isCancelled
    }
    private func read(_ expected: ProfileEditSession) async throws -> ProfileEditSnapshot {
        guard let service else { throw APIError.notConfigured }
        guard currentSession() == expected else { throw CancellationError() }
        do {
            let result = try await service.read(token: expected.token)
            guard currentSession() == expected, !Task.isCancelled else { throw CancellationError() }
            guard result.id == expected.identity.accountID else { throw APIError.malformedResponse }
            return result
        } catch {
            guard currentSession() == expected, !Task.isCancelled else { throw CancellationError() }
            if let failure = error as? ProfileReadFailure, failure.isUnauthorized { onUnauthorized(expected) }
            throw error
        }
    }
    /// True only when this invocation publishes a fresh, same-session snapshot.
    /// A retained snapshot after an error must never be mistaken for a successful reload.
    @discardableResult public func load() async -> Bool {
        synchronizeSession()
        guard !isBusy, let expected = session else { return false }
        generation += 1; let request = generation
        isBusy = true; confirmation = nil; messageKey = nil; remoteMessage = nil
        defer { if generation == request { isBusy = false } }
        do {
            let value = try await read(expected)
            guard active(expected, request) else { return false }
            snapshot = value
            reconcile(value)
            return true
        } catch {
            guard active(expected, request) else { return false }
            messageKey = isLocked ? "profile.edit.unknown"
                : (snapshot == nil ? "profile.edit.loadFailed" : "profile.edit.refreshFailed")
            return false
        }
    }
    public func prepare(_ draft: ProfileEditDraft) async {
        synchronizeSession()
        guard !isBusy, !isLocked, let expected = session, let original = snapshot else { return }
        guard draft.isValid else { messageKey = "profile.edit.nameRequired"; return }
        guard draft.normalized != original.draft.normalized else { messageKey = "profile.edit.unchanged"; return }
        generation += 1; let request = generation; isBusy = true; confirmation = nil; messageKey = nil; remoteMessage = nil
        defer { if generation == request { isBusy = false } }
        do {
            let latest = try await read(expected)
            guard active(expected, request) else { return }
            guard latest.draft == original.draft,
                  draft.routePreferenceIDs == nil || latest.tagIds == original.tagIds else { snapshot = latest; messageKey = "profile.edit.changed"; return }
            let payload = try ProfileEditPayload(draft: draft, preserving: latest)
            confirmation = .init(id: UUID(), payload: payload, snapshot: latest, session: expected)
        } catch {
            guard active(expected, request) else { return }
            messageKey = "profile.edit.loadFailed"
        }
    }
    public func cancel(_ value: ProfileEditConfirmation) { if confirmation == value { confirmation = nil } }
    public func save(_ value: ProfileEditConfirmation) async {
        synchronizeSession()
        guard !isBusy, !isLocked, confirmation == value, session == value.session, let service else { return }
        let expected = value.session
        generation += 1; let request = generation; isBusy = true; confirmation = nil; messageKey = nil; remoteMessage = nil
        defer { if generation == request { isBusy = false } }
        // Re-read after the user confirms. A conflicting change requires a new review.
        do {
            let latest = try await read(expected)
            guard active(expected, request) else { return }
            guard latest == value.snapshot else { snapshot = latest; messageKey = "profile.edit.changed"; return }
        } catch {
            guard active(expected, request) else { return }
            messageKey = "profile.edit.loadFailed"; return
        }
        pending[expected.identity.accountID] = PendingWrite(payload: value.payload)
        do {
            try await service.save(value.payload, token: expected.token)
            pending[expected.identity.accountID]?.acknowledged = true
        }
        catch let error as ProfileEditWriteError {
            // Keep unknown outcomes locked even if the session changed while awaiting POST.
            switch error {
            case .notSent: pending[expected.identity.accountID] = nil
            case .rejected(let failure):
                pending[expected.identity.accountID] = nil
                if active(expected, request) {
                    remoteMessage = failure.message; messageKey = "profile.edit.rejected"
                    if failure.isUnauthorized { onUnauthorized(expected) }
                }
            case .outcomeUnknown: break
            }
            guard active(expected, request) else { return }
            if pending[expected.identity.accountID] == nil {
                if messageKey == nil { messageKey = "profile.edit.notSent" }; return
            }
        } catch { /* Unknown transport implementations must also fail closed. */ }
        guard active(expected, request) else { return }
        do {
            let latest = try await read(expected)
            guard active(expected, request) else { return }
            snapshot = latest
            reconcile(latest)
        } catch {
            guard active(expected, request) else { return }
            messageKey = "profile.edit.unknown"
        }
    }
    private func reconcile(_ value: ProfileEditSnapshot) {
        guard let unresolved = pending[value.id] else { return }
        let matches = unresolved.payload.matches(value)
        if unresolved.acknowledged && matches {
            pending[value.id] = nil; messageKey = "profile.edit.saved"; onSaved()
        } else if matches {
            // The current fields may match while an unacknowledged request is still
            // running. Keep the lock across subsequent reads, navigation and reauth.
            messageKey = "profile.edit.readbackUnconfirmed"
        } else { messageKey = "profile.edit.unknown" }
    }

}

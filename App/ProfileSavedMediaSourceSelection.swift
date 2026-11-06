import Foundation
import Observation

@MainActor struct ProfileSavedMediaReaders {
    let avatar: ProfileCurrentAvatarReader?
    let work: ProfileCurrentMediaReader?
    let contactQR: ProfileCurrentMediaReader?
    private let readers: [ProfileCurrentMediaReader]
    init(_ values: [ProfileCurrentMediaReader]) {
        readers = values
        avatar = values.first { $0.kind == .avatar }.flatMap { ProfileCurrentAvatarReader(reader: $0) }
        work = values.first { $0.kind == .caseImage }; contactQR = values.first { $0.kind == .contactQR }
    }
    func retire() { readers.forEach { $0.retire() } }
}
/// Selects externally supplied leases separately; no default origins or issuer.
@MainActor @Observable final class ProfileSavedMediaSourceSelection {
    private final class WeakClient {
        weak var value: ProfileCurrentMediaReader?
        init(_ value: ProfileCurrentMediaReader) { self.value = value }
    }
    private var selected: [ProfileCurrentMediaKind: ProfileSavedMediaReadApproval] = [:]
    private var used: Set<UUID> = []
    private var clients: [WeakClient] = []
    private var expirationTasks: [ProfileCurrentMediaKind: Task<Void, Never>] = [:]
    private(set) var revision = UUID()
    deinit { expirationTasks.values.forEach { $0.cancel() } }
    func replace(_ kind: ProfileCurrentMediaKind, with value: ProfileSavedMediaReadApproval?) throws {
        if let value {
            guard value.kind == kind, !used.contains(value.revision), value.matches(value.context) else { throw APIError.invalidConfiguration }
        }
        revoke(kind); selected[kind] = value
        guard let value else { return }; used.insert(value.revision)
        let issuance = value.revision, clock = ContinuousClock()
        // Capture the monotonic deadline before scheduling. Wall-clock rollback or
        // delayed Task admission cannot extend this selection's original lifetime.
        let delay = Self.expirationDelay(expiresAt: value.expiresAt, observedAt: Date())
        let deadline = clock.now.advanced(by: .nanoseconds(delay))
        expirationTasks[kind] = Task { [weak self] in
            do { try await clock.sleep(until: deadline) } catch { return }
            guard !Task.isCancelled, self?.selected[kind]?.revision == issuance else { return }
            self?.revoke(kind)
        }
    }
    /// Integer-safe bound for Duration.nanoseconds; extreme future dates fail
    /// closed earlier rather than overflowing or repeatedly extending a timer.
    static func expirationDelay(expiresAt: Date, observedAt: Date) -> Int64 {
        let duration = expiresAt.timeIntervalSince(observedAt)
        guard duration.isFinite, duration > 0 else { return 0 }
        let seconds = min(duration, TimeInterval(Int64.max / 1_000_000_000))
        return Int64(seconds * 1_000_000_000)
    }
    func revoke(_ kind: ProfileCurrentMediaKind) {
        selected.removeValue(forKey: kind)?.revoke()
        expirationTasks.removeValue(forKey: kind)?.cancel()
        clients.forEach { if $0.value?.kind == kind { $0.value?.retire() } }
        clients.removeAll { $0.value == nil || $0.value?.kind == kind }; revision = UUID()
    }
    func approval(_ kind: ProfileCurrentMediaKind, for context: RuntimeDependencyContext) -> ProfileSavedMediaReadApproval? {
        guard let value = selected[kind], value.matches(context) else { return nil }; return value
    }
    func register(_ reader: ProfileCurrentMediaReader) {
        clients.removeAll { $0.value == nil }; clients.append(.init(reader))
    }
}
@MainActor extension AppCompositionRoot {
    func selectedProfileSavedMediaApproval(_ kind: ProfileCurrentMediaKind, _ context: RuntimeDependencyContext) -> ProfileSavedMediaReadApproval? {
        guard let reviewed, let api = reviewed.regional.apiConfiguration, reviewed.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              reviewed.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8) else { return nil }
        return profileSavedMediaSelection.approval(kind, for: context)
    }
}

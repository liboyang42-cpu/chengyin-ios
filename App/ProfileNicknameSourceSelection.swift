import Foundation
import Observation

/// Select an externally supplied read lease. This owner never issues one or enables an nickname writer.
@MainActor @Observable final class ProfileNicknameSourceSelection {
    private final class WeakClient {
        weak var value: ProfileNicknameAvailabilityReader?
        init(_ value: ProfileNicknameAvailabilityReader) { self.value = value }
    }
    private var selected: ProfileNicknameReadApproval?
    private var used: Set<UUID> = []
    private var clients: [WeakClient] = []
    private var expirationTask: Task<Void, Never>?
    private(set) var revision = UUID()
    init() {}
    deinit { expirationTask?.cancel() }
    func replace(with value: ProfileNicknameReadApproval?) throws {
        if let value {
            guard !used.contains(value.revision), value.matches(value.context) else { throw APIError.invalidConfiguration }
        }
        revoke(); selected = value
        guard let value else { return }; used.insert(value.revision)
        let issuance = value.revision, clock = ContinuousClock()
        // Capture before enqueueing: later wall-clock rollback or delayed task
        // admission must not extend this read selection's original lifetime.
        let delay = Self.expirationDelay(expiresAt: value.expiresAt, observedAt: Date())
        let deadline = clock.now.advanced(by: .nanoseconds(delay))
        expirationTask = Task { [weak self] in
            do { try await clock.sleep(until: deadline) } catch { return }
            guard !Task.isCancelled, self?.selected?.revision == issuance else { return }
            self?.revoke()
        }
    }
    static func expirationDelay(expiresAt: Date, observedAt: Date) -> Int64 {
        let duration = expiresAt.timeIntervalSince(observedAt)
        guard duration.isFinite, duration > 0 else { return 0 }
        let seconds = min(duration, TimeInterval(Int64.max / 1_000_000_000))
        return Int64(seconds * 1_000_000_000)
    }

    func revoke() {
        selected = nil; expirationTask?.cancel(); expirationTask = nil
        clients.forEach { $0.value?.retire() }; clients.removeAll(); revision = UUID()
    }
    func approval(for context: RuntimeDependencyContext) -> ProfileNicknameReadApproval? {
        guard let selected, selected.matches(context) else { return nil }; return selected
    }
    func register(_ client: ProfileNicknameAvailabilityReader) {
        clients.removeAll { $0.value == nil }; clients.append(.init(client))
    }
}
@MainActor extension AppCompositionRoot {
    func selectedProfileNicknameApproval(_ context: RuntimeDependencyContext) -> ProfileNicknameReadApproval? {
        guard let reviewed, let api = reviewed.regional.apiConfiguration, reviewed.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              reviewed.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8) else { return nil }
        return profileNicknameSelection.approval(for: context)
    }
}

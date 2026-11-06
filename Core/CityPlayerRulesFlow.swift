import Foundation
import Observation

/// A read lifecycle, not a participation command or cached eligibility grant.
@available(macOS 14.0, *) @MainActor @Observable public final class CityPlayerRulesFlow {
    public enum Phase: String { case unavailable, loading, ready, changed, notPublished, accessWithdrawn }
    private let client: CityPlayerRulesClient?
    private let unauthorized: () -> Void
    private var selected: () -> Bool = { false }
    private var generation = UUID()
    private var storedPhase: Phase = .unavailable
    private var stored: CityPlayerRulesSnapshot?
    private var pending: Task<Void, Never>?
    public init(client: CityPlayerRulesClient?, unauthorized: @escaping () -> Void = {}) { self.client = client; self.unauthorized = unauthorized }
    public var current: Bool { selected() && client?.current == true }
    public var phase: Phase { current ? storedPhase : .unavailable }
    public var snapshot: CityPlayerRulesSnapshot? { current && storedPhase == .ready ? stored : nil }
    public func bindSelection(_ selected: @escaping () -> Bool) { cancel(); self.selected = selected }
    public func cancel() { generation = UUID(); pending?.cancel(); pending = nil; stored = nil; storedPhase = .unavailable }
    public func load() async {
        guard !Task.isCancelled else { return }
        cancel()
        guard current, let client else { return }
        let issued = generation; storedPhase = .loading
        let task = Task { @MainActor in
            do {
                let value = try await client.load()
                guard self.current, self.generation == issued, !Task.isCancelled else { return }
                self.stored = value; self.storedPhase = .ready
            } catch {
                guard self.current, self.generation == issued, !Task.isCancelled else { return }
                self.stored = nil
                switch error {
                case APIError.unauthorized: self.storedPhase = .accessWithdrawn; self.unauthorized()
                case CityPlayerRulesError.changed: self.storedPhase = .changed
                case CityPlayerRulesError.notPublished: self.storedPhase = .notPublished
                case CityPlayerRulesError.accessWithdrawn: self.storedPhase = .accessWithdrawn
                default: self.storedPhase = .unavailable
                }
            }
        }
        pending = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        if generation == issued { pending = nil }
    }
}

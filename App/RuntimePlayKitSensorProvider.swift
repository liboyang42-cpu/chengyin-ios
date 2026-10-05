import Foundation

/// A fresh sensor owner per screen. Revocation closes both already-running streams
/// and pending authorization; a late OS grant cannot restart another account's work.
@MainActor final class RuntimePlayKitSensorProvider: PlayKitSensorProviding, PlayKitSensorAuthorizing {
    private let provider: any PlayKitSensorProviding
    private let isCurrent: () -> Bool
    private var generation = UUID()
    private var operation: Task<Void, Never>?
    init(provider: any PlayKitSensorProviding, isCurrent: @escaping () -> Bool) { self.provider = provider; self.isCurrent = isCurrent }
    var supported: Set<PlayKitSensorKind> { isCurrent() ? provider.supported : [] }
    func prepare(_ kind: PlayKitSensorKind) async throws {
        guard supported.contains(kind) else { throw PlayKitSensorError.configurationUnavailable }
        let generation = self.generation
        if let authorizing = provider as? any PlayKitSensorAuthorizing { try await authorizing.prepare(kind) }
        guard isCurrent(), generation == self.generation, !Task.isCancelled else { throw PlayKitSensorError.interrupted }
    }
    func samples(_ kind: PlayKitSensorKind) -> AsyncThrowingStream<PlayKitSensorSample, Error> {
        let generation = self.generation
        return AsyncThrowingStream { continuation in
            guard supported.contains(kind), operation == nil else { continuation.finish(throwing: PlayKitSensorError.configurationUnavailable); return }
            operation = Task { [weak self] in
                guard let self else { continuation.finish(throwing: CancellationError()); return }
                do {
                    guard self.isCurrent(), self.generation == generation, !Task.isCancelled else { throw PlayKitSensorError.interrupted }
                    for try await sample in self.provider.samples(kind) {
                        guard self.isCurrent(), self.generation == generation, !Task.isCancelled else { throw PlayKitSensorError.interrupted }
                        continuation.yield(sample)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
                if self.generation == generation { self.cancel() }
            }
            continuation.onTermination = { [weak self] _ in Task { @MainActor in
                guard self?.generation == generation else { return }; self?.cancel()
            } }
        }
    }
    func cancel() { generation = UUID(); operation?.cancel(); operation = nil; provider.cancel() }
}
@MainActor final class RuntimeSensorReference {
    weak var value: RuntimePlayKitSensorProvider?
    init(_ value: RuntimePlayKitSensorProvider) { self.value = value }
}

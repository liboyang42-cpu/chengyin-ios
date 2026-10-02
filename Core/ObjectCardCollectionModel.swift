import Foundation
import Observation

@MainActor @Observable public final class ObjectCardCollectionModel {
    public private(set) var collection: ObjectCardCollection?
    public private(set) var category: ObjectCardCategory = .all
    public private(set) var loading = false
    public private(set) var failed = false
    public private(set) var loadedScope: UUID?
    private var generation: UInt64 = 0
    public init() {}
    public func invalidate() {
        generation &+= 1; collection = nil; category = .all; loading = false; failed = false; loadedScope = nil
    }
    public func cancel() { generation &+= 1; loading = false }
    public func load(category next: ObjectCardCategory, reader: any ObjectCardReading) async {
        let scope = reader.scope
        if loadedScope != scope { invalidate() }
        guard !loading else { return }
        generation &+= 1; let captured = generation
        loading = true; failed = false
        defer { if generation == captured { loading = false } }
        do {
            let result = try await reader.list(category: next)
            guard !Task.isCancelled, captured == generation, scope == reader.scope else { return }
            collection = result; category = next; loadedScope = scope
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), captured == generation, scope == reader.scope else { return }
            failed = true; loadedScope = scope
            // A failed filter retains the last successful filter and collection.
        }
    }
}

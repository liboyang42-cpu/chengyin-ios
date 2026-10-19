import Foundation
import Observation

@MainActor @Observable public final class ObjectCardCollectionModel {
    public private(set) var collection: ObjectCardCollection?
    public private(set) var category: ObjectCardCategory = .all
    public private(set) var loading = false
    public private(set) var failed = false
    public private(set) var loadedScope: UUID?
    /// Mini-program `readAccess`: a 403 is 当前账号无法查看, not a retryable load failure.
    public private(set) var access: CollectionReadAccess?
    private var generation: UInt64 = 0
    public init() {}
    public func invalidate() {
        generation &+= 1; collection = nil; category = .all; loading = false; failed = false; loadedScope = nil; access = nil
    }
    public func cancel() { generation &+= 1; loading = false }
    public func load(category next: ObjectCardCategory, reader: any ObjectCardReading) async {
        let scope = reader.scope
        if loadedScope != scope { invalidate() }
        guard !loading else { return }
        generation &+= 1; let captured = generation
        loading = true; failed = false; access = nil
        defer { if generation == captured { loading = false } }
        do {
            let result = try await reader.list(category: next)
            guard !Task.isCancelled, captured == generation, scope == reader.scope else { return }
            collection = result; category = next; loadedScope = scope
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), captured == generation, scope == reader.scope else { return }
            failed = true; loadedScope = scope; access = CollectionReadAccess(error)
            // A failed filter retains the last successful filter and collection.
        }
    }
}

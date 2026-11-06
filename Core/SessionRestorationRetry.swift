import Foundation

/// Opaque, non-secret identity for one explicitly requested saved-session read.
public struct SessionRestorationRetryAttempt: Equatable {
    public let epoch: UInt64
    public let namespace: String
    private let identity = UUID()
    fileprivate init(epoch: UInt64, namespace: String) {
        self.epoch = epoch; self.namespace = namespace
    }
}

/// Availability is offered only by a failed/cancelled restoration. This type never
/// stores a token, dispatches a request, retries automatically or grants access.
public struct SessionRestorationRetry {
    public private(set) var isAvailable = false
    public private(set) var pending: SessionRestorationRetryAttempt?
    private var executing = false
    public init() {}
    public mutating func offer() {
        guard pending == nil else { return }
        isAvailable = true
    }
    public mutating func begin(epoch: UInt64, namespace: String) -> SessionRestorationRetryAttempt? {
        guard isAvailable, pending == nil, !namespace.isEmpty else { return nil }
        let attempt = SessionRestorationRetryAttempt(epoch: epoch, namespace: namespace)
        isAvailable = false; pending = attempt; executing = false
        return attempt
    }
    public func owns(_ attempt: SessionRestorationRetryAttempt) -> Bool { pending == attempt }
    public mutating func start(_ attempt: SessionRestorationRetryAttempt) -> Bool {
        guard owns(attempt), !executing else { return false }
        executing = true; return true
    }
    public mutating func finish(_ attempt: SessionRestorationRetryAttempt, retryable: Bool) {
        guard owns(attempt) else { return }
        pending = nil; isAvailable = retryable; executing = false
    }
    public mutating func cancel() {
        guard pending != nil else { return }
        pending = nil; isAvailable = true; executing = false
    }
    public mutating func discard() { pending = nil; isAvailable = false; executing = false }
}

import Foundation

/// Presentation invalidation only: this object cannot issue or renew read authority.
@MainActor public final class OfficialReadInvalidationSubscription {
    fileprivate var callback: (() -> Void)?
    fileprivate init(_ callback: @escaping () -> Void) { self.callback = callback }
    public func cancel() { callback = nil }
}

@MainActor public final class OfficialReadInvalidationSignal {
    private final class WeakSubscription {
        weak var value: OfficialReadInvalidationSubscription?
        init(_ value: OfficialReadInvalidationSubscription) { self.value = value }
    }
    private var subscriptions: [UUID: WeakSubscription] = [:]
    private var generation = UUID()
    public init() {}
    /// The consumer owns the token. Dropping/cancelling it stops callbacks without
    /// requiring actor-isolated work from deinit or retaining a disappeared view.
    public func observe(_ callback: @escaping () -> Void) -> OfficialReadInvalidationSubscription {
        subscriptions = subscriptions.filter { $0.value.value?.callback != nil }
        let token = OfficialReadInvalidationSubscription(callback)
        subscriptions[UUID()] = WeakSubscription(token)
        return token
    }
    func invalidate() {
        generation = UUID(); let delivery = generation
        for id in Array(subscriptions.keys) {
            guard generation == delivery else { return }
            guard let callback = subscriptions[id]?.value?.callback else { subscriptions[id] = nil; continue }
            callback()
        }
    }
}

/// A retired read snapshot is neither an empty success nor a login failure.
public enum OfficialReadInvalidationFailure: Error { case sourceChanged }

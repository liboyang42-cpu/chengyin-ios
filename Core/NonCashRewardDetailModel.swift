import Foundation

@MainActor public final class NonCashRewardDetailModel {
    public let selection: NonCashRewardDetailSelection
    public private(set) var isLoading = false
    public private(set) var loadedScope: UUID?
    private var projection: NonCashRewardDetailProjection?
    private var issue: AccountCollectionIssue?
    private var latestReference: NonCashRewardReference
    private var generation: UInt64 = 0
    private var activeRead: NonCashRewardReadLifetime?
    public init(selection: NonCashRewardDetailSelection) {
        self.selection = selection; latestReference = selection.reference
    }
    public func visibleValue(scope: UUID) -> NonCashRewardDetailProjection? {
        scope == selection.ownerScope && loadedScope == scope ? projection : nil
    }
    public func visibleIssue(scope: UUID) -> AccountCollectionIssue? { loadedScope == scope ? issue : nil }
    public func invalidate() {
        activeRead?.invalidate(); activeRead = nil
        generation &+= 1; projection = nil; issue = nil; loadedScope = nil; isLoading = false
    }
    public func cancelPending() { invalidate() }
    public func refresh(reader: any NonCashRewardReading, offeredLifetime: NonCashRewardReadLifetime? = nil) async {
        // Check before invalidate: an obsolete queued offer must not cancel a newer read.
        guard !Task.isCancelled, offeredLifetime?.isActive != false else { return }
        invalidate()
        let captured = generation, scope = reader.scope
        guard reader.isAuthenticated else { loadedScope = scope; issue = .login; return }
        guard reader.isConfigured else { loadedScope = scope; issue = .notConfigured; return }
        guard scope == selection.ownerScope else { loadedScope = scope; issue = .unavailable; return }
        let lifetime = offeredLifetime ?? NonCashRewardReadLifetime()
        activeRead = lifetime; isLoading = true
        defer {
            lifetime.invalidate()
            if captured == generation { isLoading = false; activeRead = nil }
        }
        do {
            let reference = latestReference
            let reward = try await reader.reward(reference, lifetime: lifetime)
            guard !Task.isCancelled, captured == generation, reader.scope == scope,
                  reader.isAuthenticated, reader.isConfigured else { return }
            let next = try NonCashRewardDetailProjection(reward: reward, previous: reference)
            projection = next; latestReference = NonCashRewardReference(reward); loadedScope = scope
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), captured == generation,
                  reader.scope == scope, reader.isAuthenticated, reader.isConfigured else { return }
            issue = AccountCollectionIssue(error); loadedScope = scope
        }
    }
}

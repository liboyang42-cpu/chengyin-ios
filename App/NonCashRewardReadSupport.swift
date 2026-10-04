import SwiftUI

@MainActor final class NonCashRewardCollectionScreenModel: ObservableObject {
    @Published private var revision: UInt64 = 0
    let state = NonCashRewardCollectionModel()
    func refresh(reader: any NonCashRewardReading) async {
        revision &+= 1; await state.refresh(reader: reader); revision &+= 1
    }
    func loadMore(reader: any NonCashRewardReading) async {
        revision &+= 1; await state.loadMore(reader: reader); revision &+= 1
    }
    func invalidate() { state.invalidate(); revision &+= 1 }
    func cancelPending() { state.cancelPending(); revision &+= 1 }
}
extension AccountCollectionLoadKey {
    @MainActor init(rewardReader: any NonCashRewardReading, awardId: String = "") {
        scope = rewardReader.scope; configured = rewardReader.isConfigured
        authenticated = rewardReader.isAuthenticated; query = awardId; id = nil
    }
}
/// Account identity only; no fallback to the unrelated coupon service.
@MainActor final class UnconfiguredNonCashRewardReader: NonCashRewardReading {
    private let identity: any AccountCollectionReading
    init(identity: any AccountCollectionReading) { self.identity = identity }
    var scope: UUID { identity.scope }
    var isAuthenticated: Bool { identity.isAuthenticated }
    var isConfigured: Bool { false }
    var isOfflineExample: Bool { false }
    func rewards(cursor: String?) async throws -> NonCashRewardPage { throw APIError.notConfigured }
    func reward(_ reference: NonCashRewardReference) async throws -> NonCashReward { throw APIError.notConfigured }
}

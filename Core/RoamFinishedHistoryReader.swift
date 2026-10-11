import Foundation

/// Published only after both the existing history archive and journal clear succeed.
public struct RoamFinishedHistoryReference: Equatable, Hashable {
    public let timestamp: Int64
    public let serverSessionID: Int
}

/// A local-history-only projection of the controller's existing store. It has no
/// HTTP service, location provider, mutation executor or fallback fixture records.
@MainActor public final class RoamFinishedHistoryReader: RoamExperienceReading {
    private let store: RoamHistoryStore?
    private let currentIdentity: () -> RoamExperienceIdentity?
    private let completion: () -> RoamFinishedHistoryReference?
    public let isOfflineExample: Bool
    public var isConfigured: Bool { store != nil }
    public var identity: RoamExperienceIdentity? { currentIdentity() }
    init(store: RoamHistoryStore?, offlineExample: Bool,
         currentIdentity: @escaping () -> RoamExperienceIdentity?,
         completion: @escaping () -> RoamFinishedHistoryReference?) {
        self.store = store; isOfflineExample = offlineExample
        self.currentIdentity = currentIdentity; self.completion = completion
    }
    public func history() throws -> [RoamHistoryRecord] {
        guard let snapshot = currentIdentity(), let reference = completion() else { throw APIError.unauthorized }
        guard let store else { throw APIError.notConfigured }
        guard store.scope?.storageKey == snapshot.scope.storageKey else { throw RoamExperienceFailure.scopeMismatch }
        let records = try store.readAll()
        guard let current = currentIdentity(), current.scope.storageKey == snapshot.scope.storageKey,
              current.epoch == snapshot.epoch, completion() == reference else { throw CancellationError() }
        // A replaced timestamp must never be mistaken for the just-finished session.
        // Missing history remains missing; it is not rebuilt from settlement statistics.
        if let row = records.first(where: { $0.ts == reference.timestamp }), row.serverSessionID != reference.serverSessionID {
            throw RoamExperienceFailure.historyUnreadable
        }
        return records
    }
    public func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
    public func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { throw APIError.notConfigured }
    public func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
    public func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
}

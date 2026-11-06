import Foundation
import Observation

/// Optional host access; constructing it or querying a row never fetches or copies a URL.
@MainActor struct OwnMediaApprovedLinkAccess {
    let sourceRevision: (OwnMediaAsset) -> UUID?
    let makeReader: (OwnMediaAsset) -> OwnMediaApprovedLinkReader?
}
@MainActor @Observable final class OwnMediaApprovedLinkSourceSelection {
    private final class WeakClient {
        weak var value: OwnMediaApprovedLinkReader?
        init(_ value: OwnMediaApprovedLinkReader) { self.value = value }
    }
    private var selected: [Int64: OwnMediaApprovedLinkApproval] = [:]
    private var used: Set<UUID> = []
    private var clients: [WeakClient] = []
    private var timers: [Int64: Task<Void, Never>] = [:]
    init() {}
    deinit { timers.values.forEach { $0.cancel() } }
    func replace(assetID: Int64, with value: OwnMediaApprovedLinkApproval?) throws {
        guard assetID > 0 else { throw APIError.invalidConfiguration }
        if let value {
            guard value.assetID == assetID, !used.contains(value.revision), value.matches(value.context) else { throw APIError.invalidConfiguration }
        }
        revoke(assetID: assetID); selected[assetID] = value
        guard let value else { return }; used.insert(value.revision)
        let issuance = value.revision, deadline = value.clientDeadline, clock = ContinuousClock()
        timers[assetID] = Task { [weak self] in
            do { try await clock.sleep(until: deadline) } catch { return }
            guard !Task.isCancelled, self?.selected[assetID]?.revision == issuance else { return }
            self?.revoke(assetID: assetID)
        }
    }
    func revoke(assetID: Int64) {
        selected.removeValue(forKey: assetID)?.revoke(); timers.removeValue(forKey: assetID)?.cancel()
        clients.forEach { if $0.value?.assetID == assetID { $0.value?.retire() } }
        clients.removeAll { $0.value == nil || $0.value?.assetID == assetID }
    }
    func approval(assetID: Int64, context: RuntimeDependencyContext) -> OwnMediaApprovedLinkApproval? {
        guard let value = selected[assetID], value.matches(context) else { return nil }; return value
    }
    func register(_ reader: OwnMediaApprovedLinkReader) {
        clients.removeAll { $0.value == nil }; clients.append(.init(reader))
    }
}
@MainActor extension AppCompositionRoot {
    func selectedOwnMediaApprovedLinkApproval(assetID: Int64, context: RuntimeDependencyContext) -> OwnMediaApprovedLinkApproval? {
        guard let reviewed, let api = reviewed.regional.apiConfiguration, reviewed.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              reviewed.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8) else { return nil }
        return ownMediaApprovedLinkSelection.approval(assetID: assetID, context: context)
    }
}

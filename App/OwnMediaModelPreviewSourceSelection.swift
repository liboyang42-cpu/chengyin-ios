import Foundation
import Observation

/// Optional host access; constructing it or querying a row never signs or downloads a URL.
@MainActor struct OwnMediaModelPreviewAccess {
    let sourceRevision: (OwnMediaAsset) -> UUID?
    let makeReader: (OwnMediaAsset) -> OwnMediaModelPreviewReader?
}
@MainActor @Observable final class OwnMediaModelPreviewSourceSelection {
    private final class WeakClient {
        weak var value: OwnMediaModelPreviewReader?
        init(_ value: OwnMediaModelPreviewReader) { self.value = value }
    }
    private var selected: [Int64: OwnMediaModelPreviewApproval] = [:]
    private var used: Set<UUID> = []
    private var clients: [WeakClient] = []
    private var timers: [Int64: Task<Void, Never>] = [:]
    init() {}
    deinit { timers.values.forEach { $0.cancel() } }
    func replace(assetID: Int64, with value: OwnMediaModelPreviewApproval?) throws {
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
    func approval(assetID: Int64, context: RuntimeDependencyContext) -> OwnMediaModelPreviewApproval? {
        guard let value = selected[assetID], value.matches(context) else { return nil }; return value
    }
    func register(_ reader: OwnMediaModelPreviewReader) {
        clients.removeAll { $0.value == nil }; clients.append(.init(reader))
    }
}
@MainActor extension AppCompositionRoot {
    func selectedOwnMediaModelPreviewApproval(assetID: Int64, context: RuntimeDependencyContext) -> OwnMediaModelPreviewApproval? {
        guard let reviewed, let api = reviewed.regional.apiConfiguration, reviewed.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              reviewed.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8) else { return nil }
        return ownMediaModelPreviewSelection.approval(assetID: assetID, context: context)
    }
}

/// Only this private MODEL3D group's clients. No public player/map grant is adopted.
@MainActor final class OwnMediaModelPreviewLifetime {
    private final class WeakClient {
        weak var value: OwnMediaModelPreviewReader?
        init(_ value: OwnMediaModelPreviewReader) { self.value = value }
    }
    private var clients: [WeakClient] = []
    func register(_ reader: OwnMediaModelPreviewReader) { clients.removeAll { $0.value == nil }; clients.append(.init(reader)) }
    func retireAll() {
        let retiring = clients; clients.removeAll(); retiring.forEach { $0.value?.retire() }
    }
}

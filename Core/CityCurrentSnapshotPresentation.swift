import Foundation
import Observation

/// Explicit current-read presentation. No grant issuance, location acquisition, conversion or action writer.
@MainActor @Observable public final class CityCurrentSnapshotPresentation {
    public enum Phase: Equatable { case hidden, loading, ready, unavailable, expired }
    public let captured: RuntimeDependencyContext
    public let revision: UInt64
    public let scope: CityCurrentSnapshotScope
    public private(set) var phase: Phase = .hidden
    public private(set) var isRetired = false
    public private(set) var selectedPointID: String?
    private var value: CityCurrentSnapshot?
    private var displayedGrant: CityCurrentSnapshotReadGrant?
    private var reader: CityCurrentSnapshotReader?
    private var active = false
    private var generation: UInt64 = 0
    private let currentContext: () -> RuntimeDependencyContext?
    private let currentRevision: () -> UInt64
    private let grant: () -> CityCurrentSnapshotReadGrant?
    private let now: () -> Int64

    public init(context: RuntimeDependencyContext, revision: UInt64, query: CityCurrentSnapshotQuery,
                transport: any HTTPTransport, currentContext: @escaping () -> RuntimeDependencyContext?,
                currentRevision: @escaping () -> UInt64, grant: @escaping () -> CityCurrentSnapshotReadGrant? = { nil },
                now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) throws {
        let api = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.role == context.session.role, !context.role.isEmpty,
              api.baseURL == context.baseURL, let current = currentContext(),
              ContentDraftContextFence.matches(context, current), context.session == current.session,
              current.role == current.session.role, currentRevision() == revision else { throw CityCurrentSnapshotFailure.staleSession }
        captured = context; self.revision = revision
        scope = try .init(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace,
            accountID: context.session.accountID, epoch: context.session.epoch, token: context.session.token, query: query)
        self.currentContext = currentContext; self.currentRevision = currentRevision; self.grant = grant; self.now = now
        reader = CityCurrentSnapshotReader(configuration: api, transport: transport,
            currentScope: { [weak self] in guard let self, self.active, self.isCurrent else { return nil }; return self.scope },
            grant: { [weak self] in guard let self, self.active, self.isCurrent else { return nil }; return self.grant() }, now: now)
    }
    public var isCurrent: Bool {
        guard !isRetired, let current = currentContext() else { return false }
        return currentRevision() == revision && current.role == current.session.role
            && ContentDraftContextFence.matches(captured, current) && captured.session == current.session
    }
    public var snapshot: CityCurrentSnapshot? {
        guard active, isCurrent, phase == .ready, let issued = displayedGrant, grant() === issued,
              !issued.isRevoked, let value else { return nil }
        if let expiry = value.validUntilMillis, now() >= expiry { return nil }
        return value
    }
    public var selectedPoint: CityCurrentSnapshot.Point? {
        guard let id = selectedPointID else { return nil }; return snapshot?.points.first { $0.pointId == id }
    }
    public func selectPoint(_ id: String?) {
        guard let id else { selectedPointID = nil; return }
        selectedPointID = snapshot?.points.contains(where: { $0.pointId == id }) == true ? id : nil
    }
    public func open() async {
        guard !isRetired else { return }; active = true; await refresh()
    }
    public func refresh() async {
        synchronize()
        guard active, isCurrent, let reader else { return }
        generation &+= 1; let visit = generation
        value = nil; displayedGrant = nil; selectedPointID = nil; phase = .loading
        guard let issued = grant(), !issued.isRevoked, issued.scope == scope else { phase = .unavailable; return }
        do {
            let result = try await reader.read(scope)
            guard active, generation == visit else { return }
            guard isCurrent else { retire(); return }
            guard grant() === issued, !issued.isRevoked else { phase = .unavailable; return }
            value = result; displayedGrant = issued; phase = .ready; synchronize()
        } catch {
            guard active, generation == visit else { return }
            value = nil; displayedGrant = nil; selectedPointID = nil
            phase = (error as? CityCurrentSnapshotFailure) == .expired ? .expired : .unavailable
            synchronize()
        }
    }
    public func synchronize() {
        guard isCurrent else { retire(); return }
        guard active, let issued = displayedGrant else { return }
        if grant() !== issued || issued.isRevoked { close(); phase = .unavailable; return }
        if let expiry = value?.validUntilMillis, now() >= expiry {
            generation &+= 1; value = nil; displayedGrant = nil; selectedPointID = nil; phase = .expired
        }
    }
    public func close() {
        generation &+= 1; active = false; value = nil; displayedGrant = nil; selectedPointID = nil; phase = .hidden
    }
    public func retire() { isRetired = true; close(); phase = .unavailable }
}

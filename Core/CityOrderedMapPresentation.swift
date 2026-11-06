import Foundation
import Observation

/// Explicit current-read presentation. No grant issuance, location acquisition, conversion or action writer.
@MainActor @Observable public final class CityOrderedMapPresentation {
    public enum Phase: Equatable { case hidden, loading, ready, unavailable, expired }
    public let captured: RuntimeDependencyContext
    public let revision: UInt64
    public let scope: CityCurrentSnapshotScope
    public private(set) var phase: Phase = .hidden
    public private(set) var isRetired = false
    public private(set) var selectedPointID: String?
    private var value: CityOrderedMapRead?
    private var displayedGrant: CityOrderedMapReadGrant?
    private var reader: CityOrderedMapReader?
    private var active = false
    private var generation: UInt64 = 0
    private let currentContext: () -> RuntimeDependencyContext?
    private let currentRevision: () -> UInt64
    private let grant: () -> CityOrderedMapReadGrant?

    public init(selection: CityOrderedMapRuntimeSelection, transport: any HTTPTransport,
                currentContext: @escaping () -> RuntimeDependencyContext?, currentRevision: @escaping () -> UInt64,
                currentSelection: @escaping () -> CityOrderedMapRuntimeSelection?) throws {
        let context = selection.context; let revision = selection.revision
        guard selection.matches(currentContext(), revision: currentRevision()), currentSelection() === selection else { throw CityOrderedMapFailure.staleSession }
        captured = context; self.revision = revision; scope = selection.scope
        self.currentContext = { guard currentSelection() === selection, selection.matches(currentContext(), revision: currentRevision()) else { return nil }; return currentContext() }
        self.currentRevision = currentRevision; self.grant = { selection.issued() }
        reader = CityOrderedMapReader(selection: selection, transport: transport,
            current: { [weak self] in guard let self else { return false }; return self.active && self.isCurrent })
    }
    public var isCurrent: Bool {
        guard !isRetired, let current = currentContext() else { return false }
        return currentRevision() == revision && current.role == current.session.role
            && ContentDraftContextFence.matches(captured, current) && captured.session == current.session
    }
    public var snapshot: CityCurrentSnapshot? {
        guard active, isCurrent, phase == .ready, let issued = displayedGrant, grant() === issued,
              !issued.isRevoked, let value else { return nil }
        guard value.isFresh() else { return nil }
        return value.snapshot
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
            let result = try await reader.load()
            guard active, generation == visit else { return }
            guard isCurrent else { retire(); return }
            guard grant() === issued, !issued.isRevoked else { phase = .unavailable; return }
            value = result; displayedGrant = issued; phase = .ready; synchronize()
        } catch {
            guard active, generation == visit else { return }
            value = nil; displayedGrant = nil; selectedPointID = nil
            phase = (error as? CityOrderedMapFailure) == .expired ? .expired : .unavailable
            synchronize()
        }
    }
    public func synchronize() {
        guard isCurrent else { retire(); return }
        guard active, let issued = displayedGrant else { return }
        if grant() !== issued || issued.isRevoked { close(); phase = .unavailable; return }
        if let value, !value.isFresh() {
            generation &+= 1; self.value = nil; displayedGrant = nil; selectedPointID = nil; reader?.retire(); phase = .expired
        }
    }
    public func close() {
        generation &+= 1; active = false; reader?.retire(); value = nil; displayedGrant = nil; selectedPointID = nil; phase = .hidden
    }
    public func retire() { isRetired = true; close(); phase = .unavailable }
}

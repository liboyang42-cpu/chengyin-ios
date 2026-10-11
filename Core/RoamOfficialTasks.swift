import Foundation

public struct RoamOfficialTasksOwner: Equatable, Hashable {
    public let roamReaderID: ObjectIdentifier
    public let roamScopeKey: String?
    public let roamEpoch: UInt64?
    public let officialReaderID: ObjectIdentifier
    public let officialScope: UUID
    public let configured: Bool
    public let authenticated: Bool
    @MainActor public init(roam: any RoamExperienceReading, official: any OfficialEventReading) {
        let identity = roam.identity
        roamReaderID = ObjectIdentifier(roam); roamScopeKey = identity?.scope.storageKey; roamEpoch = identity?.epoch
        officialReaderID = ObjectIdentifier(official); officialScope = official.scope
        configured = official.isConfigured; authenticated = official.isAuthenticated
    }
    public var isAuthorized: Bool { roamScopeKey != nil && configured && authenticated }
}
public struct RoamOfficialTasksSnapshot {
    public let id: UUID
    public let all: [OfficialEvent]
    public let mine: [OfficialEvent]
    public func visible(_ query: OfficialEventBrowseQuery) -> [OfficialEvent] { query.visible(query.isPrivate ? mine : all) }
}
public struct RoamOfficialTaskTarget: Hashable {
    public let id: UUID
    public let eventID: Int
    public let owner: RoamOfficialTasksOwner
    public let snapshotID: UUID
}

/// P005 delegated official task scene: two existing GET contracts form one owned snapshot.
/// No participation, publishing, arrival, GPS, cache-write or generic Activity route capability.
@MainActor public final class RoamOfficialTasksModel {
    private let roam: any RoamExperienceReading
    private let official: any OfficialEventReading
    private var loadedOwner: RoamOfficialTasksOwner?
    private var stored: RoamOfficialTasksSnapshot?
    private var storedError: Error?
    private var generation: UInt64 = 0
    private var visible = false
    public private(set) var isLoading = false
    public var onChange: (() -> Void)?
    public init(roam: any RoamExperienceReading, official: any OfficialEventReading) { self.roam = roam; self.official = official }
    public var owner: RoamOfficialTasksOwner { .init(roam: roam, official: official) }
    public var snapshot: RoamOfficialTasksSnapshot? { loadedOwner == owner ? stored : nil }
    public var error: Error? { loadedOwner == owner ? storedError : nil }
    public func appear() { visible = true }
    public func cancelPending() { visible = false; generation &+= 1; isLoading = false; onChange?() }
    public func invalidate() { cancelPending(); loadedOwner = nil; stored = nil; storedError = nil; onChange?() }
    public func load() async {
        generation &+= 1; let ticket = generation, captured = owner
        if loadedOwner != captured { stored = nil }
        loadedOwner = captured; storedError = nil; isLoading = false
        guard captured.isAuthorized else {
            stored = nil; storedError = captured.roamScopeKey == nil || !captured.authenticated ? APIError.unauthorized : APIError.notConfigured
            onChange?(); return
        }
        isLoading = true; onChange?()
        defer { if ticket == generation { isLoading = false; onChange?() } }
        do {
            let all = try await official.events(city: nil)
            guard current(ticket, captured) else { return }
            let mine = try await official.myEvents()
            guard current(ticket, captured) else { return }
            try validate(all); try validate(mine)
            stored = .init(id: UUID(), all: all, mine: mine); storedError = nil
        } catch {
            guard current(ticket, captured), !(error is CancellationError) else { return }
            // Failed refresh retains only the same owner's previous complete two-list snapshot.
            if error as? APIError == .unauthorized || error as? OfficialReadFailure == .forbidden { stored = nil }
            storedError = error
        }
    }
    public func select(eventID: Int, query: OfficialEventBrowseQuery, renderedSnapshotID: UUID) -> RoamOfficialTaskTarget? {
        guard visible, !isLoading, owner.isAuthorized, let snapshot, snapshot.id == renderedSnapshotID,
              eventID > 0, snapshot.visible(query).filter({ $0.id == eventID }).count == 1 else { return nil }
        return .init(id: UUID(), eventID: eventID, owner: owner, snapshotID: snapshot.id)
    }
    public func mayRemainOpen(_ target: RoamOfficialTaskTarget) -> Bool {
        target.owner.isAuthorized && target.owner == owner && target.snapshotID == snapshot?.id
    }
    private func current(_ ticket: UInt64, _ captured: RoamOfficialTasksOwner) -> Bool {
        !Task.isCancelled && ticket == generation && owner == captured && loadedOwner == captured
    }
    private func validate(_ rows: [OfficialEvent]) throws {
        guard rows.allSatisfy({ $0.id > 0 }), Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
    }
}

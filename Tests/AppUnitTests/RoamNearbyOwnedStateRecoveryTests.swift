import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Separate original /my and nearby/application reads, all in memory. Production grants, writers,
/// fixtures and journals are unchanged. Hosted tests use original NearbyTeamsView and TeamDetailView.
@MainActor final class RoamNearbyOwnedStateRecoveryTests: XCTestCase {
    func testPrivateReadFailureDoesNotBlockIndependentOriginalNearbyRead() async throws {
        let rig = try NearbyOwnedStateRig(); rig.ownedService.failure = TeamFailure.unavailable
        await rig.loadOwned(); await rig.nearby.loadNearby(NearbyTeamSyntheticFixtures.context)
        XCTAssertEqual(rig.owned.currentStatus(owner: rig.owner), .failed("team.loadFailed"))
        XCTAssertTrue(rig.owned.currentRows(owner: rig.owner).isEmpty)
        XCTAssertEqual(rig.nearby.teams.map(\.id.rawValue), [505]); XCTAssertEqual(rig.wire.paths, ["/api/team/nearby"])
        XCTAssertFalse(rig.nearby.canSubmit); XCTAssertEqual(rig.ownedService.writes, 0)
    }
    func testOwnedRetryUsesOnlyOriginalPrivateReaderAndRetainsIndependentNearbySnapshot() async throws {
        let rig = try NearbyOwnedStateRig(); rig.ownedService.failure = TeamFailure.unavailable
        await rig.nearby.loadNearby(NearbyTeamSyntheticFixtures.context); let rows = rig.nearby.teams
        await rig.loadOwned(); rig.ownedService.failure = nil; await rig.loadOwned()
        XCTAssertEqual(rig.ownedService.myReads, 2); XCTAssertEqual(rig.owned.currentRows(owner: rig.owner).map(\.id), [4101])
        XCTAssertEqual(rig.nearby.teams, rows); XCTAssertEqual(rig.wire.paths, ["/api/team/nearby"])
        XCTAssertEqual(rig.ownedService.writes, 0); XCTAssertTrue(rig.journal.records.isEmpty)
    }
    func testCurrentOwnerChangeHidesOriginalPrivateRowsAndCannotAdoptPendingRead() async throws {
        let rig = try NearbyOwnedStateRig(); await rig.loadOwned()
        let previousOwner = rig.owner; XCTAssertEqual(rig.owned.currentRows(owner: previousOwner).map(\.id), [4101])
        rig.ownedService.hold = true
        let old = Task { await rig.loadOwned() }; try await waitFor { rig.ownedService.pending != nil }
        defer { rig.ownedService.release() }
        rig.owner = "different-account-epoch-grant"; rig.teamSession = try TeamSyntheticFixtures.session(epoch: 2, accountID: 902)
        XCTAssertTrue(rig.owned.currentRows(owner: rig.owner).isEmpty)
        rig.ownedService.release(); await old.value
        XCTAssertEqual(rig.owned.currentStatus(owner: rig.owner), .loading)
        XCTAssertTrue(rig.owned.currentRows(owner: rig.owner).isEmpty); XCTAssertTrue(rig.journal.records.isEmpty)
    }
    func testActualNearbyMapStillLoadsWhilePrivateSourceFails() async throws {
        let rig = try NearbyOwnedStateRig(); rig.initialTab = 0; rig.ownedService.failure = TeamFailure.unavailable
        let scene = try HostedNavigationSceneWindow(), window = scene.window; mount(rig, window: window)
        defer { scene.retire(); rig.releaseAll() }
        try await waitFor { self.find("nearby.team.505", in: window) != nil && rig.owned.currentStatus(owner: rig.owner) == .failed("team.loadFailed") }
        XCTAssertEqual(rig.wire.paths, ["/api/team/nearby"]); XCTAssertFalse(rig.nearby.canSubmit)
        XCTAssertNil(find("nearby.mine.empty", in: window)); XCTAssertEqual(rig.ownedService.writes, 0)
        try await tap("nearby.w208.myTeams", in: window)
        try await waitFor { self.find("nearby.mine.owned.error", in: window) != nil }
        XCTAssertNil(find("nearby.mine.empty", in: window)); XCTAssertNil(find("nearby.mine.stat.approved", in: window))
    }
    func testActualPrivateFailureLeavesCurrentApplicationsVisibleWithoutCompleteCounts() async throws {
        let rig = try NearbyOwnedStateRig(); rig.ownedService.failure = TeamFailure.unavailable; rig.wire.emptyApplications = false
        let scene = try HostedNavigationSceneWindow(), window = scene.window; mount(rig, window: window)
        defer { scene.retire(); rig.releaseAll() }
        try await waitFor { self.find("nearby.mine.owned.error", in: window) != nil && self.find("nearby.application.502", in: window) != nil }
        XCTAssertNil(find("nearby.mine.empty", in: window)); XCTAssertNil(find("nearby.mine.stat.pending", in: window))
        XCTAssertEqual(rig.wire.paths, ["/api/team/my-applications"]); XCTAssertFalse(rig.nearby.canSubmit)
    }
    func testActualOwnedRetryRestoresJoinedRowsWithoutRefetchingIndependentApplications() async throws {
        let rig = try NearbyOwnedStateRig(); rig.ownedService.failure = TeamFailure.unavailable
        let scene = try HostedNavigationSceneWindow(), window = scene.window; mount(rig, window: window)
        defer { scene.retire(); rig.releaseAll() }
        try await waitFor { self.find("nearby.mine.owned.retry", in: window) != nil && rig.wire.paths.count == 1 }
        XCTAssertNil(find("nearby.mine.empty", in: window)); XCTAssertEqual(rig.wire.paths, ["/api/team/my-applications"])
        rig.ownedService.failure = nil; try await tap("nearby.mine.owned.retry", in: window)
        try await waitFor { self.find("nearby.joined.4101", in: window) != nil }
        XCTAssertEqual(rig.ownedService.myReads, 2); XCTAssertEqual(rig.wire.paths, ["/api/team/my-applications"])
        XCTAssertNil(find("nearby.mine.owned.error", in: window)); XCTAssertEqual(rig.ownedService.writes, 0)
    }
    func testActualConfirmedEmptyOwnedResponseFinishingLastStartsOriginalRecruitingOnce() async throws {
        let rig = try NearbyOwnedStateRig(); rig.ownedService.empty = true; rig.ownedService.hold = true
        let scene = try HostedNavigationSceneWindow(), window = scene.window; mount(rig, window: window)
        defer { scene.retire(); rig.releaseAll() }
        try await waitFor { rig.ownedService.pending != nil && rig.wire.paths == ["/api/team/my-applications"] }
        XCTAssertNil(find("nearby.mine.empty", in: window)); XCTAssertNotNil(find("nearby.mine.owned.loading", in: window))
        rig.ownedService.release()
        try await waitFor { self.find("nearby.mine.empty", in: window) != nil && rig.wire.paths.count == 2 }
        await drain(); XCTAssertEqual(rig.wire.paths, ["/api/team/my-applications", "/api/team/nearby"])
        XCTAssertEqual(rig.wire.radii, [NearbyTeamPresentation.recruitingRadius]); XCTAssertEqual(rig.ownedService.writes, 0)
    }
    func testActualApplicationsFinishingLastUsesCurrentOwnedEmptyStateForRecruiting() async throws {
        let rig = try NearbyOwnedStateRig(); rig.ownedService.empty = true; rig.wire.holdApplications = true
        let scene = try HostedNavigationSceneWindow(), window = scene.window; mount(rig, window: window)
        defer { scene.retire(); rig.releaseAll() }
        try await waitFor { rig.wire.pending != nil && rig.owned.currentStatus(owner: rig.owner) == .loaded }
        XCTAssertNil(find("nearby.mine.empty", in: window)); rig.wire.release()
        try await waitFor { self.find("nearby.mine.empty", in: window) != nil && rig.wire.paths.count == 2 }
        await drain(); XCTAssertEqual(rig.wire.paths, ["/api/team/my-applications", "/api/team/nearby"])
        XCTAssertTrue(rig.journal.records.isEmpty)
    }
    func testActualOriginalJoinedDetailPushSurvivesOwnedRetirementAndBackReadsAgain() async throws {
        let rig = try NearbyOwnedStateRig(), scene = try HostedNavigationSceneWindow(), window = scene.window
        mount(rig, window: window); defer { scene.retire(); rig.releaseAll() }
        try await waitFor { self.find("nearby.joined.4101", in: window) != nil }
        let nav = try XCTUnwrap(navigation(window.rootViewController)), count = nav.viewControllers.count
        try await tap(label: appLocalized("nearby.enter", locale: Locale(identifier: "en_US")), in: window)
        try await waitFor { nav.viewControllers.count == count + 1 && self.find("team.detail.card", in: window) != nil }
        XCTAssertEqual(rig.ownedService.detailIDs, [4101]); XCTAssertEqual(rig.owned.currentStatus(owner: rig.owner), .loading)
        XCTAssertEqual(rig.ownedService.writes, 0); XCTAssertTrue(rig.journal.records.isEmpty)
        XCTAssertNotNil(nav.popViewController(animated: false))
        try await waitFor { rig.ownedService.myReads == 2 && self.find("nearby.joined.4101", in: window) != nil }
        XCTAssertEqual(rig.ownedService.detailIDs, [4101]); XCTAssertEqual(rig.ownedService.writes, 0)
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail("Original independent nearby/owned reads did not settle"); throw TeamFailure.notConfigured
    }
    private func drain() async { for _ in 0..<12 { await Task.yield() } }
    private func mount(_ rig: NearbyOwnedStateRig, window: UIWindow) {
        let host = UIHostingController(rootView: NavigationStack { NearbyOwnedStateHost(rig: rig, owned: rig.owned) }
            .environment(\.scenePhase, .active).environment(\.locale, Locale(identifier: "en_US")))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
    }
    private func tap(_ id: String, in window: UIWindow) async throws { try await activate(id: id, label: nil, window: window) }
    private func tap(label: String, in window: UIWindow) async throws { try await activate(id: nil, label: label, window: window) }
    private func activate(id: String?, label: String?, window: UIWindow) async throws {
        for _ in 0..<35 { if find(id: id, label: label, in: window) != nil { break }; scroll(window); try await Task.sleep(nanoseconds: 40_000_000) }
        let target = try XCTUnwrap(find(id: id, label: label, in: window))
        if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(target.accessibilityActivate()) }
    }
    private func scroll(_ view: UIView) {
        if let scroll = view as? UIScrollView {
            let end = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            if scroll.contentOffset.y < end { scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(end, scroll.contentOffset.y + 300)), animated: false); scroll.layoutIfNeeded() }
        }
        for child in view.subviews { scroll(child) }
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? { find(id: id, label: nil, in: window) }
    private func find(id: String?, label: String?, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ root: NSObject) -> NSObject? {
            guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
            if let id, (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
            if let label, root.accessibilityLabel == label { return root }
            if let view = root as? UIView { for child in view.subviews { if let result = visit(child) { return result } } }
            if let children = root.accessibilityElements { for child in children { if let child = child as? NSObject, let result = visit(child) { return result } } }
            let count = root.accessibilityElementCount()
            if count > 0 && count < 1000 { for index in 0..<count { if let child = root.accessibilityElement(at: index) as? NSObject, let result = visit(child) { return result } } }
            return nil
        }
        return visit(window)
    }
    private func navigation(_ controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }; if let result = controller as? UINavigationController { return result }
        for child in controller.children { if let result = navigation(child) { return result } }; return nil
    }
}

/// Memory-only dependency host: production AppSession construction and its separate grants are source-checked,
/// not replaced by this test host or claimed to have been exercised by these native tests.
@MainActor private struct NearbyOwnedStateHost: View {
    @ObservedObject var rig: NearbyOwnedStateRig
    @ObservedObject var owned: NearbyOwnedTeamsReadModel
    @State private var destination: NearbyTeamDestination?
    var body: some View {
        NearbyTeamsView(coordinator: rig.nearby, context: NearbyTeamSyntheticFixtures.context,
            joinedTeams: owned.currentRows(owner: rig.owner), initialTab: rig.initialTab,
            joinedTeamsStatus: owned.currentStatus(owner: rig.owner),
            retryJoinedTeams: { Task { await rig.loadOwned() } }) { destination = $0 }
            .task { await rig.loadOwned() }
            .onDisappear { owned.cancel() }
            .navigationDestination(isPresented: Binding(get: { destination != nil }, set: { if !$0 { destination = nil } })) {
                if case .team(let id)? = destination {
                    TeamDetailView(lookup: .id(id.rawValue), coordinator: rig.makeTeam(), makeCoordinator: { rig.makeTeam() }, readOnly: true)
                } else { Text("Unselected test destination") }
            }
    }
}
@MainActor private final class NearbyOwnedStateRig: ObservableObject {
    @Published var owner = "same-account-original-grant"
    let owned = NearbyOwnedTeamsReadModel()
    let ownedService = NearbyOwnedStateService()
    let wire = NearbyOwnedStateWire()
    let journal = TeamMemoryJournal()
    var teamSession: TeamSession?
    var initialTab = 1
    lazy var nearby = NearbyTeamCoordinator(service: .init(readTransport: wire, liveReadGrant: true), session: teamSession.map { NearbyTeamSession(teamSession: $0) },
        locks: NearbyTeamLockStore(defaults: nil))
    init() throws { teamSession = try TeamSyntheticFixtures.session(); ownedService.rows = [try TeamSyntheticFixtures.detail().team] }
    func makeTeam() -> TeamCoordinator { .init(service: ownedService, journal: journal, currentSession: { [weak self] in self?.teamSession }) }
    func loadOwned() async {
        let captured = owner
        await owned.load(owner: captured, makeCoordinator: { makeTeam() }, currentOwner: { owner })
    }
    func releaseAll() { ownedService.release(); wire.release() }
}
@MainActor private final class NearbyOwnedStateService: TeamServing {
    let authority: TeamServiceAuthority = .readOnly
    var failure: Error?
    var empty = false
    var rows: [OwnedTeam] = []
    var myReads = 0
    var detailIDs: [Int] = []
    var writes = 0
    var hold = false
    var pending: CheckedContinuation<Void, Never>?
    func myTeams(session: TeamSession) async throws -> [OwnedTeam] {
        myReads += 1
        if hold { await withCheckedContinuation { pending = $0 } }
        if let failure { throw failure }; return empty ? [] : rows
    }
    func release() { let saved = pending; pending = nil; hold = false; saved?.resume() }
    func detail(_ lookup: TeamLookup, session: TeamSession) async throws -> TeamDetail {
        guard case .id(let id) = lookup, id == 4101 else { throw TeamFailure.invalidRequest }
        detailIDs.append(id); return try TeamSyntheticFixtures.detail()
    }
    func creationContext(ownerID: Int, session: TeamSession) async throws -> TeamCreationContext { throw TeamFailure.notConfigured }
    func submit(_ action: TeamAction, operationID: UUID, session: TeamSession) async -> TeamWriteOutcome { writes += 1; XCTFail("No write in read-only recovery"); return .notSent }
    func receipt(operationID: UUID, session: TeamSession) async throws -> TeamWriteOutcome? { XCTFail("No write recovery requested"); return nil }
}
@MainActor private final class NearbyOwnedStateWire: NearbyTeamReadTransport {
    var paths: [String] = []
    var radii: [Int] = []
    var emptyApplications = true
    var holdApplications = false
    var pending: CheckedContinuation<Void, Never>?
    func sendRead(_ request: NearbyTeamRequest, session: NearbyTeamSession) async throws -> NearbyTeamResponse {
        XCTAssertFalse(request.mutation); paths.append(request.path)
        switch request.path {
        case "/api/team/nearby":
            if let radius = request.query["radius"].flatMap(Int.init) { radii.append(radius) }
            return .init(data: Data(#"{"code":200,"data":[{"teamId":505,"title":"Original nearby joined team","viewerStatus":"JOINED","joinedCount":3,"maxMembers":4}]}"#.utf8))
        case "/api/team/my-applications":
            if holdApplications { await withCheckedContinuation { pending = $0 } }
            return .init(data: Data((emptyApplications ? #"{"code":200,"data":[]}"# : NearbyTeamSyntheticFixtures.applications).utf8))
        default: XCTFail("Unexpected read route"); throw NearbyTeamFailure.unconfigured
        }
    }
    func release() { let saved = pending; pending = nil; holdApplications = false; saved?.resume() }
}

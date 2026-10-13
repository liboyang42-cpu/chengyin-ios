import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileSettingsProfileTests: XCTestCase {
    @MainActor private final class Personal {
        var session: ProfileEditSession?
        var role = "player"
        let service: ProfileEditSyntheticService
        lazy var coordinator = ProfileEditCoordinator(service: service, currentSession: { [weak self] in self?.session })
        init(_ scenario: ProfileEditSyntheticService.Scenario = .success) throws {
            service = .init(scenario: scenario)
            session = try .init(accountID: 901, epoch: 1, token: "synthetic-settings-profile", viewerRevision: 1)
        }
        func access() -> ProfileSettingsProfileAccess? {
            guard let session else { return nil }
            return .init(accountID: session.identity.accountID, role: role,
                viewerRevision: session.viewerRevision, coordinator: coordinator)
        }
    }
    private func activeOwner() -> ProfileSettingsProfileOwner {
        let value = ProfileSettingsProfileOwner(); value.appear(); return value
    }
    func testPlayerAndClubUseSameFullPersonalEditorWithoutCreatingAnySaveAuthority() throws {
        let fixture = try Personal(), owner = activeOwner()
        for role in ["player", "club"] {
            fixture.role = role
            let route = try XCTUnwrap(owner.route(fixture.access()))
            XCTAssertEqual(route.access.target, .personal)
            XCTAssertTrue(route.access.coordinator === fixture.coordinator)
            XCTAssertNil(route.access.merchantReader); XCTAssertNil(fixture.coordinator.snapshot)
            XCTAssertTrue(owner.accepts(route, current: fixture.access()))
        }
    }
    func testMerchantUsesOriginalDecorReaderAndNeverPersonalEditor() throws {
        let reader = MerchantOperationsFixtureReader(), owner = activeOwner()
        let access = try XCTUnwrap(ProfileSettingsProfileAccess(accountID: 901, role: "merchant", viewerRevision: 1, merchantReader: reader))
        let route = try XCTUnwrap(owner.route(access))
        XCTAssertEqual(route.access.target, .brand); XCTAssertEqual(route.access.titleKey, "merchant.operations.decor")
        XCTAssertTrue(route.access.merchantReader === reader); XCTAssertNil(route.access.coordinator)
        XCTAssertEqual(reader.accessCount, 0); XCTAssertEqual(reader.saveCount, 0)
    }
    func testGuestUnknownRoleAndMismatchedPersonalOwnerHaveNoEntry() throws {
        let fixture = try Personal(), owner = activeOwner()
        for role in ["", "unknown", "merchant"] {
            XCTAssertNil(ProfileSettingsProfileAccess(accountID: 901, role: role, viewerRevision: 1, coordinator: fixture.coordinator))
        }
        XCTAssertNil(ProfileSettingsProfileAccess(accountID: 902, role: "player", viewerRevision: 1, coordinator: fixture.coordinator))
        XCTAssertNil(ProfileSettingsProfileAccess(accountID: 901, role: "player", viewerRevision: 2, coordinator: fixture.coordinator))
        fixture.session = nil; XCTAssertNil(owner.route(fixture.access()))
        let reader = MerchantOperationsFixtureReader(); reader.signOut()
        XCTAssertNil(ProfileSettingsProfileAccess(accountID: 901, role: "merchant", viewerRevision: 1, merchantReader: reader))
    }
    func testUnconfiguredCurrentEditorRetainsHonestUnavailableDestination() throws {
        let session = try ProfileEditSession(accountID: 901, epoch: 1, token: "synthetic-settings-profile", viewerRevision: 1)
        let coordinator = ProfileEditCoordinator(service: nil, currentSession: { session })
        let owner = activeOwner(), access = try XCTUnwrap(ProfileSettingsProfileAccess(accountID: 901, role: "player", viewerRevision: 1, coordinator: coordinator))
        XCTAssertFalse(access.key.configured); XCTAssertNotNil(owner.route(access))
        XCTAssertFalse(coordinator.isConfigured); XCTAssertFalse(coordinator.avatarSavingAvailable)
    }
    func testRetiredSettingsOwnerRejectsOldRoutesAndCannotRestartFromLateAppearance() throws {
        let fixture = try Personal(), owner = activeOwner(), route = try XCTUnwrap(owner.route(fixture.access()))
        owner.retire(); owner.appear()
        XCTAssertNil(owner.lifetime); XCTAssertNil(owner.route(fixture.access()))
        XCTAssertFalse(owner.accepts(route, current: fixture.access()))
        let reopened = activeOwner(), fresh = try XCTUnwrap(reopened.route(fixture.access()))
        XCTAssertFalse(reopened.accepts(route, current: fixture.access()))
        owner.retire(); XCTAssertTrue(reopened.accepts(fresh, current: fixture.access()))
    }
    func testRepeatedVisibleAppearanceDoesNotInvalidateLegitimatePushAndBack() throws {
        let fixture = try Personal(), owner = activeOwner(), route = try XCTUnwrap(owner.route(fixture.access()))
        let lifetime = owner.lifetime; owner.appear(); owner.appear()
        XCTAssertEqual(owner.lifetime, lifetime); XCTAssertTrue(owner.accepts(route, current: fixture.access()))
        let reopened = try XCTUnwrap(owner.route(fixture.access()))
        XCTAssertNotEqual(route, reopened); XCTAssertTrue(owner.accepts(reopened, current: fixture.access()))
    }
    func testChangedAccountEpochRevisionRoleAndReplacementCoordinatorRejectOldRoute() throws {
        for change in ["account", "epoch", "revision", "role", "logout", "coordinator"] {
            let fixture = try Personal(), owner = activeOwner(), route = try XCTUnwrap(owner.route(fixture.access()))
            var current: ProfileSettingsProfileAccess?
            switch change {
            case "account": fixture.session = try .init(accountID: 902, epoch: 2, token: "synthetic-b", viewerRevision: 2)
            case "epoch": fixture.session = try .init(accountID: 901, epoch: 2, token: "synthetic-b", viewerRevision: 1)
            case "revision": fixture.session = try .init(accountID: 901, epoch: 1, token: "synthetic-settings-profile", viewerRevision: 2)
            case "role": fixture.role = "club"
            case "logout": fixture.session = nil
            default:
                let replacement = try Personal(); current = replacement.access()
                XCTAssertFalse(owner.accepts(route, current: current)); continue
            }
            current = fixture.access(); XCTAssertFalse(owner.accepts(route, current: current), change)
        }
    }
    func testSameAccountReturnWithNewRevisionCannotReviveOldPersonalRoute() throws {
        let fixture = try Personal(), owner = activeOwner(), route = try XCTUnwrap(owner.route(fixture.access()))
        fixture.session = try .init(accountID: 902, epoch: 2, token: "synthetic-b", viewerRevision: 2)
        fixture.session = try .init(accountID: 901, epoch: 3, token: "synthetic-a-returned", viewerRevision: 3)
        XCTAssertFalse(owner.accepts(route, current: fixture.access()))
        XCTAssertNotNil(owner.route(fixture.access()))
    }
    func testMerchantScopeReaderConfigurationAndRoleChangesRejectOldRoute() throws {
        let reader = MerchantOperationsFixtureReader(), owner = activeOwner()
        @MainActor func access(_ r: MerchantOperationsFixtureReader? = nil, _ role: String = "merchant", _ revision: UInt64 = 1) -> ProfileSettingsProfileAccess? {
            .init(accountID: 901, role: role, viewerRevision: revision, merchantReader: r ?? reader)
        }
        let route = try XCTUnwrap(owner.route(access()))
        XCTAssertFalse(owner.accepts(route, current: access(MerchantOperationsFixtureReader())))
        XCTAssertFalse(owner.accepts(route, current: access(reader, "player")))
        XCTAssertFalse(owner.accepts(route, current: access(reader, "merchant", 2)))
        reader.isConfigured = false; XCTAssertFalse(owner.accepts(route, current: access()))
        reader.isConfigured = true; reader.signOut(); XCTAssertFalse(owner.accepts(route, current: access()))
        XCTAssertEqual(reader.accessCount, 0); XCTAssertEqual(reader.saveCount, 0)
    }
    func testPersonalCancelAndDiscardReuseOriginalEditorAndDoNotSave() async throws {
        let fixture = try Personal(), owner = activeOwner(), route = try XCTUnwrap(owner.route(fixture.access()))
        let model = ProfileEditModel(coordinator: try XCTUnwrap(route.access.coordinator)); await model.resetAndLoad()
        let original = try XCTUnwrap(fixture.coordinator.snapshot)
        model.draft.introduction = "Unsent settings draft"
        XCTAssertFalse(model.requestExit()); XCTAssertTrue(model.confirmExit(try XCTUnwrap(model.exitConfirmation)))
        let read = try await fixture.service.read(token: "synthetic-settings-profile")
        XCTAssertEqual(read, original); XCTAssertTrue(owner.accepts(route, current: fixture.access()))
    }
    func testPersonalSavedReturnStillRequiresAuthoritativeReadbackAndSingleConsumption() async throws {
        let fixture = try Personal(), owner = activeOwner(), route = try XCTUnwrap(owner.route(fixture.access()))
        let model = ProfileEditModel(coordinator: try XCTUnwrap(route.access.coordinator)); await model.resetAndLoad()
        model.draft.introduction = "Saved from settings"
        await model.prepare(); let review = try XCTUnwrap(model.confirmation)
        let result = await model.save(review), receipt = try XCTUnwrap(result)
        XCTAssertEqual(fixture.coordinator.snapshot?.introduction, "Saved from settings")
        XCTAssertTrue(model.consumeSavedReturn(receipt)); XCTAssertFalse(model.consumeSavedReturn(receipt))
        XCTAssertTrue(owner.accepts(route, current: fixture.access()))
    }
    func testUnknownAndRejectedPersonalWritesDoNotInventSuccessfulReturn() async throws {
        for scenario in [ProfileEditSyntheticService.Scenario.unknown, .rejected] {
            let fixture = try Personal(scenario), owner = activeOwner(), route = try XCTUnwrap(owner.route(fixture.access()))
            let model = ProfileEditModel(coordinator: try XCTUnwrap(route.access.coordinator)); await model.resetAndLoad()
            model.draft.introduction = "Reviewed settings change"; await model.prepare()
            let review = try XCTUnwrap(model.confirmation), result = await model.save(review)
            XCTAssertNil(result); XCTAssertEqual(fixture.coordinator.isLocked, scenario == .unknown)
            XCTAssertTrue(owner.accepts(route, current: fixture.access()))
        }
    }
    func testMerchantDestinationRetainsFreshAccessDenialAndExplicitRetry() async throws {
        let reader = MerchantOperationsFixtureReader(), owner = activeOwner()
        let access = try XCTUnwrap(ProfileSettingsProfileAccess(accountID: 901, role: "merchant", viewerRevision: 1, merchantReader: reader))
        let route = try XCTUnwrap(owner.route(access)), retained = try XCTUnwrap(route.access.merchantReader)
        reader.denied = true
        let model = MerchantOperationsViewModel(reader: retained, destination: .decor)
        await model.load(); XCTAssertNil(model.coordinator.document); XCTAssertNotNil(model.coordinator.issue)
        reader.denied = false; await model.load()
        guard case .draft(.decor) = model.coordinator.document else { return XCTFail("Existing decor editor must load") }
        XCTAssertNil(model.coordinator.issue); XCTAssertGreaterThan(reader.accessCount, 1); XCTAssertEqual(reader.saveCount, 0)
    }
    @MainActor private final class Navigation: ObservableObject {
        @Published var path: [ProfileSettingsProfileRoute] = []
    }
    @MainActor private struct Host: View {
        let fixture: Personal
        @ObservedObject var owner: ProfileSettingsProfileOwner
        @ObservedObject var navigation: Navigation
        var body: some View {
            NavigationStack(path: $navigation.path) {
                Form { Text("Synthetic settings root") }
                    .navigationDestination(for: ProfileSettingsProfileRoute.self) { route in
                        ProfileSettingsProfileDestination(route: route, owner: owner, current: fixture.access)
                    }
            }.onAppear { owner.appear() }.onDisappear { owner.retire() }
        }
    }
    func testRealNavigationStackPushLoadsFullEditorAndBackKeepsRootOwnerUntilDeparture() async throws {
        let fixture = try Personal(), owner = ProfileSettingsProfileOwner(), navigation = Navigation()
        let host = UIHostingController(rootView: Host(fixture: fixture, owner: owner, navigation: navigation))
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        for _ in 0..<100 where owner.lifetime == nil { try await Task.sleep(for: .milliseconds(20)) }
        let route = try XCTUnwrap(owner.route(fixture.access())), lifetime = owner.lifetime
        navigation.path = [route]
        for _ in 0..<100 where fixture.coordinator.snapshot == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(fixture.coordinator.snapshot); XCTAssertEqual(owner.lifetime, lifetime)
        XCTAssertTrue(owner.accepts(route, current: fixture.access()))
        navigation.path = []; try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(owner.lifetime, lifetime); XCTAssertNotNil(owner.route(fixture.access()))
        window.isHidden = true; window.rootViewController = nil
        for _ in 0..<100 where owner.lifetime != nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(owner.lifetime); XCTAssertFalse(owner.accepts(route, current: fixture.access()))
    }
}

import XCTest
@testable import QuestifyCore

@MainActor final class NativeNotificationPermissionTests: XCTestCase {
    func testReadOnlyAppearanceNeverRequestsAuthorizationOrOpensSettings() async {
        let provider = PermissionFixture(); let model = NativeNotificationPermissionState(provider: provider)
        await model.refresh(); await model.refresh()
        XCTAssertEqual(provider.requests, 0); XCTAssertEqual(provider.opened, 0)
        XCTAssertEqual(model.snapshot?.authorization, .notDetermined)
    }
    func testDeniedRequiresExplicitSettingsActionAndCannotRequestAgain() async {
        let provider = PermissionFixture(); provider.authorization = .denied
        let model = NativeNotificationPermissionState(provider: provider); await model.refresh()
        await model.requestFromUserAction(); XCTAssertEqual(provider.requests, 0)
        await model.openSettingsFromUserAction(); XCTAssertEqual(provider.opened, 1)
    }
    func testProvisionalAndEphemeralRemainDistinctFromAuthorized() async {
        let provider = PermissionFixture(); let model = NativeNotificationPermissionState(provider: provider)
        for value in [NativeNotificationPermissionAuthorization.provisional, .ephemeral, .authorized, .unknown(99)] {
            provider.authorization = value; await model.refresh(); XCTAssertEqual(model.snapshot?.authorization, value)
        }
    }
    func testOnlyExplicitNotDeterminedActionRequestsAndReadsActualResult() async {
        let provider = PermissionFixture(); let model = NativeNotificationPermissionState(provider: provider)
        await model.refresh(); await model.requestFromUserAction()
        XCTAssertEqual(provider.requests, 1); XCTAssertEqual(model.snapshot?.authorization, .provisional)
    }
    func testReadFailureIsUnknownAndDoesNotBecomeEnabled() async {
        let provider = PermissionFixture(); provider.fail = true
        let model = NativeNotificationPermissionState(provider: provider); await model.refresh()
        XCTAssertNil(model.snapshot); XCTAssertNotNil(model.issue); XCTAssertEqual(provider.requests, 0)
    }
}
@MainActor private final class PermissionFixture: NativeNotificationPermissionProviding {
    var authorization: NativeNotificationPermissionAuthorization = .notDetermined
    var requests = 0; var opened = 0; var fail = false
    func read() async throws -> NativeNotificationPermissionSnapshot {
        if fail { throw NativeChannelNotificationError.accessClosed }
        return .init(authorization: authorization, alerts: .disabled, sounds: .disabled, badges: .enabled)
    }
    func requestFromUserAction() async throws { requests += 1; authorization = .provisional }
    func openSettingsFromUserAction() async throws { opened += 1 }
}

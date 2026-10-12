import XCTest
@testable import QuestifyCore

final class RoamLocationSettingsStateTests: XCTestCase {
    private let denied = RoamLocationSettingsSnapshot(authorization: .denied, servicesEnabled: true)
    func testAllSystemStatesRemainDistinct() {
        XCTAssertEqual(Set(RoamSystemLocationAuthorization.allCases.map(\.rawValue)).count, 6)
        for authorization in RoamSystemLocationAuthorization.allCases {
            var state = RoamLocationSettingsState()
            let snapshot = RoamLocationSettingsSnapshot(authorization: authorization, servicesEnabled: true)
            let attempt = state.beginRead()
            XCTAssertTrue(state.finishRead(attempt, snapshot: snapshot))
            XCTAssertEqual(state.phase, .loaded(snapshot))
        }
    }
    func testNotDeterminedDeniedRestrictedUnknownNeverImplyAnyGrant() {
        for status: RoamSystemLocationAuthorization in [.notDetermined, .denied, .restricted, .unknown] {
            let snapshot = RoamLocationSettingsSnapshot(authorization: status, servicesEnabled: true)
            XCTAssertFalse(snapshot.foregroundAuthorized); XCTAssertFalse(snapshot.alwaysAuthorized)
        }
    }
    func testWhenInUseDoesNotImplyAlwaysPermission() {
        let snapshot = RoamLocationSettingsSnapshot(authorization: .whenInUse, servicesEnabled: true)
        XCTAssertTrue(snapshot.foregroundAuthorized); XCTAssertFalse(snapshot.alwaysAuthorized)
    }
    func testAlwaysPermissionIsOnlyAnAuthorizationFact() {
        let snapshot = RoamLocationSettingsSnapshot(authorization: .always, servicesEnabled: false)
        XCTAssertTrue(snapshot.foregroundAuthorized); XCTAssertTrue(snapshot.alwaysAuthorized)
        XCTAssertFalse(snapshot.servicesEnabled)
    }
    func testInitialStateIsIdleWithoutSettingsAction() {
        let state = RoamLocationSettingsState()
        XCTAssertEqual(state.phase, .idle); XCTAssertFalse(state.isOpeningSettings); XCTAssertFalse(state.settingsOpenFailed)
    }
    func testNewReadHidesOldLoadedStateUntilActualReadCompletes() {
        var state = RoamLocationSettingsState(); let first = state.beginRead()
        state.finishRead(first, snapshot: denied); _ = state.beginRead()
        XCTAssertEqual(state.phase, .loading)
    }
    func testOlderReadCannotOverwriteNewerStatus() {
        var state = RoamLocationSettingsState(); let first = state.beginRead(), second = state.beginRead()
        let current = RoamLocationSettingsSnapshot(authorization: .whenInUse, servicesEnabled: false)
        XCTAssertTrue(state.finishRead(second, snapshot: current)); XCTAssertFalse(state.finishRead(first, snapshot: denied))
        XCTAssertEqual(state.phase, .loaded(current))
    }
    func testReadFailureIsNotDeniedAndCanRetry() {
        var state = RoamLocationSettingsState(); let first = state.beginRead()
        XCTAssertTrue(state.finishRead(first, snapshot: nil)); XCTAssertEqual(state.phase, .failed)
        let next = state.beginRead(); XCTAssertTrue(state.finishRead(next, snapshot: denied))
        XCTAssertEqual(state.phase, .loaded(denied))
    }
    func testDuplicateCompletionIsRejected() {
        var state = RoamLocationSettingsState(); let first = state.beginRead()
        XCTAssertTrue(state.finishRead(first, snapshot: denied)); XCTAssertFalse(state.finishRead(first, snapshot: nil))
        XCTAssertEqual(state.phase, .loaded(denied))
    }
    func testRepeatedSettingsTapDoesNotCreateAnotherAttempt() throws {
        var state = RoamLocationSettingsState(); let first = try XCTUnwrap(state.beginSettingsOpen())
        XCTAssertTrue(state.acceptsSettingsOpen(first)); XCTAssertNil(state.beginSettingsOpen()); XCTAssertTrue(state.isOpeningSettings)
    }
    func testFailedOpenHasRealRetryAndSuccessClearsFailure() throws {
        var state = RoamLocationSettingsState(); let first = try XCTUnwrap(state.beginSettingsOpen())
        XCTAssertTrue(state.finishSettingsOpen(first, opened: false)); XCTAssertTrue(state.settingsOpenFailed)
        let retry = try XCTUnwrap(state.beginSettingsOpen()); XCTAssertFalse(state.settingsOpenFailed)
        XCTAssertTrue(state.finishSettingsOpen(retry, opened: true)); XCTAssertFalse(state.settingsOpenFailed)
    }
    func testOpeningSettingsNeverGrantsAuthorization() throws {
        var state = RoamLocationSettingsState(); let read = state.beginRead(); state.finishRead(read, snapshot: denied)
        let open = try XCTUnwrap(state.beginSettingsOpen()); state.finishSettingsOpen(open, opened: true)
        XCTAssertEqual(state.phase, .loaded(denied))
    }
    func testRefreshFencesPendingSettingsResult() throws {
        var state = RoamLocationSettingsState(); let open = try XCTUnwrap(state.beginSettingsOpen())
        _ = state.beginRead(); XCTAssertFalse(state.acceptsSettingsOpen(open))
        XCTAssertFalse(state.finishSettingsOpen(open, opened: false)); XCTAssertFalse(state.settingsOpenFailed)
    }
    func testDismissalFencesPendingReadAndSettingsCallbacks() throws {
        var state = RoamLocationSettingsState(); let read = state.beginRead(), open = try XCTUnwrap(state.beginSettingsOpen())
        state.invalidate(); XCTAssertFalse(state.finishRead(read, snapshot: denied))
        XCTAssertFalse(state.finishSettingsOpen(open, opened: false)); XCTAssertEqual(state.phase, .idle)
    }
    func testReentryFencesOldFailureAgainstNewSettingsAttempt() throws {
        var state = RoamLocationSettingsState(); let old = try XCTUnwrap(state.beginSettingsOpen())
        state.invalidate(); let current = try XCTUnwrap(state.beginSettingsOpen())
        XCTAssertFalse(state.finishSettingsOpen(old, opened: false)); XCTAssertTrue(state.acceptsSettingsOpen(current))
        XCTAssertFalse(state.settingsOpenFailed)
    }
}

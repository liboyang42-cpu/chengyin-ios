import XCTest
@testable import QuestifyCore

final class DevicePushRegistrationLifecycleTests: XCTestCase {
    func testFirstJourneySandboxSilentRegisterDisableRevokeStopsSendRecoverOriginal() throws {
        var lifecycle = DevicePushRegistrationLifecycle()
        let registered = try lifecycle.register(
            deviceId: "dev-c09", environment: DevicePushRegistrationLifecycle.envSandbox,
            silent: true, fixtureToken: "fixture-token-c09")
        XCTAssertTrue(registered.silent)
        XCTAssertEqual(registered.status, DevicePushRegistrationLifecycle.statusActive)
        XCTAssertEqual(registered.environment, DevicePushRegistrationLifecycle.envSandbox)
        XCTAssertTrue(try lifecycle.maySend(
            deviceId: "dev-c09", appliedProjection: ImmutableReceiptProducer.projectionApplied).allowed)

        _ = try lifecycle.disable(deviceId: "dev-c09")
        XCTAssertFalse(try lifecycle.maySend(
            deviceId: "dev-c09", appliedProjection: ImmutableReceiptProducer.projectionApplied).allowed)

        _ = try lifecycle.revoke(deviceId: "dev-c09")
        let afterRevoke = try lifecycle.maySend(
            deviceId: "dev-c09", appliedProjection: ImmutableReceiptProducer.projectionApplied)
        XCTAssertFalse(afterRevoke.allowed)
        XCTAssertEqual(afterRevoke.reason, "REVOKED_OR_DISABLED")
        XCTAssertTrue(afterRevoke.currentProjectionClaimsApplied)
        XCTAssertFalse(lifecycle.treatsAppliedProjectionAsAuthorization(ImmutableReceiptProducer.projectionApplied))
        XCTAssertFalse(lifecycle.treatsAppliedProjectionAsOriginalProof(ImmutableReceiptProducer.projectionApplied))
        XCTAssertThrowsError(try lifecycle.register(
            deviceId: "dev-c09", environment: DevicePushRegistrationLifecycle.envSandbox,
            silent: true, fixtureToken: "fixture-token-c09")) { error in
            XCTAssertEqual(error as? NotifyFailure, .revokedDeviceCannotReregister)
        }
        XCTAssertThrowsError(try lifecycle.register(
            deviceId: "dev-new", environment: DevicePushRegistrationLifecycle.envSandbox,
            silent: false, fixtureToken: "prod-apns-key")) { error in
            XCTAssertEqual(error as? NotifyFailure, .invalidFixtureToken)
        }
        XCTAssertThrowsError(try lifecycle.register(
            deviceId: "dev-env", environment: "LIVE", silent: false, fixtureToken: "fixture-ok")) { error in
            XCTAssertEqual(error as? NotifyFailure, .invalidEnvironment)
        }
        let original = lifecycle.recoverOriginal(
            originalRequestID: "dev-c09", appliedProjection: ImmutableReceiptProducer.projectionApplied)
        XCTAssertEqual(original.status, DevicePushRegistrationLifecycle.statusRevoked)
        XCTAssertEqual(lifecycle.recoverUnknown(
            originalRequestID: "dev-missing", appliedProjection: ImmutableReceiptProducer.projectionApplied).status,
                       "UNKNOWN")
        XCTAssertTrue(registered.jsonObject()["deviceId"] is String)
        XCTAssertTrue(DevicePushRegistrationLifecycle.Registration(
            deviceId: nil, environment: nil, silent: false, fixtureToken: nil, status: nil)
            .jsonObject()["deviceId"] is NSNull)
    }
}

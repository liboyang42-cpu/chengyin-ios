import XCTest
import CryptoKit
@testable import Questify

@MainActor final class NativePlatformAppTests: XCTestCase {
    func testShippedRuntimeApprovalIsAbsent() {
        XCTAssertNil(NativeRuntimeDependencies.dormant.nativePlatform)
        XCTAssertFalse(NativePlatformAcceptance().validPurpose)
    }
    func testDormantPedometerCannotRequestPermissionOrRead() async {
        let provider = IPhonePedometerProvider()
        XCTAssertEqual(provider.permission, .unsupported)
        do { _ = try await provider.read(from: Date().addingTimeInterval(-10), to: Date()); XCTFail() }
        catch { XCTAssertEqual(error as? NativePlatformIssue, .disabled) }
    }
    func testDormantNotificationProviderCannotPromptOrSchedule() async {
        let provider = AppleLocalReminderProvider()
        let permission = await provider.permission(); XCTAssertEqual(permission, .unsupported)
        do { _ = try await provider.requestPermission(); XCTFail() }
        catch { XCTAssertEqual(error as? NativePlatformIssue, .disabled) }
        let pending = await provider.pending(); XCTAssertTrue(pending.isEmpty)
    }
    func testDormantAppAttestDoesNotCreateAKey() async {
        let provider = AppAttestStepAssertionProvider()
        XCTAssertFalse(provider.supported)
        do { _ = try await provider.assertion(clientData: Data("synthetic".utf8)); XCTFail() }
        catch { XCTAssertEqual(error as? NativePlatformIssue, .unsupported) }
    }
    func testBackendGoldenVectorSHA256() throws {
        let fixture = #"{"challenge":{"challengeId":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","provider":"IOS_CMPEDOMETER_V1","accountId":7,"sessionId":51,"attemptStartedAt":1790935140000,"deviceKeyId":"device-key","sessionVersion":1,"issuedAt":1790935200000,"expiresAt":1790935320000,"timeZone":"Asia/Shanghai","dayKey":"2026-10-02","dayStartAt":1790870400000,"dayEndAt":1790956800000},"request":{"sessionId":51,"version":1,"idempotencyKey":"submit-1","action":"SUBMIT_NATIVE_STEPS","payload":{"provider":"IOS_CMPEDOMETER_V1","deviceKeyId":"device-key","challengeId":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","dayKey":"2026-10-02","sampleStartAt":1790870400000,"sampleEndAt":1790935201000,"cumulativeSteps":4000,"assertion":"dGVzdC1vbmx5"}},"canonicalPayload":"CHENGYIN_NATIVE_STEPS_V1\nIOS_CMPEDOMETER_V1\n7\n51\n1790935140000\ndevice-key\n0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n1790935200000\n1790935320000\nAsia/Shanghai\n2026-10-02\n1790870400000\n1790956800000\n1790870400000\n1790935201000\n4000\n1\nsubmit-1","clientDataHashHex":"4b1f0eab9f480291c632216a2445ebb8c16a2c9ee7b838af43f1fa6bc7f8dce7","note":"Synthetic cross-client fixture only. Assertion is not a valid App Attest proof."}"#
        let raw = try JSONDecoder().decode(PlayWireValue.self, from: Data(fixture.utf8))
        let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic")
        let challenge = try NativeStepChallenge(raw["challenge"], owner: owner, sessionID: 51, version: 1, deviceKeyID: "device-key")
        let reading = try NativePedometerReading(start: Date(timeIntervalSince1970: 1_790_870_400), end: Date(timeIntervalSince1970: 1_790_935_201), steps: 4000)
        let data = try NativeStepCanonical.clientData(challenge: challenge, reading: reading, idempotencyKey: "submit-1")
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actual, raw["clientDataHashHex"].text)
    }
}

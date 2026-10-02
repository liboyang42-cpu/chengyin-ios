import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class NativePlatformContractTests: XCTestCase {
    func testMatchesBackendGoldenCanonicalFixture() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/native-platform-v1.json")
        let fixture = try JSONDecoder().decode(PlayWireValue.self, from: Data(contentsOf: url))
        let challenge = try NativeStepChallenge(fixture["challenge"], owner: nativeOwner(), sessionID: 51, version: 1, deviceKeyID: "device-key")
        let reading = try NativePedometerReading(start: Date(timeIntervalSince1970: 1_790_870_400), end: Date(timeIntervalSince1970: 1_790_935_201), steps: 4000)
        let bytes = try NativeStepCanonical.clientData(challenge: challenge, reading: reading, idempotencyKey: "submit-1")
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), fixture["canonicalPayload"].text)
    }
    func testNativeChallengeBindsEveryIdentityAndServerDay() throws {
        let owner = try nativeOwner()
        _ = try NativeStepChallenge(nativeChallenge(), owner: owner, sessionID: 11, version: 2, deviceKeyID: "fixture-key")
        for field in ["accountId", "sessionId", "sessionVersion", "dayStartAt", "dayEndAt", "expiresAt"] {
            var raw = nativeChallenge().object!; raw[field] = .int(0)
            XCTAssertThrowsError(try NativeStepChallenge(.object(raw), owner: owner, sessionID: 11, version: 2, deviceKeyID: "fixture-key"), field)
        }
        for field in ["provider", "deviceKeyId", "timeZone", "dayKey"] {
            var raw = nativeChallenge().object!; raw[field] = .string("wrong")
            XCTAssertThrowsError(try NativeStepChallenge(.object(raw), owner: owner, sessionID: 11, version: 2, deviceKeyID: "fixture-key"), field)
        }
    }
    func testCanonicalBytesAreExactlyEighteenLinesWithoutTrailingLF() throws {
        let challenge = try NativeStepChallenge(nativeChallenge(), owner: nativeOwner(), sessionID: 11, version: 2, deviceKeyID: "fixture-key")
        let sample = try NativePedometerReading(start: Date(timeIntervalSince1970: 1_790_899_200), end: nativeNow, steps: 1234)
        let key = "00000000-0000-0000-0000-000000000001"
        let data = try NativeStepCanonical.clientData(challenge: challenge, reading: sample, idempotencyKey: key)
        let expected = ["CHENGYIN_NATIVE_STEPS_V1", "IOS_CMPEDOMETER_V1", "7", "11", "1790935190000", "fixture-key", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "1790935200000", "1790935320000", "UTC", "2026-10-02", "1790899200000", "1790985600000", "1790899200000", "1790935200000", "1234", "2", key].joined(separator: "\n")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), expected)
        XCTAssertNotEqual(data.last, 10)
    }
    func testClockDiscontinuityAndRebootRejectSample() throws {
        let anchor = NativePlatformClockAnchor(wall: nativeNow, uptime: 100)
        try anchor.validate(wall: nativeNow.addingTimeInterval(10), uptime: 110)
        XCTAssertThrowsError(try anchor.validate(wall: nativeNow.addingTimeInterval(400), uptime: 110))
        XCTAssertThrowsError(try anchor.validate(wall: nativeNow, uptime: 1))
    }
    func testExpiredAndOtherDaySampleRejected() throws {
        let challenge = try NativeStepChallenge(nativeChallenge(), owner: nativeOwner(), sessionID: 11, version: 2, deviceKeyID: "fixture-key")
        XCTAssertThrowsError(try challenge.validate(now: nativeNow.addingTimeInterval(121)))
        let bad = try NativePedometerReading(start: nativeNow.addingTimeInterval(-100), end: nativeNow, steps: 10)
        XCTAssertThrowsError(try challenge.validate(bad, now: nativeNow))
        let excessive = try NativePedometerReading(start: Date(timeIntervalSince1970: 1_790_899_200), end: nativeNow, steps: 100001)
        XCTAssertThrowsError(try challenge.validate(excessive, now: nativeNow))
    }
    func testServerWindowRequiresZoneFutureInstantAndLocalProvider() throws {
        _ = try NativeTimeWindow(nativeWindow())
        for field in ["nextOpenAt", "nextCloseAt", "serverNow"] {
            var raw = nativeWindow().object!; raw[field] = .int(0)
            XCTAssertThrowsError(try NativeTimeWindow(.object(raw)))
        }
        for field in ["timeZone", "notificationProvider", "windowVersion"] {
            var raw = nativeWindow().object!; raw[field] = .string("")
            XCTAssertThrowsError(try NativeTimeWindow(.object(raw)))
        }
    }
    func testLegacyWeRunAndTimeWindowWriteRemainRejected() throws {
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "steps", action: "SUBMIT_STEPS", payload: ["steps": .int(10)], segment: .object([:])))
        XCTAssertEqual(PlayKitActionCatalog.actions["timeWindow"], [])
        XCTAssertFalse(PlayKitActionCatalog.actions["steps"]!.contains(NativePlatformAction.submit.rawValue))
    }
}

let nativeNow = Date(timeIntervalSince1970: 1_790_935_200)
func nativeOwner(epoch: UInt64 = 1) throws -> PlayExperienceSession { try .init(accountID: 7, epoch: epoch, namespace: "synthetic-native", token: "synthetic-token") }
func nativeChallenge(version: Int = 2) -> PlayWireValue {
    .object(["provider": .string("IOS_CMPEDOMETER_V1"), "accountId": .int(7), "sessionId": .int(11), "sessionVersion": .int(version),
        "deviceKeyId": .string("fixture-key"), "challengeId": .string("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), "attemptStartedAt": .int(1_790_935_190_000),
        "issuedAt": .int(1_790_935_200_000), "expiresAt": .int(1_790_935_320_000), "dayKey": .string("2026-10-02"),
        "timeZone": .string("UTC"), "dayStartAt": .int(1_790_899_200_000), "dayEndAt": .int(1_790_985_600_000)])
}
func nativeWindow(version: String = "window-1", offset: Int = 3_600_000) -> PlayWireValue {
    .object(["enabled": .bool(true), "activityId": .int(0), "topicId": .int(71), "nodeId": .int(701), "notificationProvider": .string("LOCAL_ONLY"), "timeZone": .string("UTC"), "serverNow": .int(1_790_935_200_000),
        "openNow": .bool(false), "nextOpenAt": .int(1_790_935_200_000 + offset), "nextCloseAt": .int(1_790_942_400_000 + offset), "windowVersion": .string(version)])
}

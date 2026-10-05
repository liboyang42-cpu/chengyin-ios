import XCTest
@testable import QuestifyCore

final class NativeEnrollmentContractTests: XCTestCase {
    func testCanonicalKeyAndProofBounds() throws {
        XCTAssertTrue(NativeEnrollmentWire.validKey(enrollmentKey))
        XCTAssertFalse(NativeEnrollmentWire.validKey(enrollmentKey + "\n"))
        XCTAssertFalse(NativeEnrollmentWire.validKey(String(enrollmentKey.dropLast())))
        XCTAssertNil(NativeEnrollmentWire.canonicalBase64(Data(repeating: 0, count: 4097).base64EncodedString(), count: 1...4096))
        XCTAssertThrowsError(try NativeEnrollmentProof(deviceKeyID: enrollmentKey, challengeID: String(repeating: "a", count: 64), attestationObject: Data(repeating: 0, count: 65537).base64EncodedString()))
    }
    func testScopeAndStatusRejectAccountAppEnvironmentAndRewards() throws {
        let scope = try enrollmentScope()
        _ = try NativeEnrollmentStatus(enrollmentStatus(.active), scope: scope, expectedKey: enrollmentKey)
        for (field, wrong) in [("accountId", PlayWireValue.int(8)), ("appId", .string("WRONG.app")), ("environment", .string("development")), ("rewardEnabled", .bool(true)), ("hardwareVerified", .bool(true)), ("deviceKeyId", .string(Data(repeating: 2, count: 32).base64EncodedString()))] {
            var value = enrollmentStatus(.active).object!; value[field] = wrong
            XCTAssertThrowsError(try NativeEnrollmentStatus(.object(value), scope: scope, expectedKey: enrollmentKey), field)
        }
        XCTAssertThrowsError(try NativeEnrollmentScope(namespace: "synthetic", accountID: 7, appID: "TEST.app", environment: "development"))
    }
    func testChallengeBindsNonceAndExpiresWithoutRawFallback() throws {
        let challenge = try NativeEnrollmentChallenge(enrollmentChallenge(), scope: enrollmentScope(), key: enrollmentKey)
        XCTAssertEqual(challenge.nonce, Data(0..<32)); try challenge.validate(now: enrollmentNow)
        XCTAssertThrowsError(try challenge.validate(now: enrollmentNow.addingTimeInterval(301)))
        for (field, value) in [("challengeBase64", PlayWireValue.string("not-base64")), ("expiresAt", .int(1_790_935_501_000)), ("deviceKeyId", .string("wrong"))] {
            var raw = enrollmentChallenge().object!; raw[field] = value
            XCTAssertThrowsError(try NativeEnrollmentChallenge(.object(raw), scope: enrollmentScope(), key: enrollmentKey), field)
        }
    }
    func testJournalCannotMoveBetweenAccountsOrAppIDs() throws {
        var record = NativeEnrollmentRecord(scope: try enrollmentScope(), phase: .keyReady); record.deviceKeyID = enrollmentKey
        try record.validate(scope: enrollmentScope())
        XCTAssertThrowsError(try record.validate(scope: enrollmentScope(account: 8)))
        record.retiredKeys = [enrollmentKey]; XCTAssertThrowsError(try record.validate(scope: enrollmentScope()))
    }
}

@available(macOS 14.0, *)
@MainActor final class NativeEnrollmentLifecycleTests: XCTestCase {
    func testDefaultOffDoesNotReadStorageNetworkOrDevice() async throws {
        let store = EnrollmentTestStore(), service = EnrollmentTestService(), device = EnrollmentTestDevice()
        let model = NativeEnrollmentCoordinator(scope: try enrollmentScope(), store: store, service: service, device: device, current: { true })
        await model.load(); await model.prepareNewKey(); await model.submitReviewed(); await model.revokeReviewed()
        XCTAssertEqual(store.reads, 0); XCTAssertEqual(service.statusReads, 0); XCTAssertEqual(device.creations, 0)
    }
    func testPreparationAndSubmissionAreSeparateAndDurable() async throws {
        let store = EnrollmentTestStore(), service = EnrollmentTestService(), device = EnrollmentTestDevice()
        let model = try make(store, service, device)
        await model.load(); XCTAssertEqual(device.creations, 0)
        await model.prepareNewKey()
        XCTAssertEqual(model.phase, "review"); XCTAssertEqual(device.creations, 1); XCTAssertEqual(device.attestations, 1)
        XCTAssertEqual(device.nonce, Data(0..<32)); XCTAssertTrue(service.proofs.isEmpty)
        XCTAssertEqual(store.value?.phase, .review); XCTAssertNotNil(store.value?.proof)
        await model.submitReviewed()
        XCTAssertEqual(service.proofs.count, 1); XCTAssertEqual(model.phase, "active"); XCTAssertEqual(model.activeKeyID, enrollmentKey)
        XCTAssertNil(store.value?.proof); XCTAssertEqual(store.value?.phase, .active)
    }
    func testStorageFailureBeforeGenerationBlocksPersistentAccess() async throws {
        let store = EnrollmentTestStore(); store.failWrite = true
        let service = EnrollmentTestService(), device = EnrollmentTestDevice(), model = try make(store, service, device)
        await model.load(); await model.prepareNewKey()
        XCTAssertEqual(device.creations, 0); XCTAssertEqual(service.challenges, 0); XCTAssertEqual(model.issue, .storageUnavailable)
    }
    func testBackendDisabledAfterReviewPreventsSDKGeneration() async throws {
        let store = EnrollmentTestStore(), service = EnrollmentTestService(), device = EnrollmentTestDevice(), model = try make(store, service, device)
        await model.load(); service.enabled = false; await model.prepareNewKey()
        XCTAssertEqual(device.creations, 0); XCTAssertEqual(service.challenges, 0)
    }
    func testLostEnrollmentRetriesSameStoredProofWithoutNewKey() async throws {
        let store = EnrollmentTestStore(), service = EnrollmentTestService(), device = EnrollmentTestDevice(), first = try make(store, service, device)
        await first.load(); await first.prepareNewKey(); service.loseEnroll = true
        await first.submitReviewed(); let proof = try XCTUnwrap(store.value?.proof)
        XCTAssertEqual(store.value?.phase, .enrolling)
        let restored = try make(store, service, device); await restored.load()
        XCTAssertTrue(restored.canRetryEnrollment); XCTAssertEqual(device.creations, 1); XCTAssertEqual(service.proofs.count, 1)
        await restored.retryExactEnrollment()
        XCTAssertEqual(service.proofs, [proof, proof]); XCTAssertEqual(device.creations, 1); XCTAssertEqual(restored.activeKeyID, enrollmentKey)
    }
    func testReadbackRecoversAcceptedEnrollmentWithoutPostingAgain() async throws {
        let store = EnrollmentTestStore(), service = EnrollmentTestService(), device = EnrollmentTestDevice(), first = try make(store, service, device)
        await first.load(); await first.prepareNewKey(); service.loseEnroll = true; service.commitLostEnroll = true
        await first.submitReviewed()
        let restored = try make(store, service, device); await restored.load()
        XCTAssertEqual(restored.phase, "active"); XCTAssertEqual(service.proofs.count, 1); XCTAssertEqual(device.creations, 1)
    }
    func testExplicitServerRejectionKeepsProofButAllowsNewReviewedRecovery() async throws {
        let store = EnrollmentTestStore(), service = EnrollmentTestService(), device = EnrollmentTestDevice(), model = try make(store, service, device)
        await model.load(); await model.prepareNewKey(); service.rejectEnroll = true
        await model.submitReviewed()
        XCTAssertEqual(store.value?.phase, .rejected); XCTAssertNotNil(store.value?.proof); XCTAssertFalse(model.canRetryEnrollment)
        await model.refreshStatus(); XCTAssertTrue(model.canCreate); XCTAssertEqual(device.creations, 1)
    }
    func testRevokeNeedsGestureAndConfirmedReadback() async throws {
        let store = EnrollmentTestStore(), service = EnrollmentTestService(), device = EnrollmentTestDevice(), model = try make(store, service, device)
        await model.load(); await model.prepareNewKey(); await model.submitReviewed(); await model.refreshStatus()
        XCTAssertEqual(service.revocations, 0)
        service.loseRevoke = true; await model.revokeReviewed()
        XCTAssertNil(model.activeKeyID); XCTAssertEqual(store.value?.phase, .revoking)
        let restored = try make(store, service, device); await restored.load()
        XCTAssertEqual(restored.phase, "revoked"); XCTAssertEqual(service.revocations, 1); XCTAssertNil(restored.activeKeyID)
        await restored.refreshStatus(); XCTAssertEqual(service.revocations, 1)
    }
    func testLogoutDuringGenerationPreservesOriginalScopeHandleWithoutChallenge() async throws {
        let store = EnrollmentTestStore(), service = EnrollmentTestService(), device = EnrollmentTestDevice(); var current = true
        let model = try make(store, service, device, current: { current }); await model.load()
        device.onCreate = { current = false; model.invalidate() }
        await model.prepareNewKey()
        XCTAssertEqual(store.value?.scope.accountID, 7); XCTAssertEqual(store.value?.deviceKeyID, enrollmentKey)
        XCTAssertEqual(store.value?.phase, .keyReady); XCTAssertEqual(service.challenges, 0); XCTAssertNil(model.record)
    }
    func testSavedUnattestedHandleCanResumeWithoutAnotherKey() async throws {
        let store = EnrollmentTestStore(), service = EnrollmentTestService(), device = EnrollmentTestDevice()
        var saved = NativeEnrollmentRecord(scope: try enrollmentScope(), phase: .keyReady); saved.deviceKeyID = enrollmentKey; store.value = saved
        let model = try make(store, service, device); await model.load()
        XCTAssertTrue(model.canResumePreparation); await model.prepareSavedKey()
        XCTAssertEqual(device.creations, 0); XCTAssertEqual(device.attestations, 1); XCTAssertEqual(model.phase, "review")
        XCTAssertEqual(store.value?.deviceKeyID, enrollmentKey); XCTAssertTrue(service.proofs.isEmpty)
    }
    func testLogoutDuringAttestationPersistsProofAndNeverEnrolls() async throws {
        let store = EnrollmentTestStore(), service = EnrollmentTestService(), device = EnrollmentTestDevice(); var current = true
        let model = try make(store, service, device, current: { current }); await model.load()
        device.onAttest = { current = false; model.invalidate() }; await model.prepareNewKey()
        XCTAssertNotNil(store.value?.proof); XCTAssertEqual(store.value?.phase, .review); XCTAssertTrue(service.proofs.isEmpty)
    }
    func testRevokedKeyCannotBeReactivatedByReadback() async throws {
        let store = EnrollmentTestStore(), service = EnrollmentTestService(), device = EnrollmentTestDevice(), model = try make(store, service, device)
        await model.load(); await model.prepareNewKey(); await model.submitReviewed(); await model.revokeReviewed()
        service.state = .active; await model.refreshStatus()
        XCTAssertNil(model.activeKeyID); XCTAssertEqual(model.issue, .invalidContract); XCTAssertEqual(store.value?.phase, .revoked)
    }
    private func make(_ store: EnrollmentTestStore, _ service: EnrollmentTestService, _ device: EnrollmentTestDevice,
                      current: @escaping () -> Bool = { true }) throws -> NativeEnrollmentCoordinator {
        .init(scope: try enrollmentScope(), store: store, service: service, device: device, enabled: true, creationAllowed: true, revocationAllowed: true, current: current, now: { enrollmentNow }, uptime: { 100 })
    }
}
let enrollmentKey = Data(repeating: 1, count: 32).base64EncodedString()
let enrollmentNow = Date(timeIntervalSince1970: 1_790_935_200)
func enrollmentScope(account: Int = 7) throws -> NativeEnrollmentScope { try .init(namespace: "synthetic-enrollment", accountID: account, appID: "TEST123.example.native", environment: "production") }
func enrollmentStatus(_ state: NativeEnrollmentStatus.State, key: String? = enrollmentKey, enabled: Bool = true) -> PlayWireValue {
    .object(["protocolVersion": .int(1), "provider": .string(NativeEnrollmentWire.provider), "enabled": .bool(enabled), "rewardEnabled": .bool(false), "hardwareVerified": .bool(false), "accountId": .int(7), "deviceKeyId": key.map(PlayWireValue.string) ?? .null, "appId": enabled ? .string("TEST123.example.native") : .null, "environment": .string("production"), "status": .string(state.rawValue), "reasonCode": .string("SYNTHETIC")])
}
func enrollmentChallenge() -> PlayWireValue {
    var raw = enrollmentStatus(.challenge).object!
    raw.merge(["challengeId": .string(String(repeating: "a", count: 64)), "challengeBase64": .string(Data(0..<32).base64EncodedString()), "issuedAt": .int(1_790_935_200_000), "expiresAt": .int(1_790_935_500_000)]) { _, new in new }; return .object(raw)
}
@MainActor final class EnrollmentTestStore: NativeEnrollmentStoring {
    var value: NativeEnrollmentRecord?; var reads = 0; var failWrite = false
    func read(scope: NativeEnrollmentScope) throws -> NativeEnrollmentRecord? { reads += 1; if let value { try value.validate(scope: scope) }; return value }
    func write(_ record: NativeEnrollmentRecord) throws { if failWrite { throw NativeEnrollmentIssue.storageUnavailable }; value = record }
}
@MainActor final class EnrollmentTestDevice: NativeEnrollmentDeviceProviding {
    let supported = true; var creations = 0, attestations = 0; var nonce: Data?
    var onCreate: (() -> Void)?; var onAttest: (() -> Void)?
    func generateKey() async throws -> String { creations += 1; onCreate?(); return enrollmentKey }
    func attest(key: String, challengeBytes: Data) async throws -> String { attestations += 1; nonce = challengeBytes; onAttest?(); return Data("synthetic-not-an-attestation".utf8).base64EncodedString() }
    func cancel() {}
}
@MainActor final class EnrollmentTestService: NativeEnrollmentServing {
    var enabled = true; var state = NativeEnrollmentStatus.State.unenrolled
    var statusReads = 0, challenges = 0, revocations = 0; var proofs: [NativeEnrollmentProof] = []
    var loseEnroll = false, commitLostEnroll = false, loseRevoke = false, rejectEnroll = false
    func status(key: String?) async throws -> NativeEnrollmentStatus {
        statusReads += 1
        return try .init(enrollmentStatus(enabled ? state : .disabled, key: key, enabled: enabled), scope: enrollmentScope(), expectedKey: key)
    }
    func challenge(key: String) async throws -> NativeEnrollmentChallenge { challenges += 1; return try .init(enrollmentChallenge(), scope: enrollmentScope(), key: key) }
    func enroll(_ proof: NativeEnrollmentProof) async throws -> NativeEnrollmentStatus {
        proofs.append(proof)
        if rejectEnroll { throw NativeEnrollmentIssue.rejected }
        if loseEnroll { loseEnroll = false; if commitLostEnroll { state = .active }; throw NativeEnrollmentIssue.network }
        state = .active; return try .init(enrollmentStatus(.active), scope: enrollmentScope(), expectedKey: proof.deviceKeyID)
    }
    func revoke(key: String) async throws -> NativeEnrollmentStatus {
        revocations += 1; state = .revoked
        if loseRevoke { loseRevoke = false; throw NativeEnrollmentIssue.network }
        return try .init(enrollmentStatus(.revoked), scope: enrollmentScope(), expectedKey: key)
    }
}

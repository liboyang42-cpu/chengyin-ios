#if DEBUG
import SwiftUI

/// Synthetic in-memory journal/service and literal opaque test handles only.
/// No Apple provider, Keychain, key generation, attestation or network is invoked.
@MainActor struct NativeEnrollmentFixtureHost: View {
    @State private var model: NativeEnrollmentCoordinator
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--uitesting-enrollment-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "ready"
        let scope = try! NativeEnrollmentScope(namespace: "synthetic-ui", accountID: 7, appID: "SYNTHETIC.example.native", environment: "production")
        let service = NativeEnrollmentFixtureService(scope: scope)
        service.loseEnroll = scenario == "lost-enroll"; service.loseRevoke = scenario == "lost-revoke"
        _model = State(initialValue: NativeEnrollmentCoordinator(scope: scope, store: NativeEnrollmentFixtureStore(), service: service,
            device: NativeEnrollmentFixtureDevice(), enabled: scenario != "disabled", creationAllowed: true, revocationAllowed: true, current: { true }))
    }
    var body: some View { NavigationStack { NativeEnrollmentView(model: model, privacyURL: nil) } }
}
@MainActor private final class NativeEnrollmentFixtureStore: NativeEnrollmentStoring {
    var value: NativeEnrollmentRecord?
    func read(scope: NativeEnrollmentScope) throws -> NativeEnrollmentRecord? { if let value { try value.validate(scope: scope) }; return value }
    func write(_ record: NativeEnrollmentRecord) throws { value = record }
}
@MainActor private final class NativeEnrollmentFixtureDevice: NativeEnrollmentDeviceProviding {
    let supported = true
    func generateKey() async throws -> String { Data(repeating: 1, count: 32).base64EncodedString() }
    func attest(key: String, challengeBytes: Data) async throws -> String { Data("synthetic-not-an-Apple-attestation".utf8).base64EncodedString() }
    func cancel() {}
}
@MainActor private final class NativeEnrollmentFixtureService: NativeEnrollmentServing {
    let scope: NativeEnrollmentScope
    var state = NativeEnrollmentStatus.State.unenrolled
    var loseEnroll = false, loseRevoke = false
    init(scope: NativeEnrollmentScope) { self.scope = scope }
    private func raw(_ state: NativeEnrollmentStatus.State, key: String?) -> PlayWireValue {
        .object(["protocolVersion": .int(1), "provider": .string(NativeEnrollmentWire.provider), "enabled": .bool(true), "rewardEnabled": .bool(false), "hardwareVerified": .bool(false), "accountId": .int(scope.accountID), "deviceKeyId": key.map(PlayWireValue.string) ?? .null,
            "appId": .string(scope.appID), "environment": .string(scope.environment), "status": .string(state.rawValue), "reasonCode": .string("SYNTHETIC")])
    }
    func status(key: String?) async throws -> NativeEnrollmentStatus { try .init(raw(state, key: key), scope: scope, expectedKey: key) }
    func challenge(key: String) async throws -> NativeEnrollmentChallenge {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        var value = raw(.challenge, key: key).object!
        value.merge(["challengeId": .string(String(repeating: "a", count: 64)), "challengeBase64": .string(Data(0..<32).base64EncodedString()), "issuedAt": .int(now), "expiresAt": .int(now + 300_000)]) { _, new in new }
        return try .init(.object(value), scope: scope, key: key)
    }
    func enroll(_ proof: NativeEnrollmentProof) async throws -> NativeEnrollmentStatus {
        if loseEnroll { loseEnroll = false; throw NativeEnrollmentIssue.network }
        state = .active; return try .init(raw(.active, key: proof.deviceKeyID), scope: scope, expectedKey: proof.deviceKeyID)
    }
    func revoke(key: String) async throws -> NativeEnrollmentStatus {
        state = .revoked
        if loseRevoke { loseRevoke = false; throw NativeEnrollmentIssue.network }
        return try .init(raw(.revoked, key: key), scope: scope, expectedKey: key)
    }
}
#endif

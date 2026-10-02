import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact frozen native-device routes. Configuration grants and per-operation UI
/// consent are separate. No route is inferred from server text or SDK callbacks.
@MainActor public struct NativeEnrollmentService: NativeEnrollmentServing {
    public static let statusPath = "api/native/device/status"
    public static let challengePath = "api/native/device/enrollment-challenge"
    public static let enrollPath = "api/native/device/enroll"
    public static let revokePath = "api/native/device/revoke"
    public static let paths: Set<String> = [statusPath, challengePath, enrollPath, revokePath]
    private let api: APIConfiguration
    private let transport: any HTTPTransport
    private let scope: NativeEnrollmentScope
    private let owner: PlayExperienceSession
    private let current: () -> PlayExperienceSession?
    private let enabled: Bool
    private let enrollmentEnabled: Bool
    private let revocationEnabled: Bool
    public init(api: APIConfiguration, transport: any HTTPTransport, scope: NativeEnrollmentScope, owner: PlayExperienceSession,
                enabled: Bool = false, enrollmentEnabled: Bool = false, revocationEnabled: Bool = false,
                current: @escaping () -> PlayExperienceSession?) {
        self.api = api; self.transport = transport; self.scope = scope; self.owner = owner; self.current = current
        self.enabled = enabled; self.enrollmentEnabled = enrollmentEnabled; self.revocationEnabled = revocationEnabled
    }
    public func status(key: String?) async throws -> NativeEnrollmentStatus {
        if let key { try validateKey(key) }
        let raw = try await request(Self.statusPath, key: key)
        return try NativeEnrollmentStatus(raw, scope: scope, expectedKey: key)
    }
    public func challenge(key: String) async throws -> NativeEnrollmentChallenge {
        guard enrollmentEnabled else { throw NativeEnrollmentIssue.disabled }; try validateKey(key)
        return try NativeEnrollmentChallenge(await request(Self.challengePath, payload: keyPayload(key)), scope: scope, key: key)
    }
    public func enroll(_ proof: NativeEnrollmentProof) async throws -> NativeEnrollmentStatus {
        guard enrollmentEnabled else { throw NativeEnrollmentIssue.disabled }
        _ = try NativeEnrollmentProof(deviceKeyID: proof.deviceKeyID, challengeID: proof.challengeID, attestationObject: proof.attestationObject)
        let value = try NativeEnrollmentStatus(await request(Self.enrollPath, payload: proof.payload), scope: scope, expectedKey: proof.deviceKeyID)
        guard value.state == .active || value.state == .revoked else { throw NativeEnrollmentIssue.invalidContract }; return value
    }
    public func revoke(key: String) async throws -> NativeEnrollmentStatus {
        guard revocationEnabled else { throw NativeEnrollmentIssue.disabled }; try validateKey(key)
        let value = try NativeEnrollmentStatus(await request(Self.revokePath, payload: keyPayload(key)), scope: scope, expectedKey: key)
        guard value.state == .revoked else { throw NativeEnrollmentIssue.invalidContract }; return value
    }
    private func keyPayload(_ key: String) -> [String: PlayWireValue] { ["provider": .string(NativeEnrollmentWire.provider), "deviceKeyId": .string(key)] }
    private func validateKey(_ key: String) throws { guard NativeEnrollmentWire.validKey(key) else { throw NativeEnrollmentIssue.invalidContract } }
    private func gate() throws {
        guard enabled else { throw NativeEnrollmentIssue.disabled }
        guard current() == owner, scope.accountID == owner.accountID, scope.namespace == owner.namespace else { throw NativeEnrollmentIssue.staleSession }
    }
    private func request(_ path: String, key: String? = nil, payload: [String: PlayWireValue]? = nil) async throws -> PlayWireValue {
        try gate(); try Task.checkCancellation()
        guard Self.paths.contains(path) else { throw NativeEnrollmentIssue.invalidContract }
        var url = URLComponents(url: api.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let key { url.queryItems = [URLQueryItem(name: "deviceKeyId", value: key)] }
        var request = URLRequest(url: url.url!); request.httpMethod = payload == nil ? "GET" : "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue(owner.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let payload { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(payload) }
        let (data, status) = try await transport.send(request)
        try gate(); try Task.checkCancellation()
        guard data.count <= 131_072, (200..<300).contains(status) else { throw NativeEnrollmentIssue.network }
        let envelope = try JSONDecoder().decode(PlayWireValue.self, from: data)
        guard envelope["code"].integer == 200 else {
            if envelope["code"].integer == 409, envelope["data"]["provider"].text == NativeEnrollmentWire.provider,
               envelope["data"]["rewardEnabled"].bool == false, envelope["data"]["reasonCode"].text?.hasPrefix("APP_ATTEST_") == true {
                if envelope["data"]["reasonCode"].text == "APP_ATTEST_CHALLENGE_EXPIRED" { throw NativeEnrollmentIssue.expired }
                throw NativeEnrollmentIssue.rejected
            }
            throw NativeEnrollmentIssue.unknownResult
        }
        return envelope["data"]
    }
}

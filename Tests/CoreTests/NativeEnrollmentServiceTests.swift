import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class NativeEnrollmentServiceTests: XCTestCase {
    func testDefaultOffAndIndependentWriteGrants() async throws {
        let transport = EnrollmentHTTPRecorder(); let owner = try session()
        let disabled = try service(transport, owner: owner)
        do { _ = try await disabled.status(key: nil); XCTFail() } catch { XCTAssertEqual(error as? NativeEnrollmentIssue, .disabled) }
        let readsOnly = try service(transport, owner: owner, enabled: true)
        do { _ = try await readsOnly.challenge(key: enrollmentKey); XCTFail() } catch { XCTAssertEqual(error as? NativeEnrollmentIssue, .disabled) }
        do { _ = try await readsOnly.revoke(key: enrollmentKey); XCTFail() } catch { XCTAssertEqual(error as? NativeEnrollmentIssue, .disabled) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testExactRoutesKeysAndNoCallerSelectedAccount() async throws {
        let transport = EnrollmentHTTPRecorder(); let client = try service(transport, owner: session(), enabled: true, writes: true)
        transport.response = enrollmentStatus(.unenrolled, key: nil)
        _ = try await client.status(key: nil)
        XCTAssertNil(URLComponents(url: transport.requests.last!.url!, resolvingAgainstBaseURL: false)?.query)
        transport.response = enrollmentStatus(.unenrolled)
        _ = try await client.status(key: enrollmentKey)
        XCTAssertEqual(URLComponents(url: transport.requests.last!.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, enrollmentKey)
        transport.response = enrollmentChallenge(); _ = try await client.challenge(key: enrollmentKey)
        var body = try decoded(transport.requests.last!)
        XCTAssertEqual(Set(body.object!.keys), ["provider", "deviceKeyId"])
        XCTAssertEqual(transport.requests.last?.url?.path, "/synthetic/api/native/device/enrollment-challenge")
        let proof = try NativeEnrollmentProof(deviceKeyID: enrollmentKey, challengeID: String(repeating: "a", count: 64), attestationObject: Data("synthetic".utf8).base64EncodedString())
        transport.response = enrollmentStatus(.active); _ = try await client.enroll(proof)
        body = try decoded(transport.requests.last!)
        XCTAssertEqual(Set(body.object!.keys), ["provider", "deviceKeyId", "challengeId", "attestationObject"])
        XCTAssertEqual(body, .object(proof.payload)); XCTAssertNil(body.object?["accountId"])
        transport.response = enrollmentStatus(.revoked); _ = try await client.revoke(key: enrollmentKey)
        XCTAssertEqual(transport.requests.last?.url?.path, "/synthetic/api/native/device/revoke")
        XCTAssertEqual(Set(try decoded(transport.requests.last!).object!.keys), ["provider", "deviceKeyId"])
    }
    func testScopeChangeBeforeAndAfterResponseFailsClosed() async throws {
        let owner = try session(), transport = EnrollmentHTTPRecorder(); var current: PlayExperienceSession? = owner
        let client = try NativeEnrollmentService(api: APIConfiguration(baseURL: URL(string: "https://example.com/synthetic")!), transport: transport, scope: enrollmentScope(), owner: owner, enabled: true, current: { current })
        transport.response = enrollmentStatus(.unenrolled); transport.onSend = { current = nil }
        do { _ = try await client.status(key: enrollmentKey); XCTFail() } catch { XCTAssertEqual(error as? NativeEnrollmentIssue, .staleSession) }
        do { _ = try await client.status(key: enrollmentKey); XCTFail() } catch { XCTAssertEqual(error as? NativeEnrollmentIssue, .staleSession) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testWrongAppAndNoncanonicalKeyAreRejected() async throws {
        let transport = EnrollmentHTTPRecorder(); let client = try service(transport, owner: session(), enabled: true)
        do { _ = try await client.status(key: enrollmentKey + "\n"); XCTFail() } catch { XCTAssertEqual(error as? NativeEnrollmentIssue, .invalidContract) }
        XCTAssertTrue(transport.requests.isEmpty)
        var raw = enrollmentStatus(.active).object!; raw["appId"] = .string("OTHER.example.native"); transport.response = .object(raw)
        do { _ = try await client.status(key: enrollmentKey); XCTFail() } catch { XCTAssertEqual(error as? NativeEnrollmentIssue, .invalidContract) }
    }
    private func session() throws -> PlayExperienceSession { try .init(accountID: 7, epoch: 1, namespace: "synthetic-enrollment", token: "synthetic") }
    private func service(_ transport: EnrollmentHTTPRecorder, owner: PlayExperienceSession, enabled: Bool = false, writes: Bool = false) throws -> NativeEnrollmentService {
        try .init(api: APIConfiguration(baseURL: URL(string: "https://example.com/synthetic")!), transport: transport, scope: enrollmentScope(), owner: owner, enabled: enabled, enrollmentEnabled: writes, revocationEnabled: writes, current: { owner })
    }
    private func decoded(_ request: URLRequest) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap(request.httpBody)) }
}
@MainActor private final class EnrollmentHTTPRecorder: HTTPTransport {
    var requests: [URLRequest] = []; var response: PlayWireValue = .null; var onSend: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onSend?()
        return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": response])), 200)
    }
}

#if DEBUG
import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Entirely synthetic values, never a provider credential or an approved live endpoint.
enum USAppleFixtures {
    static func random(_ byte: UInt8) -> String {
        Data(repeating: byte, count: 32).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static let challengeID = random(1), rawNonce = random(2), state = random(3)
    static let digest = "6c1d63bbdab437c54368cbbd8886a886a79ad977297e265eebf1f5f5f01533b9"
    static func deployment() throws -> USAppleDeployment {
        try USAppleDeployment(market: .unitedStates, origin: URL(string: "https://us.example.com")!, realm: "fixture-US",
                              approvedUSOrigins: ["https://us.example.com"])
    }
    static var challengeJSON: String {
        "{\"code\":200,\"data\":{\"challengeId\":\"\(challengeID)\",\"rawNonce\":\"\(rawNonce)\",\"state\":\"\(state)\",\"expiresIn\":300,\"market\":\"US\",\"provider\":\"apple\"}}"
    }
    static let successJSON = #"{"code":200,"market":"US","token":"synthetic-session","data":{"id":7,"userType":1,"avatar":"","nickname":"Fixture","role":"player"}}"#
    static let sessionJSON = #"{"code":200,"data":{"market":"US","realm":"fixture-US","account":{"id":7,"userType":1,"avatar":null,"nickname":"Protected","role":"player"}}}"#
    static func challenge() throws -> USAppleChallenge {
        struct Envelope: Decodable { let data: USAppleChallenge }
        return try JSONDecoder().decode(Envelope.self, from: Data(challengeJSON.utf8)).data
    }
    static func account(_ id: Int = 7, nickname: String = "Verified") throws -> Account {
        try JSONDecoder().decode(Account.self, from: JSONSerialization.data(withJSONObject: ["id": id, "nickname": nickname, "role": "player"]))
    }
}

private final class USAppleFixtureTransport: HTTPTransport {
    var responses: [(String, Int)]
    var requests: [URLRequest] = []
    var afterRequest: (@MainActor () async throws -> Void)?
    init(_ responses: [(String, Int)] = []) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        try await afterRequest?()
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        let response = responses.removeFirst()
        return (Data(response.0.utf8), response.1)
    }
}

@MainActor
private final class USAppleSessionProofAuthorizer: USAppleAuthorizing {
    func authorize(_ request: USAppleAuthorizationRequest) async throws -> USAppleCredential {
        USAppleCredential(identityToken: "fixture.jwt.token", state: request.state)
    }
    func cancel() {}
}

@MainActor
final class USAppleServiceTests: XCTestCase {
    private func service(_ transport: USAppleFixtureTransport) throws -> USAppleService {
        USAppleService(offlineDeployment: try USAppleFixtures.deployment(), transport: transport)
    }
    func testProductionGateRejectsWithoutAnyNetworkOrProviderProbe() async throws {
        XCTAssertFalse(USAppleProductionGate.enabled)
        let transport = USAppleFixtureTransport()
        let service = USAppleService(deployment: try USAppleFixtures.deployment(), transport: transport)
        do { _ = try await service.challenge(); XCTFail("Production remains disabled") }
        catch { XCTAssertEqual(error as? USAppleError, .unavailable) }
        do { _ = try await service.exchange(challengeId: USAppleFixtures.challengeID, state: USAppleFixtures.state, identityToken: "fixture.jwt.token"); XCTFail("Production remains disabled") }
        catch { XCTAssertEqual(error as? USAppleError, .unavailable) }
        do { _ = try await service.currentAccount(token: "synthetic-session"); XCTFail("Production remains disabled") }
        catch { XCTAssertEqual(error as? USAppleError, .unavailable) }
        XCTAssertTrue(transport.requests.isEmpty)
        let regional = try RegionalConfiguration(market: .unitedStates, baseURL: "https://us.example.com",
            approvedBaseURLs: [.unitedStates: ["https://us.example.com"]], verifiedCapabilities: Set(RegionalCapability.allCases))
        XCTAssertTrue(regional.availableCapabilities.isEmpty)
    }
    func testOnlyApprovedTLSUSOriginAndExplicitRealmAreAccepted() throws {
        let approved = "https://us.example.com"
        XCTAssertNoThrow(try USAppleFixtures.deployment())
        for url in ["http://us.example.com", "https://u:p@us.example.com", "https://us.example.com/path", "https://us.example.com?x=1", "https://us.example.com#x", "https://us.example.com:8443", "https://evil.example.com", "https://us.example.com.evil.example.com"] {
            XCTAssertThrowsError(try USAppleDeployment(market: .unitedStates, origin: URL(string: url)!, realm: "fixture-US", approvedUSOrigins: [approved]))
        }
        XCTAssertThrowsError(try USAppleDeployment(market: .china, origin: URL(string: approved)!, realm: "fixture-US", approvedUSOrigins: [approved]))
        XCTAssertThrowsError(try USAppleDeployment(market: .unitedStates, origin: URL(string: approved)!, realm: "", approvedUSOrigins: [approved]))
    }
    func testExactJSONRoutesWithoutBearerCookiesOrIdentityExtras() async throws {
        let transport = USAppleFixtureTransport([(USAppleFixtures.challengeJSON, 200), (USAppleFixtures.successJSON, 200)])
        let service = try service(transport)
        let challenge = try await service.challenge()
        let result = try await service.exchange(challengeId: challenge.challengeId, state: challenge.state, identityToken: "fixture.jwt.token")
        XCTAssertEqual(result.account.id, 7)
        XCTAssertEqual(transport.requests.map { $0.url!.absoluteString }, ["https://us.example.com/api/us/auth/apple/challenges", "https://us.example.com/api/us/auth/apple/exchange"])
        XCTAssertEqual(transport.requests[0].httpBody, Data("{}".utf8))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: transport.requests[1].httpBody!) as? [String: String])
        XCTAssertEqual(fields, ["challengeId": challenge.challengeId, "state": challenge.state, "identityToken": "fixture.jwt.token"])
        for request in transport.requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        }
    }
    func testStableErrorCodesRequireExactHTTPPairAndNeverRetry() async throws {
        for expected in USAppleError.allCases {
            let json = "{\"code\":\(expected.httpStatus),\"errorCode\":\"\(expected.rawValue)\",\"msg\":\"Untrusted server text\"}"
            let transport = USAppleFixtureTransport([(json, expected.httpStatus)])
            do { _ = try await service(transport).challenge(); XCTFail("Must reject") }
            catch { XCTAssertEqual(error as? USAppleError, expected) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testUnknownNonJSONOffRouteRedirectAndMismatchedStatusesFailClosed() async throws {
        for (json, status) in [("<html>login</html>", 200), ("{}", 404), ("{}", 302), ("{}", 401),
            (#"{"code":200}"#, 201), (#"{"code":401,"errorCode":"US_APPLE_INVALID_IDENTITY"}"#, 200),
            (#"{"code":400,"errorCode":"US_APPLE_INVALID_IDENTITY"}"#, 400),
            (#"{"code":503,"errorCode":"UNKNOWN"}"#, 503),
            (#"{"code":200,"errorCode":"US_APPLE_UNAVAILABLE"}"#, 200)] {
            let transport = USAppleFixtureTransport([(json, status)])
            do { _ = try await service(transport).challenge(); XCTFail("Must fail closed") }
            catch { XCTAssertEqual(error as? USAppleClientError, .invalidResponse) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testChallengeBindsMarketProviderBoundedTTLAndCanonicalRandomValues() async throws {
        let valid = USAppleFixtures.challengeJSON
        let malformed = [valid.replacingOccurrences(of: "\"US\"", with: "\"CN\""),
            valid.replacingOccurrences(of: "\"apple\"", with: "\"google\""),
            valid.replacingOccurrences(of: ":300", with: ":0"), valid.replacingOccurrences(of: ":300", with: ":301"),
            valid.replacingOccurrences(of: ":300", with: ":-1"), valid.replacingOccurrences(of: ":300", with: ":\"300\""),
            valid.replacingOccurrences(of: USAppleFixtures.rawNonce, with: "short"),
            valid.replacingOccurrences(of: USAppleFixtures.state, with: USAppleFixtures.challengeID),
            valid.replacingOccurrences(of: USAppleFixtures.state, with: String(repeating: "A", count: 42) + "B")]
        for json in malformed {
            let transport = USAppleFixtureTransport([(json, 200)])
            do { _ = try await service(transport).challenge(); XCTFail("Invalid challenge") }
            catch { XCTAssertEqual(error as? USAppleClientError, .invalidResponse) }
        }
    }
    func testInvalidExchangeFieldsNeverDispatch() async throws {
        let transport = USAppleFixtureTransport(), service = try service(transport)
        for token in ["", " ", "bad\nvalue", "bad value", "非ASCII", String(repeating: "a", count: 16_385)] {
            do { _ = try await service.exchange(challengeId: USAppleFixtures.challengeID, state: USAppleFixtures.state, identityToken: token); XCTFail("Invalid token") }
            catch { XCTAssertEqual(error as? USAppleError, .invalidRequest) }
        }
        do { _ = try await service.exchange(challengeId: "bad", state: USAppleFixtures.state, identityToken: "fixture.jwt.token"); XCTFail("Invalid ID") }
        catch { XCTAssertEqual(error as? USAppleError, .invalidRequest) }
        do { _ = try await service.exchange(challengeId: USAppleFixtures.challengeID, state: "bad", identityToken: "fixture.jwt.token"); XCTFail("Invalid state") }
        catch { XCTAssertEqual(error as? USAppleError, .invalidRequest) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testExchangeRequiresUSSessionAndAllFiveSafeProfileFields() async throws {
        let valid = USAppleFixtures.successJSON
        for json in [valid.replacingOccurrences(of: "\"US\"", with: "\"CN\""),
            valid.replacingOccurrences(of: "synthetic-session", with: ""), valid.replacingOccurrences(of: "\"id\":7", with: "\"id\":0"),
            valid.replacingOccurrences(of: "\"userType\":1,", with: ""), valid.replacingOccurrences(of: "\"avatar\":\"\",", with: ""),
            valid.replacingOccurrences(of: "\"nickname\":\"Fixture\",", with: ""), valid.replacingOccurrences(of: ",\"role\":\"player\"", with: "")] {
            let transport = USAppleFixtureTransport([(json, 200)])
            do { _ = try await service(transport).exchange(challengeId: USAppleFixtures.challengeID, state: USAppleFixtures.state, identityToken: "fixture.jwt.token"); XCTFail("Invalid exchange") }
            catch { XCTAssertEqual(error as? USAppleClientError, .invalidResponse) }
        }
    }
    func testProfileDoesNotImportAdditionalEntityFieldsOrEmail() async throws {
        let json = USAppleFixtures.successJSON.replacingOccurrences(of: "\"id\":7", with: "\"id\":7,\"email\":\"relay@example.com\",\"xp\":9999,\"level\":99")
        let result = try await service(USAppleFixtureTransport([(json, 200)])).exchange(challengeId: USAppleFixtures.challengeID, state: USAppleFixtures.state, identityToken: "fixture.jwt.token")
        XCTAssertEqual(result.account.id, 7); XCTAssertEqual(result.account.xp, 0); XCTAssertEqual(result.account.level, 1)
    }
    func testExchangeAcceptsExplicitNullAvatarButRejectsWrongAvatarType() async throws {
        let valid = USAppleFixtures.successJSON.replacingOccurrences(of: "\"avatar\":\"\"", with: "\"avatar\":null")
        let accepted = try await service(USAppleFixtureTransport([(valid, 200)])).exchange(
            challengeId: USAppleFixtures.challengeID, state: USAppleFixtures.state, identityToken: "fixture.jwt.token")
        XCTAssertEqual(accepted.account.avatar, "")
        for avatar in ["7", "false", "[]", "{}"] {
            let json = valid.replacingOccurrences(of: "\"avatar\":null", with: "\"avatar\":\(avatar)")
            do { _ = try await service(USAppleFixtureTransport([(json, 200)])).exchange(
                challengeId: USAppleFixtures.challengeID, state: USAppleFixtures.state, identityToken: "fixture.jwt.token")
                XCTFail("Wrong avatar type")
            } catch { XCTAssertEqual(error as? USAppleClientError, .invalidResponse) }
        }
    }
    func testProtectedSessionUsesExactGETBearerAndNoRealmAccountOrBodyOverride() async throws {
        let transport = USAppleFixtureTransport([(USAppleFixtures.sessionJSON, 200)])
        let proof = try await service(transport).currentAccount(token: "synthetic-candidate")
        XCTAssertEqual(proof.market, .unitedStates); XCTAssertEqual(proof.realm, "fixture-US")
        XCTAssertEqual(proof.account.id, 7); XCTAssertEqual(proof.account.nickname, "Protected")
        XCTAssertEqual(proof.account.avatar, "")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://us.example.com/api/us/auth/session")
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody); XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-candidate")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }),
                       Set(["authorization", "accept", "cache-control", "pragma"]))
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }
    func testProtectedProfileOnlyImportsFiveFieldsAndAcceptsStringOrNullAvatar() async throws {
        for avatar in ["null", "\"avatar-reference\""] {
            let json = USAppleFixtures.sessionJSON.replacingOccurrences(of: "\"avatar\":null", with: "\"avatar\":\(avatar)")
                .replacingOccurrences(of: "\"id\":7", with: "\"id\":7,\"email\":\"relay@example.com\",\"xp\":500,\"level\":70")
            let proof = try await service(USAppleFixtureTransport([(json, 200)])).currentAccount(token: "synthetic-candidate")
            XCTAssertEqual(proof.account.xp, 0); XCTAssertEqual(proof.account.level, 1)
            XCTAssertEqual(proof.account.avatar, avatar == "null" ? "" : "avatar-reference")
        }
    }
    func testProtectedSessionRequiresExactServerMarketRealmAndAllSafeProfileKeys() async throws {
        let valid = USAppleFixtures.sessionJSON
        let replacements = [
            ("\"US\"", "\"CN\""), ("fixture-US", "wrong-realm"), ("fixture-US", ""),
            ("\"realm\":\"fixture-US\",", ""), ("\"market\":\"US\",", ""),
            ("\"id\":7", "\"id\":0"), ("\"id\":7", "\"id\":-7"), ("\"id\":7", "\"id\":\"7\""),
            ("\"id\":7,", ""), ("\"userType\":1,", ""), ("\"avatar\":null,", ""),
            ("\"nickname\":\"Protected\",", ""), (",\"role\":\"player\"", ""),
            ("\"avatar\":null", "\"avatar\":[]"), ("\"userType\":1", "\"userType\":null"),
            ("\"nickname\":\"Protected\"", "\"nickname\":null")
        ]
        for (old, new) in replacements {
            let json = valid.replacingOccurrences(of: old, with: new)
            do { _ = try await service(USAppleFixtureTransport([(json, 200)])).currentAccount(token: "synthetic-candidate"); XCTFail("Invalid proof") }
            catch { XCTAssertEqual(error as? USAppleClientError, .invalidResponse) }
        }
        for json in [#"{"code":200,"data":{"market":"US","realm":"fixture-US","account":null}}"#,
                     #"{"code":200,"data":{"market":"US","realm":"fixture-US","account":[]}}"#] {
            do { _ = try await service(USAppleFixtureTransport([(json, 200)])).currentAccount(token: "synthetic-candidate"); XCTFail("Invalid account shape") }
            catch { XCTAssertEqual(error as? USAppleClientError, .invalidResponse) }
        }
    }
    func testProtectedSessionRejectsGenericAndNamed401WithoutRetry() async throws {
        for json in [#"{"code":401,"msg":"generic authentication failure"}"#,
                     #"{"code":401,"errorCode":"US_SESSION_INVALID"}"#, "", "<html>Unauthorized</html>"] {
            let transport = USAppleFixtureTransport([(json, 401)])
            do { _ = try await service(transport).currentAccount(token: "synthetic-candidate"); XCTFail("401 never proves a session") }
            catch { XCTAssertEqual(error as? USAppleError, .invalidIdentity) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testProtectedSessionRejectsBothDocumented503SourcesWithoutRetry() async throws {
        for errorCode in ["US_SESSION_UNAVAILABLE", "US_APPLE_UNAVAILABLE"] {
            let json = "{\"code\":503,\"errorCode\":\"\(errorCode)\"}"
            let transport = USAppleFixtureTransport([(json, 503)])
            do { _ = try await service(transport).currentAccount(token: "synthetic-candidate"); XCTFail("Unavailable proof") }
            catch { XCTAssertEqual(error as? USAppleError, .unavailable) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testProtectedSessionRejectsUnexpectedStatusCodeAndEnvelope() async throws {
        for (json, status) in [(USAppleFixtures.sessionJSON, 201), (USAppleFixtures.sessionJSON, 302),
            ("{}", 404), ("<html>login</html>", 200), (#"{"code":503,"errorCode":"US_SESSION_UNAVAILABLE"}"#, 200),
            (#"{"code":200,"errorCode":"US_SESSION_INVALID","data":{}}"#, 200),
            (#"{"code":503,"errorCode":"UNKNOWN"}"#, 503), (#"{"code":200}"#, 503),
            (#"{"code":500,"errorCode":"US_SESSION_UNAVAILABLE"}"#, 500)] {
            let transport = USAppleFixtureTransport([(json, status)])
            do { _ = try await service(transport).currentAccount(token: "synthetic-candidate"); XCTFail("Invalid response") }
            catch { XCTAssertEqual(error as? USAppleClientError, .invalidResponse) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testProtectedSessionRejectsInvalidCandidateBeforeDispatch() async throws {
        let transport = USAppleFixtureTransport(), adapter = try service(transport)
        for token in ["", " ", "bad value", "bad\r\nheader", "非ASCII", String(repeating: "x", count: 16_385)] {
            do { _ = try await adapter.currentAccount(token: token); XCTFail("Invalid candidate") }
            catch { XCTAssertEqual(error as? USAppleError, .invalidRequest) }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testProtectedSessionRejectsOversizedResponseAndNetworkFailureWithoutRetry() async throws {
        let oversized = USAppleFixtureTransport([(String(repeating: " ", count: 65_537), 200)])
        do { _ = try await service(oversized).currentAccount(token: "synthetic-candidate"); XCTFail("Oversized proof") }
        catch { XCTAssertEqual(error as? USAppleClientError, .invalidResponse) }
        let offline = USAppleFixtureTransport()
        do { _ = try await service(offline).currentAccount(token: "synthetic-candidate"); XCTFail("Network failure") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(oversized.requests.count, 1); XCTAssertEqual(offline.requests.count, 1)
    }
    func testProtectedSessionDiscardsResponseAfterTaskCancellation() async throws {
        let transport = USAppleFixtureTransport([(USAppleFixtures.sessionJSON, 200)]), adapter = try service(transport)
        var continuation: CheckedContinuation<Void, Never>?
        transport.afterRequest = { await withCheckedContinuation { continuation = $0 } }
        let task = Task { try await adapter.currentAccount(token: "synthetic-candidate") }
        for _ in 0..<1_000 { if continuation != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(continuation)
        task.cancel(); pending.resume()
        do { _ = try await task.value; XCTFail("Cancelled proof must be discarded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testConcreteProofAdapterRunsBeforeCommitAndCoordinatorStillMatchesAccountID() async throws {
        for protectedID in [7, 8] {
            let json = USAppleFixtures.sessionJSON.replacingOccurrences(of: "\"id\":7", with: "\"id\":\(protectedID)")
            let transport = USAppleFixtureTransport([(USAppleFixtures.challengeJSON, 200),
                (USAppleFixtures.successJSON, 200), (json, 200)])
            let adapter = try service(transport)
            var commits: [LoginResult] = []
            let snapshot = USAppleSessionSnapshot(epoch: 1, market: .unitedStates, realm: "fixture-US", accountID: nil)
            let coordinator = USAppleCoordinator(offlineDeployment: try USAppleFixtures.deployment(), service: adapter,
                authorizer: USAppleSessionProofAuthorizer(), currentSession: { snapshot },
                verifyCurrentAccount: adapter.currentAccount,
                commitLogin: { result, expected in
                    XCTAssertEqual(expected, snapshot)
                    XCTAssertEqual(transport.requests.count, 3)
                    commits.append(result); return true
                }, now: { 100 }, nonceDigest: { _ in USAppleFixtures.digest })
            await coordinator.signIn()
            XCTAssertEqual(transport.requests.map { $0.httpMethod }, ["POST", "POST", "GET"])
            XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-session")
            XCTAssertEqual(commits.count, protectedID == 7 ? 1 : 0)
            if protectedID == 7 { XCTAssertEqual(commits.first?.account.nickname, "Protected") }
            else { XCTAssertEqual(coordinator.state.issue, .invalidResponse) }
        }
    }
    func testSHA256UsesLowercaseHexNotRawOrBase64() throws {
        #if canImport(CryptoKit)
        XCTAssertEqual(try USAppleValidation.nonceDigest("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try USAppleValidation.nonceDigest(USAppleFixtures.rawNonce), USAppleFixtures.digest)
        #else
        XCTAssertThrowsError(try USAppleValidation.nonceDigest("abc"))
        #endif
    }
}

#endif

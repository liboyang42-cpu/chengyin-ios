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
    init(_ responses: [(String, Int)] = []) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        let response = responses.removeFirst()
        return (Data(response.0.utf8), response.1)
    }
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

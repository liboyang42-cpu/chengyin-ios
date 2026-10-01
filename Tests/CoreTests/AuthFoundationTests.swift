import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class AuthFoundationTests: XCTestCase {
    func config() throws -> APIConfiguration { try APIConfiguration(baseURL: URL(string:"https://api.example.com/prod-api")!) }
    func testGatewayPrefixIsPreserved() throws {
        XCTAssertEqual(try config().url(for:.password).absoluteString,"https://api.example.com/prod-api/api/login")
    }
    func testConfigurationRejectsInsecurePlaceholderAndCredentialURLs() {
        for value in ["http://api.example.com", "https://api.example.invalid", "https://user:pass@example.com", "https://example.com?token=x", "https://example.com#fragment"] {
            XCTAssertThrowsError(try APIConfiguration(baseURL:URL(string:value)!))
        }
    }
    func testMultipartAndRawAuthorizationMatchExistingClient() throws {
        let request=try AuthRequestBuilder(configuration:config()).make(.password,fields:["username":"测试","password":"a&b"],token:"fixture-token",boundary:"TEST-BOUNDARY")
        XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"fixture-token")
        XCTAssertEqual(request.httpMethod,"POST")
        let body=String(data:request.httpBody!,encoding:.utf8)!
        XCTAssertTrue(body.contains("name=\"username\"\r\n\r\n测试\r\n"))
        XCTAssertTrue(body.hasSuffix("--TEST-BOUNDARY--\r\n"))
        XCTAssertTrue(body.contains("a&b"))
    }
    func testMultipartRejectsHeaderInjectionAndBoundaryCollision() throws {
        let builder=try AuthRequestBuilder(configuration:config())
        XCTAssertThrowsError(try builder.make(.password,fields:["bad\r\nheader":"value"]))
        XCTAssertThrowsError(try builder.make(.password,fields:["password":"BOUNDARY"],boundary:"BOUNDARY"))
        XCTAssertThrowsError(try builder.make(.userInfo,token:"bad\r\nheader"))
    }
    func testUserInfoDoesNotGainMultipartBody() throws {
        let request=try AuthRequestBuilder(configuration:config()).make(.userInfo,token:"fixture")
        XCTAssertNil(request.httpBody)
    }
    func testBothAccountShapesAndRoleFallback() throws {
        let a=try JSONDecoder().decode(Account.self,from:Data(#"{"id":7,"nickname":"Player","role":"player","userType":2}"#.utf8))
        XCTAssertEqual(a.effectiveRole,"player")
        let b=try JSONDecoder().decode(Account.self,from:Data(#"{"userId":8,"nickName":"Merchant","userType":"2"}"#.utf8))
        XCTAssertEqual(b.id,8);XCTAssertEqual(b.nickname,"Merchant");XCTAssertEqual(b.effectiveRole,"merchant")
    }
    func testSessionEpochRejectsOldCompletion() {
        var epoch=SessionEpoch();let old=epoch.advance();XCTAssertTrue(epoch.isCurrent(old))
        let latest=epoch.advance();XCTAssertFalse(epoch.isCurrent(old));XCTAssertTrue(epoch.isCurrent(latest))
    }
}

private struct FixtureTransport: HTTPTransport {
    let json: String
    let status: Int
    func send(_ request: URLRequest) async throws -> (Data,Int) { (Data(json.utf8),status) }
}
final class AuthServiceTests: XCTestCase {
    func service(_ json:String,status:Int=200) throws -> AuthService {
        try AuthService(configuration:APIConfiguration(baseURL:URL(string:"https://api.example.com/prod-api")!),transport:FixtureTransport(json:json,status:status))
    }
    func testLoginParsesTokenAndAccount() async throws {
        let api=try service(#"{"code":200,"token":"fixture-only","data":{"id":4,"nickname":"A"}}"#)
        let result=try await api.login(username:"a",password:"fixture-password")
        XCTAssertEqual(result.account.id,4);XCTAssertEqual(result.token,"fixture-only")
    }
    func testUserInfoUsesAppUserShape() async throws {
        let api=try service(#"{"code":200,"appUser":{"userId":5,"nickName":"B"}}"#)
        let account=try await api.currentAccount(token:"fixture-only");XCTAssertEqual(account.id,5)
    }
    func testMalformedAndEmptyLoginResponsesAreRejected() async throws {
        for json in [#"{"code":200}"#, #"{"code":200,"token":" ","data":{"id":4}}"#, #"{"code":200,"token":"fixture","data":{"id":0}}"#, "not-json"] {
            do { _=try await service(json).login(username:"a",password:"b");XCTFail("Must reject malformed response") }
            catch { XCTAssertEqual(error as? APIError,.malformedResponse) }
        }
    }
    func testUnauthorizedIsDistinctFromNetworkOrServerFailure() async throws {
        for pair in [(401,APIError.unauthorized),(503,APIError.httpStatus(503))] {
            do { _=try await service("{}",status:pair.0).currentAccount(token:"fixture");XCTFail("Must fail") }
            catch { XCTAssertEqual(error as? APIError,pair.1) }
        }
    }
    func testBusinessFailureDoesNotExposeRawServerMessage() async throws {
        do { _=try await service(#"{"code":500,"msg":"internal details"}"#).login(username:"a",password:"b");XCTFail("Must fail") }
        catch { XCTAssertEqual(error as? APIError,.businessCode(500)) }
    }
}

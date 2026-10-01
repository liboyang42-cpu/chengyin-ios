import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class AuthChannelFixtureTransport: HTTPTransport {
    var responses: [(String, Int)]
    var requests: [URLRequest] = []
    init(_ responses: [(String, Int)]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let next = responses.removeFirst()
        return (Data(next.0.utf8), next.1)
    }
}

@MainActor
final class AuthChannelServiceTests: XCTestCase {
    private let success = #"{"code":200,"token":"synthetic-token","data":{"id":7,"nickname":"Fixture"}}"#
    private func service(_ transport: AuthChannelFixtureTransport) throws -> AuthChannelService {
        try AuthChannelService(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.com/gateway")!), transport: transport)
    }
    func testSMSPhoneAppleAndCurrentAccountUseExistingRoutesAndShapes() async throws {
        let transport = AuthChannelFixtureTransport([
            (#"{"code":200,"data":{"unrelated":true}}"#, 200), (success, 200), (success, 200),
            (#"{"code":200,"appUser":{"userId":7,"nickName":"Updated","userType":2}}"#, 200)
        ])
        let service = try service(transport)
        try await service.sendSMSCode(phone: " 10000000000 ")
        let phone = try await service.loginWithPhone(phone: "10000000000", code: " 123456 ")
        let apple = try await service.loginWithApple(identityToken: "synthetic.apple.token")
        let current = try await service.currentAccount(token: apple.token)
        XCTAssertEqual(phone.account.id, 7); XCTAssertEqual(apple.token, "synthetic-token")
        XCTAssertEqual(current.nickname, "Updated"); XCTAssertEqual(current.effectiveRole, "merchant")
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/gateway/api/sms/send", "/gateway/api/login/phone", "/gateway/api/login/apple", "/gateway/api/userInfo"])
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "POST" })
        for request in transport.requests.prefix(3) {
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        }
        let smsBody = String(data: transport.requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(smsBody.contains("name=\"phone\"\r\n\r\n10000000000\r\n"))
        XCTAssertFalse(smsBody.contains("code"))
        let phoneBody = String(data: transport.requests[1].httpBody!, encoding: .utf8)!
        XCTAssertTrue(phoneBody.contains("name=\"code\"\r\n\r\n123456\r\n"))
        let appleBody = String(data: transport.requests[2].httpBody!, encoding: .utf8)!
        XCTAssertTrue(appleBody.contains("name=\"identityToken\"\r\n\r\nsynthetic.apple.token\r\n"))
        XCTAssertFalse(appleBody.contains("name=\"email\""))
        XCTAssertEqual(transport.requests[3].value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        XCTAssertNil(transport.requests[3].httpBody)
    }
    func testInvalidPhoneAndCodeNeverDispatch() async throws {
        let transport = AuthChannelFixtureTransport([]), service = try service(transport)
        for phone in ["", "1000000000", "100000000000", "+8610000000000", "１0000000000", "1000000000x", "1000\n000000"] {
            do { try await service.sendSMSCode(phone: phone); XCTFail("Invalid phone must fail") }
            catch { XCTAssertEqual(error as? AuthChannelError, .invalidPhone) }
        }
        for code in ["", "1234567", "１２３", "12 3", "12\n3", "a123"] {
            do { _ = try await service.loginWithPhone(phone: "10000000000", code: code); XCTFail("Invalid code must fail") }
            catch { XCTAssertEqual(error as? AuthChannelError, .invalidCode) }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testInvalidAppleCredentialNeverDispatches() async throws {
        let transport = AuthChannelFixtureTransport([]), service = try service(transport)
        for token in ["", " ", "bad\r\ncredential", "bad\tcredential", "bad\0credential", "非ASCII"] {
            do { _ = try await service.loginWithApple(identityToken: token); XCTFail("Invalid credential must fail") }
            catch { XCTAssertEqual(error as? AuthChannelError, .invalidAppleCredential) }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testMalformedLoginNeverCreatesResult() async throws {
        for json in [#"{"code":200}"#, #"{"code":200,"token":"token","data":{"id":0}}"#,
                     #"{"code":200,"token":" ","data":{"id":7}}"#,
                     #"{"code":200,"token":"bad\nheader","data":{"id":7}}"#,
                     #"{"code":200,"token":"token","data":[]}"#, "not-json"] {
            let transport = AuthChannelFixtureTransport([(json, 200)])
            do { _ = try await service(transport).loginWithPhone(phone: "10000000000", code: "123456"); XCTFail("Malformed login must fail") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testHTTPAndBusinessRateLimitsNeverRetry() async throws {
        for response in [("{}", 429), (#"{"code":429,"msg":"arbitrary private details"}"#, 200)] {
            let transport = AuthChannelFixtureTransport([response])
            do { try await service(transport).sendSMSCode(phone: "10000000000"); XCTFail("Must fail") }
            catch { XCTAssertEqual(error as? AuthChannelError, .rateLimited) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testBusinessAndHTTPFailuresKeepStructuredCodesWithoutRawMessage() async throws {
        for (response, expected) in [((#"{"code":500,"msg":"private server internals"}"#, 200), APIError.businessCode(500)),
                                    ((#"{"code":401}"#, 200), APIError.unauthorized),
                                    (("{}", 401), APIError.unauthorized), (("{}", 503), APIError.httpStatus(503)),
                                    (("<html>error</html>", 200), APIError.malformedResponse)] {
            let transport = AuthChannelFixtureTransport([response])
            do { try await service(transport).sendSMSCode(phone: "10000000000"); XCTFail("Must fail") }
            catch { XCTAssertEqual(error as? APIError, expected) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testAlreadyCancelledTaskNeverDispatches() async throws {
        let transport = AuthChannelFixtureTransport([]), service = try service(transport)
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { try await service.sendSMSCode(phone: "10000000000"); return false }
            catch { return error is CancellationError }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled); XCTAssertTrue(transport.requests.isEmpty)
    }
}

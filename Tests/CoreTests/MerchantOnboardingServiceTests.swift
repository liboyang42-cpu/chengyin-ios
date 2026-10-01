import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MerchantOnboardingServiceTests: XCTestCase {
    private func service(_ transport: MerchantOnboardingTransport) throws -> MerchantOnboardingService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://api.example.test")!), transport: transport)
    }
    func testApplicationReadIsEmptyMultipartAndExplicitNoneOnly() async throws {
        let transport = MerchantOnboardingTransport(body: #"{"code":200,"data":null,"applicationState":"NONE"}"#)
        let result = try await service(transport).application(token: "test-token")
        XCTAssertEqual(result, .none)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/merchant/info"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertEqual(request.timeoutInterval, 20)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertFalse(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("name=") == true)
    }
    func testExplicitNoneAcceptsNullEmptyOrMissingButNotMalformedRows() async throws {
        for body in [#"{"code":200,"applicationState":"NONE"}"#, #"{"code":200,"data":{},"applicationState":"NONE"}"#] {
            let result = try await service(.init(body: body)).application(token: "token")
            XCTAssertEqual(result, .none)
        }
        for body in [#"{"code":200,"data":null}"#, #"{"code":200,"data":{},"applicationState":"PENDING"}"#,
                     #"{"code":200,"data":[],"applicationState":"NONE"}"#,
                     #"{"code":200,"data":{"id":0},"applicationState":"NONE"}"#,
                     #"{"code":200,"data":{"id":1,"status":0}}"#] {
            do { _ = try await service(.init(body: body)).application(token: "token"); XCTFail("Malformed state became no application") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testApplicationReadPreservesRejectedAndDisabledReasons() async throws {
        let transport = MerchantOnboardingTransport(body: #"{"code":200,"data":{"id":"17","status":2,"accountStatus":2,"reson":"Old rejection","disableReason":"Platform pause"}}"#)
        let result = try await service(transport).application(token: "token")
        guard case .application(let application) = result else { return XCTFail("Expected application") }
        XCTAssertEqual(application.rejectReason, "Old rejection"); XCTAssertEqual(application.displayedReason, "Platform pause")
        XCTAssertFalse(application.canReapply)
    }
    func testIdentityReadsActualBooleanAndNeverReturnsFalseForUnknownFailures() async throws {
        for registered in [true, false] {
            let transport = MerchantOnboardingTransport(body: "{\"code\":200,\"data\":{\"registered\":\(registered)}}")
            let result = try await service(transport).identityRegistered(token: "token")
            XCTAssertEqual(result, registered)
            let request = try XCTUnwrap(transport.requests.first)
            XCTAssertEqual(request.url?.path, "/api/publisher/identity/status")
            XCTAssertEqual(String(data: request.httpBody ?? Data(), encoding: .utf8), "{}")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        }
        for body in [#"{"code":200,"data":{}}"#, #"{"code":200,"data":{"registered":"true"}}"#, #"{"code":500}"#] {
            do { _ = try await service(.init(body: body)).identityRegistered(token: "token"); XCTFail("Unknown identity must throw") }
            catch { }
        }
    }
    func testSubmitExactJSONAcknowledgementNeverInventsApproval() async throws {
        let transport = MerchantOnboardingTransport(body: #"{"code":200}"#)
        try await service(transport).submit(makeMerchantOnboardingDraft(), token: "token")
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/merchant/merchant_registration")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(fields["name"] as? String, "Example Store")
        XCTAssertEqual(fields["businessLicense"] as? String, "https://fixtures.example/license.jpg")
        XCTAssertNil(fields["status"]); XCTAssertNil(fields["accountStatus"]); XCTAssertNil(fields["roleCode"])
    }
    func testSubmitPreflightInvalidTokenAndMissingFieldsSendNothing() async throws {
        let transport = MerchantOnboardingTransport(body: #"{"code":200}"#)
        do { try await service(transport).submit(makeMerchantOnboardingDraft(), token: "bad\r\nheader"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOnboardingWriteError, .notSent) }
        do { try await service(transport).submit(.init(), token: "token"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOnboardingWriteError, .notSent) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testUploadMultipartUsesOnlyFileAndTopLevelURL() async throws {
        let transport = MerchantOnboardingTransport(body: #"{"code":200,"url":"https://fixtures.example/upload.jpg"}"#)
        let image = try MerchantOnboardingImage(jpegData: Data([0xff, 0xd8, 0xff, 0xd9]))
        let receipt = try await service(transport).uploadLicense(image, token: "token")
        XCTAssertEqual(receipt.url, "https://fixtures.example/upload.jpg")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/common/uploadOSS")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertNotNil(body.range(of: image.data))
        XCTAssertNotNil(body.range(of: Data("name=\"file\"; filename=\"business-license.jpg\"".utf8)))
        XCTAssertNil(body.range(of: Data("bizType".utf8)))
        XCTAssertNil(body.range(of: Data("COMMUNITY_POST".utf8)))
        XCTAssertNil(body.range(of: Data("token".utf8)))
    }
    func testMissingOrUnsafeUploadURLNeverCreatesLicense() async throws {
        for body in [#"{"code":200}"#, #"{"code":200,"url":null}"#, #"{"code":200,"data":{"url":"https://fixtures.example/a"}}"#,
                     #"{"code":200,"url":"file:///private/a"}"#] {
            let transport = MerchantOnboardingTransport(body: body)
            do {
                _ = try await service(transport).uploadLicense(.init(jpegData: Data([0xff, 0xd8, 0xff])), token: "token")
                XCTFail("Missing/unsafe URL accepted")
            } catch { XCTAssertEqual(error as? MerchantOnboardingWriteError, .outcomeUnknown) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testBusinessRejectionPreservesMessageAndUnknownOutcomesNeverRetry() async throws {
        let rejected = MerchantOnboardingTransport(body: #"{"code":409,"msg":"Server-only eligibility conflict"}"#)
        do { try await service(rejected).submit(makeMerchantOnboardingDraft(), token: "token"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOnboardingWriteError, .rejected(.init(code: 409, message: "Server-only eligibility conflict"))) }
        let unknowns = [MerchantOnboardingTransport(body: "not JSON"), MerchantOnboardingTransport(body: "{}"),
                        MerchantOnboardingTransport(body: #"{"code":200}"#, status: 500), MerchantOnboardingTransport(failure: URLError(.timedOut))]
        for transport in unknowns {
            do { try await service(transport).submit(makeMerchantOnboardingDraft(), token: "token"); XCTFail() }
            catch { XCTAssertEqual(error as? MerchantOnboardingWriteError, .outcomeUnknown) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testUnauthorizedAndForbiddenAreExplicitRejections() async throws {
        for code in [401, 403] {
            let transport = MerchantOnboardingTransport(body: "{\"code\":\(code)}", status: code)
            do { try await service(transport).submit(makeMerchantOnboardingDraft(), token: "token"); XCTFail() }
            catch { XCTAssertEqual(error as? MerchantOnboardingWriteError, .rejected(.init(code: code))) }
        }
        do { _ = try await service(.init(body: #"{"code":401}"#)).application(token: "token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
}

final class MerchantOnboardingTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var data: Data
    var status: Int
    var failure: Error?
    var onSend: (() -> Void)?
    var continuation: CheckedContinuation<(Data, Int), Error>?
    var suspended = false
    init(body: String = "{}", status: Int = 200, failure: Error? = nil) {
        data = Data(body.utf8); self.status = status; self.failure = failure
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onSend?()
        if suspended { return try await withCheckedThrowingContinuation { continuation = $0 } }
        if let failure { throw failure }
        return (data, status)
    }
    func resume(body: String, status: Int = 200) { continuation?.resume(returning: (Data(body.utf8), status)); continuation = nil }
}

import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic only: records requests and never opens a URLSession or socket.
private final class RegistrationFixtureTransport: HTTPTransport {
    var json: String
    var status: Int
    var error: Error?
    private(set) var requests: [URLRequest] = []

    init(_ json: String = "{}", status: Int = 200, error: Error? = nil) {
        self.json = json
        self.status = status
        self.error = error
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if let error { throw error }
        return (Data(json.utf8), status)
    }
}

final class RegistrationServiceTests: XCTestCase {
    private let quoteJSON = #"{"code":200,"data":{"payAmount":19.99,"quoteSign":" fixture/opaque-signature+= "}}"#
    private let createJSON = #"{"code":200,"data":{"registrationId":41,"registrationNo":"fixture-order","payableAmount":19.99}}"#

    private func service(_ transport: RegistrationFixtureTransport) throws -> RegistrationService {
        try RegistrationService(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.example.com/prod-api")!),
            transport: transport
        )
    }

    private func intent(appPay: Bool = true, includeOptionalFields: Bool = true) throws -> RegistrationCreateIntent {
        let quote = try JSONDecoder().decode(RegistrationQuoteResponse.self, from: Data(quoteJSON.utf8)).data
        let selection = try RegistrationQuoteRequest(ownerID: 7, ticketID: includeOptionalFields ? 11 : nil,
                                                    usePoints: includeOptionalFields)
        return try RegistrationCreateIntent(
            selection: selection, quote: quote, realName: "Fixture & Participant", phone: "fixture-phone",
            email: includeOptionalFields ? "fixture@example.invalid" : "",
            participateDate: includeOptionalFields ? "2026-10-01" : "",
            usesAppPaymentChannel: appPay, requestID: "fixture-retained-intent",
            waitlistOffer: includeOptionalFields
                ? RegistrationWaitlistOffer(id: 19, token: " fixture/opaque-offer+= ") : nil
        )
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func assertRequest(_ request: URLRequest, path: String, contentType: String = "application/json",
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/prod-api/\(path)", file: file, line: line)
        XCTAssertEqual(request.httpMethod, "POST", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-raw-token", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), contentType, file: file, line: line)
        XCTAssertEqual(request.timeoutInterval, 20, file: file, line: line)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData, file: file, line: line)
        XCTAssertNil(request.url?.query, file: file, line: line)
    }

    func testQuoteUsesExactJSONSelectionAndRawAuthorization() async throws {
        let transport = RegistrationFixtureTransport(quoteJSON)
        let selection = try RegistrationQuoteRequest(ownerID: 7, ticketID: 11, usePoints: true)
        let quote = try await service(transport).quote(selection, token: "fixture-raw-token")
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        assertRequest(request, path: "api/registration/quote")
        let body = try jsonBody(request)
        XCTAssertEqual(Set(body.keys), Set(["ownerType", "ownerId", "ticketId", "isUsePoint"]))
        XCTAssertEqual(body["ownerType"] as? Int, 2)
        XCTAssertEqual(body["ownerId"] as? Int, 7)
        XCTAssertEqual(body["ticketId"] as? Int, 11)
        XCTAssertEqual(body["isUsePoint"] as? Int, 1)
        XCTAssertEqual(quote.payAmount, Decimal(string: "19.99"))
        XCTAssertEqual(quote.quoteSign, " fixture/opaque-signature+= ")
    }

    func testQuoteOmitsUnselectedTicketAndKeepsPointsAsIntegerZero() async throws {
        let transport = RegistrationFixtureTransport(quoteJSON)
        _ = try await service(transport).quote(RegistrationQuoteRequest(ownerID: 7), token: "fixture-raw-token")
        let body = try jsonBody(XCTUnwrap(transport.requests.first))
        XCTAssertEqual(Set(body.keys), Set(["ownerType", "ownerId", "isUsePoint"]))
        XCTAssertEqual(body["isUsePoint"] as? Int, 0)
    }

    func testCreateUsesExactSourceJSONAndPreservesOpaqueValues() async throws {
        let transport = RegistrationFixtureTransport(createJSON)
        let result = try await service(transport).create(intent(), token: "fixture-raw-token")
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        assertRequest(request, path: "api/registration/create")
        let body = try jsonBody(request)
        XCTAssertEqual(Set(body.keys), Set([
            "ownerType", "ownerId", "ticketId", "isUsePoint", "realName", "phone", "email",
            "participateDate", "payChannel", "requestId", "quoteSign", "waitlistOfferId", "waitlistOfferToken"
        ]))
        XCTAssertEqual(body["ownerType"] as? Int, 2)
        XCTAssertEqual(body["ownerId"] as? Int, 7)
        XCTAssertEqual(body["ticketId"] as? Int, 11)
        XCTAssertEqual(body["isUsePoint"] as? Int, 1)
        XCTAssertEqual(body["realName"] as? String, "Fixture & Participant")
        XCTAssertEqual(body["phone"] as? String, "fixture-phone")
        XCTAssertEqual(body["email"] as? String, "fixture@example.invalid")
        XCTAssertEqual(body["participateDate"] as? String, "2026-10-01")
        XCTAssertEqual(body["payChannel"] as? String, "APP")
        XCTAssertEqual(body["requestId"] as? String, "fixture-retained-intent")
        XCTAssertEqual(body["quoteSign"] as? String, " fixture/opaque-signature+= ")
        XCTAssertEqual(body["waitlistOfferId"] as? Int, 19)
        XCTAssertEqual(body["waitlistOfferToken"] as? String, " fixture/opaque-offer+= ")
        XCTAssertEqual(result.registrationID, 41)
        XCTAssertEqual(result.registrationNo, "fixture-order")
        XCTAssertEqual(result.payableAmount, Decimal(string: "19.99"))
        XCTAssertFalse(result.hasPaymentParameters)
    }

    func testCreateOmitsOptionalFieldsAndDisabledAppChannel() async throws {
        let transport = RegistrationFixtureTransport(createJSON)
        _ = try await service(transport).create(intent(appPay: false, includeOptionalFields: false), token: "fixture-raw-token")
        let body = try jsonBody(XCTUnwrap(transport.requests.first))
        XCTAssertEqual(Set(body.keys), Set(["ownerType", "ownerId", "isUsePoint", "realName", "phone", "quoteSign", "requestId"]))
        XCTAssertEqual(body["isUsePoint"] as? Int, 0)
    }

    func testExplicitRepeatedCreatePreservesIntentIDAndEntireBody() async throws {
        let transport = RegistrationFixtureTransport(createJSON)
        let api = try service(transport)
        let retained = try intent()
        _ = try await api.create(retained, token: "fixture-raw-token")
        _ = try await api.create(retained, token: "fixture-raw-token")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].httpBody, transport.requests[1].httpBody)
        XCTAssertEqual(try jsonBody(transport.requests[1])["requestId"] as? String, retained.requestID)
    }

    func testCreateTimeoutDoesNotRetryRequoteOrRotateRequestID() async throws {
        let transport = RegistrationFixtureTransport(error: URLError(.timedOut))
        let api = try service(transport)
        let retained = try intent()
        do {
            _ = try await api.create(retained, token: "fixture-raw-token")
            XCTFail("Expected original timeout")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(transport.requests.count, 1)
        let failedBody = try XCTUnwrap(transport.requests.first?.httpBody)
        transport.error = nil
        transport.json = createJSON
        // A separate, explicit caller invocation, never an automatic service retry.
        _ = try await api.create(retained, token: "fixture-raw-token")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[1].httpBody, failedBody)
    }

    func testTransportCancellationIsPreservedAndNotRetried() async throws {
        let transport = RegistrationFixtureTransport(error: CancellationError())
        do {
            _ = try await service(transport).create(intent(), token: "fixture-raw-token")
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testInvalidTokensNeverReachTransportForAnyOperation() async throws {
        for token in ["", " \n ", "bad\r\nheader", "bad\theader", "bad\0header", "非ASCII"] {
            let transport = RegistrationFixtureTransport()
            let api = try service(transport)
            let selection = try RegistrationQuoteRequest(ownerID: 7)
            let retained = try intent()
            do { _ = try await api.quote(selection, token: token); XCTFail("Expected invalid token") }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
            do { _ = try await api.create(retained, token: token); XCTFail("Expected invalid token") }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
            do { _ = try await api.readStatus(registrationID: 41, token: token); XCTFail("Expected invalid token") }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testQuoteBusinessFailureKeepsServerMessage() async throws {
        let transport = RegistrationFixtureTransport(#"{"code":409,"msg":"价格已更新"}"#)
        do {
            _ = try await service(transport).quote(RegistrationQuoteRequest(ownerID: 7), token: "fixture-raw-token")
            XCTFail("Expected business failure")
        } catch {
            XCTAssertEqual(error as? RegistrationResponseFailure, RegistrationResponseFailure(code: 409, message: "价格已更新"))
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testCreateBusinessFailuresKeepNumericAndStringCodesWithoutRetry() async throws {
        for code in ["401", "409", #""409""#, "410"] {
            let transport = RegistrationFixtureTransport("{\"code\":\(code),\"msg\":\"fixture server message\"}")
            do {
                _ = try await service(transport).create(intent(), token: "fixture-raw-token")
                XCTFail("Expected business failure")
            } catch {
                let failure = try XCTUnwrap(error as? RegistrationResponseFailure)
                XCTAssertEqual(failure.code, Int(code.replacingOccurrences(of: "\"", with: "")))
                XCTAssertEqual(failure.message, "fixture server message")
                XCTAssertTrue(failure.hasServerMessage)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testBusinessFailurePreservesMissingEmptyAndOpaqueMessages() async throws {
        for (json, message) in [
            (#"{"code":410}"#, nil),
            (#"{"code":410,"msg":""}"#, ""),
            (#"{"code":410,"msg":"  fixture message\n "}"#, "  fixture message\n "),
            (#"{"code":410,"msg":42}"#, nil)
        ] as [(String, String?)] {
            let transport = RegistrationFixtureTransport(json)
            do {
                _ = try await service(transport).create(intent(), token: "fixture-raw-token")
                XCTFail("Expected business failure")
            } catch {
                let failure = try XCTUnwrap(error as? RegistrationResponseFailure)
                XCTAssertEqual(failure.code, 410)
                XCTAssertEqual(failure.message, message)
                XCTAssertEqual(failure.hasServerMessage, message != nil)
            }
        }
    }

    func testHTTPFailureRetainsStatusAndEnvelopeEvenForUnauthorized() async throws {
        for status in [401, 403, 409, 410, 429, 503] {
            let transport = RegistrationFixtureTransport(#"{"code":"409","msg":"fixture conflict","data":[]}"#, status: status)
            do {
                _ = try await service(transport).create(intent(), token: "fixture-raw-token")
                XCTFail("Expected HTTP failure")
            } catch {
                let failure = try XCTUnwrap(error as? RegistrationHTTPFailure)
                XCTAssertEqual(failure.statusCode, status)
                XCTAssertEqual(failure.response, RegistrationResponseFailure(code: 409, message: "fixture conflict"))
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testHTTPFailureWithoutValidEnvelopeStillKeepsStatus() async throws {
        for json in ["", "<html>service unavailable</html>", "[]", "{}", #"{"code":null,"msg":null}"#] {
            let transport = RegistrationFixtureTransport(json, status: 503)
            do {
                _ = try await service(transport).quote(RegistrationQuoteRequest(ownerID: 7), token: "fixture-raw-token")
                XCTFail("Expected HTTP failure")
            } catch {
                let failure = try XCTUnwrap(error as? RegistrationHTTPFailure)
                XCTAssertEqual(failure.statusCode, 503)
                XCTAssertNil(failure.response)
            }
        }
    }

    func testHTTPFailureKeepsMessageWhenBusinessCodeIsUnrecognized() async throws {
        let transport = RegistrationFixtureTransport(#"{"code":"FUTURE_CODE","msg":"fixture detail"}"#, status: 422)
        do {
            _ = try await service(transport).create(intent(), token: "fixture-raw-token")
            XCTFail("Expected HTTP failure")
        } catch {
            let failure = try XCTUnwrap(error as? RegistrationHTTPFailure)
            XCTAssertEqual(failure.statusCode, 422)
            XCTAssertEqual(failure.response, RegistrationResponseFailure(code: nil, message: "fixture detail"))
        }
    }

    func testRedirectStatusesFailWithoutFollowingOrRetrying() async throws {
        for status in [301, 302, 303, 307, 308] {
            let transport = RegistrationFixtureTransport(createJSON, status: status)
            do {
                _ = try await service(transport).create(intent(), token: "fixture-raw-token")
                XCTFail("Redirect must not become success")
            } catch {
                XCTAssertEqual((error as? RegistrationHTTPFailure)?.statusCode, status)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testMalformedQuoteSuccessNeverFabricatesAUsableQuote() async throws {
        for json in ["not-json", "[]", #"{"code":200}"#, #"{"code":200,"data":null}"#,
                     #"{"code":200,"data":[]}"#, #"{"code":200,"data":{"payAmount":-1}}"#] {
            let transport = RegistrationFixtureTransport(json)
            do {
                _ = try await service(transport).quote(RegistrationQuoteRequest(ownerID: 7), token: "fixture-raw-token")
                XCTFail("Expected malformed response")
            } catch {
                XCTAssertEqual(error as? APIError, .malformedResponse)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testIncompleteQuoteRemainsUnusableWithoutTriggeringCreate() async throws {
        let transport = RegistrationFixtureTransport(#"{"code":200,"data":{"quoteSign":"fixture-signature"}}"#)
        let quote = try await service(transport).quote(RegistrationQuoteRequest(ownerID: 7), token: "fixture-raw-token")
        XCTAssertNil(quote.payAmount)
        XCTAssertFalse(quote.isUsableForCreate)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.url?.lastPathComponent, "quote")
    }

    func testMalformedCreateSuccessDoesNotRetryOrReadBack() async throws {
        for json in ["not-json", #"{"code":200}"#, #"{"code":200,"data":null}"#,
                     #"{"code":200,"data":[]}"#, #"{"code":200,"data":{}}"#,
                     #"{"code":200,"data":{"registrationId":0}}"#,
                     #"{"code":200,"data":{"registrationId":41,"payableAmount":-1}}"#] {
            let transport = RegistrationFixtureTransport(json)
            do {
                _ = try await service(transport).create(intent(), token: "fixture-raw-token")
                XCTFail("Expected malformed response")
            } catch {
                XCTAssertEqual(error as? APIError, .malformedResponse)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testStringSuccessCodeIsNotAcceptedAsSuccess() async throws {
        let transport = RegistrationFixtureTransport(#"{"code":"200","data":{"registrationId":41}}"#)
        do {
            _ = try await service(transport).create(intent(), token: "fixture-raw-token")
            XCTFail("Source requires numeric 200")
        } catch {
            XCTAssertEqual((error as? RegistrationResponseFailure)?.code, 200)
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testCreateResponseVariantsDoNotLaunchPaymentOrAutomaticReadback() async throws {
        for fields in ["", #", "payableAmount":0"#, #", "payableAmount":19.99,"payParams":{}"#,
                       #", "payableAmount":"19.99","payParams":{"timeStamp":123,"sign":" fixture/pay-sign+= "}"#] {
            let transport = RegistrationFixtureTransport("{\"code\":200,\"data\":{\"registrationId\":41\(fields)}}")
            let result = try await service(transport).create(intent(), token: "fixture-raw-token")
            XCTAssertEqual(result.registrationID, 41)
            XCTAssertEqual(transport.requests.count, 1)
            XCTAssertEqual(transport.requests.first?.url?.lastPathComponent, "create")
            if result.hasPaymentParameters {
                XCTAssertEqual(result.payParams?["timeStamp"], "123")
                XCTAssertEqual(result.payParams?["sign"], " fixture/pay-sign+= ")
            }
        }
    }

    func testReadStatusUsesSourceMultipartIDAndReturnsRawSnapshot() async throws {
        let transport = RegistrationFixtureTransport(#"{"code":200,"data":{"id":41,"registrationNo":"fixture-order","registrationStatus":1,"paymentStatus":2,"verificationStatus":0}}"#)
        let snapshot = try await service(transport).readStatus(registrationID: 41, token: "fixture-raw-token")
        let request = try XCTUnwrap(transport.requests.first)
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        assertRequest(request, path: "api/registration/info", contentType: contentType)
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        let body = try XCTUnwrap(String(data: XCTUnwrap(request.httpBody), encoding: .utf8))
        XCTAssertEqual(body, "--\(boundary)\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n41\r\n--\(boundary)--\r\n")
        XCTAssertEqual(snapshot.registrationID, 41)
        XCTAssertEqual(snapshot.registrationNo, "fixture-order")
        XCTAssertEqual(snapshot.registrationStatus, 1)
        XCTAssertEqual(snapshot.paymentStatus, 2)
        XCTAssertEqual(snapshot.verificationStatus, 0)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testReadStatusKeepsMissingNullAndFutureStatusesWithoutInventingVerdict() async throws {
        for fields in ["", #", "registrationStatus":null,"paymentStatus":null,"verificationStatus":null"#] {
            let transport = RegistrationFixtureTransport("{\"code\":200,\"data\":{\"id\":41\(fields)}}")
            let snapshot = try await service(transport).readStatus(registrationID: 41, token: "fixture-raw-token")
            XCTAssertNil(snapshot.registrationStatus)
            XCTAssertNil(snapshot.paymentStatus)
            XCTAssertNil(snapshot.verificationStatus)
            XCTAssertEqual(transport.requests.count, 1)
        }
        let transport = RegistrationFixtureTransport(#"{"code":200,"data":{"id":41,"registrationStatus":999,"paymentStatus":-1,"verificationStatus":9}}"#)
        let snapshot = try await service(transport).readStatus(registrationID: 41, token: "fixture-raw-token")
        XCTAssertEqual(snapshot.registrationStatus, 999)
        XCTAssertEqual(snapshot.paymentStatus, -1)
        XCTAssertEqual(snapshot.verificationStatus, 9)
    }

    func testReadStatusRejectsMissingMalformedOrMismatchedIdentityAndMalformedStatuses() async throws {
        for data in ["{}", "null", "[]", #"{"id":0}"#, #"{"id":42}"#, #"{"id":"41"}"#,
                     #"{"id":41,"registrationStatus":"2"}"#, #"{"id":41,"paymentStatus":true}"#,
                     #"{"id":41,"verificationStatus":[]}"#] {
            let transport = RegistrationFixtureTransport("{\"code\":200,\"data\":\(data)}")
            do {
                _ = try await service(transport).readStatus(registrationID: 41, token: "fixture-raw-token")
                XCTFail("Expected malformed response")
            } catch {
                XCTAssertEqual(error as? APIError, .malformedResponse)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testReadStatusBusinessFailureIsNotAnEmptySnapshot() async throws {
        let transport = RegistrationFixtureTransport(#"{"code":404,"msg":"fixture unavailable"}"#)
        do {
            _ = try await service(transport).readStatus(registrationID: 41, token: "fixture-raw-token")
            XCTFail("Expected business failure")
        } catch {
            XCTAssertEqual(error as? RegistrationResponseFailure, RegistrationResponseFailure(code: 404, message: "fixture unavailable"))
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testInvalidReadbackIDNeverReachesTransport() async throws {
        let transport = RegistrationFixtureTransport()
        let api = try service(transport)
        for id in [0, -1] {
            do { _ = try await api.readStatus(registrationID: id, token: "fixture-raw-token"); XCTFail("Expected invalid ID") }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}

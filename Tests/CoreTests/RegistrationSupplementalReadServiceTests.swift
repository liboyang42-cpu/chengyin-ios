import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor SupplementalRecordingTransport: HTTPTransport {
    let body: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(_ body: String, status: Int = 200) { self.body = body; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data(body.utf8), status)
    }
}

final class RegistrationSupplementalReadServiceTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> RegistrationSupplementalReadService {
        try .init(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }

    func testPaymentReadinessReadsExactEndpointWithoutPaymentOrAccountSelector() async throws {
        let transport = SupplementalRecordingTransport(#"{"code":200,"data":{"ready":true,"message":"Available"}}"#)
        let value = try await service(transport).paymentReadiness(token: "synthetic-session")
        XCTAssertTrue(value.isReady)
        XCTAssertEqual(value.message, "Available")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/test/api/registration/payment-readiness")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-session")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains("name="))
    }

    func testMissingReadinessDoesNotBecomeReady() async throws {
        for fields in [#"{"ready":false}"#, #"{"ready":null}"#, #"{}"#] {
            let transport = SupplementalRecordingTransport("{\"code\":200,\"data\":\(fields)}")
            let value = try await service(transport).paymentReadiness(token: "synthetic-session")
            XCTAssertFalse(value.isReady)
        }
    }

    func testMalformedReadinessAndMissingDataFailWithoutRetry() async throws {
        for body in [#"{"code":200,"data":{"ready":"true"}}"#, #"{"code":200,"data":{"ready":1}}"#, #"{"code":200}"#, #"{"code":200,"data":null}"#] {
            let transport = SupplementalRecordingTransport(body)
            do { _ = try await service(transport).paymentReadiness(token: "synthetic-session"); XCTFail("Readiness cannot be invented") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testJoinedRegistrationUsesTokenIdentityAndPreservesServerOrder() async throws {
        let transport = SupplementalRecordingTransport(#"{"code":200,"data":{"id":41,"memberId":7,"registrationStatus":2,"paymentStatus":2,"cmsActivity":{"memberId":99}}}"#)
        let value = try await service(transport).joinedRegistration(accountID: 7, token: "synthetic-session")
        XCTAssertEqual(value?.id, 41)
        XCTAssertEqual(value?.memberID, 7)
        XCTAssertEqual(value?.ownerMemberID, 99)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/test/api/registration/join_info")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains("member_id"))
        XCTAssertFalse(body.contains("requestId"))
        XCTAssertFalse(body.contains("name="))
    }

    func testJoinedEmptySuccessIsDistinctFromMalformedOrder() async throws {
        for body in [#"{"code":200}"#, #"{"code":"200","data":null}"#] {
            let value = try await service(SupplementalRecordingTransport(body)).joinedRegistration(accountID: 7, token: "synthetic-session")
            XCTAssertNil(value)
        }
        do {
            _ = try await service(SupplementalRecordingTransport(#"{"code":200,"data":{}}"#)).joinedRegistration(accountID: 7, token: "synthetic-session")
            XCTFail("An empty object is not an absent joined order")
        } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }

    func testJoinedOrderRejectsWrongAndMissingBuyer() async throws {
        for fields in [#"{"id":41,"memberId":8,"cmsTopic":{"memberId":7}}"#, #"{"id":41,"cmsActivity":{"memberId":7}}"#] {
            do {
                _ = try await service(SupplementalRecordingTransport("{\"code\":200,\"data\":\(fields)}")).joinedRegistration(accountID: 7, token: "synthetic-session")
                XCTFail("Publisher identity cannot substitute for buyer identity")
            } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }

    func testCountsKeepServerValuesAndExactOwnerFormFieldsForBothOwnerKinds() async throws {
        for kind in [RegistrationCountOwnerKind.topic, .activity] {
            let transport = SupplementalRecordingTransport(#"{"code":200,"data":[{"participateDate":"2026-12-04","totalCount":3},{"participateDate":"2026-12-05","totalCount":0}]}"#)
            let value = try await service(transport).countsByDate(scope: .init(kind: kind, ownerID: 42), token: "synthetic-session")
            XCTAssertEqual(value.map(\.totalCount), [3, 0])
            XCTAssertEqual(value.map(\.participateDate), ["2026-12-04", "2026-12-05"])
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.url?.path, "/test/api/registration/count_by_date")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("name=\"owner_type\"\r\n\r\n\(kind.rawValue)\r\n"))
            XCTAssertTrue(body.contains("name=\"owner_id\"\r\n\r\n42\r\n"))
            XCTAssertFalse(body.contains("member_id"))
            XCTAssertFalse(body.contains("product_type"))
        }
    }

    func testEmptyCountsAreValidButMissingDataIsNotAnEmptyCalendar() async throws {
        let scope = try RegistrationCountScope(kind: .activity, ownerID: 42)
        let empty = try await service(SupplementalRecordingTransport(#"{"code":200,"data":[]}"#)).countsByDate(scope: scope, token: "synthetic-session")
        XCTAssertTrue(empty.isEmpty)
        do { _ = try await service(SupplementalRecordingTransport(#"{"code":200}"#)).countsByDate(scope: scope, token: "synthetic-session"); XCTFail("Missing counts are unknown") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }

    func testInvalidCountsAndDuplicateDaysAreRejectedInsteadOfRecalculated() async throws {
        let scope = try RegistrationCountScope(kind: .topic, ownerID: 42)
        for data in [
            #"[{"participateDate":"2026-12-04","totalCount":-1}]"#,
            #"[{"participateDate":"2026-12-04"}]"#,
            #"[{"participateDate":"2026-12-04","totalCount":"2"}]"#,
            #"[{"participateDate":"","totalCount":2}]"#,
            #"[{"participateDate":"2026-12-04","totalCount":2},{"participateDate":"2026-12-04","totalCount":3}]"#
        ] {
            do { _ = try await service(SupplementalRecordingTransport("{\"code\":200,\"data\":\(data)}")).countsByDate(scope: scope, token: "synthetic-session"); XCTFail("Invalid counts cannot become a valid chart") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }

    func testBusinessDenialWinsOverMalformedDataAndDoesNotBecomeEmptySuccess() async throws {
        do {
            _ = try await service(SupplementalRecordingTransport(#"{"code":403,"msg":"Denied","data":"bad"}"#)).countsByDate(scope: .init(kind: .topic, ownerID: 42), token: "synthetic-session")
            XCTFail("Server decides access")
        } catch {
            XCTAssertEqual((error as? RegistrationResponseFailure)?.code, 403)
            XCTAssertEqual((error as? RegistrationResponseFailure)?.message, "Denied")
        }
    }

    func testHTTP401AndBusiness401AreUnauthorizedBeforeDataDecoding() async throws {
        for transport in [SupplementalRecordingTransport("not-json", status: 401), SupplementalRecordingTransport(#"{"code":"401","data":"bad"}"#)] {
            do { _ = try await service(transport).paymentReadiness(token: "synthetic-session"); XCTFail("Session expired") }
            catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        }
    }

    func testInvalidInputNeverDispatches() async throws {
        let transport = SupplementalRecordingTransport("{}")
        let client = try service(transport)
        do { _ = try await client.paymentReadiness(token: ""); XCTFail("Invalid token") } catch {}
        do { _ = try await client.joinedRegistration(accountID: 0, token: "synthetic-session"); XCTFail("Invalid account") } catch {}
        XCTAssertThrowsError(try RegistrationCountScope(kind: .topic, ownerID: 0))
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
}

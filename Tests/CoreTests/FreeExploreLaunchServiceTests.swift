import XCTest
@testable import QuestifyCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// All values in these helpers are synthetic. No request leaves the HTTP double.
final class FXTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: (URLRequest) async throws -> (Data, Int) = { _ in throw URLError(.timedOut) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return try await handler(request)
    }
}
@MainActor final class FXStorage: TemplateAuthoringStorage {
    var values: [String: Data] = [:]
    var failWrite = false
    var ignoreWrite = false
    var ignoreRemove = false
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws {
        if failWrite { throw URLError(.cannotWriteToFile) }
        if !ignoreWrite { values[key] = data }
    }
    func remove(_ key: String) throws { if !ignoreRemove { values.removeValue(forKey: key) } }
}
enum FX {
    static func id(_ value: Int64) throws -> FreeExploreLaunchID { try FreeExploreLaunchID(value) }
    static func session(account: Int64 = 7, epoch: UInt64 = 1, market: String = "CN", namespace: String = "test", host: String = "example.test") throws -> FreeExploreLaunchSession {
        try FreeExploreLaunchSession(baseURL: URL(string: "https://" + host)!, accountID: account,
            market: market, namespace: namespace, role: "player", epoch: epoch, token: "synthetic-test-credential")
    }
    static func command(key: String = "fx-original", start: Int64 = 1_900_000_000_123) throws -> FreeExploreLaunchReservationCommand {
        try FreeExploreLaunchReservationCommand(registrationId: id(11), unitId: id(22), offerId: id(33), startAt: start, idempotencyKey: key)
    }
    static func receipt(_ command: FreeExploreLaunchReservationCommand, owner: Int64 = 7, status: String = "BOOKED") -> [String: Any] {
        ["id": 44, "registrationId": command.registrationId.value, "holderMemberId": owner,
         "unitId": command.unitId.value, "chapterId": 55, "offerId": command.offerId.value,
         "merchantId": 66, "startAt": "2030-03-18 01:46:40", "status": status,
         "idempotencyKey": command.idempotencyKey, "requestFingerprint": command.fingerprint]
    }
    static func order(_ command: FreeExploreLaunchReservationCommand, owner: Int64 = 7, reservations: [[String: Any]] = [], unitStatus: String = "AVAILABLE") -> [String: Any] {
        ["registrationId": command.registrationId.value, "registrationNo": "synthetic-order", "paymentStatus": 2, "registrationStatus": 2,
         "bundle": ["order": ["registrationId": command.registrationId.value, "holderMemberId": owner, "topicId": 88],
                    "units": [["id": command.unitId.value, "registrationId": command.registrationId.value,
                               "holderMemberId": owner, "chapterId": 55, "status": unitStatus]], "reservations": reservations]]
    }
    static var catalog: [String: Any] {
        ["topicId": 88, "topicName": "Synthetic", "productType": 2, "saleEnabled": false, "reservationEnabled": true,
         "items": [["chapterId": 55, "name": "Synthetic", "termsMode": "PERK", "unitsPerHolder": 3,
                    "stores": [["offerId": 33, "merchantName": "Synthetic", "validEnd": "2030-12-01 00:00:00"]]]]]
    }
    static func response(_ value: Any, code: Int = 200) throws -> (Data, Int) {
        (try JSONSerialization.data(withJSONObject: ["code": code, "data": value], options: [.sortedKeys]), 200)
    }
    static func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }
}

@MainActor final class FreeExploreLaunchServiceTests: XCTestCase {
    func testCatalogUsesGETQueryAndNeverOrders() async throws {
        let transport = FXTransport(), session = try FX.session()
        transport.handler = { _ in try FX.response(FX.catalog) }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session })
        let value = try await service.catalog(topicID: FX.id(88))
        XCTAssertEqual(value.topicId, try FX.id(88))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/free-explore/bundle/catalog")
        XCTAssertEqual(request.url?.query, "topicId=88")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-test-credential")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
    }
    func testReservationWritesMillisecondsAndOriginalKey() async throws {
        let transport = FXTransport(), session = try FX.session(), command = try FX.command()
        transport.handler = { _ in try FX.response(FX.receipt(command)) }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session }, reservationAllowed: { true })
        _ = try await service.reserve(command)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/free-explore/bundle/reservation")
        XCTAssertEqual(request.httpBody, try command.wireData())
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual((body["startAt"] as? NSNumber)?.int64Value, command.startAt)
        XCTAssertEqual(body["idempotencyKey"] as? String, command.idempotencyKey)
        XCTAssertEqual(Set(body.keys), ["registrationId", "unitId", "offerId", "startAt", "idempotencyKey"])
    }
    func testWriterDefaultsOffAndCancelQuoteIsUnavailableWithoutHTTP() async throws {
        let transport = FXTransport(), session = try FX.session()
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session })
        do { _ = try await service.reserve(FX.command()); XCTFail("must be disabled") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .disabled) }
        XCTAssertThrowsError(try service.cancellationQuote(reservationID: FX.id(44), useWaiver: true)) {
            XCTAssertEqual($0 as? FreeExploreLaunchFailure, .cancellationQuoteUnavailable)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testReceiptNullIsUnknownAndForeignReceiptFails() async throws {
        let transport = FXTransport(), session = try FX.session(), command = try FX.command()
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session })
        transport.handler = { _ in try FX.response(NSNull()) }
        let missing = try await service.receipt(command); XCTAssertNil(missing)
        XCTAssertEqual(transport.requests.last?.url?.query, "idempotencyKey=fx-original")
        transport.handler = { _ in try FX.response(FX.receipt(command, owner: 8)) }
        do { _ = try await service.receipt(command); XCTFail("foreign receipt") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .malformed) }
    }
    func testReceiptRejectsSameKeyWithDifferentStartTime() async throws {
        let transport = FXTransport(), session = try FX.session(), command = try FX.command()
        let other = try FX.command(start: command.startAt + 1)
        transport.handler = { _ in try FX.response(FX.receipt(other)) }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session })
        do { _ = try await service.receipt(command); XCTFail("wrong fingerprint") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .malformed) }
    }
    func testLateSessionResponseIsDiscarded() async throws {
        let transport = FXTransport(), original = try FX.session()
        var current: FreeExploreLaunchSession? = original
        transport.handler = { _ in current = nil; return try FX.response(FX.catalog) }
        let service = FreeExploreLaunchService(session: original, transport: transport, currentSession: { current })
        do { _ = try await service.catalog(topicID: FX.id(88)); XCTFail("stale response") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .staleSession) }
    }
    func test401ExpiresCapturedSessionOnly() async throws {
        let transport = FXTransport(), session = try FX.session()
        var expired: FreeExploreLaunchSession?
        transport.handler = { _ in try FX.response(NSNull(), code: 401) }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session }, onUnauthorized: { expired = $0 })
        do { _ = try await service.catalog(topicID: FX.id(88)); XCTFail("401") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, session)
    }
    func testServerBusinessCodeIsPreserved() async throws {
        let transport = FXTransport(), session = try FX.session()
        transport.handler = { _ in
            (Data(#"{"code":409,"businessCode":"BUNDLE_DISABLED"}"#.utf8), 200)
        }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session })
        do { _ = try await service.order(registrationID: FX.id(11)); XCTFail("disabled") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .response(status: 200, code: 409, businessCode: "BUNDLE_DISABLED")) }
    }
    func testRefundQuotePreservesServerAmountAndUnknownRoute() async throws {
        let transport = FXTransport(), session = try FX.session()
        transport.handler = { _ in try FX.response(["route": "FUTURE_SERVER_ROUTE", "amount": "10.07", "totalValue": "80.00",
            "remainingValue": "10.07", "remainingRatio": "0.1259", "afterSalesForMerchantBreach": true,
            "reason": "server reason", "policyVersion": "server-version"]) }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session })
        let quote = try await service.refundQuote(registrationID: FX.id(11))
        XCTAssertEqual(quote.route, "FUTURE_SERVER_ROUTE"); XCTAssertEqual(quote.amount.text, "10.07")
        XCTAssertEqual(quote.remainingRatio.text, "0.1259"); XCTAssertTrue(quote.afterSalesForMerchantBreach)
        XCTAssertEqual(transport.requests.last?.url?.path, "/api/free-explore/bundle/order/refund-quote")
    }
    func testLongIDsDoNotRoundAndMalformedIdentityIsRejected() throws {
        let large = Data(#"9223372036854775807"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(FreeExploreLaunchID.self, from: large).text, "9223372036854775807")
        for json in [#""01""#, #""9223372036854775808""#, "-1", "0", "true", "1.5"] {
            XCTAssertThrowsError(try JSONDecoder().decode(FreeExploreLaunchID.self, from: Data(json.utf8)))
        }
    }
    func testWrongOrderOwnerAndRegistrationFail() async throws {
        let transport = FXTransport(), session = try FX.session(), command = try FX.command()
        transport.handler = { _ in try FX.response(FX.order(command, owner: 8)) }
        let service = FreeExploreLaunchService(session: session, transport: transport, currentSession: { session })
        do { _ = try await service.order(registrationID: FX.id(11)); XCTFail("foreign owner") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .malformed) }
        transport.handler = { _ in try FX.response(FX.order(command)) }
        do { _ = try await service.order(registrationID: FX.id(12)); XCTFail("wrong registration") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .malformed) }
    }
}

import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic offline wire fixtures only; no default endpoint, native grant or real credential.
@MainActor enum NativeWebhookFixtures {
    static let resourceID = NativeWebhookID(rawValue: "9007199254740993")!
    static let scope = NativeWebhookScope(ownerID: NativeWebhookID(rawValue: "9007199254740995")!, channelID: NativeWebhookID(rawValue: "9223372036854775807")!)
    static func context(version: String = "fixture-permission-version-7", catalogue: Bool = true) throws -> NativeWebhookContext {
        try NativeWebhookContext(binding: NativeWebhookBinding(accountID: "19", market: "CN", namespace: "fixture-only",
            origin: URL(string: "https://webhook-fixture.invalid")!, scope: scope, authorizationVersion: version),
            eventCatalogue: catalogue ? .available(revision: "fixture-1", options: [.init(id: "channel.message.created", title: "合成事件")])
                : .unavailable(code: "WEBHOOK_EVENT_CATALOGUE_UNAVAILABLE"))
    }
    static func resourceJSON(family: NativeWebhookFamily = .subscription, revision: Int = 4, keyVersion: Int = 2, extra: String = "") -> String {
        let fields = family == .subscription ? #""url_host":"target-fixture.invalid","events":["channel.message.created"],"event_count":1,"fail_count":0,"last_error":null,"last_delivery_at":null"#
            : #""avatar_url":null,"token_prefix":"fixture","rate_limit_per_min":31,"allowed_ips":[],"last_called_at":null"#
        return "{\"id\":\"\(resourceID.rawValue)\",\"channel_id\":\"\(scope.channelID.rawValue)\",\"owner_type\":\"CLUB\",\"owner_id\":\"\(scope.ownerID.rawValue)\",\"name\":\"合成集成\",\"status\":1,\"deleted\":false,\"revision\":\(revision),\"key_version\":\(keyVersion),\"created_at\":\"2026-10-23 20:00:00.123\",\"updated_at\":null,\(fields)\(extra)}"
    }
    static func resource(family: NativeWebhookFamily = .subscription) throws -> NativeWebhookResource {
        try JSONDecoder().decode(NativeWebhookResource.self, from: Data(resourceJSON(family: family).utf8))
    }
    static func deliveryJSON(id: String = "81", state: String = "UNKNOWN", attempt: Int = 1, event: String = "fixture-event-1") -> String {
        "{\"id\":\"\(id)\",\"delivery_id\":\"\(id)\",\"event_id\":\"\(event)\",\"event_type\":\"channel.message.created\",\"state\":\"\(state)\",\"attempt\":\(attempt),\"reason\":null,\"response_snippet\":null,\"http_status\":null,\"latency_ms\":null,\"next_retry_at\":null,\"created_at\":null,\"payload_json\":{\"message_id\":\"9007199254740993\"}}"
    }
    static func delivery(id: String = "81", state: String = "UNKNOWN", attempt: Int = 1) throws -> NativeWebhookDelivery {
        try JSONDecoder().decode(NativeWebhookDelivery.self, from: Data(deliveryJSON(id: id, state: state, attempt: attempt).utf8))
    }
    static func envelope(_ json: String) -> Data { Data(("{\"code\":200,\"msg\":\"ok\",\"trace_id\":\"fixture-trace\",\"data\":" + json + "}").utf8) }
    static func list() -> Data { envelope("{\"list\":[" + resourceJSON() + "],\"has_more\":false,\"next_cursor\":null}") }
}

@MainActor final class NativeWebhookFixtureProvider: NativeWebhookScopeProvider, NativeWebhookRequestAuthorizer {
    var value: NativeWebhookContext
    var rejected = false
    var endpointApproved = true
    var unauthorizedCount = 0
    init(_ value: NativeWebhookContext) { self.value = value }
    func currentContext() async throws -> NativeWebhookContext {
        if rejected { throw NativeWebhookClientError.denied(code: "PERMISSION_DENIED", traceID: nil) }; return value
    }
    func revalidate(_ binding: NativeWebhookBinding) async throws -> NativeWebhookContext {
        let live = try await currentContext(); guard live.binding == binding else { throw NativeWebhookClientError.scopeChanged }; return live
    }
    func authorize(_ request: URLRequest, binding: NativeWebhookBinding) async throws -> URLRequest {
        _ = try await revalidate(binding)
        guard endpointApproved else { throw NativeWebhookClientError.sourceUnavailable("WEBHOOK_REVIEWED_ENDPOINT_APPROVAL_UNAVAILABLE") }
        return request
    }
    func unauthorized(_ binding: NativeWebhookBinding) { unauthorizedCount += 1 }
}
@MainActor final class NativeWebhookFixtureTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var respond: (URLRequest) async throws -> (Data, Int)
    init(_ respond: @escaping (URLRequest) async throws -> (Data, Int)) { self.respond = respond }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try await respond(request) }
}
@MainActor final class NativeWebhookMemoryJournal: OperationPendingJournal {
    var record: OperationPendingRecord?
    var failWrite = false, failClear = false
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        guard let record, record.ownerKey == ownerKey, record.targetKey == targetKey else { return nil }; return record
    }
    func write(_ record: OperationPendingRecord) throws { if failWrite { throw APIError.malformedResponse }; self.record = record }
    func clear(_ record: OperationPendingRecord) throws {
        guard !failClear, self.record == record else { throw APIError.invalidRequest }; self.record = nil
    }
}

@MainActor final class NativeWebhookContractsTests: XCTestCase {
    func testDecimalResponseIDsAndNumericRequestLongNeverUseDouble() throws {
        for raw in ["9007199254740991", "9007199254740992", "9007199254740993", "9223372036854775807"] {
            let id = try XCTUnwrap(NativeWebhookID(rawValue: raw))
            XCTAssertEqual(try JSONDecoder().decode(NativeWebhookID.self, from: Data(("\"" + raw + "\"").utf8)), id)
            let change = NativeWebhookChange(requestID: .make(), ownerType: "CLUB", ownerID: id.requestNumber, channelID: id.requestNumber, name: "fixture")
            let text = String(decoding: try NativeWebhookHTTPService.encoded(change), as: UTF8.self)
            XCTAssertTrue(text.contains("\"owner_id\":" + raw)); XCTAssertFalse(text.contains("\"owner_id\":\""))
        }
        for raw in ["0", "-1", "+1", "01", "1.0", "9223372036854775808"] { XCTAssertNil(NativeWebhookID(rawValue: raw)) }
        XCTAssertThrowsError(try JSONDecoder().decode(NativeWebhookID.self, from: Data("9007199254740993".utf8)))
    }
    func testShanghaiTimestampIsNotUTCAndNullRemainsNil() throws {
        let value = try NativeWebhookFixtures.resource()
        let time = try XCTUnwrap(value.createdAt)
        XCTAssertEqual(time.rawValue, "2026-10-23 20:00:00.123")
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(formatter.string(from: time.date), "2026-10-23T12:00:00.123Z")
        XCTAssertNil(value.updatedAt); XCTAssertNil(value.lastDeliveryAt)
        XCTAssertThrowsError(try JSONDecoder().decode(NativeWebhookServerTime.self, from: Data(#""2026-10-23T20:00:00Z""#.utf8)))
    }
    func testAllDeliveryStatesPayloadAndNullableFieldsSurvive() throws {
        for state in NativeWebhookDeliveryState.allCases {
            let row = try NativeWebhookFixtures.delivery(state: state.rawValue)
            XCTAssertEqual(row.state, state); XCTAssertNil(row.httpStatus); XCTAssertNil(row.latencyMilliseconds); XCTAssertNil(row.responseSnippet)
            XCTAssertNotNil(row.payload)
            XCTAssertEqual(row.offersExplicitRetry, state == .failed || state == .unknown)
        }
        XCTAssertFalse(try NativeWebhookFixtures.delivery(state: "FAILED", attempt: 5).offersExplicitRetry)
    }
    func testOneTimeCredentialDescriptionAndMirrorAreRedacted() {
        let secret = NativeWebhookOneTimeCredential(requestID: .make(), secret: "synthetic-only-secret", endpointURL: "https://fixture.invalid/private-token", oldTokenInvalidAfter: nil)
        XCTAssertFalse(String(describing: secret).contains(secret.secret)); XCTAssertFalse(String(reflecting: secret).contains("private-token"))
        XCTAssertEqual(Mirror(reflecting: secret).children.count, 1)
        XCTAssertEqual(Mirror(reflecting: secret).children.first?.value as? String, "<redacted>")
    }
    func testRequestIDRejectsInvalidCharactersAndOverlength() {
        for raw in ["", "a/b", "x y", String(repeating: "a", count: 65), "中文"] { XCTAssertNil(NativeWebhookRequestID(rawValue: raw)) }
        XCTAssertNotNil(NativeWebhookRequestID(rawValue: "A-z_019"))
    }
    func testCanonicalEquivalentNamespaceIsStillADifferentRuntimeBinding() throws {
        let original = try NativeWebhookFixtures.context().binding
        let one = try NativeWebhookBinding(accountID: original.accountID, market: original.market, namespace: "e\u{301}", origin: original.origin, scope: original.scope, authorizationVersion: original.authorizationVersion)
        let two = try NativeWebhookBinding(accountID: original.accountID, market: original.market, namespace: "\u{e9}", origin: original.origin, scope: original.scope, authorizationVersion: original.authorizationVersion)
        XCTAssertNotEqual(one, two); XCTAssertEqual(Set([one, two]).count, 2)
    }
}

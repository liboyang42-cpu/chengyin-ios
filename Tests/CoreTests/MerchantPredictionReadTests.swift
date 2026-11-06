import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor PredictionReadWire: HTTPTransport {
    let body: String
    let status: Int
    var requests: [URLRequest] = []
    init(_ body: String, status: Int = 200) { self.body = body; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(body.utf8), status) }
}
final class MerchantPredictionReadTests: XCTestCase {
    private let row = #"{"nodeId":17,"topicId":4,"nodeName":"Shop","playDay":"2024-02-29","question":"Which choice?","options":[{"key":"a","label":"A"},{"key":"b","label":"B"}],"betCount":3,"daysLeft":0}"#
    private func decode(_ text: String) throws -> MerchantPredictionInboxRound { try JSONDecoder().decode(MerchantPredictionInboxRound.self, from: Data(text.utf8)) }
    private func access(allowed: Bool = true) throws -> MerchantAccess {
        try JSONDecoder().decode(MerchantAccess.self, from: Data("{\"active\":true,\"merchant\":{\"id\":31},\"roleCode\":\"MERCHANT_MANAGER\",\"permissions\":\(allowed ? "[\"merchant:project:manage\"]" : "[]")}".utf8))
    }
    private func service(_ wire: PredictionReadWire) throws -> MerchantPredictionReadService {
        .init(configuration: try .init(baseURL: URL(string: "https://predict.example/native")!), transport: wire)
    }
    func testRoundPreservesNaturalDayValueAndNullableTopic() throws {
        let value = try decode(row)
        XCTAssertEqual(value.id, "17:2024-02-29"); XCTAssertEqual(value.daysLeft, 0); XCTAssertEqual(value.betCount, 3)
        XCTAssertEqual(value.options.map(\.key), ["a", "b"])
        XCTAssertNil(try decode(row.replacingOccurrences(of: #""topicId":4"#, with: #""topicId":null"#)).topicID)
    }
    func testInvalidCalendarDaysAndNegativeCountersAreRejected() {
        for date in ["2026-02-29", "2024-02-30", "2024-13-01", "2024-00-01", "2024-2-29", "0000-02-01"] {
            XCTAssertThrowsError(try decode(row.replacingOccurrences(of: "2024-02-29", with: date)))
        }
        for field in ["betCount", "daysLeft"] {
            let original = field == "betCount" ? "3" : "0"
            XCTAssertThrowsError(try decode(row.replacingOccurrences(of: "\"\(field)\":\(original)", with: "\"\(field)\":-1")))
        }
    }
    func testMissingAndAmbiguousOptionIdentityIsRejectedWithoutInventingAnswer() throws {
        XCTAssertThrowsError(try decode(row.replacingOccurrences(of: #""key":"b""#, with: #""key":"a""#)))
        XCTAssertThrowsError(try decode(row.replacingOccurrences(of: #""key":"a""#, with: #""key":"""#)))
        XCTAssertThrowsError(try decode(row.replacingOccurrences(of: #""key":"a""#, with: #""key":"   ""#)))
        XCTAssertThrowsError(try decode(row.replacingOccurrences(of: #""topicId":4,"#, with: "")))
        for counter in ["true", "2.5"] {
            XCTAssertThrowsError(try decode(row.replacingOccurrences(of: #""betCount":3"#, with: "\"betCount\":\(counter)")))
        }
        let noQuestion = try decode(row.replacingOccurrences(of: "Which choice?", with: ""))
        XCTAssertEqual(noQuestion.question, "")
    }
    func testExactReadRequestHasNoBodyCookiesOrSettlementFields() async throws {
        let wire = PredictionReadWire("{\"code\":200,\"data\":[\(row)]}")
        let result = try await service(wire).inbox(access: access(), token: "synthetic")
        XCTAssertEqual(result.count, 1)
        let requests = await wire.requests, r = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(r.url?.path, "/native/api/merchant/predict/inbox")
        XCTAssertEqual(r.httpMethod, "POST"); XCTAssertNil(r.httpBody); XCTAssertNil(r.httpBodyStream)
        XCTAssertNil(r.value(forHTTPHeaderField: "Content-Type")); XCTAssertFalse(r.httpShouldHandleCookies)
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "synthetic")
    }
    func testPermissionDenialNeverReadsInbox() async throws {
        let wire = PredictionReadWire("{}")
        do { _ = try await service(wire).inbox(access: access(allowed: false), token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        let requests = await wire.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testDuplicateRoundsAndRowsEnvelopeDoNotBecomeValidInbox() async throws {
        for payload in ["[\(row),\(row)]", "{\"rows\":[\(row)]}"] {
            let wire = PredictionReadWire("{\"code\":200,\"data\":\(payload)}")
            do { _ = try await service(wire).inbox(access: access(), token: "synthetic"); XCTFail() } catch {}
        }
    }
    func testEmptyInboxAndAuthoritativeErrorsStayDistinct() async throws {
        let empty = PredictionReadWire(#"{"code":200,"data":[]}"#)
        let rows = try await service(empty).inbox(access: access(), token: "synthetic"); XCTAssertTrue(rows.isEmpty)
        for (status, code) in [(401, 200), (200, 401), (403, 200), (200, 403), (200, 500)] {
            let wire = PredictionReadWire("{\"code\":\(code),\"data\":[]}", status: status)
            do { _ = try await service(wire).inbox(access: access(), token: "synthetic"); XCTFail() }
            catch {
                if status == 401 || code == 401 { XCTAssertEqual(error as? APIError, .unauthorized) }
                else if status == 403 || code == 403 { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
                else { XCTAssertEqual(error as? APIError, .businessCode(500)) }
            }
        }
    }
}

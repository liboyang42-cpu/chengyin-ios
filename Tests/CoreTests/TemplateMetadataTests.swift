import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class TemplateMetadataTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func service(_ wire: Wire) throws -> DiscoveryService {
        try .init(configuration: APIConfiguration(baseURL: base), transport: wire)
    }
    private func assertFailure(_ json: String, status: Int = 200, expected: APIError,
                               file: StaticString = #filePath, line: UInt = #line) async throws {
        let wire = Wire(json, status: status)
        do { _ = try await service(wire).templateMetadataDictionary(kind: .players); XCTFail("Invalid metadata accepted", file: file, line: line) }
        catch { XCTAssertEqual(error as? APIError, expected, file: file, line: line) }
        XCTAssertEqual(wire.requests.count, 1, file: file, line: line)
    }

    func testBothTypedKindsConstructExactCanonicalRequestsAndKeepRawToken() async throws {
        let tokens: [String?] = [nil, "synthetic-metadata-token"]
        for kind in TemplateMetadataKind.allCases {
            for token in tokens {
                let wire = Wire()
                let rows = try await service(wire).templateMetadataDictionary(kind: kind, token: token)
                XCTAssertTrue(rows.isEmpty); XCTAssertEqual(wire.requests.count, 1)
                let request = try XCTUnwrap(wire.requests.first)
                XCTAssertEqual(request.url?.absoluteString, base.absoluteString + "/api/common/dict")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), token)
                XCTAssertNil(request.httpBodyStream)
                let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
                let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
                let canonical = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/common/dict"),
                    fields: ["dictType": kind.rawValue], token: token, boundary: boundary)
                XCTAssertEqual(request.httpBody, canonical.httpBody)
                XCTAssertEqual(TemplateMetadataReadRoute(request: request, baseURL: base)?.kind, kind)
            }
        }
        XCTAssertEqual(TemplateMetadataKind.allCases.count, 2)
        XCTAssertNil(TemplateMetadataKind(rawValue: "app_template_difficulty"))
    }
    func testRawStringsResponseOrderDuplicatesAndUnsupportedValuesSurvive() async throws {
        let wire = Wire(#"{"code":"200","data":[{"dictValue":" 6+ ","dictLabel":" 多人 ","dictSort":99,"status":"1"},{"dictValue":"60m","dictLabel":"one hour","dictSort":0},{"dictValue":" 6+ ","dictLabel":"different label"},{"dictValue":"","dictLabel":""}]}"#)
        let rows = try await service(wire).templateMetadataDictionary(kind: .duration)
        XCTAssertEqual(rows, [.init(value: " 6+ ", label: " 多人 "), .init(value: "60m", label: "one hour"),
                             .init(value: " 6+ ", label: "different label"), .init(value: "", label: "")])
        XCTAssertTrue(rows.allSatisfy { $0.losslessDurationMinutes == nil })
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testEmptyArrayIsSuccessForNumericAndStringStatusWithoutFallbackOrRetry() async throws {
        for code in ["200", "\"200\""] {
            let wire = Wire("{\"code\":\(code),\"data\":[]}")
            let rows = try await service(wire).templateMetadataDictionary(kind: .duration)
            XCTAssertEqual(rows, []); XCTAssertEqual(wire.requests.count, 1)
        }
    }
    func testStatusIsCheckedBeforePayloadIncludingMalformedOptionalMessage() async throws {
        try await assertFailure("not-json", status: 401, expected: .unauthorized)
        try await assertFailure("not-json", status: 503, expected: .httpStatus(503))
        for code in ["401", "\"401\""] {
            try await assertFailure("{\"code\":\(code),\"msg\":{},\"data\":false}", expected: .unauthorized)
        }
        for code in ["403", "\"403\""] {
            try await assertFailure("{\"code\":\(code),\"data\":null}", expected: .businessCode(403))
        }
    }
    func testMissingNullScalarObjectAndRowsPayloadAreMalformedRatherThanEmpty() async throws {
        for json in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{}}"#,
                     #"{"code":200,"data":{"rows":[]}}"#, #"{"code":200,"data":0}"#,
                     #"{"code":200,"data":"[]"}"#, #"{"code":200,"data":false}"#] {
            try await assertFailure(json, expected: .malformedResponse)
        }
    }
    func testEveryRowRequiresBothStrictStringsAndOneMalformedRowRejectsAll() async throws {
        for row in [#"{}"#, #"{"dictValue":"4"}"#, #"{"dictLabel":"Four"}"#,
                    #"{"dictValue":4,"dictLabel":"Four"}"#, #"{"dictValue":"4","dictLabel":4}"#,
                    #"{"dictValue":null,"dictLabel":"Four"}"#, #"{"dictValue":"4","dictLabel":null}"#,
                    #"{"dictValue":true,"dictLabel":"Four"}"#, #"{"dictValue":[],"dictLabel":"Four"}"#,
                    #"{"dictValue":"4","dictLabel":{}}"#, "null", "[]", "4"] {
            try await assertFailure("{\"code\":200,\"data\":[{\"dictValue\":\"1\",\"dictLabel\":\"One\"},\(row)]}", expected: .malformedResponse)
        }
    }
    func testMalformedStatusCannotBecomeSuccessAndOtherDiscoveryDecoderIsUnchanged() async throws {
        for code in ["null", "true", "false", "{}", "[]", "200.5", "\"0200\"", "\"+200\"", "\" 200\"", "\"200.0\""] {
            try await assertFailure("{\"code\":\(code),\"data\":[]}", expected: .malformedResponse)
        }
        try await assertFailure(#"{"data":[]}"#, expected: .malformedResponse)
        let wire = Wire(#"{"code":"200","data":[]}"#)
        do { _ = try await service(wire).categories(type: 4); XCTFail("Unrelated discovery status semantics changed") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testDurationProjectionRequiresLosslessCanonicalJavaInteger() {
        let supported = ["0": 0, "1": 1, "60": 60, "-1": -1, "2147483647": Int(Int32.max), "-2147483648": Int(Int32.min)]
        for (text, expected) in supported {
            let row = TemplateMetadataOption(value: text, label: "Display text")
            XCTAssertEqual(row.losslessDurationMinutes, expected); XCTAssertEqual(row.value, text)
        }
        for text in ["", " ", "+1", "01", "-0", "-01", " 60", "60 ", "60\n", "60.0", "1e2", "60m", "one hour",
                     "2147483648", "-2147483649", "9223372036854775808", "６０", "٦٠"] {
            let row = TemplateMetadataOption(value: text, label: "60")
            XCTAssertNil(row.losslessDurationMinutes, text); XCTAssertEqual(row.value, text)
        }
    }
    func testRouteAcceptsOnlyValidNativeBoundaryLengths() throws {
        for boundary in ["x", String(repeating: "A", count: 70), "native-123-XYZ"] {
            let request = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/common/dict"),
                fields: ["dictType": TemplateMetadataKind.players.rawValue], token: nil, boundary: boundary)
            XCTAssertEqual(TemplateMetadataReadRoute(request: request, baseURL: base)?.kind, .players)
        }
    }

    private final class Wire: HTTPTransport {
        var json: String
        var status: Int
        var requests: [URLRequest] = []
        init(_ json: String = #"{"code":200,"data":[]}"#, status: Int = 200) { self.json = json; self.status = status }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); return (Data(json.utf8), status)
        }
    }
}

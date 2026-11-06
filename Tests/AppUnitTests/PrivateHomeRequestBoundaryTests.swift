import XCTest
@testable import Questify

/// Real CompositionHTTPTransport and original PrivateHomeService over an in-memory recorder.
/// No URLSession, account login, permission, OS Keychain or live request is used.
@MainActor final class PrivateHomeRequestBoundaryTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var response: (Data, Int) = (Data(#"{"code":200,"data":{"version":0,"status":"DELETED"}}"#.utf8), 200)
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return response }
    }
    private let endpoint = URL(string: "https://private-home-boundary.example.test/native")!
    private let token = "synthetic-home-token"
    private func setup(_ wire: Wire, granted: Bool = true) throws -> (CompositionHTTPTransport, PlayExperienceSession) {
        func deployment(_ grant: PrivateHomeTransportGrant?) throws -> ReviewedAppDeployment {
            try .init(market: .china, baseURL: endpoint.absoluteString,
                approvedBaseURLs: [.china: [endpoint.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
                bundleIdentifier: "test.questify.homeBoundary", realm: "synthetic", privateHome: grant)
        }
        let base = try deployment(nil)
        let grant = try PrivateHomeTransportGrant(storageScope: base.storageScope, accountID: 7, role: "player")
        let transport = CompositionHTTPTransport(deployment: try deployment(granted ? grant : nil), underlying: wire)
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: self.token) }
        return (transport, try .init(accountID: 7, epoch: 1, namespace: base.storageScope.service, token: token, role: "player"))
    }
    private func request(_ method: String = "PUT", body: String? = nil) -> URLRequest {
        var request = URLRequest(url: endpoint.appendingPathComponent(PrivateHomeService.path))
        request.httpMethod = method; request.httpBody = body.map { Data($0.utf8) }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    private let valid = #"{"requestId":"synthetic-put","expectedVersion":0,"label":"Synthetic","latitude":12,"longitude":45,"datum":"WGS84"}"#
    private let delete = #"{"requestId":"synthetic-delete","expectedVersion":1}"#
    private func reject(_ request: URLRequest, using transport: CompositionHTTPTransport,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await transport.send(request); XCTFail("Invalid private-home request was forwarded", file: file, line: line) }
        catch {}
    }

    func testOriginalServiceGetPutDeleteStillForwardExactProducerBytes() async throws {
        let wire = Wire(), (transport, owner) = try setup(wire)
        let service = PrivateHomeService(api: try .init(baseURL: endpoint), transport: transport,
            owner: owner, enabled: true, current: { owner })
        _ = try await service.load()
        let put = try PrivateHomeMutation(requestId: "normal-put", expectedVersion: 0, label: "合成地点",
            point: PrivateHomePoint(latitude: Decimal(string: "12.345678")!, longitude: Decimal(string: "-45.678901")!))
        wire.response = (Data(#"{"code":200,"data":{"requestId":"normal-put","decision":"SAVED","version":1}}"#.utf8), 200)
        _ = try await service.mutate(put)
        let delete = try PrivateHomeMutation(requestId: "normal-delete", expectedVersion: 1)
        wire.response = (Data(#"{"code":200,"data":{"requestId":"normal-delete","decision":"DELETED","version":2}}"#.utf8), 200)
        _ = try await service.mutate(delete)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(wire.requests.map(\.httpMethod), ["GET", "PUT", "DELETE"])
        XCTAssertNil(wire.requests[0].httpBody)
        XCTAssertEqual(wire.requests[1].httpBody, try encoder.encode(put))
        XCTAssertEqual(wire.requests[2].httpBody, try encoder.encode(delete))
    }
    func testLegitimateWhitespaceOrderEscapesAndNumericSpellingsArePreserved() async throws {
        let wire = Wire(), (transport, _) = try setup(wire)
        let variants = [
            " \n" + valid + "\t\n",
            #"{"datum":"WGS84", "longitude":45, "latitude":12, "label":"Synthetic", "expectedVersion":0, "reque\u0073tId":"synthetic-put"}"#,
            valid.replacingOccurrences(of: ":12,", with: ":12.00000000000000000000,"),
            valid.replacingOccurrences(of: ":12,", with: ":120000000000000000000000000000000000000000000000000e-49,"),
            valid.replacingOccurrences(of: ":12,", with: ":1000e-9,"),
            valid.replacingOccurrences(of: ":12,", with: ":-0.0000000000e+100,"),
            valid.replacingOccurrences(of: ":12,", with: ":90,")
        ]
        for body in variants { _ = try await transport.send(request(body: body)) }
        XCTAssertEqual(wire.requests.compactMap(\.httpBody), variants.map { Data($0.utf8) })
        let unicodePadding = valid.replacingOccurrences(of: "Synthetic", with: String(repeating: "家", count: 40))
        _ = try await transport.send(request(body: unicodePadding))
        XCTAssertEqual(wire.requests.last?.httpBody, Data(unicodePadding.utf8))
        let largeVersion = #" { "expectedVersion":9223372036854775806, "requestId":"synthetic-delete" } "#
        _ = try await transport.send(request("DELETE", body: largeVersion))
        XCTAssertEqual(wire.requests.last?.httpBody, Data(largeVersion.utf8))
    }
    func testUnknownCallerIdentityAndExtraPayloadFieldsAreRejectedBeforeWire() async throws {
        let wire = Wire(), (transport, _) = try setup(wire)
        for extra in [#", "ownerId":7"#, #", "accountID":7"#, #", "role":"player""#,
                      #", "proofId":"synthetic-proof""#, #", "nested":{}"#, #", "items":[]"#] {
            await reject(request(body: String(valid.dropLast()) + extra + "}"), using: transport)
        }
        await reject(request("DELETE", body: valid), using: transport)
        await reject(request("PUT", body: delete), using: transport)
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testDuplicateDecodedKeysAndTrailingJSONAreRejected() async throws {
        let wire = Wire(), (transport, _) = try setup(wire)
        for body in [
            String(valid.dropLast()) + #", "requestId":"synthetic-put"}"#,
            String(valid.dropLast()) + #", "reque\u0073tId":"synthetic-put"}"#,
            String(valid.dropLast()) + #", "latitude":12}"#,
            valid + "{}", valid + " null", "[" + valid + "]"
        ] { await reject(request(body: body), using: transport) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testIntegerVersionCannotUseFloatingBooleanStringNullOrOverflow() async throws {
        let wire = Wire(), (transport, _) = try setup(wire)
        for value in ["0.0", "0e0", "true", "null", #""0""#, "-1", "9223372036854775807", "9223372036854775808"] {
            await reject(request(body: valid.replacingOccurrences(of: #""expectedVersion":0"#, with: #""expectedVersion":"# + value)), using: transport)
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testOriginalCoordinateTokensCannotRoundIntoValidScaleOrRange() async throws {
        let wire = Wire(), (transport, _) = try setup(wire)
        for value in ["12.1234567", "12.00000000000000000000000000000000000000001", "1e-7",
                      "90.000001", "-90.000001", "1e200", "1e-2147483648", "0e-2147483648",
                      "0e2147483648", "NaN", "Infinity", #""12""#, "true", "null", "{}", "[]", "01", "+12"] {
            await reject(request(body: valid.replacingOccurrences(of: ":12,", with: ":" + value + ",")), using: transport)
        }
        for value in ["180.000001", "-180.000001"] {
            await reject(request(body: valid.replacingOccurrences(of: ":45,", with: ":" + value + ",")), using: transport)
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testCoordinatesAndLabelsRetainOriginalDomainValidation() async throws {
        let wire = Wire(), (transport, _) = try setup(wire)
        for body in [valid.replacingOccurrences(of: "WGS84", with: "GCJ02"),
                     valid.replacingOccurrences(of: "Synthetic", with: " "),
                     valid.replacingOccurrences(of: "Synthetic", with: String(repeating: "x", count: 41)),
                     valid.replacingOccurrences(of: "Synthetic", with: #"\ud83d\ude00"#),
                     valid.replacingOccurrences(of: "Synthetic", with: #"line\nline"#),
                     valid.replacingOccurrences(of: "synthetic-put", with: "bad/id")] {
            await reject(request(body: body), using: transport)
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testGetBodyBodyStreamAndWrongMediaTypeCannotCrossBoundary() async throws {
        let wire = Wire(), (transport, _) = try setup(wire)
        await reject(request("GET", body: valid), using: transport)
        for method in ["GET", "PUT", "DELETE"] {
            var streamed = request(method)
            streamed.httpBodyStream = InputStream(data: Data(valid.utf8))
            streamed.setValue("application/json", forHTTPHeaderField: "Content-Type")
            await reject(streamed, using: transport)
        }
        var wrong = request(body: valid); wrong.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        await reject(wrong, using: transport)
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testPrivacyCacheRequirementsAreCheckedAtFinalForward() async throws {
        let wire = Wire(), (transport, _) = try setup(wire)
        for method in ["GET", "PUT", "DELETE"] {
            for variant in 0..<3 {
                var value = request(method, body: method == "GET" ? nil : (method == "PUT" ? valid : delete))
                if variant == 0 { value.cachePolicy = .useProtocolCachePolicy }
                if variant == 1 { value.setValue(nil, forHTTPHeaderField: "Cache-Control") }
                if variant == 2 { value.setValue(nil, forHTTPHeaderField: "Pragma") }
                await reject(value, using: transport)
            }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExactRouteMethodAndExistingGrantRemainRequired() async throws {
        let wire = Wire(), (transport, _) = try setup(wire)
        for suffix in ["?ownerId=7", "?", "/", "/return/restore", "#fragment"] {
            var value = request(body: valid)
            value.url = URL(string: endpoint.appendingPathComponent(PrivateHomeService.path).absoluteString + suffix)
            await reject(value, using: transport)
        }
        for method in ["POST", "PATCH", "HEAD"] { await reject(request(method, body: valid), using: transport) }
        let (disabled, _) = try setup(wire, granted: false)
        await reject(request("GET"), using: disabled)
        var foreignToken = request("GET"); foreignToken.setValue("another-token", forHTTPHeaderField: "Authorization")
        await reject(foreignToken, using: transport)
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testControllerUTF16LengthBoundAndMalformedUTF8FailClosed() async throws {
        let wire = Wire(), (transport, _) = try setup(wire)
        let atLimit = valid + String(repeating: " ", count: 4096 - valid.utf16.count)
        _ = try await transport.send(request(body: atLimit))
        let multibyte = valid.replacingOccurrences(of: "Synthetic", with: String(repeating: "家", count: 40))
        let multibyteAtLimit = multibyte + String(repeating: " ", count: 4096 - multibyte.utf16.count)
        XCTAssertGreaterThan(multibyteAtLimit.utf8.count, 4096)
        _ = try await transport.send(request(body: multibyteAtLimit))
        await reject(request(body: atLimit + " "), using: transport)
        var badUTF8 = request(body: valid); badUTF8.httpBody = Data([0xff, 0xfe])
        await reject(badUTF8, using: transport)
        XCTAssertEqual(wire.requests.count, 2); XCTAssertEqual(wire.requests[0].httpBody, Data(atLimit.utf8))
        XCTAssertEqual(wire.requests[1].httpBody, Data(multibyteAtLimit.utf8))
    }
    func testBoundaryDoesNotChangeResponsesOrInventSuccess() async throws {
        let wire = Wire(), (transport, _) = try setup(wire)
        let raw = Data(#"{"code":503,"msg":"PRIVATE_HOME_UNAVAILABLE"}"#.utf8)
        wire.response = (raw, 503)
        let result = try await transport.send(request("GET"))
        XCTAssertEqual(result.0, raw); XCTAssertEqual(result.1, 503)
        XCTAssertEqual(wire.requests.count, 1)
    }
}

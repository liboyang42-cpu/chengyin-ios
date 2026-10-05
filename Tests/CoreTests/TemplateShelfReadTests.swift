import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class TemplateShelfReadTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func context(account: Int = 7, epoch: UInt64 = 1, role: String = "player", namespace: String = "shelf", token: String = "synthetic") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: role, session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    private func form(_ path: String, _ fields: [String: String], boundary: String = "Shelf-boundary") throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: fields, token: "synthetic", boundary: boundary)
    }
    private var fields: [String: String] { ["is_quote": "", "keyword": "", "category_id": "", "pageNum": "1", "pageSize": "10"] }
    func testCanonicalActualBuildersAndBoundedPages() throws {
        let config = try APIConfiguration(baseURL: base)
        XCTAssertEqual("\r\n".count, 1)
        XCTAssertEqual(Array("\r\n".utf8), [13, 10])
        for page in [1, 2, 100] {
            for keyword in ["", "x", "城", "城 & café", "e\u{301}", "👩🏽‍💻", "می\u{200C}روم", "♥\u{FE0E}", "♥\u{FE0F}", "禰\u{E0100}", String(repeating: "界", count: 170) + "aa", String(repeating: "x", count: 512)] {
                for boundary in ["B", "Shelf-boundary", String(repeating: "Z", count: 70)] {
                    let request = try TemplateAuthoringWireRequestBuilder.make(TemplateOwnShelfPage.request(page: page, keyword: keyword), configuration: config, token: "synthetic", boundary: boundary)
                    XCTAssertEqual(TemplateShelfReadRoute(request: request, baseURL: base), .page(page, keyword: keyword))
                    // Verify the actual producer bytes keep each complete value and its CRLF.
                    let body = try XCTUnwrap(request.httpBody)
                    XCTAssertNotNil(body.range(of: Data(("name=\"pageSize\"\r\n\r\n10\r\n").utf8)))
                    XCTAssertNotNil(body.range(of: Data(("name=\"keyword\"\r\n\r\n" + keyword + "\r\n").utf8)))
                }
            }
        }
        for value in [1, 9, 10, 41, Int.max] {
            let id = try XCTUnwrap(MemberPlayTemplateID(rawValue: value))
            let request = try form("api/template/myinfo", ["id": String(value)])
            XCTAssertEqual(TemplateShelfReadRoute(request: request, baseURL: base), .detail(id))
            XCTAssertNotNil(try XCTUnwrap(request.httpBody).range(of: Data(("name=\"id\"\r\n\r\n\(value)\r\n").utf8)))
        }
        XCTAssertNil(TemplateShelfReadRoute(request: try TemplateAuthoringWireRequestBuilder.make(TemplateAuthoringContract.listMine(), configuration: config, token: "synthetic"), baseURL: base))
    }
    func testRejectsAllAlternateFormsBeforeDispatch() throws {
        var invalid: [URLRequest] = []
        for (key, value) in [("pageNum", "0"), ("pageNum", "101"), ("pageNum", "01"), ("pageNum", "+1"), ("pageNum", "1.0"), ("pageSize", "100"), ("scope", "merchant"), ("memberId", "8"), ("category_id", "1"), ("is_quote", "1"), ("keyword", String(repeating: "x", count: 513)), ("keyword", "x\r\ny")] {
            var values = fields; values[key] = value; invalid.append(try form("api/template/my-list", values))
        }
        for id in ["0", "-1", "01", "+1", "1.0", " 1", "true", "99999999999999999999999"] { invalid.append(try form("api/template/myinfo", ["id": id])) }
        invalid.append(try form("api/template/myinfo", ["id": "41", "scope": "merchant"]))
        for path in ["draft", "publish", "delete", "updateLibraryStatus", "info", "list", "41/market-submit"] { invalid.append(try form("api/template/" + path, fields)) }
        invalid.append(try form("api/common/dict", ["dictType": "app_template_difficulty"]))
        let canonical = try form("api/template/myinfo", ["id": "41"])
        let body = String(data: canonical.httpBody!, encoding: .utf8)!
        for altered in ["--Shelf-boundary\r\nContent-Disposition: form-data; name=\"\r\n\r\nx\r\n--Shelf-boundary--\r\n", "--Shelf-boundary\r\nContent-Disposition: form-data; name=\"", body.replacingOccurrences(of: "name=\"id\"", with: "name=\"\""), body.replacingOccurrences(of: "name=\"id\"", with: "name=\"id\"; filename=\"a\""), body.replacingOccurrences(of: "\r\n\r\n41", with: "\r\nContent-Type: text/plain\r\n\r\n41"), body.replacingOccurrences(of: "--Shelf-boundary--", with: "--Shelf-boundary\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n41\r\n--Shelf-boundary--"), body + "extra", body.replacingOccurrences(of: "41\r\n--Shelf-boundary", with: "41\n--Shelf-boundary"), body.replacingOccurrences(of: "41\r\n--Shelf-boundary", with: "41\r--Shelf-boundary"), body.replacingOccurrences(of: "41\r\n--Shelf-boundary", with: "41--Shelf-boundary"), body.replacingOccurrences(of: "41\r\n--Shelf-boundary", with: "41\r\n\r\n--Shelf-boundary"), body.replacingOccurrences(of: "\r\n", with: "\n")] {
            var request = canonical; request.httpBody = Data(altered.utf8); invalid.append(request)
        }
        for type in ["application/json", "multipart/form-data; boundary=Shelf-boundary; charset=utf-8", "multipart/form-data; boundary=\"Shelf-boundary\""] { var request = canonical; request.setValue(type, forHTTPHeaderField: "Content-Type"); invalid.append(request) }
        for url in ["https://evil.test/native/api/template/myinfo", "https://example.test/other/api/template/myinfo", "https://example.test/native/api/template/myinfo?x=1", "https://example.test/native/api/template/myinfo#x", "https://example.test/native/api/template/%6dyinfo", "https://example.test/native/api/template/../template/myinfo"] { var request = canonical; request.url = URL(string: url); invalid.append(request) }
        var request = canonical; request.httpMethod = "GET"; invalid.append(request)
        request = canonical; request.httpBody = Data(repeating: 65, count: 4097); invalid.append(request)
        request = canonical; request.httpBodyStream = InputStream(data: Data()); invalid.append(request)
        for request in invalid { XCTAssertNil(TemplateShelfReadRoute(request: request, baseURL: base), "\(request)") }
    }
    func testKeywordJoinersDoNotAdmitControlsBidiFormatsOrUnicodeLineBreaks() throws {
        // Exercise actual multipart requests rather than a policy helper alone.
        let controls = Array(0...31) + Array(127...159) + [0x061C, 0x200B, 0x200E, 0x200F,
            0x2028, 0x2029, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
            0x2060, 0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF, 0xE0067, 0xE007F]
        for value in controls {
            let scalar = try XCTUnwrap(UnicodeScalar(value))
            var values = fields; values["keyword"] = "a" + String(scalar) + "b"
            let request = try form("api/template/my-list", values)
            XCTAssertNil(TemplateShelfReadRoute(request: request, baseURL: base), "Forbidden scalar U+\(String(value, radix: 16))")
        }
        for keyword in [String(repeating: "界", count: 171), "👩🏽‍💻" + "\r\n", "می\u{200C}روم\u{202E}"] {
            var values = fields; values["keyword"] = keyword
            XCTAssertNil(TemplateShelfReadRoute(request: try form("api/template/my-list", values), baseURL: base))
        }
    }
    func testIndependentCanReadNeverCanSubmitAndRejectsForgedReadMutation() async throws {
        let wire = Wire(), context = try context(), lease = try TemplateShelfReadApproval(context: context, expiresAt: Date().addingTimeInterval(600))
        let read = TemplateShelfReadTransport(configuration: try .init(baseURL: base), http: wire, approval: lease, current: { context })
        let adapter = TemplateAuthoringAdapter(shelfReadTransport: read)
        XCTAssertTrue(adapter.canRead); XCTAssertFalse(adapter.canSubmit); XCTAssertFalse(adapter.canSimulate)
        _ = try await adapter.listMinePage(page: 1, keyword: "")
        XCTAssertEqual(wire.requests.count, 1)
        do { _ = try await adapter.listMine(); XCTFail("first100 preflight granted") } catch {}
        for path in ["draft", "publish", "delete", "updateLibraryStatus", "41/market-submit"] {
            for mutates in [false, true] {
                let descriptor = TemplateAuthoringRequest(path: "/api/template/" + path, body: .form(fields), mutates: mutates)
                do { _ = try await read.page(descriptor); XCTFail() } catch {}
                let outcome = await adapter.submit(descriptor); XCTAssertEqual(outcome, .notSent)
            }
        }
        XCTAssertEqual(wire.requests.count, 1)
        lease.revoke(); XCTAssertFalse(adapter.canRead)
        do { _ = try await adapter.listMinePage(page: 1, keyword: ""); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testDetailRequiresExactOwnedIdentityAndNeverFallsBack() async throws {
        for row in [#"{"id":41,"memberId":7}"#, #"{"id":42,"memberId":7}"#, #"{"id":41,"memberId":8}"#, #"{"id":41}"#] {
            let wire = Wire(); wire.json = "{\"code\":200,\"data\":\(row)}"
            let context = try context(), lease = try TemplateShelfReadApproval(context: context, expiresAt: Date().addingTimeInterval(600))
            let read = TemplateShelfReadTransport(configuration: try .init(baseURL: base), http: wire, approval: lease, current: { context })
            do { _ = try await read.detail(MemberPlayTemplateID(rawValue: 41)!); XCTAssertEqual(row, #"{"id":41,"memberId":7}"#) }
            catch { XCTAssertNotEqual(row, #"{"id":41,"memberId":7}"#) }
            XCTAssertEqual(wire.requests.count, 1)
            let request = try XCTUnwrap(wire.requests.first, "A canonical owned-detail read must dispatch exactly once")
            XCTAssertEqual(request.url?.path, "/native/api/template/myinfo")
        }
    }
    func testLeaseExactContextAndIrreversibleExpiry() throws {
        let original = try context(), lease = try TemplateShelfReadApproval(context: original, expiresAt: Date().addingTimeInterval(600))
        XCTAssertTrue(lease.matches(original))
        for changed in [try context(account: 8), try context(epoch: 2), try context(role: "merchant"), try context(namespace: "other"), try context(token: "rotated")] { XCTAssertFalse(lease.matches(changed)) }
        XCTAssertThrowsError(try TemplateShelfReadApproval(context: original, expiresAt: Date().addingTimeInterval(86_500)))
        let insecure = RuntimeDependencyContext(market: .china, baseURL: URL(string: "http://example.test/native")!, role: "player", session: original.session)
        XCTAssertThrowsError(try TemplateShelfReadApproval(context: insecure, expiresAt: Date().addingTimeInterval(600)))
        lease.expireIfNeeded(now: lease.expiresAt); XCTAssertFalse(lease.matches(original, now: Date.distantPast))
        XCTAssertEqual(TemplateShelfReadApproval.expiryDelay(until: Date(timeIntervalSince1970: 100), now: Date(timeIntervalSince1970: 90)), 10)
    }
    func testReadOnlyRefreshRevocationAndReopenPreserveBothPendingJournals() async throws {
        let context = try context(), lease = try TemplateShelfReadApproval(context: context, expiresAt: Date().addingTimeInterval(600))
        let storage = TemplateAuthoringMemoryStorage(), store = TemplateAuthoringLocalStore(storage: storage), wire = Wire()
        let session = try TemplateAuthoringSession(accountID: 7, namespace: "shelf", epoch: 1, authorizationRevision: "player")
        var current: TemplateAuthoringSession? = session
        let identity = TemplateAuthoringIdentity()
        let pending = TemplateAuthoringPending(operationID: UUID(), ownerKey: session.ownerKey, identity: identity, request: try TemplateAuthoringContract.request(.init(title: "Unknown draft"), intent: .saveDraft), createdAt: Date())
        try store.savePending(pending, session: session)
        let row = try JSONDecoder().decode(DiscoveryPlayTemplate.self, from: Data(#"{"id":41,"title":"Unknown shelf"}"#.utf8))
        let shelf = TemplateOwnShelfPending(review: try .init(row: row, action: .remove, session: session, generation: 0))
        try store.saveShelfPending(shelf, session: session)
        let read = TemplateShelfReadTransport(configuration: try .init(baseURL: base), http: wire, approval: lease, current: { current == nil ? nil : context })
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(shelfReadTransport: read), store: store, currentSession: { current })
        coordinator.open(); await coordinator.shelfReader.refresh()
        // Even an explicit legacy first100 call remains blocked and cannot reconcile.
        await coordinator.loadMine(); lease.revoke(); current = nil; coordinator.synchronizeSession()
        current = session; coordinator.open(); await coordinator.shelfReader.refresh()
        XCTAssertEqual(try store.pending(session: session, identity: identity), pending)
        XCTAssertEqual(try store.shelfPending(session: session), shelf)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertFalse(coordinator.canSubmit)
    }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var json = #"{"code":200,"data":{"rows":[],"total":0}}"#
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(json.utf8), 200) }
    }
}

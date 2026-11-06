import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ProjectAuthorInputReaderTests: XCTestCase {
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var templates: [String: Any] = ["id": 41, "memberId": 7, "canEdit": true, "delFlag": 0, "advancedConfigJson": "{}"]
        var callback: (() -> Void)?
        var status = 200
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); callback?()
            let matrix: [String: Any] = ["schemaVersion": 1, "types": [], "addons": [], "constraints": [:], "legacyProofs": [:],
                "zeroHpPolicies": ["generic": ["WAIT"], "legacy": ["BLOCK_HP_COST"]]]
            return (try JSONSerialization.data(withJSONObject: ["code": status, "data": request.httpMethod == "GET" ? matrix : templates]), status)
        }
    }
    private func context(account: Int = 7) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://author.test/")!, role: "player",
            session: try .init(accountID: account, epoch: 2, namespace: "author-fixture", token: "test-token", role: "player"))
    }
    private func session(account: Int = 7) throws -> ProjectEditSession { try .init(accountID: account, epoch: 2, storageNamespace: "author-fixture") }
    private func routes() throws -> Set<BusinessRuntimeRoute> { [try ProjectAuthorInputReadRoute.support.businessRoute, try ProjectAuthorInputReadRoute.template(41).businessRoute] }
    private func draft(bound: Bool = true) -> ProjectEditDraft {
        var d = ProjectEditDraft()
        if bound { var node = ProjectEditNode(); node.templateID = 41; var chapter = ProjectEditChapter(); chapter.nodes = [node, node]; d.chapters = [chapter] }
        return d
    }
    func testOnlyDedicatedExactMethodsAreCatalogued() throws {
        for route in try routes() {
            XCTAssertTrue(BusinessRuntimeFeature.projectAuthorInputRead.accepts(route))
            XCTAssertFalse(BusinessRuntimeFeature.projectRead.accepts(route)); XCTAssertFalse(BusinessRuntimeFeature.publishingRead.accepts(route))
        }
        XCTAssertFalse(BusinessRuntimeFeature.projectAuthorInputRead.accepts(try .post(NativeRuntimeStructureAuthorInputs.supportPath)))
        XCTAssertFalse(BusinessRuntimeFeature.projectAuthorInputRead.accepts(try .init(method: "GET", path: NativeRuntimeStructureAuthorInputs.templatePath)))
    }
    func testMissingGrantAndDefaultCurrentAreZeroNetwork() async throws {
        let wire = Wire(), c = try context(), s = try session()
        XCTAssertThrowsError(try ProjectAuthorInputReader(context: c, session: s, routes: [], transport: wire))
        let reader = try ProjectAuthorInputReader(context: c, session: s, routes: routes(), transport: wire)
        do { _ = try await reader.runtimeStructureInputs(draft: draft(), session: s); XCTFail("default grant opened") } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testRealMatrixAndExactDeduplicatedOwnedTemplateRead() async throws {
        let wire = Wire(), c = try context(), s = try session()
        let reader = try ProjectAuthorInputReader(context: c, session: s, routes: routes(), transport: wire, current: { true })
        let inputs = try await reader.runtimeStructureInputs(draft: draft(), session: s)
        XCTAssertEqual(wire.requests.count, 2)
        XCTAssertEqual(ProjectAuthorInputReadRoute(request: wire.requests[0], baseURL: c.baseURL), .support)
        XCTAssertEqual(ProjectAuthorInputReadRoute(request: wire.requests[1], baseURL: c.baseURL), .template(41))
        XCTAssertEqual(inputs.matrix["zeroHpPolicies"]?.object?["generic"], .array([.string("WAIT")]))
        XCTAssertEqual(Set(inputs.templates.keys), [41]); XCTAssertTrue(reader.runtimeStructureInputsAreCurrent(inputs, session: s))
        XCTAssertFalse(reader.runtimeStructureInputsAreCurrent(inputs, session: try session(account: 8)))
        XCTAssertTrue(wire.requests.allSatisfy { !$0.httpShouldHandleCookies })
    }
    func testBoundTemplateNeedsOwnRouteBeforeEvenMatrixRead() async throws {
        let wire = Wire(), s = try session()
        let reader = try ProjectAuthorInputReader(context: context(), session: s, routes: [try ProjectAuthorInputReadRoute.support.businessRoute], transport: wire, current: { true })
        do { _ = try await reader.runtimeStructureInputs(draft: draft(), session: s); XCTFail("partial route accepted") } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testForeignPublicStrippedOrNoneditableTemplateNeverCountsAsOwnedProof() async throws {
        for field in ["memberId", "canEdit", "id", "advancedConfigJson"] {
            let wire = Wire(), s = try session()
            switch field { case "memberId": wire.templates[field] = 8
            case "canEdit": wire.templates[field] = false
            case "id": wire.templates[field] = 42
            default: wire.templates[field] = ["untrusted": true] }
            let reader = try ProjectAuthorInputReader(context: context(), session: s, routes: routes(), transport: wire, current: { true })
            do { _ = try await reader.runtimeStructureInputs(draft: draft(), session: s); XCTFail(field) } catch {}
            XCTAssertEqual(wire.requests.count, 2)
        }
    }
    func testRevocationDuringReadDiscardsResponseAndCannotReviveSameReader() async throws {
        let wire = Wire(), s = try session(); var current = true
        let reader = try ProjectAuthorInputReader(context: context(), session: s, routes: routes(), transport: wire, current: { current })
        wire.callback = { current = false }
        do { _ = try await reader.runtimeStructureInputs(draft: draft(), session: s); XCTFail("late response accepted") } catch {}
        XCTAssertEqual(wire.requests.count, 1); current = true; wire.callback = nil
        do { _ = try await reader.runtimeStructureInputs(draft: draft(), session: s); XCTFail("retired reader revived") } catch {}
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testUnauthorizedReadRetiresCapturedReaderWithoutWriting() async throws {
        let wire = Wire(), s = try session(); wire.status = 401
        let reader = try ProjectAuthorInputReader(context: context(), session: s, routes: routes(), transport: wire, current: { true })
        do { _ = try await reader.runtimeStructureInputs(draft: draft(), session: s); XCTFail("401 accepted") } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        wire.status = 200
        do { _ = try await reader.runtimeStructureInputs(draft: draft(), session: s); XCTFail("401 reader revived") } catch {}
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testMerchantScopeAndQueryCookieAlternateOriginAreRejected() throws {
        let c = try context()
        func request(scope: String = "") throws -> URLRequest {
            var r = try AuthRequestBuilder.makeFormRequest(url: c.baseURL.appendingPathComponent(NativeRuntimeStructureAuthorInputs.templatePath), fields: ["id": "41", "scope": scope], token: c.session.token)
            r.httpShouldHandleCookies = false; return r
        }
        XCTAssertNotNil(ProjectAuthorInputReadRoute(request: try request(), baseURL: c.baseURL))
        XCTAssertNil(ProjectAuthorInputReadRoute(request: try request(scope: "MERCHANT"), baseURL: c.baseURL))
        XCTAssertNil(ProjectAuthorInputReadRoute(request: try request(scope: "MY"), baseURL: c.baseURL))
        for bad in ["https://other.test/api/template/myinfo", "https://author.test/api/template/myinfo?id=41", "https://author.test/api/template/myinfo#x"] {
            var r = try request(); r.url = URL(string: bad); XCTAssertNil(ProjectAuthorInputReadRoute(request: r, baseURL: c.baseURL))
        }
        var r = try request(); r.httpShouldHandleCookies = true; XCTAssertNil(ProjectAuthorInputReadRoute(request: r, baseURL: c.baseURL))
    }
}

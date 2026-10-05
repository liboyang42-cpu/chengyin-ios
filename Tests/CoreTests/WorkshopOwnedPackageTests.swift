import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

enum WorkshopPackageTestData {
    static func info() -> [String: Any] {
        ["versionLabel": "fixture-v1", "validUntil": "2026-11-04T00:00:00Z", "schemaVersion": 1,
         "contentHash": String(repeating: "a", count: 64), "termsVersion": "terms-1", "termsHash": String(repeating: "b", count: 64),
         "commercialUse": "PROHIBITED", "adaptation": "BIND_RESOURCES_ONLY", "translation": "ALLOWED", "updates": "EXACT_PURCHASED_VERSION",
         "redistribution": "PROHIBITED", "allowedRegions": ["fixture-region"], "themeLimit": ["unlimited": false, "maximum": 1],
         "merchantLimit": ["unlimited": false, "maximum": 0], "runLimit": ["unlimited": true, "maximum": 0], "requiredBindingCount": 0]
    }
    static func object(id: String = "synthetic-claim", state: String = "PACKAGE_METADATA_ONLY", info: [String: Any]? = WorkshopPackageTestData.info()) -> [String: Any] {
        ["schema": "workshop-package-v1", "scope": "FREE_INDIVIDUAL_ONLY", "claimId": id, "checkedAt": "2026-10-05T00:00:00Z",
         "availability": state, "purchasedLibraryStatus": "NOT_AVAILABLE", "contentUseStatus": "UNAVAILABLE", "manifestStatus": "NOT_AVAILABLE",
         "editorStatus": "POST_INSTALL_POLICY_UNAVAILABLE", "packageInfo": info as Any? ?? NSNull()]
    }
}
final class WorkshopPackageDecoderTests: XCTestCase {
    func testFrozenMetadataPreservesZeroAndUnlimited() throws {
        let value: WorkshopOwnedPackage = try WorkshopOwnedTestData.decode(WorkshopPackageTestData.object())
        XCTAssertEqual(value.packageInfo?.versionLabel, "fixture-v1"); XCTAssertEqual(value.packageInfo?.translation, .allowed)
        XCTAssertEqual(value.packageInfo?.merchantLimit.maximum, 0); XCTAssertEqual(value.packageInfo?.runLimit.unlimited, true)
    }
    func testUnavailableCannotContainMetadata() throws {
        for state in ["NOT_ENABLED", "UNAVAILABLE"] {
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopPackageTestData.object(state: state), as: WorkshopOwnedPackage.self))
            let value: WorkshopOwnedPackage = try WorkshopOwnedTestData.decode(WorkshopPackageTestData.object(state: state, info: nil)); XCTAssertNil(value.packageInfo)
        }
        XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopPackageTestData.object(info: nil), as: WorkshopOwnedPackage.self))
    }
    func testNoPaidContentManifestOrEditorExpansion() throws {
        for (key, value) in [("scope", "PAID"), ("contentUseStatus", "ALLOWED"), ("manifestStatus", "AVAILABLE"), ("editorStatus", "EDITABLE"), ("purchasedLibraryStatus", "AVAILABLE")] {
            var object = WorkshopPackageTestData.object(); object[key] = value
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(object, as: WorkshopOwnedPackage.self))
        }
    }
    func testMissingOrPrivateFieldsFailClosed() throws {
        for key in WorkshopPackageTestData.info().keys {
            var info = WorkshopPackageTestData.info(); info.removeValue(forKey: key)
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopPackageTestData.object(info: info), as: WorkshopOwnedPackage.self))
        }
        for key in ["content", "questionAnswer", "sourceId", "moduleId", "seller", "termsDocumentReference"] {
            var info = WorkshopPackageTestData.info(); info[key] = "private"
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopPackageTestData.object(info: info), as: WorkshopOwnedPackage.self))
        }
    }
    func testUnknownRightsCannotBeCoerced() throws {
        for (key, value) in [("updates", "ALL_FUTURE_VERSIONS"), ("redistribution", "ALLOWED"), ("adaptation", "UNLIMITED"), ("commercialUse", "YES")] {
            var info = WorkshopPackageTestData.info(); info[key] = value
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopPackageTestData.object(info: info), as: WorkshopOwnedPackage.self))
        }
    }
    func testExplicitQuotaAndRegionBounds() throws {
        let limits: [[String: Any]] = [["unlimited": true, "maximum": 1], ["unlimited": false, "maximum": -1], ["unlimited": "false", "maximum": 0]]
        for limit in limits {
            var info = WorkshopPackageTestData.info(); info["themeLimit"] = limit
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopPackageTestData.object(info: info), as: WorkshopOwnedPackage.self))
        }
        for regions in [[], ["same", "same"], (0..<65).map { "r-\($0)" }] as [[String]] {
            var info = WorkshopPackageTestData.info(); info["allowedRegions"] = regions
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopPackageTestData.object(info: info), as: WorkshopOwnedPackage.self))
        }
    }
    func testDisplayTextHashesAndDeadlineAreStrict() throws {
        for text in ["", " leading", "a\nb", "a\u{202E}b", String(repeating: "x", count: 129)] {
            var info = WorkshopPackageTestData.info(); info["versionLabel"] = text
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopPackageTestData.object(info: info), as: WorkshopOwnedPackage.self))
        }
        for key in ["contentHash", "termsHash", "validUntil"] {
            var info = WorkshopPackageTestData.info(); info[key] = NSNull()
            XCTAssertThrowsError(try WorkshopOwnedTestData.decode(WorkshopPackageTestData.object(info: info), as: WorkshopOwnedPackage.self))
        }
    }
}

@MainActor final class WorkshopPackageFlowTests: XCTestCase {
    private final class State { var approval: WorkshopOwnedPackageReadApproval?; var unauthorized = 0 }
    private final class Transport: HTTPTransport {
        var paused = false
        var requests: [URLRequest] = []
        var pending: [CheckedContinuation<(Data, Int), Error>] = []
        var response: (Data, Int) = try! WorkshopOwnedTestData.response(WorkshopPackageTestData.object())
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); if paused { return try await withCheckedThrowingContinuation { pending.append($0) } }; return response }
        func release(_ value: (Data, Int)) throws { let first = try XCTUnwrap(pending.first); pending.removeFirst(); first.resume(returning: value) }
    }
    private struct Harness { let browser: WorkshopOwnedPackageBrowser; let transport: Transport; let state: State; let permit: WorkshopOwnedPresentationPermit }
    private func harness(approved: Bool = true) throws -> Harness {
        let c = try WorkshopOwnedTestData.context(), state = State(), transport = Transport()
        let approval = try WorkshopOwnedPackageReadApproval(context: c, expiresAt: .distantFuture); state.approval = approved ? approval : nil
        let lease = ContentDraftSessionLease(context: c, current: { c })
        let service = WorkshopOwnedPackageService(api: try APIConfiguration(baseURL: c.baseURL), transport: transport, lease: lease,
            approval: state.approval, currentApproval: { state.approval }, onUnauthorized: { _ in state.unauthorized += 1 })
        let browser = WorkshopOwnedPackageBrowser(reader: service, lease: lease)
        return .init(browser: browser, transport: transport, state: state, permit: try XCTUnwrap(browser.present(claimId: "synthetic-claim")))
    }
    private var unauthorized: (Data, Int) { (Data("{\"code\":401}".utf8), 200) }
    private func wait(_ check: () -> Bool) async throws { for _ in 0..<100 { if check() { return }; await Task.yield() }; XCTAssertTrue(check()); if !check() { throw WorkshopOwnedIssue.unavailable } }
    func testSeparateApprovalDefaultsOff() async throws { let h = try harness(approved: false); await h.browser.load(claimId: "synthetic-claim", action: h.permit.offer()!); XCTAssertEqual(h.browser.phase, .unavailable); XCTAssertTrue(h.transport.requests.isEmpty) }
    func testExactPackageFormAndSuccess() async throws {
        let h = try harness(); await h.browser.load(claimId: "synthetic-claim", action: h.permit.offer()!); XCTAssertEqual(h.browser.phase, .ready)
        let r = try XCTUnwrap(h.transport.requests.first); XCTAssertEqual(r.url?.path, "/native/api/workshop/owned/package")
        XCTAssertEqual(r.httpBody, Data("claim_id=synthetic-claim".utf8)); XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Length"), String(r.httpBody!.count)); XCTAssertNil(r.url?.query)
    }
    func testWrongIdentityAndUnavailableCannotKeepPriorMetadata() async throws {
        let h = try harness(); await h.browser.load(claimId: "synthetic-claim", action: h.permit.offer()!)
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopPackageTestData.object(id: "other")); await h.browser.load(claimId: "synthetic-claim", action: h.permit.offer()!)
        XCTAssertNil(h.browser.value); XCTAssertEqual(h.browser.issue, .malformed)
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopPackageTestData.object(state: "UNAVAILABLE", info: nil)); await h.browser.load(claimId: "synthetic-claim", action: h.permit.offer()!)
        XCTAssertEqual(h.browser.phase, .unavailable); XCTAssertNil(h.browser.value?.packageInfo)
    }
    func testCloseAndCancelledReadSuppressLate401() async throws {
        for cancel in [false, true] {
            let h = try harness(); h.transport.paused = true; let read = Task { [action = h.permit.offer()!] in await h.browser.load(claimId: "synthetic-claim", action: action) }; try await wait { h.transport.pending.count == 1 }
            if cancel { read.cancel() } else { h.browser.close() }; try h.transport.release(unauthorized); await read.value
            XCTAssertEqual(h.state.unauthorized, 0); XCTAssertNil(h.browser.value)
        }
    }
    func testNewSelectionRetiresOld401() async throws {
        let h = try harness(); h.transport.paused = true
        let first = Task { [action = h.permit.offer()!] in await h.browser.load(claimId: "synthetic-claim", action: action) }; try await wait { h.transport.pending.count == 1 }
        let nextPermit = try XCTUnwrap(h.browser.present(claimId: "next-claim"))
        let next = Task { [action = nextPermit.offer()!] in await h.browser.load(claimId: "next-claim", action: action) }; try await wait { h.transport.pending.count == 2 }
        try h.transport.release(unauthorized); await first.value; XCTAssertEqual(h.state.unauthorized, 0)
        try h.transport.release(WorkshopOwnedTestData.response(WorkshopPackageTestData.object(id: "next-claim"))); await next.value; XCTAssertEqual(h.browser.value?.claimId, "next-claim")
    }
    func testInvalidSelectionRetiresOldRead() async throws {
        let h = try harness(); h.transport.paused = true
        let read = Task { [action = h.permit.offer()!] in await h.browser.load(claimId: "synthetic-claim", action: action) }; try await wait { h.transport.pending.count == 1 }
        XCTAssertNil(h.browser.present(claimId: "x&owner=8")); try h.transport.release(unauthorized); await read.value
        XCTAssertEqual(h.state.unauthorized, 0); XCTAssertEqual(h.browser.issue, .invalid)
    }
    func testRevokedApprovalAndInvalidationSuppress401() async throws {
        for invalidate in [false, true] {
            let h = try harness(); h.transport.paused = true
            let read = Task { [action = h.permit.offer()!] in await h.browser.load(claimId: "synthetic-claim", action: action) }; try await wait { h.transport.pending.count == 1 }
            if invalidate { h.browser.invalidate() } else { h.state.approval = nil }
            try h.transport.release(unauthorized); await read.value; XCTAssertEqual(h.state.unauthorized, 0); XCTAssertNil(h.browser.value)
        }
    }
    func testCurrent401StillNotifies() async throws { let h = try harness(); h.transport.response = unauthorized; await h.browser.load(claimId: "synthetic-claim", action: h.permit.offer()!); XCTAssertEqual(h.state.unauthorized, 1) }
}

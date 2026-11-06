import XCTest
import Observation
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Original two GETs and both pre-existing approval selections; memory transport only.
@MainActor final class RoamPassportToolsGrantScopeTests: XCTestCase {
    func testReadGrantReplacementChangesScopeButNotIdentity() throws {
        let r = try PassportScopeRig(), scope = r.reader.readScope, identity = r.reader.identity
        XCTAssertEqual(scope, r.reader.readScope)
        r.readAccess = try r.readGrant()
        XCTAssertEqual(identity, r.reader.identity); XCTAssertNotEqual(scope, r.reader.readScope)
        XCTAssertEqual(r.reader.readScope, r.reader.readScope); XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testPrivateGrantKeepsOriginalPriorityAndUnusedFallbackDoesNotRetire() throws {
        let r = try PassportScopeRig(); r.privateAccess = try r.privateGrant()
        let scope = r.reader.readScope
        r.readAccess = try r.readGrant(); XCTAssertEqual(scope, r.reader.readScope)
        r.readAccess?.revoke(); XCTAssertEqual(scope, r.reader.readScope)
        r.privateAccess = try r.privateGrant(); XCTAssertNotEqual(scope, r.reader.readScope)
        XCTAssertTrue(r.reader.isConfigured); XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testPrivateRevocationFallsBackToExistingReadGrantWithANewScope() throws {
        let r = try PassportScopeRig(); r.privateAccess = try r.privateGrant()
        let scope = r.reader.readScope, identity = r.reader.identity
        r.privateAccess?.revoke()
        XCTAssertTrue(r.reader.isConfigured); XCTAssertEqual(identity, r.reader.identity)
        XCTAssertNotEqual(scope, r.reader.readScope)
        let fallback = r.reader.readScope; r.privateAccess = try r.privateGrant()
        XCTAssertNotEqual(fallback, r.reader.readScope)
    }
    func testSelectedRevocationIsObservableAndReapprovalCannotReviveOldScope() throws {
        let r = try PassportScopeRig(), original = r.reader.readScope
        let changed = expectation(description: "selected approval changed")
        withObservationTracking { _ = r.reader.readScope } onChange: { changed.fulfill() }
        r.readAccess?.revoke(); let unavailable = r.reader.readScope
        XCTAssertFalse(r.reader.isConfigured); XCTAssertNotEqual(original, unavailable)
        r.readAccess = try r.readGrant()
        XCTAssertNotEqual(original, r.reader.readScope); XCTAssertNotEqual(unavailable, r.reader.readScope)
        wait(for: [changed], timeout: 0.1)
    }
    func testContextTokenBoundaryDoesNotNeedAnIdentityChange() throws {
        let r = try PassportScopeRig(), original = r.reader.readScope, identity = r.reader.identity
        r.context = .init(market: .china, baseURL: PassportScopeRig.base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "passport-scope", token: "new-synthetic-token"))
        XCTAssertEqual(identity, r.reader.identity); XCTAssertNotEqual(original, r.reader.readScope)
        XCTAssertFalse(r.reader.isConfigured); XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testFullSessionTokenAndNilBoundaryAlsoRetireReadPresentation() throws {
        let r = try PassportScopeRig(), live = try r.fullSessionReader()
        let original = live.readScope, identity = live.identity
        r.session = try .init(scope: r.session!.identity.scope, epoch: 1, token: "new-session-token")
        XCTAssertEqual(identity, live.identity); XCTAssertNotEqual(original, live.readScope)
        let changed = live.readScope; r.session = nil
        XCTAssertNil(live.identity); XCTAssertFalse(live.isConfigured); XCTAssertNotEqual(changed, live.readScope)
    }
    func testOtherPrivatePathsCannotAuthorizeTheseTwoGETs() throws {
        let r = try PassportScopeRig(); r.readAccess = nil
        r.privateAccess = try r.privateGrant(paths: RoamPrivateToolsRoute.reads)
        _ = r.reader.readScope; XCTAssertFalse(r.reader.isConfigured)
        r.privateAccess = try r.privateGrant(paths: Set(RoamPassportToolsService.paths))
        XCTAssertTrue(r.reader.isConfigured); XCTAssertFalse(r.privateAccess!.allowsWrites)
        XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testMonthlyDetailAndOldReturnRetireBeforeViewCallbacksOnSameIdentityReplacement() async throws {
        let r = try PassportScopeRig(), model = r.model()
        await model.activate(); let row = try XCTUnwrap(model.page?.items.first)
        XCTAssertTrue(model.open(row)); let detail = try XCTUnwrap(model.presentation)
        let count = r.wire.requests.count; r.readAccess = try r.readGrant()
        XCTAssertFalse(model.isLive); XCTAssertFalse(model.isCurrent(detail))
        await model.completeReturn(detail)
        XCTAssertNil(model.page); XCTAssertNil(model.presentation); XCTAssertEqual(r.wire.requests.count, count)
        await model.activate(); await model.retry()
        XCTAssertEqual(r.wire.requests.count, count, "Old model cannot use a new grant")
        let fresh = r.model(); await fresh.activate()
        XCTAssertEqual(fresh.page?.items.first?.id, "90"); XCTAssertNil(fresh.error)
        XCTAssertFalse(fresh.isCurrent(detail)); XCTAssertEqual(r.wire.requests.count, count + 1)
    }
    func testOriginalMonthlyContinuationAndExactReturnSurviveStableScope() async throws {
        let r = try PassportScopeRig(), model = r.model()
        await model.select(month: "2026-09"); await model.select(kind: .places); await model.nextPage()
        XCTAssertEqual(model.page?.sourceBeforeID, "90")
        XCTAssertTrue(model.open(try XCTUnwrap(model.page?.items.first)))
        let detail = try XCTUnwrap(model.presentation), scope = r.reader.readScope
        model.suspend(); XCTAssertTrue(model.isCurrent(detail)); XCTAssertEqual(scope, r.reader.readScope)
        await model.completeReturn(detail)
        XCTAssertEqual(r.wire.fields.last?["beforeId"], "90")
        XCTAssertEqual(r.wire.fields.last?["month"], "2026-09"); XCTAssertEqual(r.wire.fields.last?["kind"], "places")
        let count = r.wire.requests.count; await model.completeReturn(detail)
        XCTAssertEqual(r.wire.requests.count, count)
    }
    func testInFlightMonthlyOldGrantResponseCannotPopulateNewScope() async throws {
        let r = try PassportScopeRig(), old = r.model(); r.wire.hold = true
        let work = Task { await old.activate() }; try await waitFor { r.wire.pending != nil }
        r.readAccess = try r.readGrant(); _ = r.reader.readScope
        r.wire.finish(); await work.value
        XCTAssertNil(old.page); XCTAssertFalse(old.isLoading); XCTAssertEqual(old.error as? APIError, .notConfigured)
        r.wire.hold = false; let fresh = r.model(); await fresh.activate()
        XCTAssertNotNil(fresh.page); XCTAssertEqual(r.wire.requests.count, 2)
    }
    func testOriginalReaderStillCancelsIssuedReadWhenSelectedApprovalChanges() async throws {
        let r = try PassportScopeRig(); r.wire.hold = true
        let work = Task { try await r.reader.monthlyRecap(.init(month: "2026-10")) }
        try await waitFor { r.wire.pending != nil }
        r.privateAccess = try r.privateGrant(); _ = r.reader.readScope
        r.wire.finish()
        do { _ = try await work.value; XCTFail("Old read must not be accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(r.wire.requests.count, 1)
    }
    func testNilAccessScopeObservationNeverDispatchesOrAuthorizes() async throws {
        let r = try PassportScopeRig(); r.readAccess = nil
        let scope = r.reader.readScope; XCTAssertEqual(scope, r.reader.readScope)
        let model = r.model(); await model.activate()
        XCTAssertFalse(model.isLive); XCTAssertNil(model.page); XCTAssertEqual(model.error as? APIError, .notConfigured)
        XCTAssertTrue(r.wire.requests.isEmpty)
    }
    private func waitFor(_ ready: () -> Bool) async throws {
        for _ in 0..<200 { if ready() { return }; await Task.yield() }
        XCTFail("Memory read never entered"); throw APIError.notConfigured
    }
}

@MainActor private final class PassportScopeRig {
    static let base = URL(string: "https://example.test/passport-scope")!
    let wire = PassportScopeWire()
    var context: RuntimeDependencyContext
    var session: RoamExperienceSession?
    var privateAccess: RoamPrivateToolsAccess?
    var readAccess: RoamPassportToolsReadAccess?
    lazy var reader = RoamPassportToolsSessionReader(service: try! .init(configuration: .init(baseURL: Self.base), transport: wire),
        current: { [weak self] in self?.context }, access: { [weak self] _ in self?.privateAccess },
        readAccess: { [weak self] _ in self?.readAccess })
    init() throws {
        context = .init(market: .china, baseURL: Self.base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "passport-scope", token: "synthetic-passport-scope"))
        let scope = try RoamHistoryScope(market: "cn", deployment: Self.base, accountID: 7, namespace: "passport-scope")
        session = try .init(scope: scope, epoch: 1, token: "synthetic-passport-scope")
        readAccess = try readGrant()
    }
    func readGrant() throws -> RoamPassportToolsReadAccess {
        try .init(context: context, approval: .init(baseURL: Self.base, namespace: context.session.namespace,
            accountID: context.session.accountID, paths: Set(RoamPassportToolsService.paths)))
    }
    func privateGrant(paths: Set<String> = Set(RoamPassportToolsService.paths)) throws -> RoamPrivateToolsAccess {
        try .init(context: context, approval: .init(baseURL: Self.base, namespace: context.session.namespace,
            accountID: context.session.accountID, paths: paths))
    }
    func fullSessionReader() throws -> RoamPassportToolsSessionReader {
        .init(configuration: try .init(baseURL: Self.base), transport: wire,
            currentSession: { [weak self] in self?.session }, current: { [weak self] in self?.context },
            access: { [weak self] _ in self?.readAccess })
    }
    func model() -> RoamMonthlyRecapCoordinator {
        .init(reader: reader, now: { Date(timeIntervalSince1970: 1_792_382_400) })
    }
}
@MainActor private final class PassportScopeWire: HTTPTransport {
    var requests: [URLRequest] = [], fields: [[String: String]] = []
    var hold = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    private var held = Data()
    func finish() { let result = pending; pending = nil; result?.resume(returning: (held, 200)) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard request.httpMethod == "GET", request.httpBody == nil, request.url?.lastPathComponent == "monthly-recap" else {
            XCTFail("Only the original read is permitted in this memory transport"); throw APIError.notConfigured
        }
        let values = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        fields.append(values)
        let first = values["beforeId"] == nil, id = first ? "90" : "80", month = values["month"]!, kind = values["kind"]!
        let data = Data(#"{"code":200,"data":{"month":"\#(month)","kind":"\#(kind)","timeZone":"Asia/Shanghai","counts":{"routes":2,"places":2,"stamps":2},"items":[{"id":"\#(id)","objectId":7001,"title":"Synthetic record","occurredAt":"\#(month)-01 10:00:00"}],"hasMore":\#(first),"nextBeforeId":\#(first ? "90" : "null")}}"#.utf8)
        if hold { held = data; return try await withCheckedThrowingContinuation { pending = $0 } }
        return (data, 200)
    }
}

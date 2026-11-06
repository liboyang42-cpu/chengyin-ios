import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class ReportProgressWire: HTTPTransport {
    var requests: [URLRequest] = []
    var after: (() -> Void)?
    var raw: Data?
    var status = 200
    var code = 200
    var failure: Error?
    var payload: (URLRequest) -> Any = { r in
        switch r.url?.lastPathComponent {
        case "mine": return [ReportProgressFixture.row()]
        case "taxonomy": return ReportProgressFixture.taxonomy()
        default: return ReportProgressFixture.row(stage: "RESOLVED", version: 2)
        }
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let data = try raw ?? JSONSerialization.data(withJSONObject: ["code": code, "data": payload(request)])
        after?(); if let failure { throw failure }; return (data, status)
    }
}
@MainActor private final class ReportProgressFixture {
    let context: RuntimeDependencyContext
    var current: RuntimeDependencyContext?
    let approval: MemberReportProgressApproval
    var selected: MemberReportProgressApproval?
    let wire = ReportProgressWire()
    lazy var reader = makeReader()
    init(caps: Set<MemberReportProgressCapability> = [.history, .detail, .taxonomy]) throws {
        context = .init(market: .china, baseURL: URL(string: "https://report-read.example.test/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "report-synthetic", token: "synthetic-report-token", role: "player"))
        current = context; approval = try .init(context: context, expiresAt: Date().addingTimeInterval(600), capabilities: caps); selected = approval
    }
    func makeReader() -> MemberReportProgressReader {
        .init(approval: approval, transport: wire, current: { [unowned self] in current }, selected: { [unowned self] _ in selected })
    }
    static func row(id: Int64 = 1, target: String = "COMMENT", stage: String = "INVESTIGATING", version: Int = 1) -> [String: Any] {
        ["id": id, "targetType": target, "targetId": 9, "reasonCode": "OTHER", "policyVersion": "POLICY_SYNTHETIC",
         "description": " 原说明 ", "evidenceAssetIds": [11], "anonymityPolicy": "SUBJECT_HIDDEN", "stage": stage,
         "publicStage": "IN_REVIEW", "version": version, "createTime": "2026-10-28 21:10:00",
         "estimatedResolveAt": "2026-10-29T13:10:00+00:00", "decisionSummary": " 原来源结论 ",
         "timeline": [["eventType": "STAGE_CHANGED", "fromStage": "SUBMITTED", "toStage": stage,
                       "publicNote": " 公开说明 ", "createTime": 1_793_000_000_000 as Int64]]]
    }
    static func taxonomy() -> [String: Any] { ["policyVersion": "POLICY_SYNTHETIC", "reasons": [["code": "OTHER", "label": "来源原因"]]] }
    func decode(_ raw: [String: Any]) throws -> MemberReportProgressRecord {
        try JSONDecoder().decode(MemberReportProgressRecord.self, from: JSONSerialization.data(withJSONObject: raw))
    }
    func request(_ route: MemberReportProgressRoute) -> URLRequest {
        var r = URLRequest(url: context.baseURL.appendingPathComponent(route.path)); r.httpMethod = "GET"; r.httpShouldHandleCookies = false
        r.setValue("application/json", forHTTPHeaderField: "Accept"); r.setValue(context.session.token, forHTTPHeaderField: "Authorization"); return r
    }
}

/// Independent source specimens only. No original fixture, writer, assertion or account is changed.
@MainActor final class MemberReportProgressC6ReadTests: XCTestCase {
    func testRealArrayHistoryHasNoPaginationOrOwnerQuery() async throws {
        let f = try ReportProgressFixture(), records = try await f.reader.history()
        XCTAssertEqual(records.count, 1); XCTAssertEqual(records[0].description, " 原说明 ")
        let request = try XCTUnwrap(f.wire.requests.first)
        XCTAssertEqual(request.url?.path, "/native/api/community-trust/reports/mine")
        XCTAssertNil(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.query)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody); XCTAssertFalse(request.httpShouldHandleCookies)
    }
    func testLocalTwentyRowExpansionNeverCallsNetwork() async throws {
        let f = try ReportProgressFixture(caps: [.history]), flow = f.reader.makeCoordinator(), owner = flow.beginHistory()
        f.wire.payload = { _ in (1...45).map { ReportProgressFixture.row(id: Int64($0)) } }
        await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner)))
        XCTAssertEqual(flow.records.count, 20); XCTAssertTrue(flow.hasMore)
        let next = try XCTUnwrap(flow.capture(owner)); flow.showMore(intent: next); flow.showMore(intent: next)
        XCTAssertEqual(flow.records.count, 40)
        flow.showMore(intent: try XCTUnwrap(flow.capture(owner))); XCTAssertEqual(flow.records.count, 45); XCTAssertFalse(flow.hasMore)
        XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testLocalFiltersUseOnlyRealTerminalStagesAndKeepAppealedActive() async throws {
        let f = try ReportProgressFixture(caps: [.history]), flow = f.reader.makeCoordinator(), owner = flow.beginHistory()
        let stages = ["SUBMITTED", "TRIAGED", "INVESTIGATING", "RESOLVED", "CLOSED", "APPEALED", "NEW_UNKNOWN"]
        f.wire.payload = { _ in stages.enumerated().map { ReportProgressFixture.row(id: Int64($0.offset + 1), stage: $0.element) } }
        await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner)))
        flow.changeFilter(.decided, intent: try XCTUnwrap(flow.capture(owner))); XCTAssertEqual(flow.records.map(\.stage), ["RESOLVED", "CLOSED"])
        flow.changeFilter(.active, intent: try XCTUnwrap(flow.capture(owner))); XCTAssertEqual(flow.records.count, 5)
        XCTAssertEqual(flow.records.last?.stageKey, "UNKNOWN"); XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testAllSevenSourceTargetsRemainReadOnlyAndDistinct() async throws {
        let f = try ReportProgressFixture()
        let targets = ["MEMBER", "MERCHANT", "CLUB", "ACTIVITY", "CONTENT", "COMMENT", "SAFETY_RATING"]
        f.wire.payload = { _ in targets.enumerated().map { ReportProgressFixture.row(id: Int64($0.offset + 1), target: $0.element) } }
        let records = try await f.reader.history(); XCTAssertEqual(records.map(\.targetKey), targets)
    }
    func testEmptyArrayIsTheOnlyEmptySuccessNotOldKeysetObject() async throws {
        let f = try ReportProgressFixture(); f.wire.payload = { _ in [Any]() }
        let records = try await f.reader.history(); XCTAssertTrue(records.isEmpty)
        let objects: [[String: Any]] = [["items": [], "nextBeforeID": NSNull()], ["rows": [], "total": 0]]
        for object in objects {
            f.wire.payload = { _ in object }; do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? MemberReportProgressFailure, .malformed) }
        }
    }
    func testDuplicateOrMalformedRowRejectsWholeHistory() async throws {
        let f = try ReportProgressFixture(); f.wire.payload = { _ in [ReportProgressFixture.row(), ReportProgressFixture.row()] }
        do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? MemberReportProgressFailure, .malformed) }
        for key in ["id", "targetId", "version"] {
            var bad = ReportProgressFixture.row(id: 2); bad[key] = -1; f.wire.payload = { _ in [ReportProgressFixture.row(), bad] }
            do { _ = try await f.reader.history(); XCTFail(key) } catch { }
        }
    }
    func testOversizedArrayAndBytesAreExplicitFailureNotTruncatedSuccess() async throws {
        let f = try ReportProgressFixture()
        f.wire.payload = { _ in (1...(MemberReportProgressReader.maximumRecords + 1)).map { ReportProgressFixture.row(id: Int64($0)) } }
        do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? MemberReportProgressFailure, .oversized) }
        f.wire.raw = Data(repeating: 32, count: MemberReportProgressReader.maximumBytes + 1)
        do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? MemberReportProgressFailure, .oversized) }
    }
    func testDuplicateJSONKeysAreRejected() async throws {
        let f = try ReportProgressFixture(); f.wire.raw = Data(#"{"code":200,"code":200,"data":[]}"#.utf8)
        do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? MemberReportProgressFailure, .malformed) }
    }
    func testDetailChecksCaseTargetAndImmutableOriginalFields() async throws {
        let f = try ReportProgressFixture(), original = try f.decode(ReportProgressFixture.row())
        for key in ["id", "targetId", "targetType", "reasonCode", "policyVersion", "description", "evidenceAssetIds", "anonymityPolicy", "createTime"] {
            var bad = ReportProgressFixture.row(version: 2)
            switch key { case "id", "targetId": bad[key] = 99; case "evidenceAssetIds": bad[key] = [99]; default: bad[key] = "different" }
            f.wire.payload = { _ in bad }; do { _ = try await f.reader.detail(for: original); XCTFail(key) } catch { }
        }
    }
    func testDetailPreservesPublicFactsAndNeverRetainsPrivateProjectionKeys() async throws {
        let f = try ReportProgressFixture(), original = try f.decode(ReportProgressFixture.row())
        var raw = ReportProgressFixture.row(stage: "RESOLVED", version: 2)
        raw["reporterMemberId"] = 999; raw["payloadHash"] = "private"; raw["requestId"] = "private"
        var event = (raw["timeline"] as! [[String: Any]])[0]; event["internalNote"] = "private"; event["actorId"] = 999; raw["timeline"] = [event]
        f.wire.payload = { _ in raw }; let value = try await f.reader.detail(for: original)
        XCTAssertEqual(value.decisionSummary, " 原来源结论 "); XCTAssertEqual(value.timeline?.first?.publicNote, " 公开说明 ")
        XCTAssertTrue(value.isDecided); XCTAssertEqual(value.evidenceAssetIds, [11])
        XCTAssertFalse(Mirror(reflecting: value).children.contains { ["reporterMemberId", "payloadHash", "requestId"].contains($0.label ?? "") })
        XCTAssertFalse(Mirror(reflecting: try XCTUnwrap(value.timeline?.first)).children.contains { ["internalNote", "actorId"].contains($0.label ?? "") })
    }
    func testDetailVersionCannotRegressAcrossRepeatedRefreshes() async throws {
        let f = try ReportProgressFixture(caps: [.detail]), flow = f.reader.makeCoordinator(), original = try f.decode(ReportProgressFixture.row())
        let owner = flow.beginDetail(original); f.wire.payload = { _ in ReportProgressFixture.row(version: 5) }
        await flow.loadDetail(intent: try XCTUnwrap(flow.capture(owner))); XCTAssertEqual(flow.detail?.version, 5)
        f.wire.payload = { _ in ReportProgressFixture.row(version: 4) }
        await flow.loadDetail(intent: try XCTUnwrap(flow.capture(owner))); XCTAssertNil(flow.detail); XCTAssertEqual(flow.failure, .malformed)
    }
    func testTaxonomyFailureUsesFallbackWithoutErasingHistory() async throws {
        let f = try ReportProgressFixture(), flow = f.reader.makeCoordinator(), owner = flow.beginHistory()
        f.wire.payload = { r in if r.url?.lastPathComponent == "taxonomy" { return ["bad": true] }; return [ReportProgressFixture.row()] }
        await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner))); XCTAssertEqual(flow.records.count, 1)
        XCTAssertNil(flow.reasonLabel(for: try XCTUnwrap(flow.records.first))); XCTAssertNil(flow.failure)
    }
    func testCurrentTaxonomyIsNotPresentedAsOldPolicySnapshot() async throws {
        let f = try ReportProgressFixture(), taxonomy = try await f.reader.taxonomy(), original = try f.decode(ReportProgressFixture.row())
        XCTAssertEqual(taxonomy.label(for: original), "来源原因")
        var old = ReportProgressFixture.row(); old["policyVersion"] = "OLD_POLICY"
        XCTAssertNil(taxonomy.label(for: try f.decode(old)))
    }
    func testExactRoutesRejectWritersSubjectOriginalRecoveryKeyAndKeyset() throws {
        let f = try ReportProgressFixture(), good = f.request(.history)
        XCTAssertEqual(MemberReportProgressRoute(request: good, baseURL: f.context.baseURL), .history)
        for path in ["reports/mine/community", "reports/submit", "reports/appeal", "reports/1/subject", "reports/01", "reports/0", "reports/-1"] {
            var r = good; r.url = f.context.baseURL.appendingPathComponent("api/community-trust/" + path)
            XCTAssertNil(MemberReportProgressRoute(request: r, baseURL: f.context.baseURL), path)
        }
        for query in ["?requestId=original", "?memberId=7", "?stage=CLOSED", "?beforeId=2", "?pageNum=1", "?"] {
            var r = good; r.url = URL(string: good.url!.absoluteString + query); XCTAssertNil(MemberReportProgressRoute(request: r, baseURL: f.context.baseURL), query)
        }
        var r = good; r.httpMethod = "POST"; XCTAssertNil(MemberReportProgressRoute(request: r, baseURL: f.context.baseURL))
        r = good; r.httpBody = Data(); XCTAssertNil(MemberReportProgressRoute(request: r, baseURL: f.context.baseURL))
        r = good; r.httpShouldHandleCookies = true; XCTAssertNil(MemberReportProgressRoute(request: r, baseURL: f.context.baseURL))
        r = good; r.setValue("x", forHTTPHeaderField: "Cookie"); XCTAssertNil(MemberReportProgressRoute(request: r, baseURL: f.context.baseURL))
    }
    func testScopedTransportRejectsMissingCapabilityWrongTokenAndOtherHost() async throws {
        let f = try ReportProgressFixture(caps: [.history]), transport = MemberReportProgressScopedTransport(approval: f.approval, underlying: f.wire, current: { f.current }, stillSelected: { true })
        do { _ = try await transport.send(f.request(.taxonomy)); XCTFail() } catch { }
        var r = f.request(.history); r.setValue("wrong", forHTTPHeaderField: "Authorization")
        do { _ = try await transport.send(r); XCTFail() } catch { }
        r = f.request(.history); r.url = URL(string: "https://other.example.test/native/api/community-trust/reports/mine")
        do { _ = try await transport.send(r); XCTFail() } catch { }; XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testNoDetailOrTaxonomyCapabilityIsBorrowedFromHistory() async throws {
        let f = try ReportProgressFixture(caps: [.history]), flow = f.reader.makeCoordinator(), owner = flow.beginHistory()
        await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner)))
        XCTAssertEqual(f.wire.requests.count, 1); XCTAssertNil(flow.select(try XCTUnwrap(flow.records.first), intent: try XCTUnwrap(flow.capture(owner))))
        do { _ = try await f.reader.taxonomy(); XCTFail() } catch { XCTAssertEqual(error as? MemberReportProgressFailure, .disabled) }
    }
    func testOldOwnerAndConsumedIntentCannotDispatchOrClearReplacement() async throws {
        let f = try ReportProgressFixture(caps: [.history]), flow = f.reader.makeCoordinator(), old = flow.beginHistory(), queued = try XCTUnwrap(flow.capture(old))
        flow.end(old); let new = flow.beginHistory(); flow.end(old)
        await flow.loadHistory(intent: queued); XCTAssertTrue(f.wire.requests.isEmpty)
        let intent = try XCTUnwrap(flow.capture(new)); await flow.loadHistory(intent: intent); await flow.loadHistory(intent: intent)
        XCTAssertEqual(f.wire.requests.count, 1); XCTAssertTrue(flow.loaded)
    }
    func testQueuedCancellationNeverReads() async throws {
        let f = try ReportProgressFixture(), flow = f.reader.makeCoordinator(), owner = flow.beginHistory(), intent = try XCTUnwrap(flow.capture(owner))
        await Task { withUnsafeCurrentTask { $0?.cancel() }; await flow.loadHistory(intent: intent) }.value
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertFalse(flow.loaded)
    }
    func testDepartureDuringReplyCannotRestoreOldData() async throws {
        let f = try ReportProgressFixture(), flow = f.reader.makeCoordinator(), owner = flow.beginHistory()
        f.wire.after = { flow.end(owner) }; await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner)))
        XCTAssertTrue(flow.records.isEmpty); XCTAssertFalse(flow.loaded); XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testSwitchingAccountImmediatelyHidesCachedDataWithoutUICallback() async throws {
        let f = try ReportProgressFixture(), flow = f.reader.makeCoordinator(), owner = flow.beginHistory()
        await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner))); let queued = try XCTUnwrap(flow.capture(owner))
        f.current = nil; XCTAssertTrue(flow.records.isEmpty); XCTAssertFalse(flow.loaded)
        f.wire.requests = []; await flow.loadHistory(intent: queued); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testReplacementSourceMakesOldReaderAndOldSelectionInvalid() async throws {
        let f = try ReportProgressFixture(), flow = f.reader.makeCoordinator(), owner = flow.beginHistory()
        await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner))); let row = try XCTUnwrap(flow.records.first), intent = try XCTUnwrap(flow.capture(owner))
        f.selected = try .init(context: f.context, expiresAt: Date().addingTimeInterval(600))
        XCTAssertFalse(f.reader.isCurrent); XCTAssertNil(flow.select(row, intent: intent)); XCTAssertTrue(flow.records.isEmpty)
    }
    func testRevocationAndClientRetirementClearIndependentDetail() async throws {
        let f = try ReportProgressFixture(), history = f.reader.makeCoordinator(), owner = history.beginHistory()
        await history.loadHistory(intent: try XCTUnwrap(history.capture(owner))); let selection = try XCTUnwrap(history.select(try XCTUnwrap(history.records.first), intent: try XCTUnwrap(history.capture(owner))))
        let detail = selection.reader.makeCoordinator(), detailOwner = detail.beginDetail(selection.record)
        history.end(owner); await detail.loadDetail(intent: try XCTUnwrap(detail.capture(detailOwner))); XCTAssertNotNil(detail.detail)
        f.reader.retire(); XCTAssertNil(detail.detail); XCTAssertNil(detail.detailRecord)
    }
    func testPermissionDenialHidesAllClientsSharingLease() async throws {
        for status in [401, 403] {
            let f = try ReportProgressFixture(), history = f.reader.makeCoordinator(), owner = history.beginHistory()
            await history.loadHistory(intent: try XCTUnwrap(history.capture(owner)))
            let another = f.makeReader(), detail = another.makeCoordinator(), detailOwner = detail.beginDetail(try XCTUnwrap(history.records.first))
            await detail.loadDetail(intent: try XCTUnwrap(detail.capture(detailOwner))); XCTAssertNotNil(detail.detail)
            f.wire.status = status; f.wire.raw = Data("not JSON".utf8)
            do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? MemberReportProgressFailure, .denied) }
            XCTAssertTrue(f.approval.accessDenied); XCTAssertTrue(history.records.isEmpty); XCTAssertNil(detail.detail); XCTAssertNil(detail.detailRecord)
        }
    }
    func testTypedTransportDenialRevokesOnlyStillCurrentLease() async throws {
        for error in [APIError.unauthorized, .httpStatus(403), .businessCode(401)] {
            let f = try ReportProgressFixture(); f.wire.failure = error
            do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? MemberReportProgressFailure, .denied) }
            XCTAssertTrue(f.approval.accessDenied)
        }
        let f = try ReportProgressFixture(); f.wire.failure = APIError.unauthorized; f.wire.after = { f.current = nil }
        do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? MemberReportProgressFailure, .stale) }
        XCTAssertFalse(f.approval.revoked)
    }
    func testBusinessDenialIsRecognizedEvenWithWrongPayloadShape() async throws {
        for code in [401, 403] {
            let f = try ReportProgressFixture(); f.wire.raw = Data("{\"code\":\(code),\"data\":\"wrong shape\"}".utf8)
            do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? MemberReportProgressFailure, .denied) }
            XCTAssertTrue(f.approval.revoked)
        }
    }
    func testTaxonomyDenialDoesNotLeavePrivateHistoryVisible() async throws {
        let f = try ReportProgressFixture(), flow = f.reader.makeCoordinator(), owner = flow.beginHistory()
        f.wire.after = { if f.wire.requests.last?.url?.lastPathComponent == "mine" { f.wire.code = 403 } }
        await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner)))
        XCTAssertTrue(f.approval.revoked); XCTAssertTrue(flow.records.isEmpty); XCTAssertFalse(flow.loaded)
    }
    func testCancelledThrownDenialCannotRevokeLease() async throws {
        let f = try ReportProgressFixture(); f.wire.failure = APIError.unauthorized
        await Task {
            f.wire.after = { withUnsafeCurrentTask { $0?.cancel() } }
            do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        }.value
        XCTAssertFalse(f.approval.revoked)
    }
    func testLateDenialAfterIdentityChangeDoesNotRevokeNewScope() async throws {
        let f = try ReportProgressFixture(); f.wire.status = 401; f.wire.after = { f.current = nil }
        do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? MemberReportProgressFailure, .stale) }
        XCTAssertFalse(f.approval.revoked); XCTAssertFalse(f.approval.accessDenied)
    }
    func testFullRoleAndExpiredLeaseAreRejectedBeforeRead() throws {
        let f = try ReportProgressFixture()
        let wrong = RuntimeDependencyContext(market: .china, baseURL: f.context.baseURL, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "report-synthetic", token: "synthetic-report-token", role: "merchant"))
        XCTAssertFalse(f.approval.matches(wrong))
        XCTAssertThrowsError(try MemberReportProgressApproval(context: wrong, expiresAt: Date().addingTimeInterval(10)))
        XCTAssertThrowsError(try MemberReportProgressApproval(context: f.context, expiresAt: .distantPast))
    }
    func testSafeDatesPreserveZonelessTextAndRejectInvalidOrUnboundedValues() throws {
        let raw = "2026-10-28 21:10:00", zoneA = TimeZone(secondsFromGMT: 0)!, zoneB = TimeZone(secondsFromGMT: 8 * 3600)!
        XCTAssertEqual(MemberReportProgressTime.text(raw).display(timeZone: zoneA), raw)
        XCTAssertEqual(MemberReportProgressTime.text(raw).display(timeZone: zoneB), raw)
        for value in [Int64.min, -1, 0, 253_402_300_800_000, Int64.max] { XCTAssertNil(MemberReportProgressTime.milliseconds(value).display()) }
        for text in ["not time", "2026-02-30 12:00:00", "2026-02-30T12:00:00Z", "0000-01-01 00:00:00"] { XCTAssertNil(MemberReportProgressTime.text(text).display()) }
        let instant = MemberReportProgressTime.text("2026-10-28T13:10:00+00:00")
        XCTAssertNotNil(instant.display(timeZone: zoneA)); XCTAssertNotEqual(instant.display(timeZone: zoneA), instant.display(timeZone: zoneB))
        XCTAssertEqual(MemberReportProgressTime.text("2026-10-28T13:10:00+0000").display(timeZone: zoneA), instant.display(timeZone: zoneA))
    }
}

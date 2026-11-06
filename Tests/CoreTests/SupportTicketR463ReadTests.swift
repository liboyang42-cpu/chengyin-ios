import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class SupportR463Wire: HTTPTransport {
    var requests: [URLRequest] = []
    var body = "", status = 200
    var after: (() -> Void)?
    var failure: Error?
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); after?(); if let failure { throw failure }; return (Data(body.utf8), status) }
}
@MainActor private final class SupportR463Fixture {
    let context: RuntimeDependencyContext
    var current: RuntimeDependencyContext?
    let approval: SupportTicketReadApproval
    var selected: SupportTicketReadApproval?
    let wire = SupportR463Wire()
    lazy var reader = SupportTicketReadReader(approval: approval, transport: wire, current: { [unowned self] in current }, selected: { [unowned self] _ in selected })
    static let ticket = #"{"ticket_no":"CS20261021-000123","requester_role":"PLAYER","category":"ACCOUNT","subject":"Original subject","status":"OPEN","version":9007199254740993,"timezone":"Asia/Shanghai","create_time":"2026-10-21T12:00:00Z"}"#
    static let message = #"{"id":9007199254740993,"sender_type":"AGENT","content":" Original answer ","content_type":"TEXT","create_time":"2026-10-21T12:00:00Z","attachments":[]}"#
    static let event = #"{"id":9007199254740993,"event_type":"CLOSE","actor_type":"MEMBER","created_at":"2026-10-21T12:00:00Z","result_state":"UNAVAILABLE","request_id":"original-request"}"#
    static func listing(_ rows: [String] = [ticket], cursor: Int64 = 1, more: Bool = false) -> String { "{\"code\":200,\"data\":{\"list\":[\(rows.joined(separator: ","))],\"has_more\":\(more),\"next_cursor\":\(cursor)}}" }
    static func detail(messages: [String] = [message], cursor: Int64 = 9007199254740993, more: Bool = false, timeline: String? = nil) -> String {
        "{\"code\":200,\"data\":{\"ticket\":\(ticket),\"messages\":[\(messages.joined(separator: ","))],\"next_cursor\":\(cursor),\"has_more\":\(more),\"business_result\":\"NO_FINANCIAL_ACTION\"\(timeline.map { ",\"timeline\":" + $0 } ?? "")}}"
    }
    static func timeline(_ events: [String] = [event], cursor: Int64 = 9007199254740993, more: Bool = false) -> String { "{\"resource_type\":\"CS_TICKET\",\"ticket_no\":\"CS20261021-000123\",\"audience\":\"MEMBER\",\"source\":\"cs_ticket_event\",\"events\":[\(events.joined(separator: ","))],\"next_before\":\(cursor),\"has_more\":\(more)}" }
    init(capabilities: Set<SupportTicketReadCapability> = [.history,.detail,.timeline]) throws {
        context = .init(market: .china, baseURL: URL(string: "https://support-read.example.test/native")!, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "support-synthetic", token: "synthetic-support-token", role: "player"))
        current = context; approval = try .init(context: context, expiresAt: Date().addingTimeInterval(600), capabilities: capabilities); selected = approval; wire.body = Self.listing()
    }
    func request(_ route: SupportTicketReadRoute) throws -> URLRequest {
        var r = URLRequest(url: context.baseURL.appendingPathComponent(route.path)); r.httpMethod = "POST"; r.httpShouldHandleCookies = false; r.httpBody = try route.body()
        for (key,value) in ["Accept":"application/json","Content-Type":"application/json","Authorization":context.session.token,"Cache-Control":"no-store","Pragma":"no-cache"] { r.setValue(value, forHTTPHeaderField: key) }; return r
    }
}
@MainActor final class SupportTicketR463ReadTests: XCTestCase {
    func testR463HistoryUsesOriginalPOSTAndExactCursorWithoutWriterFields() async throws {
        let f = try SupportR463Fixture(), page = try await f.reader.history()
        XCTAssertEqual(page.list.first?.version, 9007199254740993); XCTAssertEqual(page.list.first?.create_time, "2026-10-21T12:00:00Z")
        let r = try XCTUnwrap(f.wire.requests.first); XCTAssertEqual(r.httpMethod, "POST"); XCTAssertEqual(r.url?.path, "/native/api/support/tickets/list")
        XCTAssertEqual(SupportTicketReadRoute(request: r, baseURL: f.context.baseURL), .history(before: 0)); XCTAssertEqual(r.value(forHTTPHeaderField: "Cache-Control"), "no-store")
    }
    func testPublicDetailPreservesExactIDsOriginalTextAndTicketBinding() async throws {
        let f = try SupportR463Fixture(); f.wire.body = SupportR463Fixture.detail()
        let v = try await f.reader.detail(number: "CS20261021-000123")
        XCTAssertEqual(v.messages.first?.id, 9007199254740993); XCTAssertEqual(v.messages.first?.content, " Original answer ")
        XCTAssertEqual(v.ticket.ticket_no, "CS20261021-000123"); XCTAssertEqual(v.business_result, "NO_FINANCIAL_ACTION")
    }
    func testTimelinePreservesUnavailableWithoutPromotingCurrentStatusOrReceipt() async throws {
        let f = try SupportR463Fixture(); f.wire.body = SupportR463Fixture.detail(timeline: SupportR463Fixture.timeline())
        let v = try await f.reader.timeline(number: "CS20261021-000123")
        XCTAssertEqual(v.events.first?.result_state, "UNAVAILABLE"); XCTAssertNil(v.events.first?.historical_status)
        XCTAssertEqual(v.events.first?.request_id, "original-request"); XCTAssertEqual(v.next_before, 9007199254740993)
        let r = try XCTUnwrap(f.wire.requests.first); XCTAssertEqual(SupportTicketReadRoute(request: r, baseURL: f.context.baseURL), .timeline(number: "CS20261021-000123", before: 0))
    }
    func testReadRouteRejectsWritesRequestRecoveryAttachmentAndRelatedBusiness() throws {
        let f = try SupportR463Fixture(), good = try f.request(.detail(number: "CS20261021-000123", after: 0))
        for path in ["", "/reply", "/close", "/reopen", "/rate", "/request", "/attachments/bytes", "/attachments/request", "/attachments/scan"] {
            var r = good; r.url = f.context.baseURL.appendingPathComponent(SupportTicketReadRoute.root + path); XCTAssertNil(SupportTicketReadRoute(request: r, baseURL: f.context.baseURL))
        }
        for extra in ["related_business": "true", "request_id": "\"old\"", "member_id": "7", "expected_version": "1"] {
            var r = good; r.httpBody = Data("{\"ticket_no\":\"CS20261021-000123\",\"cursor\":0,\"\(extra.key)\":\(extra.value)}".utf8); XCTAssertNil(SupportTicketReadRoute(request: r, baseURL: f.context.baseURL))
        }
    }
    func testRouteRejectsQueriesCookiesWrongMethodAndDuplicateKeys() throws {
        let f = try SupportR463Fixture(), good = try f.request(.history(before: 0))
        var r = good; r.httpMethod = "GET"; XCTAssertNil(SupportTicketReadRoute(request: r, baseURL: f.context.baseURL))
        r = good; r.url = URL(string: good.url!.absoluteString + "?member_id=7"); XCTAssertNil(SupportTicketReadRoute(request: r, baseURL: f.context.baseURL))
        r = good; r.httpShouldHandleCookies = true; XCTAssertNil(SupportTicketReadRoute(request: r, baseURL: f.context.baseURL))
        r = good; r.httpBody = Data(#"{"cursor":0,"cursor":1}"#.utf8); XCTAssertNil(SupportTicketReadRoute(request: r, baseURL: f.context.baseURL))
    }
    func testNoSourceOrSubsetGrantCannotDispatchOtherRead() async throws {
        let f = try SupportR463Fixture(capabilities: [.history])
        do { _ = try await f.reader.detail(number: "CS20261021-000123"); XCTFail() } catch { }
        f.selected = nil
        do { _ = try await f.reader.history(); XCTFail() } catch { }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testScopedTransportRequiresExactTokenHeadersAndCapability() async throws {
        let f = try SupportR463Fixture(capabilities: [.history]), t = SupportTicketReadScopedTransport(approval: f.approval, underlying: f.wire, current: { f.current }, stillSelected: { true })
        for header in ["Authorization","Accept","Content-Type","Cache-Control","Pragma"] {
            var r = try f.request(.history(before: 0)); r.setValue("wrong", forHTTPHeaderField: header)
            do { _ = try await t.send(r); XCTFail() } catch { }
        }
        do { _ = try await t.send(f.request(.detail(number: "CS20261021-000123", after: 0))); XCTFail() } catch { }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testMalformedListCursorDuplicatesAndImpossibleMoreReject() async throws {
        for body in [SupportR463Fixture.listing(cursor: 0),SupportR463Fixture.listing(more: true),SupportR463Fixture.listing([SupportR463Fixture.ticket,SupportR463Fixture.ticket]),SupportR463Fixture.listing([],cursor: 2)] {
            let f = try SupportR463Fixture(); f.wire.body = body
            do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? SupportTicketReadFailure, .malformed) }
        }
    }
    func testHistoryCursorMustAdvanceDescending() async throws {
        let f = try SupportR463Fixture(); f.wire.body = SupportR463Fixture.listing(cursor: 5)
        do { _ = try await f.reader.history(before: 5); XCTFail() } catch { XCTAssertEqual(error as? SupportTicketReadFailure, .malformed) }
    }
    func testPublicMessageRejectsInternalMarkerDuplicateAndWrongCursor() async throws {
        for body in [SupportR463Fixture.detail(messages: [SupportR463Fixture.message.replacingOccurrences(of: "\"attachments\":[]", with: "\"attachments\":[],\"is_internal\":0")]),SupportR463Fixture.detail(messages: [SupportR463Fixture.message,SupportR463Fixture.message]),SupportR463Fixture.detail(cursor: 2)] {
            let f = try SupportR463Fixture(); f.wire.body = body
            do { _ = try await f.reader.detail(number: "CS20261021-000123"); XCTFail() } catch { XCTAssertEqual(error as? SupportTicketReadFailure, .malformed) }
        }
    }
    func testDetailCannotChangeTicketNumberOrPretendFinancialAction() async throws {
        for body in [SupportR463Fixture.detail().replacingOccurrences(of: "CS20261021-000123", with: "CS20261021-000124"),SupportR463Fixture.detail().replacingOccurrences(of: "NO_FINANCIAL_ACTION", with: "REFUNDED")] {
            let f = try SupportR463Fixture(); f.wire.body = body
            do { _ = try await f.reader.detail(number: "CS20261021-000123"); XCTFail() } catch { }
        }
    }
    func testHistoricalReferenceMustKeepOriginalMemberNotCurrentRoleInference() async throws {
        let f = try SupportR463Fixture()
        let ticket = String(SupportR463Fixture.ticket.replacingOccurrences(of: "\"PLAYER\"", with: "\"CLUB_OWNER\"").dropLast()) + #", "related_reference":{"source":"ums_member","domain_type":"USER","resource_id":"8","owner_type":"MEMBER","owner_member_id":"8"}}"#
        f.wire.body = SupportR463Fixture.listing([String(ticket)])
        do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? SupportTicketReadFailure, .malformed) }
    }
    func testTimelineRejectsStaffAudienceOtherTicketInternalFieldsAndBadOrder() async throws {
        for timeline in [SupportR463Fixture.timeline().replacingOccurrences(of: "\"audience\":\"MEMBER\"", with: "\"audience\":\"STAFF\""),SupportR463Fixture.timeline().replacingOccurrences(of: "CS20261021-000123", with: "CSother"),SupportR463Fixture.timeline([String(SupportR463Fixture.event.dropLast()) + ",\"actor_id\":7}"]),SupportR463Fixture.timeline([SupportR463Fixture.event,SupportR463Fixture.event])] {
            let f = try SupportR463Fixture(); f.wire.body = SupportR463Fixture.detail(timeline: timeline)
            do { _ = try await f.reader.timeline(number: "CS20261021-000123"); XCTFail() } catch { XCTAssertEqual(error as? SupportTicketReadFailure, .malformed) }
        }
    }
    func testCurrentHTTPBusinessAndTypedDenialRevokeLease() async throws {
        for kind in 0...2 {
            let f = try SupportR463Fixture()
            if kind == 0 { f.wire.status = 403 } else if kind == 1 { f.wire.body = #"{"code":401,"data":"invalid"}"# } else { f.wire.failure = APIError.unauthorized }
            do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? SupportTicketReadFailure, .denied) }
            XCTAssertTrue(f.approval.revoked)
        }
    }
    func testOriginal409CapabilityWithdrawalRevokesButNotFoundIsNotAuthority() async throws {
        for reason in ["CS_CAPABILITY_NOT_ENABLED", "CS_NOT_FOUND"] {
            let f = try SupportR463Fixture(); f.wire.body = "{\"code\":409,\"msg\":\"\(reason)\"}"
            do { _ = try await f.reader.history(); XCTFail() } catch { }
            XCTAssertEqual(f.approval.revoked, reason == "CS_CAPABILITY_NOT_ENABLED")
        }
    }
    func testLate401DoesNotRevokeNewIdentity() async throws {
        let f = try SupportR463Fixture(); f.wire.status = 401; f.wire.after = { f.current = nil }
        do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertEqual(error as? SupportTicketReadFailure, .stale) }
        XCTAssertFalse(f.approval.revoked)
    }
    func testCancelledReadDoesNotDispatchOrRevokeLease() async throws {
        let f = try SupportR463Fixture()
        await Task { withUnsafeCurrentTask { $0?.cancel() }; do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertTrue(error is CancellationError) } }.value
        XCTAssertTrue(f.wire.requests.isEmpty)
        f.wire.after = { withUnsafeCurrentTask { $0?.cancel() } }; f.wire.failure = APIError.unauthorized
        await Task { do { _ = try await f.reader.history(); XCTFail() } catch { XCTAssertTrue(error is CancellationError) } }.value
        XCTAssertFalse(f.approval.revoked)
    }
    func testSameContextNewSourceCannotReviveOldReader() async throws {
        let f = try SupportR463Fixture(); f.selected = try .init(context: f.context, expiresAt: Date().addingTimeInterval(600))
        do { _ = try await f.reader.history(); XCTFail() } catch { }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testDuplicateJSONAndOversizedEnvelopeReject() async throws {
        for body in [#"{"code":200,"code":200,"data":{"list":[],"has_more":false,"next_cursor":0}}"#,String(repeating: "x", count: 8_388_609)] {
            let f = try SupportR463Fixture(); f.wire.body = body
            do { _ = try await f.reader.history(); XCTFail() } catch { }
        }
    }
    func testLifecycleExitRetiresDataAndQueuedActionsWithoutNetwork() async throws {
        let f = try SupportR463Fixture(), flow = f.reader.makeCoordinator(), visit = flow.begin()
        let intent = try XCTUnwrap(flow.capture(visit)); await flow.loadHistory(intent); XCTAssertFalse(flow.tickets.isEmpty)
        let queued = try XCTUnwrap(flow.capture(visit)); flow.end(visit); f.wire.requests = []
        await flow.loadHistory(queued); XCTAssertTrue(flow.tickets.isEmpty); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testSameOwnerNewVisitCannotBeEndedByOldVisit() throws {
        let f = try SupportR463Fixture(), flow = f.reader.makeCoordinator(), old = flow.begin(), new = flow.begin()
        flow.end(old); XCTAssertNotNil(flow.capture(new)); XCTAssertNil(flow.capture(old))
    }
    func testFailedReloadClearsOldRowsWithoutEmptySuccess() async throws {
        let f = try SupportR463Fixture(), flow = f.reader.makeCoordinator(), visit = flow.begin()
        await flow.loadHistory(try XCTUnwrap(flow.capture(visit))); f.wire.status = 500
        await flow.loadHistory(try XCTUnwrap(flow.capture(visit))); XCTAssertTrue(flow.tickets.isEmpty); XCTAssertFalse(flow.loaded); XCTAssertEqual(flow.failure, .unavailable)
    }
    func testCompleteHistoryDetailEventsAndSameTicketResumeClearsPrivateText() async throws {
        let f = try SupportR463Fixture(), flow = f.reader.makeCoordinator(), visit = flow.begin()
        await flow.loadHistory(try XCTUnwrap(flow.capture(visit)))
        let row = try XCTUnwrap(flow.tickets.first)
        f.wire.body = SupportR463Fixture.detail(); await flow.open(row, intent: try XCTUnwrap(flow.capture(visit)))
        XCTAssertEqual(flow.messages.first?.content, " Original answer ")
        f.wire.body = SupportR463Fixture.detail(timeline: SupportR463Fixture.timeline())
        await flow.loadTimeline(try XCTUnwrap(flow.capture(visit))); XCTAssertTrue(flow.timelineLoaded)
        let selectedNumber = try XCTUnwrap(flow.ticket?.ticket_no), queued = try XCTUnwrap(flow.capture(visit))
        flow.end(visit); XCTAssertNil(flow.ticket); XCTAssertTrue(flow.messages.isEmpty); XCTAssertTrue(flow.events.isEmpty)
        let reopened = flow.begin(); f.wire.body = SupportR463Fixture.detail()
        await flow.resumeDetail(number: selectedNumber, intent: try XCTUnwrap(flow.capture(reopened)))
        XCTAssertEqual(flow.ticket?.ticket_no, selectedNumber); XCTAssertFalse(flow.timelineLoaded)
        await flow.loadHistory(queued); XCTAssertEqual(f.wire.requests.count, 4)
    }
    func testRealThirtyRowHistoryPaginationUsesReturnedCursorAndDeduplicates() async throws {
        let f = try SupportR463Fixture(), flow = f.reader.makeCoordinator(), visit = flow.begin()
        let rows = (1...30).map { SupportR463Fixture.ticket.replacingOccurrences(of: "CS20261021-000123", with: "CS\($0)") }
        f.wire.body = SupportR463Fixture.listing(rows, cursor: 31, more: true)
        await flow.loadHistory(try XCTUnwrap(flow.capture(visit))); XCTAssertEqual(flow.tickets.count, 30); XCTAssertTrue(flow.hasMoreTickets)
        f.wire.body = SupportR463Fixture.listing([SupportR463Fixture.ticket], cursor: 30)
        await flow.loadHistory(try XCTUnwrap(flow.capture(visit)), next: true); XCTAssertEqual(flow.tickets.count, 31)
        let request = try XCTUnwrap(f.wire.requests.last); XCTAssertEqual(SupportTicketReadRoute(request: request, baseURL: f.context.baseURL), .history(before: 31))
    }
    func testFullCapturedIdentityChangesPreventDispatch() async throws {
        let variants: [(Int, UInt64, String, String, String)] = [(8,1,"support-synthetic","synthetic-support-token","player"),(7,2,"support-synthetic","synthetic-support-token","player"),(7,1,"other","synthetic-support-token","player"),(7,1,"support-synthetic","new-token","player"),(7,1,"support-synthetic","synthetic-support-token","merchant")]
        for (account,epoch,namespace,token,role) in variants {
            let f = try SupportR463Fixture()
            f.current = .init(market: .china, baseURL: f.context.baseURL, role: role, session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: role))
            do { _ = try await f.reader.history(); XCTFail() } catch { }
            XCTAssertTrue(f.wire.requests.isEmpty)
        }
    }
    func testExpiredAndWrongRoleCannotConstructLease() throws {
        let f = try SupportR463Fixture(); XCTAssertThrowsError(try SupportTicketReadApproval(context: f.context, expiresAt: .distantPast))
        let wrong = RuntimeDependencyContext(market: .china, baseURL: f.context.baseURL, role: "merchant", session: f.context.session)
        XCTAssertThrowsError(try SupportTicketReadApproval(context: wrong, expiresAt: Date().addingTimeInterval(600)))
    }
}

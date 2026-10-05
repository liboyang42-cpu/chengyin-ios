import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor TicketWalletTransport: HTTPTransport {
    struct Reply { let json: String; var status: Int = 200 }
    let replies: [String: Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [String: Reply] = [:]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let route = request.url?.lastPathComponent == "info" ? "detail" : body.contains("name=\"owner_type\"\r\n\r\n1\r\n") ? "route" : "activity"
        let reply = replies[route] ?? Reply(json: #"{"code":200,"data":[]}"#)
        return (Data(reply.json.utf8), reply.status)
    }
}
private actor TicketWalletSuspendedTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let index = requests.count; requests.append(request)
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func waitForRequests(_ count: Int) async {
        while pending.count < count { await Task.yield() }
    }
    func finishAll(_ json: String, status: Int = 200) {
        let values = Array(pending.values); pending.removeAll()
        for continuation in values { continuation.resume(returning: (Data(json.utf8), status)) }
    }
}

final class TicketWalletTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> TicketWalletService {
        try TicketWalletService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func decode(_ json: String) throws -> TicketWalletTicket {
        try JSONDecoder().decode(TicketWalletTicket.self, from: Data(json.utf8))
    }
    private func body(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }
    func testExactTwoLaneRequestsRawAuthorizationAndFreshReads() async throws {
        let t = TicketWalletTransport(["route": .init(json: TicketWalletSyntheticFixtures.routeListJSON), "activity": .init(json: TicketWalletSyntheticFixtures.activityListJSON)])
        let api = try service(t)
        let wallet = try await api.wallet(token: "synthetic-token")
        XCTAssertEqual(wallet.tickets.map(\.id), [901, 902, 903, 904, 905])
        XCTAssertNil(wallet.partialFailure)
        _ = try await api.wallet(token: "synthetic-token")
        let requests = await t.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests.filter { body($0).contains("name=\"owner_type\"\r\n\r\n1\r\n") }.count, 2)
        XCTAssertEqual(requests.filter { body($0).contains("name=\"owner_type\"\r\n\r\n2\r\n") }.count, 2)
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/test/api/registration/list")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data;") == true)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            for key in ["status", "is_online", "pageNum", "pageSize", "ownerType"] { XCTAssertFalse(body(request).contains("name=\"\(key)\"")) }
        }
    }
    func testListEnvelopeContractAndMalformedRowsNeverBecomeEmptySuccess() async throws {
        for json in [#"{"code":200,"data":[{"id":7}]}"#, #"{"code":200,"data":{"rows":[{"id":7}]}}"#] {
            let t = TicketWalletTransport(["route": .init(json: json)])
            let rows = try await service(t).list(lane: .route, token: "synthetic-token")
            XCTAssertEqual(rows.map(\.id), [7])
        }
        for json in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":[]}"#] {
            for lane in TicketWalletLane.allCases {
                let t = TicketWalletTransport(["route": .init(json: json), "activity": .init(json: json)])
                let rows = try await service(t).list(lane: lane, token: "synthetic-token")
                XCTAssertTrue(rows.isEmpty)
            }
        }
        for (lane, json) in [(TicketWalletLane.activity, #"{"code":200,"data":{"rows":[]}}"#), (.route, #"{"code":200,"data":[{"id":7},3]}"#), (.activity, #"{"code":200,"data":[{}]}"#), (.route, #"{"code":200,"data":"bad"}"#)] {
            let t = TicketWalletTransport(["route": .init(json: json), "activity": .init(json: json)])
            do { _ = try await service(t).list(lane: lane, token: "synthetic-token"); XCTFail("Malformed list accepted") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testPartialFailuresPreserveOtherLaneEvenWhenEmptyAndBothFailurePrefersRoute() async throws {
        for failedLane in TicketWalletLane.allCases {
            for empty in [false, true] {
                let failure = #"{"code":500,"msg":"Explicit server message","data":"bad"}"#
                let success = empty ? #"{"code":200,"data":[]}"# : #"{"code":200,"data":[{"id":7}]}"#
                let t = TicketWalletTransport(["route": .init(json: failedLane == .route ? failure : success), "activity": .init(json: failedLane == .activity ? failure : success)])
                let result = try await service(t).wallet(token: "synthetic-token")
                XCTAssertEqual(result.tickets.count, empty ? 0 : 1)
                XCTAssertEqual(result.partialFailure, .init(lane: failedLane, issue: .server("Explicit server message")))
            }
        }
        let t = TicketWalletTransport(["route": .init(json: #"{"code":501,"msg":"route failure"}"#), "activity": .init(json: #"{"code":502,"msg":"activity failure"}"#)])
        do { _ = try await service(t).wallet(token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? TicketWalletReadFailure, .rejected(code: 501, message: "route failure")) }
    }
    func testCurrentUnauthorizedLaneClosesWholeWalletAndPrecedesPayloadAndProse() async throws {
        for lane in TicketWalletLane.allCases {
            for http401 in [false, true] {
                let failure = TicketWalletTransport.Reply(json: http401 ? "bad payload" : #"{"code":401,"msg":{},"data":"bad"}"#, status: http401 ? 401 : 200)
                let t = TicketWalletTransport([lane == .route ? "route" : "activity": failure])
                do { _ = try await service(t).wallet(token: "synthetic-token"); XCTFail() }
                catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            }
        }
    }
    func testServerMessageProvenanceAndMissingMessagesRemainDifferent() async throws {
        let text = "路线票加载失败"
        for json in ["{\"code\":500,\"msg\":\"\(text)\"}", #"{"code":500,"msg":""}"#, #"{"code":500}"#] {
            let t = TicketWalletTransport(["detail": .init(json: json)])
            do { _ = try await service(t).detail(id: 7, token: "synthetic-token"); XCTFail() }
            catch {
                let expected: TicketWalletIssue = json.contains(text) ? .server(text) : json.contains("msg") ? .server("") : .failure
                XCTAssertEqual(TicketWalletIssue(error), expected)
            }
        }
    }
    func testDetailUsesInfoAndRejectsNullMismatchMalformedAndInvalidIDBeforeTransport() async throws {
        let t = TicketWalletTransport(["detail": .init(json: "{\"code\":200,\"data\":\(TicketWalletSyntheticFixtures.detailJSON)}")])
        let result = try await service(t).detail(id: 901, token: "synthetic-token")
        XCTAssertEqual(result.id, 901)
        let requests = await t.requests
        XCTAssertEqual(requests.first?.url?.path, "/test/api/registration/info")
        XCTAssertTrue(body(try XCTUnwrap(requests.first)).contains("name=\"id\"\r\n\r\n901\r\n"))
        for json in [#"{"code":200,"data":null}"#, #"{"code":200,"data":{"id":8}}"#] {
            do { _ = try await service(TicketWalletTransport(["detail": .init(json: json)])).detail(id: 7, token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? TicketWalletReadFailure, .unavailable) }
        }
        do { _ = try await service(TicketWalletTransport(["detail": .init(json: #"{"code":200,"data":{}}"#)])).detail(id: 7, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        let invalid = TicketWalletTransport()
        for id in [0, -1] { do { _ = try await service(invalid).detail(id: id, token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) } }
        do { _ = try await service(invalid).wallet(token: "\n"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        let invalidRequests = await invalid.requests; XCTAssertTrue(invalidRequests.isEmpty)
    }
    func testStatusPrecedenceAndActionRoutingAreIndependent() throws {
        for (registration, expectedStatus, expectedAction) in [(1, TicketWalletStatus.pending, TicketWalletAction.paymentUnavailable), (2, .ready, .detail), (3, .cancelled, .cancelled), (4, .expired, .expired), (99, .unknown, .unknown)] {
            for verification in [0, 1] {
                let ticket = try decode("{\"id\":1,\"registrationStatus\":\(registration),\"verificationStatus\":\(verification)}")
                XCTAssertEqual(ticket.status, verification == 1 ? .verified : expectedStatus)
                XCTAssertEqual(ticket.action, expectedAction)
            }
        }
        XCTAssertEqual(try decode(#"{"id":1}"#).status, .unknown)
    }
    func testEntitlementsRemainAuthoritativeAfterFirstVerificationAndUnknownNeverBecomesPending() throws {
        let ticket = try decode(TicketWalletSyntheticFixtures.detailJSON)
        XCTAssertEqual(ticket.status, .verified); XCTAssertEqual(ticket.pendingCount, 1)
        XCTAssertEqual(ticket.redemption, .notImplemented)
        XCTAssertEqual(ticket.purchaseKind, "EXPLORE_PASS")
        XCTAssertEqual(ticket.entitlements.map(\.id), [31, 32, 33])
        XCTAssertEqual(ticket.entitlements.map(\.statusKey), ["redeemed", "pending", "invalid"])
        let unknown = try decode(#"{"id":1,"registrationStatus":2,"entitlements":[{"id":2}]}"#)
        XCTAssertEqual(unknown.pendingCount, 0); XCTAssertEqual(unknown.redemption, .unknown)
        XCTAssertTrue(unknown.hasUnknownEntitlementStatus)
        for (raw, expected) in [(1, TicketWalletRedemption.unpaid), (3, .cancelled), (4, .expired), (99, .unknown)] {
            XCTAssertEqual(try decode("{\"id\":1,\"registrationStatus\":\(raw)}").redemption, expected)
        }
        XCTAssertEqual(try decode(#"{"id":1,"registrationStatus":2,"verificationStatus":1}"#).redemption, .complete)
    }
    func testOwnerPrecedenceAllProductTypesAndUnknownMoneyRetained() throws {
        let ticket = try decode(#"{"id":7,"cmsActivity":{"name":"activity","productType":1},"cmsTopic":{"name":"topic","productType":2},"payableAmount":0}"#)
        XCTAssertEqual(ticket.title, "activity"); XCTAssertEqual(ticket.productType, 1); XCTAssertEqual(ticket.payableAmount, 0)
        XCTAssertNil(try decode(#"{"id":7,"cmsTopic":{"name":"topic"}}"#).payableAmount)
        for json in [#"{"id":0}"#, #"{"id":-1}"#, #"{"id":1,"registrationStatus":true}"#, #"{"id":1,"entitlements":[{"id":0}]}"#] { XCTAssertThrowsError(try decode(json)) }
    }
    @MainActor func testGuestAndUnconfiguredNeverStartPrivateReads() async throws {
        let t = TicketWalletTransport()
        let guest = TicketWalletSessionReader(service: try service(t), currentSession: { nil })
        do { _ = try await guest.ticketWallet(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        let session = try TicketWalletReadSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let unconfigured = TicketWalletSessionReader(service: nil, currentSession: { session })
        do { _ = try await unconfigured.ticketDetail(id: 7); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let requests = await t.requests; XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testStaleSuccessAnd401CannotCrossAccountEpochTokenOrSignOut() async throws {
        let first = try TicketWalletReadSession(accountID: 1, epoch: 1, token: "synthetic-first")
        let nextSessions: [TicketWalletReadSession?] = [nil,
            try TicketWalletReadSession(accountID: 2, epoch: 1, token: "synthetic-first"),
            try TicketWalletReadSession(accountID: 1, epoch: 2, token: "synthetic-first"),
            try TicketWalletReadSession(accountID: 1, epoch: 1, token: "synthetic-rotated")]
        for next in nextSessions {
            for unauthorized in [false, true] {
                var current: TicketWalletReadSession? = first
                var invalidations = 0
                let t = TicketWalletSuspendedTransport()
                let reader = TicketWalletSessionReader(service: try service(t), currentSession: { current }, onUnauthorized: { _ in invalidations += 1 })
                let scope = reader.scope
                let task = Task { try await reader.ticketDetail(id: 7) }
                await t.waitForRequests(1)
                current = next
                XCTAssertNotEqual(scope, reader.scope)
                await t.finishAll(unauthorized ? #"{"code":401}"# : #"{"code":200,"data":{"id":7}}"#)
                do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(invalidations, 0)
            }
        }
    }
    @MainActor func testWalletPairStaleResponsesAndCancellationDoNotInvalidateNewSession() async throws {
        let first = try TicketWalletReadSession(accountID: 1, epoch: 1, token: "synthetic-first")
        for cancel in [false, true] {
            var current: TicketWalletReadSession? = first
            var invalidations = 0
            let t = TicketWalletSuspendedTransport()
            let reader = TicketWalletSessionReader(service: try service(t), currentSession: { current }, onUnauthorized: { _ in invalidations += 1 })
            let task = Task { try await reader.ticketWallet() }
            await t.waitForRequests(2)
            if cancel { task.cancel() } else { current = nil }
            await t.finishAll(#"{"code":401}"#)
            do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(invalidations, 0)
        }
    }
    @MainActor func testCurrent401InvalidatesExactlyOnce() async throws {
        let session = try TicketWalletReadSession(accountID: 1, epoch: 1, token: "synthetic-first")
        let t = TicketWalletTransport(["route": .init(json: #"{"code":401}"#), "activity": .init(json: #"{"code":401}"#)])
        var invalidations: [TicketWalletReadSession] = []
        let reader = TicketWalletSessionReader(service: try service(t), currentSession: { session }, onUnauthorized: { invalidations.append($0) })
        do { _ = try await reader.ticketWallet(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(invalidations, [session])
    }
    @MainActor func testScreenGenerationFreshReadScopeHidingAndDisappearance() async throws {
        let model = TicketWalletReadModel<String>()
        var scope = UUID()
        await model.load(scope: scope, currentScope: { scope }) { "first" }
        XCTAssertEqual(model.visibleValue(scope: scope), "first")
        var pending: CheckedContinuation<String, Error>?
        let oldScope = scope
        let old = Task { await model.load(scope: oldScope, currentScope: { scope }) { try await withCheckedThrowingContinuation { pending = $0 } } }
        while pending == nil { await Task.yield() }
        XCTAssertNil(model.visibleValue(scope: scope)); XCTAssertTrue(model.isLoading)
        await model.load(scope: scope, currentScope: { scope }) { "newer" }
        pending?.resume(returning: "stale"); await old.value
        XCTAssertEqual(model.visibleValue(scope: scope), "newer")
        model.cancelPending()
        XCTAssertEqual(model.visibleValue(scope: scope), "newer", "Pushing detail must preserve list row identity")
        scope = UUID(); XCTAssertNil(model.visibleValue(scope: scope))
        await model.load(scope: scope, currentScope: { scope }) { throw APIError.httpStatus(503) }
        XCTAssertNil(model.visibleValue(scope: scope)); XCTAssertEqual(model.visibleIssue(scope: scope), .failure)
        model.invalidate(); XCTAssertNil(model.visibleIssue(scope: scope)); XCTAssertNil(model.loadedScope)
    }
    @MainActor func testScreenStaleFailureAndLateResponseAfterLeavingCannotReplaceNewState() async throws {
        let model = TicketWalletReadModel<String>()
        let scope = UUID()
        var pending: CheckedContinuation<String, Error>?
        let old = Task { await model.load(scope: scope, currentScope: { scope }) { try await withCheckedThrowingContinuation { pending = $0 } } }
        while pending == nil { await Task.yield() }
        await model.load(scope: scope, currentScope: { scope }) { "current" }
        pending?.resume(throwing: APIError.unauthorized); await old.value
        XCTAssertEqual(model.visibleValue(scope: scope), "current"); XCTAssertNil(model.visibleIssue(scope: scope))
        pending = nil
        let leaving = Task { await model.load(scope: scope, currentScope: { scope }) { try await withCheckedThrowingContinuation { pending = $0 } } }
        while pending == nil { await Task.yield() }
        model.cancelPending()
        pending?.resume(returning: "late"); await leaving.value
        XCTAssertNil(model.visibleValue(scope: scope)); XCTAssertFalse(model.isLoading)
    }
}

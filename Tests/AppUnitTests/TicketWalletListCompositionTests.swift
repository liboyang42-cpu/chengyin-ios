import XCTest
@testable import Questify

/// Only synthetic transports. No production URL, real credentials, device or HTTP connection.
@MainActor final class TicketWalletListCompositionTests: XCTestCase {
    private let base = URL(string:"https://example.test/native")!
    private func deployment() throws -> ReviewedAppDeployment {
        try .init(market:.china,baseURL:base.absoluteString,approvedBaseURLs:[.china:[base.absoluteString]],
            verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.ticket-list",realm:"synthetic",reads:[])
    }
    private func form(_ owner: String = "1", extra: [String:String] = [:], path: String = "api/registration/list") throws -> URLRequest {
        var fields = extra; fields["owner_type"] = owner
        return try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent(path),fields:fields,token:"synthetic-7")
    }
    private func transport(_ wire: Wire) throws -> CompositionHTTPTransport {
        let value = CompositionHTTPTransport(deployment:try deployment(),underlying:wire)
        value.current = { .init(epoch:1,accountID:7,role:"player",token:"synthetic-7",viewerRevision:1) }; return value
    }
    private func root(_ wire: Wire, _ vault: Vault) throws -> AppCompositionRoot {
        let name = "ticket-list-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName:name))
        addTeardownBlock { defaults.removePersistentDomain(forName:name) }
        return .init(deployment:.reviewed(try deployment()),storage:.init(defaults:defaults,tokenStore:{ _ in vault }),makeTransport:{ wire })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456")
        XCTAssertEqual(session.account?.id,7)
    }
    func testNormalExistingSessionWalletReadsTwoRealTableLanesWithoutNewUIOrGrant() async throws {
        let wire = Wire(), session = try root(wire,Vault()).makeSession(); await login(session); wire.requests = []
        let wallet = try await session.ticketWalletReader.ticketWallet()
        XCTAssertEqual(wallet.tickets.map(\.id),[41,42]); XCTAssertNil(wallet.partialFailure)
        XCTAssertEqual(Set(wire.requests.compactMap { TicketWalletListReadRoute(request:$0,baseURL:base)?.rawValue }),[1,2])
        XCTAssertEqual(wire.requests.count,2)
    }
    func testGuestAndUnconfiguredSessionMakeNoWalletRequests() async throws {
        let wire = Wire(), session = try root(wire,Vault()).makeSession()
        do { _ = try await session.ticketWalletReader.ticketWallet(); XCTFail() } catch { XCTAssertEqual(error as? APIError,.unauthorized) }
        XCTAssertTrue(wire.requests.isEmpty)
        let unconfigured = CompositionHTTPTransport(deployment:nil,underlying:wire)
        do { _ = try await unconfigured.send(form()); XCTFail() } catch { XCTAssertEqual(error as? APIError,.notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testClonesRetainExactTwoLaneAllowanceAndResponseFence() async throws {
        for order in [false,true] {
            let original = Wire(), wire = Wire(), t = try transport(original)
            let clone = order ? t.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection()) : t.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
            _ = try await clone.send(form("1")); _ = try await clone.send(form("2"))
            wire.overrides[1] = #"{"code":200,"data":[{"id":41,"memberId":8,"ownerType":1}]}"#
            do { _ = try await clone.send(form()); XCTFail() } catch { XCTAssertEqual(error as? APIError,.malformedResponse) }
            XCTAssertEqual(wire.requests.count,3); XCTAssertTrue(original.requests.isEmpty)
        }
    }
    func testOtherOwnerTypesAddedQueryDetailsAndWritesNeverDispatch() async throws {
        let wire = Wire(), t = try transport(wire); var invalid = [URLRequest]()
        for value in ["0","3","4","01","1 "] { invalid.append(try form(value)) }
        for key in ["memberId","member_id","pageNum","pageSize","status","is_online"] { invalid.append(try form(extra:[key:"1"])) }
        for path in ["api/registration/info","api/registration/pay","api/registration/create","api/registration/cancel","api/verify/dyncode/issue","api/team/my"] { invalid.append(try form(path:path)) }
        invalid.append(try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent("api/registration/info"),fields:["id":"41"],token:"synthetic-7"))
        for suffix in ["?x=1","?owner_type=1","#x"] { var r = try form(); r.url = URL(string:r.url!.absoluteString + suffix); invalid.append(r) }
        for request in invalid { do { _ = try await t.send(request); XCTFail() } catch {} }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExactTokenAndCompleteSignedInIdentityRequiredBeforeDispatch() async throws {
        let wire = Wire(), t = try transport(wire); var wrongToken = try form(); wrongToken.setValue("other",forHTTPHeaderField:"Authorization")
        do { _ = try await t.send(wrongToken); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        let identities: [CompositionHTTPTransport.SessionIdentity] = [
            .init(epoch:1,accountID:nil,role:nil,token:nil),.init(epoch:1,accountID:0,role:"player",token:"synthetic-7"),
            .init(epoch:1,accountID:7,role:nil,token:"synthetic-7"),.init(epoch:1,accountID:7,role:"admin",token:"synthetic-7"),
            .init(epoch:1,accountID:7,role:"player",token:nil)]
        for identity in identities { t.current = { identity }; do { _ = try await t.send(form()); XCTFail() } catch {} }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testForeignLaneCannotPublishRowsAndHealthyLaneRetainsPartialWarning() async throws {
        let wire = Wire(), session = try root(wire,Vault()).makeSession(); await login(session)
        wire.overrides[1] = #"{"code":200,"data":{"rows":[{"id":41,"memberId":7,"ownerType":1},{"id":99,"memberId":8,"ownerType":1}]}}"#
        let wallet = try await session.ticketWalletReader.ticketWallet()
        XCTAssertEqual(wallet.tickets.map(\.id),[42]); XCTAssertEqual(wallet.partialFailure?.lane,.route)
        XCTAssertEqual(wallet.partialFailure?.issue,.malformed)
    }
    func testCurrent401StillExpiresCurrentSessionThroughExistingReader() async throws {
        for status in [200,401] {
            let wire = Wire(), vault = Vault(), session = try root(wire,vault).makeSession(); await login(session)
            wire.status = status; wire.overrides[1] = #"{"code":401,"data":false}"#
            do { _ = try await session.ticketWalletReader.ticketWallet(); XCTFail() } catch { XCTAssertEqual(error as? APIError,.unauthorized) }
            XCTAssertNil(session.account); XCTAssertNil(vault.value)
        }
    }
    func testLateSuccessErrorAnd401AfterIdentityTokenEpochViewerOrCancelAreDiscarded() async throws {
        for transition in ["account","token","epoch","roleABA","cancel"] {
            for outcome in [200,401,-1] {
                let wire = Wire(), t = try transport(wire), started = expectation(description:"synthetic paused read")
                wire.pause = true; wire.onPaused = { started.fulfill() }
                let request = try form(), task = Task { try await t.send(request) }
                await fulfillment(of:[started],timeout:2)
                switch transition {
                case "account": t.current = { .init(epoch:2,accountID:8,role:"player",token:"synthetic-8",viewerRevision:2) }
                case "token": t.current = { .init(epoch:1,accountID:7,role:"player",token:"rotated",viewerRevision:1) }
                case "epoch": t.current = { .init(epoch:2,accountID:7,role:"player",token:"synthetic-7",viewerRevision:1) }
                case "roleABA": t.current = { .init(epoch:1,accountID:7,role:"player",token:"synthetic-7",viewerRevision:3) }
                default: task.cancel()
                }
                wire.finish(outcome)
                do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            }
        }
    }
    @MainActor private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], overrides: [Int:String] = [:], status = 200, pause = false
        var onPaused: (() -> Void)?
        private var pending: CheckedContinuation<(Data,Int),Error>?
        private var pausedValue = Data()
        func finish(_ outcome: Int) {
            let p = pending; pending = nil
            if outcome == -1 { p?.resume(throwing:URLError(.notConnectedToInternet)) }
            else { p?.resume(returning:(outcome == 200 ? pausedValue : Data("{\"code\":\(outcome)}".utf8),200)) }
        }
        func send(_ request: URLRequest) async throws -> (Data,Int) {
            requests.append(request); let path = request.url!.path
            if path.hasSuffix("/phone") { return (Data(#"{"code":200,"token":"synthetic-7","data":{"id":7,"role":"player"}}"#.utf8),200) }
            if path.hasSuffix("/userInfo") { return (Data(#"{"code":200,"appUser":{"userId":7,"role":"player"}}"#.utf8),200) }
            let lane = TicketWalletListReadRoute(request:request,baseURL:URL(string:"https://example.test/native")!)?.rawValue ?? 0
            let body = overrides[lane] ?? "{\"code\":200,\"data\":{\"rows\":[{\"id\":\(40+lane),\"memberId\":7,\"ownerType\":\(lane),\"registrationStatus\":2}],\"total\":1}}"
            if pause { pausedValue = Data(body.utf8); return try await withCheckedThrowingContinuation { pending = $0; onPaused?() } }
            return (Data(body.utf8),status)
        }
    }
}

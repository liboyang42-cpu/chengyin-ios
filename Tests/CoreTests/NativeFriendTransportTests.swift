import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeFriendTransportTests: XCTestCase {
    private func context(account: Int = 2, epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://friend.test/")!, role: "player",
              session: try .init(accountID: account, epoch: epoch, namespace: "friend-test", token: "test-token", role: "player"))
    }
    private func approval(_ context: RuntimeDependencyContext, writes: Bool = true) throws -> NativeFriendApproval {
        try .init(endpoint: .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID,
                                 paths: writes ? NativeFriendApproval.readPaths.union(NativeFriendApproval.writePaths) : NativeFriendApproval.readPaths), expiresAt: Date().addingTimeInterval(600))
    }
    private func request(_ context: RuntimeDependencyContext, path: String = "api/friend/request", fields: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: context.baseURL.appendingPathComponent(path));request.httpShouldHandleCookies = false;request.httpMethod = "POST"
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization");request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields ?? ["peer_id": 9, "request_id": UUID().uuidString, "msg": "hello"]);return request
    }
    func testInvalidEndpointRemainsRejectedBeforeTransport() {
        XCTAssertThrowsError(try APIConfiguration(baseURL: URL(string: "https://friend.invalid/")!)) { error in
            XCTAssertEqual(error as? APIError, .invalidConfiguration)
        }
    }
    func testExactWriteAndReadContract() throws {
        let c = try context(), a = try approval(c);XCTAssertTrue(NativeFriendTransportPolicy.accepts(try request(c), context: c, approval: a))
        var read = try request(c);read.httpMethod = "GET";read.httpBody = nil;read.url = URL(string: "https://friend.test/api/friend/requests?cursor=0&limit=50")!
        XCTAssertTrue(NativeFriendTransportPolicy.accepts(read, context: c, approval: a))
        read.url = URL(string: "https://friend.test/api/friend/requests?cursor=0&limit=50&viewer_id=3")!
        XCTAssertFalse(NativeFriendTransportPolicy.accepts(read, context: c, approval: a))
        read.url = URL(string: "https://friend.test/api/friend/requests?cursor=0&cursor=1&limit=50")!
        XCTAssertFalse(NativeFriendTransportPolicy.accepts(read, context: c, approval: a))
    }
    func testCookieStreamProxyAndOriginSmugglingAreRejected() throws {
        let c = try context(), a = try approval(c), good = try request(c)
        var bad = good;bad.httpShouldHandleCookies = true;XCTAssertFalse(NativeFriendTransportPolicy.accepts(bad, context: c, approval: a))
        bad = good;bad.setValue("sid=wrong", forHTTPHeaderField: "Cookie");XCTAssertFalse(NativeFriendTransportPolicy.accepts(bad, context: c, approval: a))
        bad = good;bad.setValue("wrong", forHTTPHeaderField: "Proxy-Authorization");XCTAssertFalse(NativeFriendTransportPolicy.accepts(bad, context: c, approval: a))
        bad = good;bad.httpBodyStream = InputStream(data: Data("{}".utf8));XCTAssertFalse(NativeFriendTransportPolicy.accepts(bad, context: c, approval: a))
        for url in ["https://other.invalid/api/friend/request", "https://friend.test/api/friend/request?peer_id=8", "https://friend.test/api/friend/request#extra", "https://u:p@friend.test/api/friend/request", "https://friend.test/api/im/start"] {
            bad = good;bad.url = URL(string: url)!;XCTAssertFalse(NativeFriendTransportPolicy.accepts(bad, context: c, approval: a))
        }
    }
    func testBodyKeysAndNumberTypesCannotBypassGrant() throws {
        let c = try context(), a = try approval(c), id = UUID().uuidString
        for peer: Any in [true, "9", 9.5, 0, 2] {
            XCTAssertFalse(NativeFriendTransportPolicy.accepts(try request(c, fields: ["peer_id": peer, "request_id": id, "msg": "hello"]), context: c, approval: a))
        }
        for fields: [String: Any] in [["peer_id": 9, "request_id": id, "msg": "hello", "viewer_id": 2], ["peer_id": 9, "request_id": id, "msg": "hello", "expected_version": "1"], ["peer_id": 9, "request_id": id, "msg": String(repeating: "a", count: 61)]] {
            XCTAssertFalse(NativeFriendTransportPolicy.accepts(try request(c, fields: fields), context: c, approval: a))
        }
        for version: Any in [true, "1", 1.5, 0] {
            XCTAssertFalse(NativeFriendTransportPolicy.accepts(try request(c, path: "api/friend/accept", fields: ["peer_id": 9, "request_id": id, "msg": "", "expected_version": version]), context: c, approval: a))
        }
        XCTAssertTrue(NativeFriendTransportPolicy.accepts(try request(c, path: "api/friend/accept", fields: ["peer_id": 9, "request_id": id, "msg": "", "expected_version": 1]), context: c, approval: a))
    }
    func testReadGrantExpiryAccountAndMethodDoNotGrantWrites() throws {
        let c = try context(), a = try approval(c), request = try request(c)
        XCTAssertFalse(NativeFriendTransportPolicy.accepts(request, context: c, approval: try approval(c, writes: false)))
        XCTAssertFalse(NativeFriendTransportPolicy.accepts(request, context: c, approval: a, now: a.expiresAt))
        XCTAssertFalse(NativeFriendTransportPolicy.accepts(request, context: try context(account: 3), approval: a))
        var changed = request;changed.httpMethod = "PUT";XCTAssertFalse(NativeFriendTransportPolicy.accepts(changed, context: c, approval: a))
    }
    private final class Recorder: HTTPTransport {
        var requests: [URLRequest] = [];var reply = Data();var status = 200;var duringSend: (() -> Void)?;var failure: NativeFriendFailure?
        func send(_ request: URLRequest) async throws -> (Data, Int) { if let failure { throw failure };requests.append(request);duringSend?();return (reply, status) }
    }
    func testActualServiceDisablesCookiesAndRejectsOtherViewerResponse() async throws {
        let c = try context(), a = try approval(c), transport = Recorder()
        transport.reply = Data(#"{"code":200,"data":{"viewer_id":8,"peer_id":9,"state":1,"version":1}}"#.utf8)
        let service = try NativeFriendService(context: c, approval: a, currentApproval: { a }, transport: transport, current: { c })
        do { _ = try await service.relationship(peerID: 9);XCTFail("wrong viewer accepted") } catch { XCTAssertEqual(error as? NativeFriendFailure, .invalid) }
        XCTAssertEqual(transport.requests.count, 1);XCTAssertFalse(try XCTUnwrap(transport.requests.first).httpShouldHandleCookies)
    }
    func testPostDispatchEpochOrApprovalLossIsUnknownNotSuccess() async throws {
        let c = try context(), a = try approval(c), transport = Recorder();var current: RuntimeDependencyContext? = c
        transport.duringSend = { current = nil };transport.reply = Data(#"{"code":200,"data":{}}"#.utf8)
        let service = try NativeFriendService(context: c, approval: a, currentApproval: { a }, transport: transport, current: { current })
        do { _ = try await service.write(.init(peerID: 9, action: .request, message: "hello"));XCTFail("stale write accepted") }
        catch { XCTAssertEqual(error as? NativeFriendFailure, .unknown) }
    }
    func testWithdrawnThenReissuedIdenticalGrantCannotReviveOldService() throws {
        let c = try context(), first = try approval(c), transport = Recorder();var currentGrant: NativeFriendApproval? = first
        let old = try NativeFriendService(context: c, approval: first, currentApproval: { currentGrant }, transport: transport, current: { c })
        XCTAssertTrue(old.isCurrent);currentGrant = nil;XCTAssertFalse(old.isCurrent)
        currentGrant = first;XCTAssertFalse(old.isCurrent, "observed withdrawal permanently retires the captured service")
        let reissued = try NativeFriendApproval(endpoint: first.endpoint, expiresAt: first.expiresAt)
        XCTAssertNotEqual(reissued.issuanceID, first.issuanceID);currentGrant = reissued;XCTAssertFalse(old.isCurrent)
        let fresh = try NativeFriendService(context: c, approval: reissued, currentApproval: { currentGrant }, transport: transport, current: { c })
        XCTAssertTrue(fresh.isCurrent)
    }
    func testTrustedPreForwardNotSentIsPreservedButTransportUncertaintyIsNotDowngraded() async throws {
        let c = try context(), a = try approval(c), transport = Recorder()
        let service = try NativeFriendService(context: c, approval: a, currentApproval: { a }, transport: transport, current: { c })
        for failure in [NativeFriendFailure.notSent, .unknown] {
            transport.failure = failure
            do { _ = try await service.write(.init(peerID: 9, action: .request, message: "hello"));XCTFail("failure accepted") }
            catch { XCTAssertEqual(error as? NativeFriendFailure, failure) }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testCancellationBeforeServiceDispatchIsKnownNotSent() async throws {
        let c = try context(), a = try approval(c), transport = Recorder()
        let service = try NativeFriendService(context: c, approval: a, currentApproval: { a }, transport: transport, current: { c })
        let task = Task { try await service.write(.init(peerID: 9, action: .request, message: "hello")) }
        task.cancel()
        do { _ = try await task.value;XCTFail("cancelled write accepted") }
        catch { XCTAssertEqual(error as? NativeFriendFailure, .notSent) }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testExactHTTP401AuthenticationRefusalClearsFlowJournalAndNotifiesCurrentSession() async throws {
        let c = try context(), a = try approval(c), transport = Recorder();var expired: [RuntimeDependencyContext] = []
        transport.reply = Data(#"{"code":200,"data":{"viewer_id":2,"incoming":[],"outgoing":[],"friends":[],"has_more":false}}"#.utf8)
        let service = try NativeFriendService(context: c, approval: a, currentApproval: { a }, transport: transport, current: { c }, onUnauthorized: { expired.append($0) })
        let suite = "NativeFriend401Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite));defer { defaults.removePersistentDomain(forName: suite) }
        let journal = OperationDefaultsJournal(defaults: defaults), flow = NativeFriendFlow(service: service, journal: journal, ownerKey: "owner-2")
        await flow.load();XCTAssertTrue(flow.canWrite)
        transport.status = 401;transport.reply = Data(#"{"code":401,"msg":"sign-in expired"}"#.utf8)
        await flow.perform(.init(peerID: 9, action: .request, message: "hello"))
        XCTAssertEqual(expired, [c]);XCTAssertTrue(try journal.pendingRecords(ownerKey: "owner-2").isEmpty)
        XCTAssertNil(flow.pending);XCTAssertEqual(flow.issue, "friend.sessionExpired");XCTAssertFalse(service.isCurrent)
    }
    func testNonmatching401AndHTTP5xxRemainUnknownAndLate401CannotExpireReplacementSession() async throws {
        for status in [401, 503] {
            let c = try context(), a = try approval(c), transport = Recorder();var notified = false
            transport.status = status;transport.reply = Data(#"{"code":503}"#.utf8)
            let service = try NativeFriendService(context: c, approval: a, currentApproval: { a }, transport: transport, current: { c }, onUnauthorized: { _ in notified = true })
            do { _ = try await service.write(.init(peerID: 9, action: .request, message: "hello"));XCTFail("uncertain write accepted") }
            catch { XCTAssertEqual(error as? NativeFriendFailure, .unknown) };XCTAssertFalse(notified)
        }
        let c = try context(), replacement = try context(epoch: 2), a = try approval(c), transport = Recorder();var current: RuntimeDependencyContext? = c;var notified = false
        transport.status = 401;transport.reply = Data(#"{"code":401}"#.utf8);transport.duringSend = { current = replacement }
        let service = try NativeFriendService(context: c, approval: a, currentApproval: { a }, transport: transport, current: { current }, onUnauthorized: { _ in notified = true })
        do { _ = try await service.write(.init(peerID: 9, action: .request, message: "hello"));XCTFail("late refusal published") }
        catch { XCTAssertEqual(error as? NativeFriendFailure, .unknown) };XCTAssertFalse(notified)
    }

    func testReviewCursorAndCancelIdentityAreStrictlyScoped() throws {
        let c = try context(), a = try approval(c), id = UUID().uuidString
        var read = try request(c);read.httpMethod = "GET";read.httpBody = nil
        read.url = URL(string: "https://friend.test/api/friend/requests?cursor=0&limit=50&review_cursor=71")!
        XCTAssertTrue(NativeFriendTransportPolicy.accepts(read, context: c, approval: a))
        for url in ["https://friend.test/api/friend/list?cursor=0&limit=50&review_cursor=71", "https://friend.test/api/friend/requests?cursor=0&limit=50&review_cursor=-1", "https://friend.test/api/friend/requests?cursor=0&limit=50&review_cursor=1&review_cursor=2"] {
            read.url = URL(string: url)!;XCTAssertFalse(NativeFriendTransportPolicy.accepts(read, context: c, approval: a))
        }
        let fields: [String: Any] = ["peer_id": 9, "request_id": id, "msg": "", "expected_version": 1, "review_id": 71]
        XCTAssertTrue(NativeFriendTransportPolicy.accepts(try request(c, path: "api/friend/cancel", fields: fields), context: c, approval: a))
        for action in ["accept", "reject", "request"] {
            XCTAssertFalse(NativeFriendTransportPolicy.accepts(try request(c, path: "api/friend/" + action, fields: fields), context: c, approval: a))
        }
        for invalid: Any in [true, "71", 1.5, 0] {
            var bad = fields;bad["review_id"] = invalid
            XCTAssertFalse(NativeFriendTransportPolicy.accepts(try request(c, path: "api/friend/cancel", fields: bad), context: c, approval: a))
        }
    }
    private func reviewPayload(requestID: String, outcome: String = "PENDING_REVIEW", reviewID: Int64 = 71, action: String = "request", originalID: String? = nil, state: String? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 200, "data": [
            "viewer_id": 2, "peer_id": 9, "action": action, "request_id": requestID, "outcome": outcome,
            "relationship": ["viewer_id": 2, "peer_id": 9, "state": 0, "version": 0],
            "review": ["id": reviewID, "peer_id": 9, "request_id": originalID ?? requestID, "state": state ?? outcome, "version": 1, "msg": "private application", "expires_at_ms": 1_900_000_000_000]
        ]])
    }
    func testActualServiceDecodesPendingAndEveryTerminalOriginalReceipt() async throws {
        let c = try context(), a = try approval(c), transport = Recorder(), id = UUID().uuidString
        let service = try NativeFriendService(context: c, approval: a, currentApproval: { a }, transport: transport, current: { c })
        for state in ["PENDING_REVIEW", "APPLIED", "REJECTED", "CANCELLED", "EXPIRED", "INVALIDATED"] {
            transport.reply = try reviewPayload(requestID: id, outcome: state)
            let receipt = try await service.receipt(peerID: 9, action: .request, requestID: id)
            XCTAssertEqual(receipt.review?.state.rawValue, state);XCTAssertEqual(receipt.relationship?.state, .none)
        }
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && !$0.httpShouldHandleCookies })
    }
    func testWrongOriginalReviewIdentityOrOutcomeCannotResolveWrite() async throws {
        let c = try context(), a = try approval(c), transport = Recorder(), command = NativeFriendCommand(peerID: 9, action: .request, message: "private application")
        let service = try NativeFriendService(context: c, approval: a, currentApproval: { a }, transport: transport, current: { c })
        for reply in [try reviewPayload(requestID: command.requestID, originalID: UUID().uuidString), try reviewPayload(requestID: command.requestID, state: "REJECTED")] {
            transport.reply = reply
            do { _ = try await service.write(command);XCTFail("mismatched private review accepted") }
            catch { XCTAssertEqual(error as? NativeFriendFailure, .invalid) }
        }
    }
    func testActualReviewCancelSendsExactProposalAndRejectsDifferentReceipt() async throws {
        let c = try context(), a = try approval(c), transport = Recorder(), command = NativeFriendCommand(peerID: 9, action: .cancel, expectedVersion: 1, reviewID: 71)
        let service = try NativeFriendService(context: c, approval: a, currentApproval: { a }, transport: transport, current: { c })
        transport.reply = try reviewPayload(requestID: command.requestID, outcome: "APPLIED", reviewID: 72, action: "cancel", originalID: UUID().uuidString, state: "CANCELLED")
        do { _ = try await service.write(command);XCTFail("different proposal accepted") }
        catch { XCTAssertEqual(error as? NativeFriendFailure, .unknown) }
        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(fields["review_id"] as? Int, 71);XCTAssertEqual(fields["expected_version"] as? Int, 1)
        XCTAssertEqual(fields["request_id"] as? String, command.requestID)
        transport.reply = try reviewPayload(requestID: command.requestID, outcome: "APPLIED", action: "cancel", originalID: UUID().uuidString, state: "CANCELLED")
        let result = try await service.write(command);XCTAssertEqual(result.review?.state, .cancelled)
    }

}

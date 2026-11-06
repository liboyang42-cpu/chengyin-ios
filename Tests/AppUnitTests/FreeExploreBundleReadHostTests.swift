import XCTest
@testable import Questify

@MainActor final class FreeExploreBundleReadHostTests: XCTestCase {
    func testNilApprovalCreatesNoHostAndNoRequests() throws {
        let rig = try Rig(); rig.selected = nil
        XCTAssertNil(rig.host()); XCTAssertTrue(rig.wire.requests.isEmpty)
    }
    func testExactRegistrationAndServerBundleTopicBecomeTarget() async throws {
        let rig = try Rig(), host = try XCTUnwrap(rig.host())
        await host.load()
        let model = try XCTUnwrap(host.model)
        XCTAssertEqual(model.registrationID.value, 41); XCTAssertEqual(model.topicID.value, 901)
        XCTAssertEqual(rig.wire.requests.first?.url?.query, "registrationId=41")
        await model.load()
        XCTAssertTrue(rig.wire.requests.contains { $0.url?.query == "topicId=901" })
        XCTAssertTrue(rig.wire.requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertFalse(model.canReserve); XCTAssertFalse(model.canRetry)
    }
    func testWrongMemberResponseCannotCreateModel() async throws {
        let rig = try Rig(); rig.wire.memberID = 8
        let host = try XCTUnwrap(rig.host()); await host.load()
        XCTAssertNil(host.model); XCTAssertTrue(host.failed)
    }
    func testCallerAccountMismatchFailsBeforeNetwork() throws {
        let rig = try Rig()
        XCTAssertNil(rig.host(accountID: 8)); XCTAssertTrue(rig.wire.requests.isEmpty)
    }
    func testNavigationRetirementIsIrreversibleAndClearsModel() async throws {
        let rig = try Rig(), host = try XCTUnwrap(rig.host()); await host.load()
        let old = try XCTUnwrap(host.model); host.retire(); await host.load()
        XCTAssertNil(host.model); XCTAssertFalse(host.current); XCTAssertFalse(old.current)
        XCTAssertEqual(rig.wire.requests.count, 1)
    }
    func testAccountChangeDuringReadDiscardsLateResult() async throws {
        let rig = try Rig(), host = try XCTUnwrap(rig.host())
        rig.wire.onSend = { rig.current = try Rig.context(account: 8, epoch: 2) }
        await host.load()
        XCTAssertNil(host.model); XCTAssertTrue(host.retired); XCTAssertEqual(rig.unauthorizedCount, 0)
    }
    func testGrantRevocationDuringReadDiscardsLateResult() async throws {
        let rig = try Rig(), host = try XCTUnwrap(rig.host())
        rig.wire.onSend = { rig.selected?.revoke() }
        await host.load(); XCTAssertNil(host.model); XCTAssertTrue(host.retired)
    }
    func testGrantReplacementDoesNotReviveOldHost() async throws {
        let rig = try Rig(), host = try XCTUnwrap(rig.host())
        rig.selected = try FreeExploreBundleReadApproval(context: rig.captured, expiresAt: Date().addingTimeInterval(60))
        await host.load(); XCTAssertTrue(host.retired); XCTAssertTrue(rig.wire.requests.isEmpty)
    }
    func testLate401CannotExpireNewSession() async throws {
        let rig = try Rig(), host = try XCTUnwrap(rig.host()); rig.wire.status = 401
        rig.wire.onSend = { rig.current = try Rig.context(account: 7, epoch: 2) }
        await host.load()
        XCTAssertEqual(rig.unauthorizedCount, 0); XCTAssertNil(host.model); XCTAssertTrue(host.retired)
    }
    func testMatching401ExpiresCapturedSessionOnly() async throws {
        let rig = try Rig(), host = try XCTUnwrap(rig.host()); rig.wire.status = 401
        await host.load()
        XCTAssertEqual(rig.unauthorizedCount, 1); XCTAssertNil(host.model); XCTAssertTrue(host.retired)
    }
    func test403RetiresPermissionWithoutLogout() async throws {
        let rig = try Rig(), host = try XCTUnwrap(rig.host()); rig.wire.status = 403
        await host.load()
        XCTAssertTrue(host.retired); XCTAssertNil(host.model); XCTAssertEqual(rig.unauthorizedCount, 0)
    }
    func testKeychainReadFailureDoesNotFallbackOrSend() async throws {
        let rig = try Rig(), host = try XCTUnwrap(rig.host()); rig.store.failRead = true
        await host.load()
        XCTAssertTrue(host.failed); XCTAssertNil(host.model); XCTAssertTrue(rig.wire.requests.isEmpty)
        XCTAssertEqual(rig.store.writes, 0); XCTAssertEqual(rig.store.removes, 0)
    }
    func testNilBundleRemainsLegacyWithoutInventedTopic() async throws {
        let rig = try Rig(), host = try XCTUnwrap(rig.host()); rig.wire.legacy = true
        await host.load(); XCTAssertTrue(host.legacy); XCTAssertNil(host.model)
        XCTAssertEqual(rig.wire.requests.count, 1)
    }
    func testReadTransportRejectsPOSTForeignOrderAndRefundRoute() async throws {
        let rig = try Rig(), gate = FreeExploreBundleReadTransport(context: rig.captured,
            registrationID: try FreeExploreLaunchID(41), original: nil, underlying: rig.wire,
            current: { true }, denied: {})
        for (method, path) in [("POST", "reservation"), ("GET", "order?registrationId=42"),
                               ("GET", "order/refund-quote?registrationId=41"),
                               ("GET", "order?registrationId=41&memberId=7")] {
            var request = URLRequest(url: URL(string: "https://example.test/api/free-explore/bundle/" + path)!)
            request.httpMethod = method; request.setValue(rig.captured.session.token, forHTTPHeaderField: "Authorization")
            do { _ = try await gate.send(request); XCTFail("unexpected dispatch") } catch {}
        }
        XCTAssertTrue(rig.wire.requests.isEmpty)
    }
    private final class Rig {
        let captured: RuntimeDependencyContext
        var current: RuntimeDependencyContext?
        var selected: FreeExploreBundleReadApproval?
        let store = Store(), wire = Wire()
        var unauthorizedCount = 0
        init() throws {
            captured = try Self.context(); current = captured
            selected = try FreeExploreBundleReadApproval(context: captured, expiresAt: Date().addingTimeInterval(60))
        }
        static func context(account: Int = 7, epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
            .init(market: .china, baseURL: URL(string: "https://example.test")!, role: "player",
                  session: try PlayExperienceSession(accountID: account, epoch: epoch, namespace: "test-realm",
                                                     token: "synthetic-token-\(epoch)", role: "player"))
        }
        func host(accountID: Int64 = 7) -> FreeExploreBundleReadHost? {
            FreeExploreBundleReadHost(registrationID: 41, accountID: accountID, context: captured, approval: selected,
                currentContext: { [weak self] in self?.current }, currentApproval: { [weak self] in self?.selected },
                originCurrent: { true }, storage: store, transport: wire,
                unauthorized: { [weak self] in self?.unauthorizedCount += 1 })
        }
    }
    private final class Store: TemplateAuthoringStorage {
        var failRead = false, writes = 0, removes = 0
        func read(_ key: String) throws -> Data? { if failRead { throw FreeExploreLaunchFailure.storageUnavailable }; return nil }
        func write(_ data: Data, key: String) throws { writes += 1 }
        func remove(_ key: String) throws { removes += 1 }
    }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var onSend: (() throws -> Void)?
        var memberID = 7, status = 200
        var legacy = false
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); try onSend?()
            let value: [String: Any]
            if request.url?.path.hasSuffix("catalog") == true {
                value = ["topicId": 901, "productType": 2, "saleEnabled": false, "reservationEnabled": true, "items": []]
            } else if legacy { value = ["registrationId": 41] }
            else {
                value = ["registrationId": 41, "bundle": ["order": ["registrationId": 41,
                    "holderMemberId": memberID, "topicId": 901], "units": [], "reservations": []]]
            }
            return (try JSONSerialization.data(withJSONObject: ["code": status, "data": value]), status)
        }
    }
}

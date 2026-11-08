import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class OwnedCorrelationWire: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: (URLRequest) async throws -> (Data, Int)
    init(_ handler: @escaping (URLRequest) async throws -> (Data, Int)) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try await handler(request) }
}
@MainActor final class OwnedOrderSignedInCorrelationTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func session(account: Int = 7, epoch: UInt64 = 1, viewer: UInt64 = 3, approval: UUID = UUID()) throws -> OwnedOrderReadSession {
        .init(context: .init(market: .china, baseURL: base, role: "player",
              session: try .init(accountID: account, epoch: epoch, namespace: "synthetic", token: "synthetic-\(account)")),
              viewerRevision: viewer, approvalRevision: approval)
    }
    private func signed(_ session: OwnedOrderReadSession) -> ProfileReadIdentity {
        .init(accountID: session.context.session.accountID, epoch: session.context.session.epoch, viewerRevision: session.viewerRevision)
    }
    private func payload(_ request: URLRequest, account: Int = 7) -> (Data, Int) {
        let row = "{\"id\":41,\"memberId\":\(account),\"payableAmount\":12.3456,\"registrationStatus\":2,\"paymentStatus\":0,\"refundApplication\":{\"status\":1,\"payoutStatus\":0,\"refundAmount\":3.21}}"
        let data = request.url!.path.hasSuffix("/list") ? "{\"rows\":[\(row)],\"total\":1}" : row
        return (Data("{\"code\":200,\"data\":\(data)}".utf8), 200)
    }
    private func reader(_ wire: OwnedCorrelationWire, current: @escaping () -> OwnedOrderReadSession?, signed: @escaping () -> ProfileReadIdentity?, unauthorized: @escaping (OwnedOrderReadSession) -> Void = { _ in }) throws -> OwnedOrderSessionReader {
        .init(service: .init(configuration: try .init(baseURL: base), transport: wire), current: current, signedInIdentity: signed, onUnauthorized: unauthorized)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 { if condition() { return }; await Task.yield() }; throw APIError.invalidRequest
    }
    func testMatchingCanonicalSignInAndSelectedGrantReadOriginalListAndDetail() async throws {
        let selected = try session(), wire = OwnedCorrelationWire { self.payload($0) }
        let reader = try reader(wire, current: { selected }, signed: { self.signed(selected) })
        XCTAssertTrue(reader.isConfigured); XCTAssertEqual(reader.identity, selected.identity)
        let rows = try await reader.profileOrders(), detail = try await reader.profileOrder(id: 41)
        XCTAssertEqual(rows.map(\.id), [41]); XCTAssertEqual(detail.memberID, 7)
        XCTAssertEqual(detail.payableAmount, Decimal(string: "12.3456")); XCTAssertEqual(detail.paymentStatus, 0)
        XCTAssertEqual(detail.refundPayoutStatus, 0); XCTAssertEqual(detail.refundAmount, Decimal(string: "3.21"))
        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/native/api/registration/list", "/native/api/registration/info"])
        XCTAssertTrue(String(data: wire.requests[0].httpBody!, encoding: .utf8)!.contains("name=\"owner_type\"\r\n\r\n3"))
        XCTAssertTrue(String(data: wire.requests[1].httpBody!, encoding: .utf8)!.contains("name=\"id\"\r\n\r\n41"))
    }
    func testMismatchedAccountEpochOrViewerDoesNotExposeOldGrantOrDispatch() async throws {
        let selected = try session(), wire = OwnedCorrelationWire { self.payload($0) }
        let others = [ProfileReadIdentity(accountID: 8, epoch: 1, viewerRevision: 3),
                      .init(accountID: 7, epoch: 2, viewerRevision: 3), .init(accountID: 7, epoch: 1, viewerRevision: 4)]
        for current in others {
            let reader = try reader(wire, current: { selected }, signed: { current })
            XCTAssertFalse(reader.isConfigured); XCTAssertEqual(reader.identity, current)
            do { _ = try await reader.profileOrders(); XCTFail("old selected grant dispatched") }
            catch { XCTAssertEqual(error as? APIError, .notConfigured) }
            do { _ = try await reader.profileOrder(id: 41); XCTFail("old selected detail grant dispatched") }
            catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testGuestAndInvalidSignedIdentityCannotExposeSelectedOwner() async throws {
        let selected = try session(), wire = OwnedCorrelationWire { self.payload($0) }
        for current in [nil, ProfileReadIdentity(accountID: 0, epoch: 1, viewerRevision: 3)] {
            let reader = try reader(wire, current: { selected }, signed: { current })
            XCTAssertNil(reader.identity); XCTAssertFalse(reader.isConfigured)
            do { _ = try await reader.profileOrder(id: 41); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testSignedIdentityAloneNeverGrantsReadAndNilServiceStaysUnavailable() async throws {
        let selected = try session(), signIn = signed(selected), wire = OwnedCorrelationWire { self.payload($0) }
        let noGrant = try reader(wire, current: { nil }, signed: { signIn })
        XCTAssertEqual(noGrant.identity, signIn); XCTAssertFalse(noGrant.isConfigured)
        do { _ = try await noGrant.profileOrders(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let noService = OwnedOrderSessionReader(service: nil, current: { selected }, signedInIdentity: { signIn })
        XCTAssertFalse(noService.isConfigured)
        do { _ = try await noService.profileOrder(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testSignOutOrIdentityChangeDuringSuccessRejectsLateListAndDetail() async throws {
        for detail in [false, true] {
            for transition in ["guest", "account", "epoch", "viewer"] {
                let selected = try session(); var signIn: ProfileReadIdentity? = signed(selected)
                let wire = OwnedCorrelationWire { request in
                    switch transition {
                    case "guest": signIn = nil
                    case "account": signIn = .init(accountID: 8, epoch: 1, viewerRevision: 3)
                    case "epoch": signIn = .init(accountID: 7, epoch: 2, viewerRevision: 3)
                    default: signIn = .init(accountID: 7, epoch: 1, viewerRevision: 4)
                    }
                    return self.payload(request)
                }
                let reader = try reader(wire, current: { selected }, signed: { signIn })
                do { if detail { _ = try await reader.profileOrder(id: 41) } else { _ = try await reader.profileOrders() }; XCTFail(transition) }
                catch { XCTAssertTrue(error is CancellationError, "\(error)") }
                XCTAssertFalse(reader.isConfigured)
            }
        }
    }
    func testLateUnauthorizedAfterSignedOwnerChangeCannotExpireNewOwner() async throws {
        for http in [false, true] {
            let selected = try session(); var signIn: ProfileReadIdentity? = signed(selected); var expired: [OwnedOrderReadSession] = []
            let wire = OwnedCorrelationWire { _ in
                signIn = .init(accountID: 8, epoch: 2, viewerRevision: 4)
                return (Data("{\"code\":401}".utf8), http ? 401 : 200)
            }
            let reader = try reader(wire, current: { selected }, signed: { signIn }, unauthorized: { expired.append($0) })
            do { _ = try await reader.profileOrder(id: 41); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertTrue(expired.isEmpty)
        }
    }
    func testCurrentUnauthorizedStillExpiresExactlyTheMatchingOwner() async throws {
        let selected = try session(); var expired: [OwnedOrderReadSession] = []
        let wire = OwnedCorrelationWire { _ in (Data("{\"code\":401}".utf8), 200) }
        let reader = try reader(wire, current: { selected }, signed: { self.signed(selected) }, unauthorized: { expired.append($0) })
        do { _ = try await reader.profileOrders(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, [selected])
    }
    func testCurrentBusinessFailureRemainsRetryableWithoutExpiringOwner() async throws {
        let selected = try session(); var expired = false
        let wire = OwnedCorrelationWire { _ in (Data("{\"code\":503,\"msg\":\"synthetic retry\"}".utf8), 200) }
        let reader = try reader(wire, current: { selected }, signed: { self.signed(selected) }, unauthorized: { _ in expired = true })
        do { _ = try await reader.profileOrders(); XCTFail() }
        catch { XCTAssertEqual(error as? ProfileReadFailure, .init(code: 503, message: "synthetic retry")) }
        XCTAssertFalse(expired); XCTAssertTrue(reader.isConfigured)
    }
    func testFreshMatchingGrantRestoresReadWithoutRebindingOldBuyer() async throws {
        let old = try session(); var selected: OwnedOrderReadSession? = old
        var signIn: ProfileReadIdentity? = .init(accountID: 8, epoch: 2, viewerRevision: 4)
        let wire = OwnedCorrelationWire { self.payload($0, account: 8) }
        let reader = try reader(wire, current: { selected }, signed: { signIn })
        do { _ = try await reader.profileOrder(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        selected = try session(account: 8, epoch: 2, viewer: 4); signIn = signed(selected!)
        let fresh = try await reader.profileOrder(id: 41)
        XCTAssertEqual(fresh.memberID, 8); XCTAssertEqual(wire.requests.count, 1)
    }
    func testSelectedGrantReplacementStillRejectsOldInFlightReceipt() async throws {
        var selected: OwnedOrderReadSession? = try session(); let signIn = signed(selected!)
        var pending: CheckedContinuation<(Data, Int), Error>?
        let wire = OwnedCorrelationWire { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        let reader = try reader(wire, current: { selected }, signed: { signIn })
        let task = Task { try await reader.profileOrder(id: 41) }; try await waitUntil { pending != nil }
        selected = try session() // New independent approval revision, same account facts.
        let request = try XCTUnwrap(wire.requests.first); pending!.resume(returning: payload(request))
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
}

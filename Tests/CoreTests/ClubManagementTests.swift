import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

private func managementSnapshot(owner: Bool = true, admin: Bool = false, requests: Bool = true) throws -> ClubManagementSnapshot {
    let club = try JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":81,\"name\":\"Fixture club\",\"isOwner\":\(owner),\"viewerIsAdmin\":\(admin),\"isJoined\":true}".utf8))
    let rows = try JSONDecoder().decode([ClubManagementRequest].self, from: Data((requests ? #"[{"memberId":3,"nickname":"Applicant"}]"# : "[]").utf8))
    let members = try JSONDecoder().decode([ClubMember].self, from: Data(#"[{"memberId":1,"isOwner":true},{"memberId":2,"role":1,"nickname":"Member"}]"#.utf8))
    return .init(club: club, requests: rows, members: members)
}

final class ClubManagementContractTests: XCTestCase {
    func testOwnerAdminAndOrdinaryPermissions() throws {
        let owner = try managementSnapshot(), admin = try managementSnapshot(owner: false, admin: true), ordinary = try managementSnapshot(owner: false)
        for action in [ClubManagementAction.approve, .reject] {
            XCTAssertTrue(owner.allows(action, memberID: 3)); XCTAssertTrue(admin.allows(action, memberID: 3))
            XCTAssertFalse(ordinary.allows(action, memberID: 3)); XCTAssertFalse(owner.allows(action, memberID: 99))
        }
        XCTAssertTrue(owner.allows(.remove, memberID: 2))
        XCTAssertFalse(owner.allows(.remove, memberID: 1)); XCTAssertFalse(admin.allows(.remove, memberID: 2))
        XCTAssertFalse(owner.allows(.remove, memberID: 99))
    }
    func testUnknownAndDuplicateTargetsFailClosed() throws {
        for value in [0, -1] {
            XCTAssertThrowsError(try JSONDecoder().decode(ClubManagementRequest.self, from: Data("{\"memberId\":\(value)}".utf8)))
        }
        let s = try managementSnapshot()
        let duplicate = ClubManagementSnapshot(club: s.club, requests: s.requests + s.requests, members: s.members + s.members)
        XCTAssertFalse(duplicate.allows(.approve, memberID: 3)); XCTAssertFalse(duplicate.allows(.remove, memberID: 2))
    }
}

private final class ManagementTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var reply = #"{"code":200,"msg":"  Server receipt  "}"#
    var status = 200
    var handler: ((URLRequest) async throws -> (Data, Int))?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if let handler { return try await handler(request) }
        return (Data(reply.utf8), status)
    }
}
final class ClubManagementServiceTests: XCTestCase {
    private func service(_ t: ManagementTransport) throws -> ClubManagementService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/")!), transport: t)
    }
    func testAllThreeExactJSONRoutesAndNoRetries() async throws {
        for action in ClubManagementAction.allCases {
            let t = ManagementTransport()
            let receipt = try await service(t).perform(action, clubID: 81, memberID: 3, token: "fixture-token")
            XCTAssertEqual(receipt.message, "  Server receipt  ")
            let request = try XCTUnwrap(t.requests.first)
            XCTAssertEqual(request.url?.path, "/" + action.path)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
            XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Int], ["clubId":81,"memberId":3])
            XCTAssertEqual(t.requests.count, 1)
        }
    }
    func testRejectionsUnknownAndMalformedAreDistinct() async throws {
        for (status, reply, unknown) in [(200, #"{"code":403,"msg":"Denied"}"#, false), (403, "invalid", false), (500, #"{"code":200}"#, true), (200, "{}", true)] {
            let t = ManagementTransport(); t.status = status; t.reply = reply
            do { _ = try await service(t).perform(.remove, clubID: 81, memberID: 2, token: "fixture-token"); XCTFail() }
            catch let error as ClubActionWriteError {
                switch error {
                case .rejected: XCTAssertFalse(unknown)
                case .outcomeUnknown: XCTAssertTrue(unknown)
                default: XCTFail("Unexpected \(error)")
                }
            }
            XCTAssertEqual(t.requests.count, 1)
        }
    }
    func testInvalidInputsNeverDispatch() async throws {
        let t = ManagementTransport()
        for (club, member, token) in [(0,3,"token"), (81,0,"token"), (81,3,"bad\nheader")] {
            do { _ = try await service(t).perform(.approve, clubID: club, memberID: member, token: token); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .notSent(.invalidRequest)) }
        }
        XCTAssertTrue(t.requests.isEmpty)
    }
    @MainActor func testTokenReplacementDuringPreflightNeverWrites() async throws {
        let t = ManagementTransport()
        var session: ClubManagementSession? = try .init(accountID: 1, epoch: 1, token: "first")
        t.handler = { _ in
            session = try .init(accountID: 1, epoch: 1, token: "replacement")
            return (Data(#"{"code":200,"data":{"id":81,"isOwner":true}}"#.utf8), 200)
        }
        let access = ClubManagementSessionAccess(service: try service(t), currentSession: { session })
        do { _ = try await access.perform(.approve, clubID: 81, memberID: 3, expectedIdentity: .init(accountID: 1, epoch: 1)); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .preflightFailed) }
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/club/detail"])
    }
    @MainActor func testPermissionLossDuringPreflightNeverWrites() async throws {
        let t = ManagementTransport(); t.reply = #"{"code":200,"data":{"id":81,"isOwner":false,"viewerIsAdmin":false}}"#
        let session = try ClubManagementSession(accountID: 1, epoch: 1, token: "fixture-token")
        let access = ClubManagementSessionAccess(service: try service(t), currentSession: { session })
        do { _ = try await access.perform(.remove, clubID: 81, memberID: 2, expectedIdentity: session.identity); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .preflightFailed) }
        XCTAssertEqual(t.requests.count, 1)
    }
}

@MainActor private final class ManagementAccess: ClubManagementAccess {
    var identity: ClubReadIdentity? = .init(accountID: 1, epoch: 1)
    let isConfigured = true
    var value = try! managementSnapshot()
    var writes = 0
    var readFails = false
    var failure: ClubActionWriteError?
    var onWrite: (() -> Void)?
    var readHook: (() async -> Void)?
    func snapshot(clubID: Int) async throws -> ClubManagementSnapshot {
        if let readHook { await readHook() }
        if readFails { throw APIError.malformedResponse }
        return value
    }
    func perform(_ action: ClubManagementAction, clubID: Int, memberID: Int, expectedIdentity: ClubReadIdentity) async throws -> ClubActionReceipt {
        writes += 1; onWrite?()
        if let failure { throw failure }
        return .init(state: nil, message: nil)
    }
}
final class ClubManagementCoordinatorTests: XCTestCase {
    @MainActor func testCancelAndStaleConfirmationNeverWrite() async throws {
        let a = ManagementAccess(), owner = UUID()
        let c = ClubManagementCoordinator(access: a)
        let p = try await c.prepare(clubID: 81, action: .approve, memberID: 3, expectedIdentity: a.identity!, ownerID: owner)
        XCTAssertEqual(a.writes, 0); XCTAssertEqual(p.memberName, "Applicant")
        c.cancel(p)
        let result = await c.confirm(p)
        XCTAssertEqual(result, .blocked(.staleConfirmation)); XCTAssertEqual(a.writes, 0)
    }
    @MainActor func testAcknowledgementUsesReadbackNeverOptimisticRemoval() async throws {
        let a = ManagementAccess()
        let coordinator = ClubManagementCoordinator(access: a)
        let p = try await coordinator.prepare(clubID: 81, action: .remove, memberID: 2, expectedIdentity: a.identity!)
        _ = await coordinator.confirm(p)
        XCTAssertEqual(a.writes, 1)
        XCTAssertEqual(coordinator.readback(clubID: 81), .received(a.value))
        XCTAssertEqual(a.value.members.count, 2)
        _ = await coordinator.confirm(p); XCTAssertEqual(a.writes, 1)
    }
    @MainActor func testUnknownLocksAcrossNavigationAndSameAccountRelogin() async throws {
        let a = ManagementAccess(); a.failure = .outcomeUnknown(.transport)
        let c = ClubManagementCoordinator(access: a), owner = UUID()
        let p = try await c.prepare(clubID: 81, action: .reject, memberID: 3, expectedIdentity: a.identity!, ownerID: owner)
        _ = await c.confirm(p)
        c.leaveScreen(clubID: 81, expectedIdentity: a.identity!, ownerID: owner)
        a.identity = .init(accountID: 1, epoch: 2); c.synchronizeSession()
        _ = await c.readBack(clubID: 81)
        XCTAssertTrue(c.state(clubID: 81).preventsNewAction)
        do { _ = try await c.prepare(clubID: 81, action: .approve, memberID: 3, expectedIdentity: a.identity!); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionBlock, .pendingOperation) }
        XCTAssertEqual(a.writes, 1)
    }
    @MainActor func testSwitchAccountDuringWriteDoesNotExposeReceipt() async throws {
        let a = ManagementAccess()
        let coordinator = ClubManagementCoordinator(access: a)
        let p = try await coordinator.prepare(clubID: 81, action: .approve, memberID: 3, expectedIdentity: a.identity!)
        a.onWrite = { a.identity = .init(accountID: 2, epoch: 2) }
        let result = await coordinator.confirm(p)
        XCTAssertEqual(result, .ignoredStale); XCTAssertEqual(coordinator.state(clubID: 81), .idle)
        a.identity = .init(accountID: 1, epoch: 3)
        XCTAssertTrue(coordinator.state(clubID: 81).preventsNewAction)
    }
    @MainActor func testReadbackFailurePreservesAcknowledgement() async throws {
        let a = ManagementAccess()
        let coordinator = ClubManagementCoordinator(access: a)
        let p = try await coordinator.prepare(clubID: 81, action: .approve, memberID: 3, expectedIdentity: a.identity!)
        a.onWrite = { a.readFails = true }
        _ = await coordinator.confirm(p)
        XCTAssertEqual(coordinator.state(clubID: 81), .acknowledged(.init(state: nil, message: nil)))
        XCTAssertEqual(coordinator.readback(clubID: 81), .unavailable)
    }
}

@MainActor private final class ManagementGate {
    var continuation: CheckedContinuation<Void, Never>?
    func pause() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
extension ClubManagementCoordinatorTests {
    @MainActor func testLeavingDuringPrepareInvalidatesLateConfirmation() async throws {
        let a = ManagementAccess(), gate = ManagementGate(), owner = UUID()
        let c = ClubManagementCoordinator(access: a)
        a.readHook = { await gate.pause() }
        let task = Task { try await c.prepare(clubID: 81, action: .approve, memberID: 3, expectedIdentity: a.identity!, ownerID: owner) }
        while gate.continuation == nil { await Task.yield() }
        c.leaveScreen(clubID: 81, expectedIdentity: a.identity!, ownerID: owner)
        gate.release()
        do { _ = try await task.value; XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionBlock, .cancelledBeforeDispatch) }
        XCTAssertEqual(a.writes, 0); XCTAssertEqual(c.state(clubID: 81), .idle)
    }
    @MainActor func testSecondPrepareAndOldScreenCannotCancelCurrentConfirmation() async throws {
        let a = ManagementAccess()
        let coordinator = ClubManagementCoordinator(access: a), current = UUID()
        let p = try await coordinator.prepare(clubID: 81, action: .approve, memberID: 3, expectedIdentity: a.identity!, ownerID: current)
        do { _ = try await coordinator.prepare(clubID: 81, action: .reject, memberID: 3, expectedIdentity: a.identity!); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionBlock, .pendingOperation) }
        coordinator.leaveScreen(clubID: 81, expectedIdentity: a.identity!, ownerID: UUID())
        XCTAssertEqual(coordinator.state(clubID: 81), .awaitingConfirmation)
        _ = await coordinator.confirm(p); XCTAssertEqual(a.writes, 1)
    }
    @MainActor func testSameAccountNewEpochInvalidatesOldConfirmation() async throws {
        let a = ManagementAccess()
        let c = ClubManagementCoordinator(access: a)
        let p = try await c.prepare(clubID: 81, action: .approve, memberID: 3, expectedIdentity: a.identity!)
        a.identity = .init(accountID: 1, epoch: 2)
        let result = await c.confirm(p)
        XCTAssertEqual(result, .blocked(.accountChanged)); XCTAssertEqual(a.writes, 0)
    }
}

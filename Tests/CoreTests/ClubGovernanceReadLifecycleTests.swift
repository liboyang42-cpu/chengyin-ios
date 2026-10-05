import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Deliberately ignores cancellation: the reader must fence the returned bytes itself.
private actor SuspendedClubHistoryTransport: HTTPTransport {
    private var pending: CheckedContinuation<(Data, Int), Error>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var paths: [String] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        paths.append(request.url!.path)
        return try await withCheckedThrowingContinuation {
            pending = $0; started?.resume(); started = nil
        }
    }
    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func reply(_ value: ClubGovernanceValue = .null, code: Int = 200, status: Int = 200) throws {
        let data = try JSONEncoder().encode(ClubGovernanceValue.object(["code": .integer(code), "data": value]))
        let completion = pending; pending = nil
        completion?.resume(returning: (data, status))
    }
}

@MainActor private final class ClubHistoryReadFixture {
    let wire = SuspendedClubHistoryTransport()
    let service: ClubGovernanceService
    var session: ClubGovernanceSession?
    var runtime: RuntimeDependencyContext?
    var viewerRevision: UInt64 = 1
    var expired: [ClubReadIdentity] = []
    lazy var access = ClubGovernanceSessionAccess(service: service, currentSession: { [unowned self] in session },
        runtimeContext: { [unowned self] in runtime }, viewerRevision: { [unowned self] in viewerRevision },
        onUnauthorized: { [unowned self] in expired.append($0) })
    init() throws {
        let url = URL(string: "https://example.test")!
        service = ClubGovernanceService(configuration: try .init(baseURL: url), transport: wire)
        session = try .init(accountID: 701, epoch: 1, token: "synthetic", storageNamespace: "fixture")
        runtime = try .init(market: .china, baseURL: url, role: "club",
            session: .init(accountID: 701, epoch: 1, namespace: "fixture", token: "synthetic"))
    }
    func read(check: @escaping () throws -> Void = {}) -> Task<ClubGovernanceSnapshot, Error> {
        let reader: any ClubGovernanceAccess = access
        return Task { try await reader.read(.customer, scope: .init(clubID: 81, memberID: 704), options: [:], check: check) }
    }
    func waitForDetail() async throws {
        await wire.waitForRequest()
        try await wire.reply(ClubGovernanceFixtures.value(.access))
        await wire.waitForRequest()
    }
}

@MainActor final class ClubGovernanceReadLifecycleTests: XCTestCase {
    private func expectStale(_ task: Task<ClubGovernanceSnapshot, Error>, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await task.value; XCTFail("Obsolete read was accepted", file: file, line: line) }
        catch { XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)", file: file, line: line) }
    }
    func testDelayed401AfterSameSessionRoleChangeDoesNotExpireCurrentViewer() async throws {
        let fixture = try ClubHistoryReadFixture(), task = fixture.read()
        try await fixture.waitForDetail()
        let original = try XCTUnwrap(fixture.runtime)
        fixture.runtime = .init(market: original.market, baseURL: original.baseURL, role: "player", session: original.session)
        fixture.viewerRevision &+= 1
        try await fixture.wire.reply(code: 401)
        await expectStale(task)
        XCTAssertTrue(fixture.expired.isEmpty)
    }
    func testDelayed401AfterUnobservedRoleABAUsesMonotonicViewerFence() async throws {
        let fixture = try ClubHistoryReadFixture()
        let original = try XCTUnwrap(fixture.runtime), authority = fixture.access.authorizationGeneration
        let task = fixture.read()
        try await fixture.waitForDetail()
        fixture.runtime = .init(market: original.market, baseURL: original.baseURL, role: "player", session: original.session)
        fixture.viewerRevision &+= 1
        fixture.runtime = original; fixture.viewerRevision &+= 1
        XCTAssertEqual(fixture.access.authorizationGeneration, authority, "The lazy authority getter never observed the intermediate role")
        try await fixture.wire.reply(code: 401)
        await expectStale(task)
        XCTAssertTrue(fixture.expired.isEmpty)
    }
    func testDelayed401AfterAuthorityChangeWithSameViewerRevisionIsDiscarded() async throws {
        let fixture = try ClubHistoryReadFixture(), task = fixture.read()
        try await fixture.waitForDetail()
        fixture.runtime = nil
        try await fixture.wire.reply(status: 401)
        await expectStale(task)
        XCTAssertTrue(fixture.expired.isEmpty)
    }
    func testDelayed401AfterNewerReadOrBackUsesCallerGenerationFence() async throws {
        for replacement in [1, 2] {
            let fixture = try ClubHistoryReadFixture()
            var generation = 0
            let task = fixture.read { guard generation == 0 else { throw CancellationError() } }
            try await fixture.waitForDetail()
            generation = replacement // Reload and Back both invalidate the captured generation.
            try await fixture.wire.reply(code: 401)
            await expectStale(task)
            XCTAssertTrue(fixture.expired.isEmpty)
        }
    }
    func testStaleCallerFailsBeforeAnyRequest() async throws {
        let fixture = try ClubHistoryReadFixture()
        await expectStale(fixture.read { throw CancellationError() })
        let paths = await fixture.wire.paths
        XCTAssertTrue(paths.isEmpty); XCTAssertTrue(fixture.expired.isEmpty)
    }
    func testDelayed401AfterSessionReplacementCannotExpireNewSession() async throws {
        let replacements: [ClubGovernanceSession?] = [nil,
            try .init(accountID: 702, epoch: 1, token: "synthetic", storageNamespace: "fixture"),
            try .init(accountID: 701, epoch: 2, token: "synthetic", storageNamespace: "fixture"),
            try .init(accountID: 701, epoch: 1, token: "replacement", storageNamespace: "fixture")]
        for replacement in replacements {
            let fixture = try ClubHistoryReadFixture(), task = fixture.read()
            try await fixture.waitForDetail()
            fixture.session = replacement
            try await fixture.wire.reply(code: 401)
            await expectStale(task)
            XCTAssertTrue(fixture.expired.isEmpty)
        }
    }
    func testCancelledReadCannotExpireSessionEvenIfTransportReturns401() async throws {
        let fixture = try ClubHistoryReadFixture(), task = fixture.read()
        try await fixture.waitForDetail()
        task.cancel()
        try await fixture.wire.reply(code: 401)
        await expectStale(task)
        XCTAssertTrue(fixture.expired.isEmpty)
    }
    func testCurrent401StillExpiresExactlyOnceAtAccessAndDetailBoundaries() async throws {
        for detail in [false, true] {
            for status in [200, 401] {
                let fixture = try ClubHistoryReadFixture(), task = fixture.read()
                if detail { try await fixture.waitForDetail() } else { await fixture.wire.waitForRequest() }
                try await fixture.wire.reply(code: status == 200 ? 401 : 200, status: status)
                do { _ = try await task.value; XCTFail("Current 401 was accepted") }
                catch { XCTAssertEqual(error as? ClubGovernanceFailure, .signedOut) }
                XCTAssertEqual(fixture.expired, [try XCTUnwrap(fixture.session).identity])
            }
        }
    }
    func testCurrentCustomerReadStillReturnsPermissionCheckedSnapshot() async throws {
        let fixture = try ClubHistoryReadFixture(), task = fixture.read()
        try await fixture.waitForDetail()
        try await fixture.wire.reply(ClubGovernanceFixtures.value(.customer))
        let snapshot = try await task.value
        XCTAssertEqual(snapshot.scope, .init(clubID: 81, memberID: 704))
        XCTAssertEqual(snapshot.value["summary"]["memberId"].int, 704)
        XCTAssertTrue(snapshot.permissions?.allows(ClubGovernanceRead.customer.permission, scope: snapshot.scope) == true)
        XCTAssertTrue(fixture.expired.isEmpty)
        let paths = await fixture.wire.paths
        XCTAssertEqual(paths, ["/api/club/access/me", "/api/club/crm/customers/detail"])
    }
    func testDelayedSuccessfulCustomerSnapshotAfterRoleABAIsDiscarded() async throws {
        let fixture = try ClubHistoryReadFixture(), task = fixture.read()
        try await fixture.waitForDetail()
        fixture.viewerRevision &+= 2
        try await fixture.wire.reply(ClubGovernanceFixtures.value(.customer))
        await expectStale(task)
        XCTAssertTrue(fixture.expired.isEmpty)
    }
}

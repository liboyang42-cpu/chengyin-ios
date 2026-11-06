import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Synthetic responses only. A rejected session cannot unlock a dispatched original request.
@MainActor final class ClubBadgeSessionRetirementTests: XCTestCase {
    typealias Fixture = ClubBadgeOriginalConsumerRecoveryTests.Fixture

    func testCurrentRead401RetiresEvenWhenHostCallbackDoesNotChangeContext() async throws {
        for application401 in [false, true] {
            let f = try Fixture()
            f.wire.response = (try f.envelope(code: application401 ? 401 : 200), application401 ? 200 : 401)
            do { _ = try await f.service.detail(); XCTFail("401 must fail") } catch {}
            XCTAssertFalse(f.service.isCurrent)
            XCTAssertFalse(f.service.canRead)
            XCTAssertFalse(f.service.canWrite)
            do { _ = try await f.service.detail(); XCTFail("Retired instance must not read") } catch {}
            let entry = try f.entry()
            guard case .notSent = try await f.send(entry) else { return XCTFail("Retired instance must not write") }
            XCTAssertEqual(f.wire.requests.count, 1)
            XCTAssertTrue(try f.journal.read(f.context, clubID: 7).isEmpty)
        }
    }

    func testDispatched401RetiresWithoutSettlingOrErasingOriginalRequest() async throws {
        for application401 in [false, true] {
            let f = try Fixture(), entry = try f.entry()
            f.wire.response = (try f.envelope(code: application401 ? 401 : 200), application401 ? 200 : 401)
            guard case .unknown = try await f.send(entry) else { return XCTFail("401 does not prove non-execution") }
            XCTAssertFalse(f.service.isCurrent)
            let rows = try f.journal.read(f.context, clubID: 7)
            XCTAssertEqual(rows.first?.requestID, entry.requestID)
            XCTAssertEqual(rows.first?.outcome, "UNKNOWN")
            XCTAssertThrowsError(try f.journal.reserve(f.entry(), context: f.context))
            do { _ = try await f.service.receipt(entry); XCTFail("Retired service cannot recover") } catch {}
            XCTAssertEqual(f.wire.requests.count, 1)
            // A genuinely recreated, approved service may read the same original identity.
            let restored = ClubBadgeManagementService(context: f.context, clubID: 7, transport: f.wire,
                current: { f.current }, approval: { _ in f.approval })
            f.wire.response = (try f.envelope(data: f.receipt(entry, terminal: false)), 200)
            let outcome = try await restored.receipt(entry)
            XCTAssertFalse(outcome.isTerminal)
            XCTAssertEqual(try f.journal.read(f.context, clubID: 7).first?.outcome, "UNKNOWN")
            XCTAssertEqual(f.wire.requests.count, 2)
        }
    }

    func testOtherReadErrorsDoNotRetireSession() async throws {
        for (http, application) in [(403, 200), (503, 200), (200, 403), (200, 503)] {
            let f = try Fixture()
            f.wire.response = (try f.envelope(code: application), http)
            do { _ = try await f.service.detail(); XCTFail("Error response must fail") } catch {}
            XCTAssertTrue(f.service.isCurrent)
            XCTAssertTrue(f.service.canRead)
        }
    }

    private final class OfflineWire: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, Int) { throw URLError(.timedOut) }
    }
    func testNetworkTimeoutDoesNotRetireSession() async throws {
        let f = try Fixture()
        var notifications = 0
        let service = ClubBadgeManagementService(context: f.context, clubID: 7, transport: OfflineWire(),
            current: { f.current }, approval: { _ in f.approval }, unauthorized: { notifications += 1 })
        do { _ = try await service.detail(); XCTFail("Timeout must fail") } catch {}
        XCTAssertTrue(service.isCurrent)
        XCTAssertEqual(notifications, 0)
    }

    func testLateOldContext401DoesNotNotifyOrRetireCurrentContext() async throws {
        let f = try Fixture()
        var notifications = 0
        let service = ClubBadgeManagementService(context: f.context, clubID: 7, transport: f.wire,
            current: { f.current }, approval: { _ in f.approval }, unauthorized: { notifications += 1 })
        f.wire.response = (try f.envelope(code: 401), 200)
        f.wire.afterDispatch = { f.current = nil }
        do { _ = try await service.detail(); XCTFail("Old response must fail") } catch {}
        XCTAssertEqual(notifications, 0)
        f.current = f.context
        XCTAssertTrue(service.isCurrent, "Old response cannot permanently retire an unrelated lifetime")
    }
}

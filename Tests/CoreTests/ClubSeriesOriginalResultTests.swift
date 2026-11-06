import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ClubSeriesOriginalResultTests: XCTestCase {
    final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var response: (Data, Int) = (Data(), 500)
        var onSend: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); onSend?(); return response
        }
    }
    final class Fixture {
        let wire = Wire(), access = ClubGovernanceFixtureAccess()
        let scope = ClubGovernanceScope(clubID: 81, topicID: 91)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context: RuntimeDependencyContext
        var current: RuntimeDependencyContext?
        var approval: ClubSeriesOriginalResultApproval?
        lazy var store = ClubSeriesOriginalRequestFileStore(directory: directory)
        lazy var reader = ClubSeriesOriginalResultReader(transport: wire, current: { self.current }, approval: { _ in self.approval })
        lazy var coordinator = ClubGovernanceCoordinator(access: access, seriesRequests: store, seriesResults: reader)
        init(enabled: Bool = true) throws {
            let session = try PlayExperienceSession(accountID: 701, epoch: 1, namespace: "series-fixture", token: "synthetic-token")
            context = .init(market: .china, baseURL: URL(string: "https://example.test/")!, role: "player", session: session)
            current = context
            access.identity = .init(accountID: 701, epoch: 1)
            access.storageNamespace = "\(context.market)|\(context.baseURL.absoluteString)|\(session.namespace)"
            let endpoints = try OperationEndpointApproval(baseURL: context.baseURL, namespace: session.namespace, accountID: 701,
                paths: [ClubSeriesOriginalResultApproval.path])
            approval = try .init(endpoints: endpoints, scopes: [scope], reads: enabled)
        }
        func original(id: String = " original ") throws -> ClubSeriesOriginalRequest {
            let command = try ClubGovernanceCommand(operation: .createSeries, scope: scope, values: [
                "requestId": .string(id), "recurrenceType": .string("ONCE"), "startDate": .string("2020-01-02"),
                "startTime": .string("09:00"), "occurrenceCount": .integer(1), "customDates": .null,
                "defaultLeadMemberId": .null, "capacity": .null, "waitlistEnabled": .bool(true), "offerMinutes": .integer(1440)])
            return try .init(realm: access.journalRealm, accountID: 701,
                lockKey: "\(access.journalRealm)|701|createSeries|clubId=81&topicId=91", command: command)
        }
        func unknown() -> [String: ClubGovernanceValue] {
            ["version": .integer(1), "actorMemberId": .integer(701), "clubId": .integer(81), "topicId": .integer(91),
             "requestId": .string("original"), "state": .string("UNKNOWN")]
        }
        func applied() throws -> [String: ClubGovernanceValue] {
            var value = unknown(), fields = try original().fields
            fields["rrule"] = .null; fields["seriesId"] = .null; fields["expectedVersion"] = .null
            value["state"] = .string("APPLIED"); value["wire"] = .object(fields)
            value["effectiveDates"] = .array([.string("2020-01-02")]); value["startTime"] = .string("09:00")
            value["receiptHash"] = .string(String(repeating: "a", count: 64))
            value["series"] = .object(["id": .integer(100), "clubId": .integer(81), "topicId": .integer(91),
                "createdByMemberId": .integer(701), "requestId": .string("original"), "status": .string("ACTIVE"),
                "version": .integer(0), "timezone": .string("Asia/Shanghai"), "defaultLeadMemberId": .integer(999),
                "defaultCapacity": .null, "waitlistEnabled": .bool(true), "offerMinutes": .integer(1440),
                "createdAtEpochMs": .integer(1000), "updatedAtEpochMs": .integer(1000), "recurrenceType": .string("ONCE"),
                "requestFingerprint": .string(String(repeating: "b", count: 64))])
            value["occurrences"] = .array([.object(["id": .integer(101), "seriesId": .integer(100), "activityId": .integer(102),
                "defaultLeadMemberId": .integer(999), "status": .string("ACTIVE"), "version": .integer(0),
                "createdAtEpochMs": .integer(1000), "occurrenceAtEpochMs": .integer(1_577_926_800_000)])])
            return value
        }
        func respond(_ value: [String: ClubGovernanceValue], code: Int = 200) throws {
            wire.response = (try JSONEncoder().encode(ClubGovernanceValue.object(["code": .integer(code), "data": .object(value)])), 200)
        }
        func read() async throws -> ClubSeriesOriginalResult {
            try await coordinator.readOriginalSeriesResult(scope: scope, identity: access.identity, check: {})
        }
    }
    func fixture(enabled: Bool = true) throws -> Fixture {
        let f = try Fixture(enabled: enabled)
        addTeardownBlock { try? FileManager.default.removeItem(at: f.directory) }; return f
    }
    func testDefaultClosedNoTransportAndNoLocalWrites() async throws {
        let f = try fixture(enabled: false)
        do { _ = try await f.read(); XCTFail() } catch {}
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: f.directory.path))
    }
    func testLegacyMissingOriginalNeverFabricatesRequestOrCallsOutcomeEndpoint() async throws {
        let f = try fixture()
        let result = try await f.read(); XCTAssertEqual(result, .legacyUnknown)
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertTrue(f.access.sent.isEmpty)
    }
    func testRelaunchUsesExactRetainedOldInputAndNeverResendsWriter() async throws {
        let f = try fixture(), original = try f.original(); try f.store.reserve(original); try f.respond(f.unknown())
        let relaunched = ClubGovernanceCoordinator(access: f.access,
            seriesRequests: ClubSeriesOriginalRequestFileStore(directory: f.directory), seriesResults: f.reader)
        let result = try await relaunched.readOriginalSeriesResult(scope: f.scope, identity: f.access.identity, check: {})
        XCTAssertEqual(result, .unknown(requestID: " original "))
        XCTAssertEqual(f.wire.requests.map { $0.url?.path }, ["/api/club/event-ops/series/original-result"])
        XCTAssertEqual(try JSONDecoder().decode([String: ClubGovernanceValue].self, from: XCTUnwrap(f.wire.requests.first?.httpBody)), original.fields)
        XCTAssertEqual(try f.store.read(lockKey: original.lockKey, realm: original.realm, accountID: 701), original)
        XCTAssertTrue(try f.store.contains(lockKey: original.lockKey)); XCTAssertTrue(f.access.sent.isEmpty)
    }
    func testCompleteOriginalReadDoesNotReleaseLockOrManufactureNavigation() async throws {
        let f = try fixture(), original = try f.original(); try f.store.reserve(original); try f.respond(f.applied())
        guard case .applied(let receipt) = try await f.read() else { return XCTFail() }
        XCTAssertEqual(receipt.seriesID, 100); XCTAssertEqual(receipt.occurrences.count, 1)
        XCTAssertTrue(try f.store.contains(lockKey: original.lockKey)); XCTAssertTrue(f.access.sent.isEmpty)
        XCTAssertEqual(f.coordinator.state, .idle)
    }
    func testNavigationOnlyScopeIDsDoNotCreateAnotherRecoveryIdentity() async throws {
        let f = try fixture(); try f.store.reserve(f.original()); try f.respond(f.unknown())
        let result = try await f.coordinator.readOriginalSeriesResult(scope: ClubGovernanceFixtures.scope,
            identity: f.access.identity, check: {})
        XCTAssertEqual(result, .unknown(requestID: " original ")); XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testClosingViewBeforeAndAfterReadDiscardsResultWithoutWrites() async throws {
        for closeAfterDispatch in [false, true] {
            let f = try fixture(); try f.store.reserve(f.original()); try f.respond(f.applied())
            var active = closeAfterDispatch
            f.wire.onSend = { active = false }
            do {
                _ = try await f.coordinator.readOriginalSeriesResult(scope: f.scope, identity: f.access.identity, check: {
                    if !active { throw ClubSeriesOriginalResultFailure.stale }
                }); XCTFail()
            } catch {}
            XCTAssertEqual(f.wire.requests.count, closeAfterDispatch ? 1 : 0); XCTAssertTrue(f.access.sent.isEmpty)
        }
    }
    func testCurrentAuthorityRevocationStopsBeforeOriginalRead() async throws {
        let f = try fixture(); try f.store.reserve(f.original())
        var revoked = ClubGovernanceFixtures.permissions.object!; revoked["roleCodes"] = .array([]); revoked["permissions"] = .array([])
        f.access.permissionValue = .object(revoked)
        do { _ = try await f.read(); XCTFail() } catch {}
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testAccountOrApprovalChangesDiscardLateResponse() async throws {
        for changeApproval in [false, true] {
            let f = try fixture(); try f.store.reserve(f.original()); try f.respond(f.applied())
            f.wire.onSend = {
                if changeApproval { f.approval = nil }
                else { f.current = nil; f.access.identity = nil }
            }
            do { _ = try await f.read(); XCTFail() } catch {}
            XCTAssertEqual(f.wire.requests.count, 1); XCTAssertTrue(f.access.sent.isEmpty)
        }
    }
    func testUnknownCannotCarrySuccessAndChangedWireCannotPass() throws {
        let f = try fixture(), original = try f.original()
        var unknown = f.unknown(); unknown["series"] = .object(["id": .integer(100)])
        XCTAssertThrowsError(try ClubSeriesOriginalReceipt.decode(.object(unknown), original: original))
        var applied = try f.applied(), wire = applied["wire"]!.object!
        wire["defaultLeadMemberId"] = .integer(999); applied["wire"] = .object(wire)
        XCTAssertThrowsError(try ClubSeriesOriginalReceipt.decode(.object(applied), original: original))
        applied = try f.applied(); applied["occurrences"] = .array([])
        XCTAssertThrowsError(try ClubSeriesOriginalReceipt.decode(.object(applied), original: original))
    }
    func testUnicodeEquivalentButDifferentOriginalBytesAreRejected() throws {
        let f = try fixture(), decomposed = try f.original(id: "e\u{0301}")
        var value = try f.applied(), wire = value["wire"]!.object!, series = value["series"]!.object!
        value["requestId"] = .string("e\u{0301}"); series["requestId"] = value["requestId"]; value["series"] = .object(series)
        wire["requestId"] = .string("é"); value["wire"] = .object(wire)
        XCTAssertThrowsError(try ClubSeriesOriginalReceipt.decode(.object(value), original: decomposed))
    }
}

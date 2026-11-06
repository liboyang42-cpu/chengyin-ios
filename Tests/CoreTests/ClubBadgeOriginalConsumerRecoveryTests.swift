import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Synthetic transport only; never contacts a server or grants a real badge.
@MainActor final class ClubBadgeOriginalConsumerRecoveryTests: XCTestCase {
    final class Wire: HTTPTransport {
        var response: (Data, Int) = (Data(), 503)
        var requests: [URLRequest] = []
        var afterDispatch: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); afterDispatch?(); return response
        }
    }
    final class Fixture {
        let context: RuntimeDependencyContext
        let wire = Wire()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var approval: ClubBadgeManagementApproval?
        var current: RuntimeDependencyContext?
        lazy var journal = ClubBadgeManagementJournal(directory: directory)
        lazy var service = ClubBadgeManagementService(context: context, clubID: 7, transport: wire,
            current: { [weak self] in self?.current }, approval: { [weak self] _ in self?.approval })
        init(approved: Bool = true) throws {
            context = try WorkshopOwnedTestData.context(); current = context
            if approved {
                let endpoints = try OperationEndpointApproval(baseURL: context.baseURL, namespace: context.session.namespace,
                    accountID: context.session.accountID, paths: ClubBadgeManagementRoute.paths)
                approval = try .init(endpoints: endpoints, clubIDs: [7], reviewedPolicyVersion: "synthetic-v1", reads: true, writes: true)
            }
        }
        var fields: [String: Any] { ["clubId": 7, "badgeName": "Trail"] }
        func entry() throws -> ClubBadgeManagementEntry { try .init(context: context, clubID: 7, operation: "CREATE", fields: fields) }
        func send(_ entry: ClubBadgeManagementEntry) async throws -> ClubBadgeMutationOutcome {
            try await service.mutate(entry, fields: fields, isCurrentView: { true }, reserve: { try self.journal.reserve(entry, context: self.context) })
        }
        func envelope(code: Int = 200, data: [String: Any]? = nil) throws -> Data {
            var value: [String: Any] = ["code": code]
            if let data { value["data"] = data }
            return try JSONSerialization.data(withJSONObject: value)
        }
        func receipt(_ entry: ClubBadgeManagementEntry, terminal: Bool) -> [String: Any] {
            var value: [String: Any] = ["protocolVersion": 1, "clubId": 7, "actorMemberId": context.session.accountID,
                "requestId": entry.requestID, "operation": "CREATE", "sourceSHA256": entry.sourceSHA256,
                "state": terminal ? "CREATED" : "UNKNOWN"]
            if terminal { value.merge(["badgeId": 11, "badgeCode": "CLUB7_1", "appliedAt": 1_800_000_000_000 as Int64, "auditId": 15], uniquingKeysWith: { _, new in new }) }
            return value
        }
    }
    func testDefaultOffNeverReservesOrDispatches() async throws {
        let f = try Fixture(approved: false), entry = try f.entry()
        guard case .notSent = try await f.send(entry) else { return XCTFail("Must not send without approval") }
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertTrue(try f.journal.read(f.context, clubID: 7).isEmpty)
    }
    func testHTTP200ApplicationErrorsRemainOriginalUnknown() async throws {
        for code in [400, 403, 409, 500, 503] {
            let f = try Fixture(), entry = try f.entry(); f.wire.response = (try f.envelope(code: code), 200)
            guard case .unknown = try await f.send(entry) else { return XCTFail("Error envelope cannot prove non-execution") }
            XCTAssertEqual(try f.journal.read(f.context, clubID: 7).first?.requestID, entry.requestID)
            XCTAssertEqual(try f.journal.read(f.context, clubID: 7).first?.outcome, "UNKNOWN")
            XCTAssertThrowsError(try f.journal.reserve(f.entry(), context: f.context))
            XCTAssertEqual(f.wire.requests.count, 1)
        }
    }
    func testOriginalUnknownReadDoesNotResendOrResolveJournal() async throws {
        let f = try Fixture(), entry = try f.entry(); try f.journal.reserve(entry, context: f.context)
        f.wire.response = (try f.envelope(data: f.receipt(entry, terminal: false)), 200)
        let result = try await f.service.receipt(entry)
        XCTAssertFalse(result.isTerminal); XCTAssertEqual(try f.journal.read(f.context, clubID: 7).first?.outcome, "UNKNOWN")
        XCTAssertEqual(f.wire.requests.map { $0.url?.path }, ["/api/club/badge/original-receipt"])
    }
    func testOnlyExactTerminalReceiptCanSettleOriginalJournal() async throws {
        let f = try Fixture(), entry = try f.entry(); try f.journal.reserve(entry, context: f.context)
        f.wire.response = (try f.envelope(data: f.receipt(entry, terminal: true)), 200)
        let result = try await f.service.receipt(entry)
        try f.journal.settle(entry, outcome: "CONFIRMED", receipt: result, context: f.context)
        XCTAssertEqual(try f.journal.read(f.context, clubID: 7).first?.receipt, result)
        let other = try f.entry(); XCTAssertThrowsError(try result.validate(other))
        XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testWithdrawalAfterDispatchPreservesOriginalUnknown() async throws {
        let f = try Fixture(), entry = try f.entry(); f.wire.response = (try f.envelope(data: f.receipt(entry, terminal: true)), 200)
        f.wire.afterDispatch = { f.approval = nil }
        guard case .unknown = try await f.send(entry) else { return XCTFail("Withdrawn approval cannot consume late receipt") }
        XCTAssertEqual(try f.journal.read(f.context, clubID: 7).first?.outcome, "UNKNOWN")
    }
    func testReservationFailurePreventsTransport() async throws {
        let f = try Fixture(), entry = try f.entry()
        do {
            _ = try await f.service.mutate(entry, fields: f.fields, isCurrentView: { true }, reserve: { throw ClubBadgeManagementFailure.persistence })
            XCTFail("Storage failure must abort")
        } catch { XCTAssertTrue(f.wire.requests.isEmpty) }
    }
}

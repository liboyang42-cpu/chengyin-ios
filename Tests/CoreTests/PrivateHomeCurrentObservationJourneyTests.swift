import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// NOT_RUN. Real Service + Coordinator; all current reads, receipts and storage are synthetic in-memory values.
/// No network, location, OS Keychain, production grant or backend operation.
@available(macOS 14.0, *) @MainActor final class PrivateHomeCurrentObservationJourneyTests: XCTestCase {
    private static func snapshot(_ version: Int64, active: Bool = true, label: String = "Synthetic") -> Data {
        let value = active
            ? "{\"version\":\(version),\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"\(label)\",\"latitude\":12,\"longitude\":45,\"datum\":\"WGS84\"}"
            : "{\"version\":\(version),\"status\":\"DELETED\"}"
        return Data("{\"code\":200,\"data\":\(value)}".utf8)
    }
    @MainActor private final class Wire: HTTPTransport {
        var currentData = PrivateHomeCurrentObservationJourneyTests.snapshot(3)
        var currentStatus = 200
        var requests: [URLRequest] = [], mutations: [PrivateHomeMutation] = []
        var receipts: [String: Data] = [:]
        var decision: String?, receiptVersion: Int64?
        var loseNextWrite = false
        var afterSend: (() -> Void)?, afterWrite: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); afterSend?()
            if request.httpMethod == "GET" { return (currentData, currentStatus) }
            let mutation = try JSONDecoder().decode(PrivateHomeMutation.self, from: XCTUnwrap(request.httpBody))
            mutations.append(mutation)
            if receipts[mutation.requestId] == nil {
                let result = decision ?? (mutation.method == "PUT" ? "SAVED" : "DELETED")
                let version = receiptVersion ?? (mutation.expectedVersion + 1)
                receipts[mutation.requestId] = Data("{\"code\":200,\"data\":{\"requestId\":\"\(mutation.requestId)\",\"decision\":\"\(result)\",\"version\":\(version)}}".utf8)
            }
            afterWrite?()
            if loseNextWrite { loseNextWrite = false; throw PrivateHomeIssue.unknownOutcome }
            return (try XCTUnwrap(receipts[mutation.requestId]), 200)
        }
        var reads: Int { requests.filter { $0.httpMethod == "GET" }.count }
    }
    @MainActor private final class Journal: PrivateHomeSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: PrivateHomeMutation?
        var saves = 0, clears = 0
        var failRead = false, failClear = false
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() throws -> PrivateHomeMutation? {
            if failRead { throw PrivateHomeIssue.storageUnavailable }; return value
        }
        func save(_ mutation: PrivateHomeMutation) throws {
            guard value == nil || value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            value = mutation; saves += 1
        }
        func clear(matching mutation: PrivateHomeMutation) throws {
            guard !failClear, value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            value = nil; clears += 1
        }
    }
    @MainActor private final class Session {
        var current: PlayExperienceSession?
        init(_ owner: PlayExperienceSession) { current = owner }
    }
    @MainActor private final class Fixture {
        let owner: PlayExperienceSession, session: Session, journal: Journal, wire: Wire
        let service: PrivateHomeService, model: PrivateHomeCoordinator
        init(account: Int = 7, enabled: Bool = true) throws {
            let owner = try PlayExperienceSession(accountID: account, epoch: 1, namespace: "synthetic-home", token: "synthetic-token")
            let session = Session(owner), journal = Journal(owner), wire = Wire()
            let service = PrivateHomeService(api: try APIConfiguration(baseURL: URL(string: "https://example.test")!),
                transport: wire, owner: owner, enabled: enabled, current: { session.current })
            self.owner = owner; self.session = session; self.journal = journal; self.wire = wire; self.service = service
            model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: enabled, current: { session.current })
        }
    }
    private func point() throws -> PrivateHomePoint { try .init(latitude: 12, longitude: 45) }
    private func blocked(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(f.model.phase, .blocked, file: file, line: line)
        XCTAssertEqual(f.model.issue, .unavailable, file: file, line: line)
        XCTAssertNil(f.model.home, file: file, line: line)
        XCTAssertFalse(f.model.canEdit, file: file, line: line)
        XCTAssertFalse(f.model.canConfirm, file: file, line: line)
        XCTAssertFalse(f.model.canRetry, file: file, line: line)
    }

    func testPreviouslyObservedActiveOrDeletedVersionCannotRegressBeforeAnyMutation() async throws {
        for active in [true, false] {
            let f = try Fixture(); f.wire.currentData = Self.snapshot(8, active: active)
            await f.model.load(); XCTAssertTrue(f.model.canEdit)
            f.wire.currentData = Self.snapshot(3); await f.model.load(); blocked(f)
            f.model.prepareSet(label: "Must not stage", point: try point()); f.model.prepareDelete()
            await f.model.confirm(); await f.model.retryExact()
            XCTAssertNil(f.model.review); XCTAssertNil(f.model.decision); XCTAssertNil(f.journal.value)
            XCTAssertTrue(f.wire.mutations.isEmpty); XCTAssertEqual(f.journal.saves, 0)
        }
    }

    func testEveryValidatedReadAdvancesTheFloorAndEqualFreshReadCanRecover() async throws {
        let f = try Fixture(); await f.model.load()
        f.wire.currentData = Self.snapshot(8); await f.model.load()
        f.wire.currentData = Self.snapshot(5); await f.model.load(); blocked(f)
        f.wire.currentData = Self.snapshot(8); await f.model.load()
        XCTAssertEqual(f.model.phase, .ready); XCTAssertTrue(f.model.canEdit); XCTAssertNil(f.model.issue)
        f.model.prepareDelete(); XCTAssertEqual(f.model.review?.expectedVersion, 8)
        XCTAssertTrue(f.wire.mutations.isEmpty); XCTAssertEqual(f.journal.saves, 0)
    }

    func testSameVersionKeepsOriginalSnapshotValidationWithoutInventingPayloadIdentity() async throws {
        let f = try Fixture(); f.wire.currentData = Self.snapshot(8); await f.model.load()
        // The floor compares versions only, not an invented hash or receipt-derived current point.
        f.wire.currentData = Self.snapshot(8, label: "Independent current read"); await f.model.load()
        XCTAssertEqual(f.model.home?.label, "Independent current read"); XCTAssertTrue(f.model.canEdit)
        XCTAssertNil(f.model.decision); XCTAssertNil(f.journal.value)
    }

    func testInitialAbsentHomeVersionZeroStillAllowsExplicitReview() async throws {
        let f = try Fixture(); f.wire.currentData = Self.snapshot(0, active: false); await f.model.load()
        XCTAssertTrue(f.model.canEdit); XCTAssertEqual(f.model.home?.status, .deleted)
        f.model.prepareSet(label: "Synthetic", point: try point())
        XCTAssertEqual(f.model.review?.expectedVersion, 0); XCTAssertTrue(f.wire.mutations.isEmpty)
    }

    func testMaximumInt64ReadUsesComparisonWithoutArithmeticOrVersionReset() async throws {
        let f = try Fixture(); f.wire.currentData = Self.snapshot(Int64.max, active: false); await f.model.load()
        XCTAssertEqual(f.model.home?.version, Int64.max)
        f.wire.currentData = Self.snapshot(Int64.max - 1); await f.model.load(); blocked(f)
        f.wire.currentData = Self.snapshot(Int64.max, active: false); await f.model.load()
        f.model.prepareSet(label: "Exhausted version", point: try point())
        XCTAssertFalse(f.model.canConfirm); XCTAssertEqual(f.model.issue, .invalid)
        XCTAssertTrue(f.wire.mutations.isEmpty); XCTAssertNil(f.journal.value)
    }

    func testInvalidHighVersionBodyCannotRaiseTheObservedFloor() async throws {
        let f = try Fixture(); await f.model.load()
        f.wire.currentData = Data(#"{"code":200,"data":{"version":100,"status":"ACTIVE","label":"Invalid missing point"}}"#.utf8)
        await f.model.load(); XCTAssertEqual(f.model.phase, .blocked); XCTAssertFalse(f.model.canEdit)
        f.wire.currentData = Self.snapshot(4); await f.model.load()
        XCTAssertTrue(f.model.canEdit); XCTAssertEqual(f.model.home?.version, 4)
    }

    func testTransportFailureCannotResetAnAlreadyObservedFloor() async throws {
        let f = try Fixture(); f.wire.currentData = Self.snapshot(8); await f.model.load()
        f.wire.currentStatus = 503; await f.model.load(); XCTAssertEqual(f.model.phase, .blocked); XCTAssertFalse(f.model.canEdit)
        f.wire.currentStatus = 200; f.wire.currentData = Self.snapshot(7); await f.model.load(); blocked(f)
        f.wire.currentData = Self.snapshot(9); await f.model.load(); XCTAssertTrue(f.model.canEdit)
        XCTAssertTrue(f.wire.mutations.isEmpty)
    }

    func testJournalReadFailureNeverObservesTheUnrequestedHighVersion() async throws {
        let f = try Fixture(); f.wire.currentData = Self.snapshot(8); await f.model.load()
        f.journal.failRead = true; f.wire.currentData = Self.snapshot(100); await f.model.load()
        XCTAssertEqual(f.wire.reads, 1); XCTAssertEqual(f.model.issue, .storageUnavailable); XCTAssertFalse(f.model.canEdit)
        f.journal.failRead = false; f.wire.currentData = Self.snapshot(9); await f.model.load()
        XCTAssertEqual(f.model.home?.version, 9); XCTAssertTrue(f.model.canEdit)
        f.wire.currentData = Self.snapshot(8); await f.model.load(); blocked(f)
    }

    func testPendingCurrentReadRaisesFloorButNeverReplacesOriginalReceipt() async throws {
        let f = try Fixture(), original = try PrivateHomeMutation(requestId: "original", expectedVersion: 3)
        f.journal.value = original; f.wire.currentData = Self.snapshot(8); await f.model.load()
        XCTAssertEqual(f.model.phase, .unknown); XCTAssertEqual(f.journal.value, original); XCTAssertFalse(f.model.canEdit)
        f.wire.currentData = Self.snapshot(5); await f.model.load()
        XCTAssertEqual(f.model.phase, .unknown); XCTAssertEqual(f.model.issue, .unknownOutcome); XCTAssertNil(f.model.home)
        XCTAssertTrue(f.wire.mutations.isEmpty); XCTAssertEqual(f.journal.clears, 0)
        // An original valid v4 receipt can settle, but cannot lower the observed v8 current floor.
        f.wire.currentData = Self.snapshot(7); await f.model.retryExact(); blocked(f)
        XCTAssertEqual(f.model.decision, .deleted); XCTAssertNil(f.journal.value); XCTAssertEqual(f.journal.clears, 1)
        XCTAssertEqual(f.wire.mutations, [original]); XCTAssertEqual(f.journal.saves, 0)
        f.wire.currentData = Self.snapshot(8); await f.model.load()
        XCTAssertTrue(f.model.canEdit); XCTAssertEqual(f.wire.mutations, [original])
    }

    func testLowerHistoricalConflictReceiptDoesNotDiscardTheObservedVersion() async throws {
        let f = try Fixture(); f.wire.currentData = Self.snapshot(8); await f.model.load()
        f.model.prepareSet(label: "Explicit review", point: try point())
        f.wire.decision = "VERSION_CONFLICT"; f.wire.receiptVersion = 2; f.wire.currentData = Self.snapshot(7)
        await f.model.confirm(); blocked(f)
        XCTAssertEqual(f.model.decision, .conflict); XCTAssertNil(f.journal.value); XCTAssertEqual(f.journal.clears, 1)
        XCTAssertEqual(f.wire.mutations.count, 1); XCTAssertEqual(f.wire.mutations[0].expectedVersion, 8)
        f.wire.currentData = Self.snapshot(8); await f.model.load(); XCTAssertTrue(f.model.canEdit)
    }

    func testNewerPostSettlementCurrentReadExtendsTheOriginalReceiptFloor() async throws {
        let f = try Fixture(); await f.model.load(); f.model.prepareDelete()
        f.wire.currentData = Self.snapshot(8); await f.model.confirm()
        XCTAssertEqual(f.model.decision, .deleted); XCTAssertEqual(f.model.home?.version, 8); XCTAssertTrue(f.model.canEdit)
        f.wire.currentData = Self.snapshot(7); await f.model.load(); blocked(f)
        XCTAssertEqual(f.model.decision, .deleted); XCTAssertNil(f.journal.value); XCTAssertEqual(f.wire.mutations.count, 1)
    }

    func testLostReplyAndFailedClearKeepUnknownDespiteNewerCurrentObservation() async throws {
        let f = try Fixture(); await f.model.load(); f.model.prepareDelete()
        f.wire.loseNextWrite = true; await f.model.confirm()
        let original = try XCTUnwrap(f.journal.value)
        f.wire.currentData = Self.snapshot(8); await f.model.load()
        f.journal.failClear = true; await f.model.retryExact()
        XCTAssertEqual(f.model.phase, .unknown); XCTAssertNil(f.model.decision); XCTAssertEqual(f.journal.value, original)
        f.journal.failClear = false; f.wire.currentData = Self.snapshot(7); await f.model.retryExact(); blocked(f)
        XCTAssertEqual(f.model.decision, .deleted); XCTAssertNil(f.journal.value); XCTAssertEqual(f.journal.clears, 1)
        XCTAssertEqual(f.wire.mutations, [original, original, original])
    }

    func testSessionRevokedDuringReadCannotPublishOrRecoverTheOldInstance() async throws {
        let f = try Fixture(); await f.model.load()
        f.wire.currentData = Self.snapshot(100); f.wire.afterSend = { f.session.current = nil }
        await f.model.load()
        XCTAssertEqual(f.model.phase, .invalidated); XCTAssertNil(f.model.home); XCTAssertFalse(f.model.canEdit)
        f.session.current = f.owner; f.wire.afterSend = nil; await f.model.load()
        XCTAssertEqual(f.model.phase, .invalidated); XCTAssertEqual(f.wire.reads, 2)
        XCTAssertTrue(f.wire.mutations.isEmpty)
    }

    func testFloorIsOwnerInstanceLocalNotAnInventedDurableOrCrossOwnerGuarantee() async throws {
        let f = try Fixture(); f.wire.currentData = Self.snapshot(100); await f.model.load()
        let other = try Fixture(account: 9); other.wire.currentData = Self.snapshot(1); await other.model.load()
        XCTAssertEqual(other.model.home?.version, 1); XCTAssertTrue(other.model.canEdit)
        // Explicitly document the limit: no new journal record/tombstone is written for a GET.
        f.model.invalidate(); f.wire.currentData = Self.snapshot(1)
        let recreated = PrivateHomeCoordinator(service: f.service, journal: f.journal, owner: f.owner, enabled: true, current: { f.session.current })
        await recreated.load(); XCTAssertEqual(recreated.home?.version, 1); XCTAssertTrue(recreated.canEdit)
        XCTAssertEqual(f.journal.saves, 0); XCTAssertNil(f.journal.value); XCTAssertTrue(f.wire.mutations.isEmpty)
    }

    func testDefaultDisabledPathStillCannotReadOrCreateAFloor() async throws {
        let f = try Fixture(enabled: false); await f.model.load()
        XCTAssertEqual(f.model.phase, .disabled); XCTAssertNil(f.model.home); XCTAssertFalse(f.model.canEdit)
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertEqual(f.journal.saves, 0)
    }
}

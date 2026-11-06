import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// NOT_RUN. Original value/service/coordinator with synthetic transport and journal.
/// No database, Keychain, location or production deletion is performed.
@available(macOS 14.0, *) @MainActor final class PrivateHomeDeletedSnapshotJourneyTests: XCTestCase {
    private static func deleted(_ version: Int64 = 4, fields: String = "") -> String {
        "{\"version\":\(version),\"status\":\"DELETED\"\(fields.isEmpty ? "" : "," + fields)}"
    }
    private static func active(_ version: Int64 = 3) -> String {
        "{\"version\":\(version),\"status\":\"ACTIVE\",\"label\":\"Synthetic\",\"latitude\":12,\"longitude\":45,\"datum\":\"WGS84\",\"changedAt\":1,\"effectiveAt\":2}"
    }
    private static func decode(_ body: String) throws -> PrivateHomeSnapshot {
        try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(body.utf8))
    }
    @MainActor private final class Wire: HTTPTransport {
        var current = PrivateHomeDeletedSnapshotJourneyTests.active()
        var deleteResidue = "", loseNext = false
        var requests: [URLRequest] = [], mutations: [PrivateHomeMutation] = []
        var receipts: [String: String] = [:]
        func send(_ request: URLRequest) throws -> (Data, Int) {
            requests.append(request)
            if request.httpMethod == "GET" { return envelope(current) }
            let mutation = try JSONDecoder().decode(PrivateHomeMutation.self, from: XCTUnwrap(request.httpBody))
            mutations.append(mutation)
            if receipts[mutation.requestId] == nil {
                let version = mutation.expectedVersion + 1, deleted = mutation.method == "DELETE"
                receipts[mutation.requestId] = "{\"requestId\":\"\(mutation.requestId)\",\"decision\":\"\(deleted ? "DELETED" : "SAVED")\",\"version\":\(version)}"
                current = deleted ? PrivateHomeDeletedSnapshotJourneyTests.deleted(version, fields: deleteResidue)
                    : PrivateHomeDeletedSnapshotJourneyTests.active(version)
            }
            if loseNext { loseNext = false; throw PrivateHomeIssue.unknownOutcome }
            return envelope(try XCTUnwrap(receipts[mutation.requestId]))
        }
        private func envelope(_ body: String) -> (Data, Int) { (Data("{\"code\":200,\"data\":\(body)}".utf8), 200) }
    }
    @MainActor private final class Journal: PrivateHomeSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: PrivateHomeMutation?
        var saves = 0, clears = 0
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() -> PrivateHomeMutation? { value }
        func save(_ mutation: PrivateHomeMutation) throws {
            guard value == nil || value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            saves += 1; value = mutation
        }
        func clear(matching mutation: PrivateHomeMutation) throws {
            guard value == mutation else { throw PrivateHomeIssue.storageUnavailable }
            clears += 1; value = nil
        }
    }
    @MainActor private final class Fixture {
        let owner: PlayExperienceSession, wire: Wire, journal: Journal, service: PrivateHomeService
        init() throws {
            let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic-delete", token: "synthetic-token")
            let wire = Wire(); self.owner = owner; self.wire = wire; journal = Journal(owner)
            service = PrivateHomeService(api: try APIConfiguration(baseURL: URL(string: "https://deleted-home.example.test")!),
                transport: wire, owner: owner, enabled: true, current: { owner })
        }
        func model() -> PrivateHomeCoordinator { .init(service: service, journal: journal, owner: owner, enabled: true, current: { self.owner }) }
    }

    func testOmittedOrExplicitNullDeletedFieldsRemainValidAtAllOriginalVersionBounds() throws {
        for version in [Int64(0), 4, Int64.max] {
            for fields in ["", #""label":null,"latitude":null,"longitude":null,"datum":null,"changedAt":null,"effectiveAt":null"#] {
                let value = try Self.decode(Self.deleted(version, fields: fields)); try value.validate()
                XCTAssertEqual(value.version, version); XCTAssertEqual(value.status, .deleted)
                XCTAssertNil(value.changedAt); XCTAssertNil(value.effectiveAt)
            }
        }
    }
    func testAnyRetainedDeletedTimestampIsInvalidIncludingZeroAndNegativeValues() throws {
        for field in ["changedAt", "effectiveAt"] {
            for value in [Int64.min, -1, 0, 1, Int64.max] {
                let snapshot = try Self.decode(Self.deleted(fields: "\"\(field)\":\(value)"))
                XCTAssertThrowsError(try snapshot.validate()) { XCTAssertEqual($0 as? PrivateHomeIssue, .invalid) }
            }
        }
        let both = try Self.decode(Self.deleted(fields: #""changedAt":1,"effectiveAt":2"#))
        XCTAssertThrowsError(try both.validate())
    }
    func testExistingDeletedPrivatePayloadExclusionsStillApply() throws {
        for fields in [#""label":"Synthetic""#, #""latitude":0"#, #""longitude":0"#, #""datum":"WGS84""#] {
            let value = try Self.decode(Self.deleted(fields: fields)); XCTAssertThrowsError(try value.validate())
        }
    }
    func testActiveTimestampContractRemainsUnchanged() throws {
        let valid = try Self.decode(Self.active()); try valid.validate()
        for body in [Self.active().replacingOccurrences(of: #""changedAt":1"#, with: #""changedAt":null"#),
                     Self.active().replacingOccurrences(of: #""effectiveAt":2"#, with: #""effectiveAt":null"#),
                     Self.active().replacingOccurrences(of: #""changedAt":1"#, with: #""changedAt":-1"#),
                     Self.active().replacingOccurrences(of: #""effectiveAt":2"#, with: #""effectiveAt":0"#)] {
            let value = try Self.decode(body); XCTAssertThrowsError(try value.validate())
        }
    }
    func testCurrentServiceRejectsContradictoryDeletedStateWithoutWritingOrRepairingIt() async throws {
        let f = try Fixture()
        for fields in [#""changedAt":1"#, #""effectiveAt":2"#, #""changedAt":0,"effectiveAt":0"#] {
            let original = Self.deleted(fields: fields); f.wire.current = original
            do { _ = try await f.service.load(); XCTFail("Contradictory current state must not be accepted") }
            catch { XCTAssertEqual(error as? PrivateHomeIssue, .invalid) }
            XCTAssertEqual(f.wire.current, original); XCTAssertTrue(f.wire.mutations.isEmpty)
        }
    }
    func testInvalidDeletedReadCannotEnableEditingButExplicitValidRefreshCan() async throws {
        let f = try Fixture(), model = f.model(); f.wire.current = Self.deleted(fields: #""changedAt":1"#)
        await model.load(); XCTAssertEqual(model.phase, .blocked); XCTAssertFalse(model.canEdit)
        model.prepareSet(label: "Must not stage", point: try .init(latitude: 12, longitude: 45)); await model.confirm()
        XCTAssertNil(model.review); XCTAssertEqual(f.journal.saves, 0); XCTAssertTrue(f.wire.mutations.isEmpty)
        f.wire.current = Self.deleted(); await model.load(); XCTAssertTrue(model.canEdit)
        model.prepareDelete(); XCTAssertNil(model.review) // An already deleted current state cannot be deleted again.
        model.prepareSet(label: "Explicit new home", point: try .init(latitude: 12, longitude: 45))
        XCTAssertEqual(model.review?.expectedVersion, 4); XCTAssertTrue(f.wire.mutations.isEmpty)
    }
    func testKnownTerminalDeleteIsNotRelabeledUnknownWhenCurrentReadIsInvalid() async throws {
        let f = try Fixture(), model = f.model(); f.wire.deleteResidue = #""effectiveAt":2"#
        await model.load(); model.prepareDelete(); let original = try XCTUnwrap(model.review)
        await model.confirm()
        XCTAssertEqual(f.wire.mutations, [original]); XCTAssertEqual(model.decision, .deleted)
        XCTAssertEqual(model.phase, .blocked); XCTAssertFalse(model.canEdit); XCTAssertFalse(model.canRetry)
        XCTAssertNil(f.journal.value); XCTAssertEqual(f.journal.clears, 1)
        // Only the synthetic server response changes; product code never repairs a snapshot.
        f.wire.current = Self.deleted(); await model.load()
        XCTAssertEqual(model.decision, .deleted); XCTAssertTrue(model.canEdit); XCTAssertEqual(f.wire.mutations, [original])
        model.prepareSet(label: "Explicit next request", point: try .init(latitude: 12, longitude: 45))
        XCTAssertEqual(model.review?.expectedVersion, 4); XCTAssertNotEqual(model.review?.requestId, original.requestId)
    }
    func testLostDeleteRemainsUnknownThroughBadGetAndOnlyOriginalRetryCanSettle() async throws {
        let f = try Fixture(), model = f.model(); f.wire.deleteResidue = #""changedAt":1"#
        await model.load(); model.prepareDelete(); let original = try XCTUnwrap(model.review)
        f.wire.loseNext = true; await model.confirm()
        await model.load()
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(f.journal.value, original); XCTAssertEqual(f.journal.clears, 0)
        XCTAssertEqual(f.wire.mutations, [original]); XCTAssertNil(model.decision); XCTAssertFalse(model.canEdit)
        await model.retryExact()
        XCTAssertEqual(f.wire.mutations, [original, original]); XCTAssertEqual(model.decision, .deleted)
        XCTAssertEqual(model.phase, .blocked); XCTAssertNil(f.journal.value); XCTAssertEqual(f.journal.clears, 1)
        f.wire.current = Self.deleted(); await model.load(); XCTAssertTrue(model.canEdit)
        XCTAssertEqual(f.wire.mutations.count, 2)
    }
    func testColdOriginalCannotBeUnlockedByEvenValidDeletedCurrentState() async throws {
        let f = try Fixture(); let original = try PrivateHomeMutation(requestId: "cold-original-delete", expectedVersion: 3)
        f.journal.value = original; f.wire.current = Self.deleted(fields: #""effectiveAt":2"#)
        let model = f.model(); await model.load()
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(f.journal.value, original); XCTAssertEqual(f.journal.clears, 0)
        f.wire.current = Self.deleted(); await model.load()
        XCTAssertEqual(model.phase, .unknown); XCTAssertFalse(model.canEdit)
        XCTAssertEqual(f.journal.value, original); XCTAssertTrue(f.wire.mutations.isEmpty)
    }
    func testInvalidDeletedReadDoesNotAdvanceTheObservedVersionFloor() async throws {
        let f = try Fixture(), model = f.model(); await model.load(); XCTAssertEqual(model.home?.version, 3)
        f.wire.current = Self.deleted(999, fields: #""changedAt":1"#); await model.load()
        XCTAssertEqual(model.phase, .blocked); XCTAssertFalse(model.canEdit)
        f.wire.current = Self.deleted(4); await model.load()
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.home?.version, 4); XCTAssertTrue(f.wire.mutations.isEmpty)
    }
}

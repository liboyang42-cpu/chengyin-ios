import XCTest
@testable import QuestifyCore

final class ClubCustomerHistoryTopicRouteTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81, memberID: 704)
    private var context: ClubGovernanceReadContext { makeContext() }
    private func makeContext(operation: ClubGovernanceRead = .customer, scope: ClubGovernanceScope? = nil,
                             identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1), revision: UInt64 = 4,
                             authorization: UUID? = nil) -> ClubGovernanceReadContext {
        .init(operation: operation, scope: scope ?? self.scope, identity: identity, viewerRevision: revision, authorizationGeneration: authorization)
    }
    private func record(_ topicID: ClubGovernanceValue = .integer(91), extra: [String: ClubGovernanceValue] = [:]) -> ClubGovernanceValue {
        var fields: [String: ClubGovernanceValue] = ["key": .string("registration-121"), "topicId": topicID, "statusCode": .string("PENDING"), "id": .integer(121), "activityId": .integer(101)]
        fields.merge(extra) { _, new in new }; return .object(fields)
    }
    private func snapshot(records: [ClubGovernanceValue], memberID: Int = 704, scope: ClubGovernanceScope? = nil,
                          operation: ClubGovernanceRead = .customer, permissions: Bool = true) throws -> ClubGovernanceSnapshot {
        var value = ClubGovernanceFixtures.value(.customer).object!
        var summary = value["summary"]!.object!; summary["memberId"] = .integer(memberID)
        value["summary"] = .object(summary); value["records"] = .array(records)
        return .init(operation: operation, scope: scope ?? self.scope,
                     permissions: permissions ? try ClubGovernancePermissions(value: ClubGovernanceFixtures.permissions, scope: self.scope) : nil,
                     value: .object(value))
    }
    private func route(_ row: ClubGovernanceValue, in snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext? = nil) -> ClubCustomerHistoryTopicRoute? {
        .init(record: row, snapshot: snapshot, context: context ?? self.context, snapshotGeneration: 7)
    }
    func testReturnedTopicIDOpensOrdinaryTopicAndNeverUsesOtherIdentifiers() throws {
        let row = record(), snapshot = try snapshot(records: [row])
        let route = try XCTUnwrap(route(row, in: snapshot))
        XCTAssertEqual(route.topicID, 91)
        XCTAssertNotEqual(route.topicID, 121); XCTAssertNotEqual(route.topicID, 101); XCTAssertNotEqual(route.topicID, 704)
        XCTAssertTrue(route.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: 7))
    }
    func testSafeIntegerRepresentationsAndMaximum() throws {
        for value in [ClubGovernanceValue.integer(1), .string("91"), .decimal(91), .integer(9_007_199_254_740_991)] {
            let row = record(value)
            XCTAssertNotNil(route(row, in: try snapshot(records: [row])))
        }
    }
    func testMissingMalformedFractionalAndUnsafeIDsRemainNonNavigable() throws {
        let values: [ClubGovernanceValue] = [.null, .integer(0), .integer(-1), .integer(Int.max), .integer(9_007_199_254_740_992),
            .decimal(91.5), .decimal(.infinity), .decimal(.nan), .string(""), .string("not-an-id"), .string("91.5"), .bool(true), .object([:]), .array([])]
        for value in values {
            let row = record(value)
            XCTAssertNil(route(row, in: try snapshot(records: [row])))
        }
        var missing = record().object!; missing.removeValue(forKey: "topicId")
        let row = ClubGovernanceValue.object(missing)
        XCTAssertNil(route(row, in: try snapshot(records: [row])))
    }
    func testMissingTopicDoesNotInvalidateOtherwiseValidHistory() throws {
        let rows = [record(.null), record(.integer(-1), extra: ["key": .string("second")])]
        let snapshot = try snapshot(records: rows)
        XCTAssertNoThrow(try ClubGovernanceValidation.validate(snapshot.value, operation: .customer, scope: scope))
        for row in rows { XCTAssertNil(route(row, in: snapshot)) }
    }
    func testForeignOrSubstitutedRowCannotCreateRoute() throws {
        let accepted = record(), foreign = record(.integer(92))
        XCTAssertNil(route(foreign, in: try snapshot(records: [accepted])))
        for extra in [["clubId": ClubGovernanceValue.integer(82)], ["memberId": .integer(705)], ["clubId": .string("bad")]] {
            let row = record(extra: extra)
            XCTAssertNil(route(row, in: try snapshot(records: [row])))
        }
        let row = record(extra: ["clubId": .integer(81), "memberId": .integer(704)])
        XCTAssertNotNil(route(row, in: try snapshot(records: [row])))
    }
    func testWrongCustomerClubOperationAndMissingAuthorityFailClosed() throws {
        let row = record()
        XCTAssertNil(route(row, in: try snapshot(records: [row], memberID: 705)))
        XCTAssertNil(route(row, in: try snapshot(records: [row], scope: .init(clubID: 82, memberID: 704))))
        XCTAssertNil(route(row, in: try snapshot(records: [row], operation: .topicOverview)))
        XCTAssertNil(route(row, in: try snapshot(records: [row], permissions: false)))
        let foreignScope = ClubGovernanceScope(clubID: 82, memberID: 704)
        XCTAssertNil(route(row, in: try snapshot(records: [row], scope: foreignScope), context: makeContext(scope: foreignScope)))
    }
    func testAmbiguousOrEmptyRecordKeysNeverNavigate() throws {
        let row = record()
        XCTAssertNil(route(row, in: try snapshot(records: [row, row])))
        for key in ["", "  "] {
            let row = record(extra: ["key": .string(key)])
            XCTAssertNil(route(row, in: try snapshot(records: [row])))
        }
    }
    func testSignedOutAndInvalidAccountNeverCreateRoute() throws {
        let row = record(), snapshot = try snapshot(records: [row])
        for identity in [nil, ClubReadIdentity(accountID: nil, epoch: 1), .init(accountID: 0, epoch: 1), .init(accountID: -1, epoch: 1)] {
            XCTAssertNil(route(row, in: snapshot, context: makeContext(identity: identity)))
        }
    }
    func testAccountEpochRoleAndAuthorityChangesInvalidateSelection() throws {
        let row = record(), snapshot = try snapshot(records: [row])
        let route = try XCTUnwrap(route(row, in: snapshot))
        let changed = [makeContext(identity: nil), makeContext(identity: .init(accountID: 702, epoch: 1)),
            makeContext(identity: .init(accountID: 701, epoch: 2)), makeContext(revision: 5), makeContext(revision: 6), makeContext(authorization: UUID())]
        for context in changed { XCTAssertFalse(route.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: 7)) }
    }
    func testNewerReadNilSnapshotAndDifferentTargetsInvalidateSelection() throws {
        let row = record(), snapshot = try snapshot(records: [row])
        let route = try XCTUnwrap(route(row, in: snapshot))
        XCTAssertFalse(route.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: 8))
        XCTAssertFalse(route.isCurrent(snapshot: nil, context: context, snapshotGeneration: 7))
        for context in [makeContext(scope: .init(clubID: 82, memberID: 704)), makeContext(scope: .init(clubID: 81, memberID: 705)), makeContext(operation: .customers)] {
            XCTAssertFalse(route.isCurrent(snapshot: snapshot, context: context, snapshotGeneration: 7))
        }
    }
    func testRemovedOrRetargetedRecordCannotRenderAnOldSelection() throws {
        let row = record(), route = try XCTUnwrap(route(row, in: snapshot(records: [row])))
        for rows in [[], [record(.integer(92))], [record(extra: ["memberId": .integer(705)])], [row, row]] {
            XCTAssertFalse(route.isCurrent(snapshot: try snapshot(records: rows), context: context, snapshotGeneration: 7))
        }
    }
    func testReadContextRejectsLateResponseForDifferentCustomerOrOperation() throws {
        let row = record()
        XCTAssertTrue(context.accepts(try snapshot(records: [row])))
        XCTAssertFalse(context.accepts(try snapshot(records: [row], scope: .init(clubID: 81, memberID: 705))))
        XCTAssertFalse(context.accepts(try snapshot(records: [row], operation: .customers)))
        XCTAssertNotEqual(context, makeContext(revision: 6), "An ABA role restoration cannot reuse the original read context")
    }
}

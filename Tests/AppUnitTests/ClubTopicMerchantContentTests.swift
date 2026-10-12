import XCTest
@testable import Questify

@MainActor final class ClubTopicMerchantContentTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "synthetic-topic-merchants"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var sends = 0
        var reads = 0
        var nodes: [ClubGovernanceValue] = [.object(["nodeId": .integer(11), "merchantName": .string("Merchant"), "name": .string("Station"), "state": .string("ASSIGNED")])]
        var allowed = true
        var scope = ClubGovernanceScope(clubID: 81, topicID: 91)
        func response() throws -> ClubGovernanceSnapshot {
            let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array([]),
                "permissions": .array(allowed ? [.string("club:content:manage")] : []), "canManageRoles": .bool(false)]), scope: scope)
            return .init(operation: .recruit, scope: scope, permissions: permissions, value: .object(["nodes": .array(nodes)]))
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            reads += 1; XCTAssertEqual(operation, .recruit); XCTAssertEqual(scope, self.scope); XCTAssertTrue(options.isEmpty); return try response()
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
    }
    private func context(_ a: Access) -> ClubGovernanceReadContext {
        .init(operation: .recruit, scope: a.scope, identity: a.identity, viewerRevision: 0, authorizationGeneration: a.authorizationGeneration, accessIdentity: ObjectIdentifier(a))
    }
    private func state(_ snapshot: ClubGovernanceSnapshot, _ context: ClubGovernanceReadContext, _ a: Access, generation: UInt64 = 3) -> ClubTopicMerchantReadGate.State {
        ClubTopicMerchantReadGate.state(snapshot: snapshot, context: context, snapshotGeneration: 3, readGeneration: generation, access: a)
    }
    private func rows(_ state: ClubTopicMerchantReadGate.State) -> [ClubTopicMerchantRow]? {
        if case .ready(let list) = state { return list.rows }; return nil
    }
    func testActualAcceptedSnapshotShowsRowsWithoutAdditionalRequestsOrWrites() throws {
        let a = Access(), result = state(try a.response(), context(a), a)
        XCTAssertEqual(rows(result)?.map(\.id), [11]); XCTAssertEqual(a.reads, 0); XCTAssertEqual(a.sends, 0)
    }
    func testParentReadRefreshCanReplaceListWithGenuineEmpty() async throws {
        let a = Access(), c = context(a)
        let first = try await a.read(.recruit, scope: a.scope, options: [:]); XCTAssertEqual(rows(state(first, c, a))?.count, 1)
        a.nodes = [.object(["nodeId": .integer(11), "state": .string("OPEN")])]
        let second = try await a.read(.recruit, scope: a.scope, options: [:]); XCTAssertTrue(rows(state(second, c, a))?.isEmpty == true)
        XCTAssertEqual(a.reads, 2); XCTAssertEqual(a.sends, 0)
    }
    func testNewReadGenerationHidesOldRows() throws {
        let a = Access(); XCTAssertEqual(state(try a.response(), context(a), a, generation: 4), .stale)
    }
    func testAccountOrEpochChangeHidesOldRows() throws {
        let a = Access(), c = context(a), source = try a.response()
        a.identity = .init(accountID: 702, epoch: 2); XCTAssertEqual(state(source, c, a), .stale)
        a.identity = .init(accountID: 701, epoch: 2); XCTAssertEqual(state(source, c, a), .stale)
    }
    func testAuthorityChangeConfigurationAndReaderReplacementHideOldRows() throws {
        let a = Access(), c = context(a), source = try a.response(), other = Access()
        other.authorizationGeneration = a.authorizationGeneration; XCTAssertEqual(state(source, c, other), .stale)
        a.authorizationGeneration = UUID(); XCTAssertEqual(state(source, c, a), .stale)
        a.authorizationGeneration = c.authorizationGeneration; a.isConfigured = false; XCTAssertEqual(state(source, c, a), .stale)
    }
    func testPermissionLossIsFailureNotEmptyList() throws {
        let a = Access(); a.allowed = false
        XCTAssertEqual(state(try a.response(), context(a), a), .failed(.forbidden))
    }
    func testMalformedRowsAreFailureNotEmptyList() throws {
        let a = Access(); a.nodes = [.object(["merchantName": .string("No target")])]
        XCTAssertEqual(state(try a.response(), context(a), a), .failed(.malformed))
    }
    func testForeignTopicResponseDoesNotRenderInCurrentRoute() throws {
        let a = Access(), c = context(a); a.scope = .init(clubID: 81, topicID: 92)
        XCTAssertEqual(state(try a.response(), c, a), .failed(.targetChanged))
    }
}

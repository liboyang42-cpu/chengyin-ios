import XCTest
@testable import Questify

@MainActor final class ClubRosterInteractionTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "synthetic-roster"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var sends = 0, version = 4
        var resources: [ClubGovernanceRead] = []
        var allowed = true
        func response(scope: ClubGovernanceScope = .init(clubID: 81, activityID: 205)) throws -> ClubGovernanceSnapshot {
            let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
                "roleCodes": .array([]), "permissions": .array(allowed ? [.string("club:event:checkin")] : []), "canManageRoles": .bool(false)]), scope: scope)
            return .init(operation: .roster, scope: scope, permissions: permissions, value: .object(["phoneIncluded": .bool(false),
                "registered": .array([.object(["memberId": .integer(41), "nickname": .string("Member"), "correctionVersion": .integer(version)])]),
                "waitlist": .array([]), "arrived": .array([]), "noShow": .array([])]))
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            resources.append(operation); XCTAssertEqual(operation, .roster); XCTAssertTrue(options.isEmpty); return try response(scope: scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
    }
    private func context(_ access: Access) -> ClubGovernanceReadContext {
        .init(operation: .roster, scope: .init(clubID: 81, activityID: 205), identity: access.identity, viewerRevision: 0,
              authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
    }
    private func target(_ access: Access) throws -> (ClubRosterCorrectionRoute, ClubGovernanceSnapshot, ClubGovernanceReadContext) {
        let snapshot = try access.response(), expected = context(access), value = try ClubRosterPresentation(snapshot: snapshot, context: expected)
        return (try XCTUnwrap(value.correctionRoute(memberID: 41, bucket: .registered, context: expected, snapshotGeneration: 3, namespace: access.storageNamespace)), snapshot, expected)
    }
    private func form(_ target: ClubRosterCorrectionRoute, _ source: ClubGovernanceSnapshot?, _ expected: ClubGovernanceReadContext, _ access: Access, generation: UInt64 = 3) -> ClubGovernanceFormRoute? {
        ClubRosterInteraction.formRoute(target, snapshot: source, context: expected, snapshotGeneration: 3, readGeneration: generation, access: access)
    }
    func testCurrentRowCreatesOnlyExistingScopedFormWithImmutableVersion() throws {
        let access = Access(), (target, source, expected) = try self.target(access), route = try XCTUnwrap(form(target, source, expected, access))
        XCTAssertEqual(route.operation, .correctAttendance); XCTAssertEqual(route.scope, .init(clubID: 81, activityID: 205, memberID: 41))
        XCTAssertEqual(route.seed, ["expectedVersion": .integer(4), "arrived": .bool(true)]); XCTAssertEqual(access.sends, 0); XCTAssertEqual(access.resources, [])
    }
    func testReloadInProgressAndMissingSnapshotCannotOpenOldRow() throws {
        let access = Access(), (target, source, expected) = try self.target(access)
        XCTAssertNil(form(target, source, expected, access, generation: 4)); XCTAssertNil(form(target, nil, expected, access))
    }
    func testIdentityEpochOrAuthorityChangeCannotOpen() throws {
        let access = Access(), (target, source, expected) = try self.target(access)
        access.identity = .init(accountID: 701, epoch: 2); XCTAssertNil(form(target, source, expected, access))
        access.identity = expected.identity; access.authorizationGeneration = UUID(); XCTAssertNil(form(target, source, expected, access))
    }
    func testReaderNamespaceAndConfigurationChangesCannotOpen() throws {
        let access = Access(), (target, source, expected) = try self.target(access), other = Access()
        other.authorizationGeneration = access.authorizationGeneration; XCTAssertNil(form(target, source, expected, other))
        access.storageNamespace = "another"; XCTAssertNil(form(target, source, expected, access))
        access.storageNamespace = target.namespace; access.isConfigured = false; XCTAssertNil(form(target, source, expected, access))
    }
    func testChangedVersionSnapshotCannotOpenPriorRow() throws {
        let access = Access(), (target, _, expected) = try self.target(access); access.version = 5
        XCTAssertNil(form(target, try access.response(), expected, access))
    }
    func testExistingPrepareAndCancelThenReadbackNeverSends() async throws {
        let access = Access(), (target, source, expected) = try self.target(access), route = try XCTUnwrap(form(target, source, expected, access))
        var draft = ClubGovernanceFormDraft(operation: route.operation, scope: route.scope, seed: route.seed)
        draft.text["reason"] = "Correcting attendance"; draft.flags["arrived"] = true
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(draft.command())
        XCTAssertEqual(review.command.fields["expectedVersion"], .integer(4)); XCTAssertEqual(review.command.fields["arrived"], .bool(true))
        coordinator.cancelReview()
        _ = try await access.read(.roster, scope: expected.scope, options: [:])
        XCTAssertEqual(access.resources, [.roster, .roster]); XCTAssertEqual(access.sends, 0); XCTAssertFalse(access.canDispatch(review.command))
    }
    func testExistingFreshVersionCheckStillRejectsBeforeWrite() async throws {
        let access = Access(), (target, source, expected) = try self.target(access), route = try XCTUnwrap(form(target, source, expected, access))
        var draft = ClubGovernanceFormDraft(operation: route.operation, scope: route.scope, seed: route.seed); draft.text["reason"] = "Correction"
        access.version = 5; let coordinator = ClubGovernanceCoordinator(access: access)
        do { _ = try await coordinator.prepare(draft.command()); XCTFail("Expected stale member") }
        catch { XCTAssertEqual(error as? ClubGovernanceFailure, .staleReview) }
        XCTAssertEqual(access.sends, 0)
    }
    func testExistingFreshPermissionCheckStillRejectsBeforeWrite() async throws {
        let access = Access(), (target, source, expected) = try self.target(access), route = try XCTUnwrap(form(target, source, expected, access))
        var draft = ClubGovernanceFormDraft(operation: route.operation, scope: route.scope, seed: route.seed); draft.text["reason"] = "Correction"
        access.allowed = false; let coordinator = ClubGovernanceCoordinator(access: access)
        do { _ = try await coordinator.prepare(draft.command()); XCTFail("Expected forbidden") }
        catch { XCTAssertEqual(error as? ClubGovernanceFailure, .forbidden) }
        XCTAssertEqual(access.sends, 0)
    }
}

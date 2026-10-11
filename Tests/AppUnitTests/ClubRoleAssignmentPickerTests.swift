import XCTest
@testable import Questify

@MainActor final class ClubRoleAssignmentPickerTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        let storageNamespace = "synthetic-role-picker"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var resources: [ClubGovernanceRead] = []
        var sends = 0
        var memberID = 41
        var rolePermission = true, memberPermission = true
        var held: ClubGovernanceRead?
        var failure: ClubGovernanceFailure?
        var entered: (() -> Void)?
        var pending: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        func response(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope = .init(clubID: 81)) throws -> ClubGovernanceSnapshot {
            let permission = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
                "roleCodes": .array([.string("CLUB_OWNER")]), "permissions": .array([]),
                "canManageRoles": .bool(operation == .members ? memberPermission : rolePermission)]), scope: scope)
            let value: ClubGovernanceValue
            if operation == .roles {
                let kind = scope.activityID == nil ? "CLUB" : "EVENT"
                let codes = scope.activityID == nil ? ["CLUB_OPERATOR", "CLUB_CO_OWNER"] : ["EVENT_LEAD", "EVENT_CHECKIN"]
                value = .object(["roles": .array(codes.map { .object(["roleCode": .string($0), "scopeType": .string(kind),
                    "name": .string($0), "permissions": .array([])]) }), "assignments": .array([])])
            } else {
                value = .array([.object(["memberId": .integer(memberID), "nickname": .string("Member"), "isOwner": .bool(false)])])
            }
            return .init(operation: operation, scope: scope, permissions: permission, value: value)
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            resources.append(operation); XCTAssertTrue(options.isEmpty)
            if let failure { throw failure }
            if operation == held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
            return try response(operation, scope: scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1; throw ClubGovernanceFailure.notConfigured
        }
    }
    private func context(_ access: Access, activityID: Int? = nil) -> ClubGovernanceReadContext {
        ClubRoleAssignmentReadModel.context(scope: .init(clubID: 81, activityID: activityID), identity: access.identity, access: access)
    }
    private func activate(_ model: ClubRoleAssignmentReadModel, _ context: ClubGovernanceReadContext) throws -> ClubRoleAssignmentReadModel.Permit {
        model.bind(context); return try XCTUnwrap(model.activate(context))
    }
    func testReadsRolesThenMembersFromExistingAccessWithoutWrites() async throws {
        let access = Access(), model = ClubRoleAssignmentReadModel(), expected = context(access)
        let permit = try activate(model, expected)
        await model.load(permit, access: access)
        XCTAssertEqual(access.resources, [.roles, .members]); XCTAssertEqual(access.sends, 0)
        XCTAssertEqual(model.accepted(expected, access: access)?.members.map(\.id), [41])
        XCTAssertFalse(model.loading); XCTAssertNil(model.failure)
    }
    func testDeniedRoleManagementCannotDispatchMemberRead() async throws {
        let access = Access(), model = ClubRoleAssignmentReadModel(); access.rolePermission = false
        let permit = try activate(model, context(access)); await model.load(permit, access: access)
        XCTAssertEqual(access.resources, [.roles]); XCTAssertNil(model.options); XCTAssertEqual(model.failure, .forbidden)
    }
    func testAuthorityRevokedBetweenReadsCannotPublishOptions() async throws {
        let access = Access(), model = ClubRoleAssignmentReadModel(); access.memberPermission = false
        let permit = try activate(model, context(access)); await model.load(permit, access: access)
        XCTAssertEqual(access.resources, [.roles, .members]); XCTAssertNil(model.options); XCTAssertEqual(model.failure, .forbidden)
    }
    func testIdentityChangeWhileRolesAwaitPreventsSecondDispatch() async throws {
        let access = Access(), model = ClubRoleAssignmentReadModel(); access.held = .roles
        let permit = try activate(model, context(access)), started = expectation(description: "roles")
        access.entered = { started.fulfill() }
        let task = Task { await model.load(permit, access: access) }; await fulfillment(of: [started], timeout: 1)
        access.identity = .init(accountID: 702, epoch: 2)
        access.pending[0].resume(returning: try access.response(.roles)); await task.value
        XCTAssertEqual(access.resources, [.roles]); XCTAssertNil(model.options); XCTAssertFalse(model.loading)
    }
    func testNewerReadWinsAndOldRenderedSelectionNonceIsRetired() async throws {
        let access = Access(), model = ClubRoleAssignmentReadModel(), expected = context(access)
        let permit = try activate(model, expected); await model.load(permit, access: access)
        let oldOptions = try XCTUnwrap(model.options), oldID = model.snapshotID
        access.held = .members
        let first = expectation(description: "first"), second = expectation(description: "second")
        access.entered = { access.pending.count == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await model.load(permit, access: access) }; await fulfillment(of: [first], timeout: 1)
        let new = Task { await model.load(permit, access: access) }; await fulfillment(of: [second], timeout: 1)
        access.memberID = 43; access.pending[1].resume(returning: try access.response(.members)); await new.value
        access.memberID = 41; access.pending[0].resume(returning: try access.response(.members)); await old.value
        XCTAssertEqual(model.options?.members.map(\.id), [43])
        XCTAssertFalse(model.canSelect(oldOptions, snapshotID: oldID, permit: permit, access: access)); XCTAssertNil(model.failure)
    }
    func testScopeReplacementRetiresOldRetryBeforeItCanClearNewOptions() async throws {
        let access = Access(), model = ClubRoleAssignmentReadModel()
        let oldContext = context(access), oldPermit = try activate(model, context(access))
        await model.load(oldPermit, access: access)
        let current = context(access, activityID: 205), next = try activate(model, context(access, activityID: 205))
        await model.load(next, access: access)
        let reads = access.resources.count
        await model.load(oldPermit, access: access)
        XCTAssertEqual(access.resources.count, reads); XCTAssertNotNil(model.accepted(current, access: access))
        XCTAssertNil(model.accepted(oldContext, access: access)); XCTAssertEqual(model.options?.roles.first?.code, "EVENT_LEAD")
    }
    func testBothCurrentChoicesRequiredBeforeReviewAndAuthorityLossDisables() async throws {
        let access = Access(), model = ClubRoleAssignmentReadModel(), expected = context(access)
        let permit = try activate(model, expected); await model.load(permit, access: access)
        func ready(_ member: String, _ role: String) -> Bool {
            model.canPrepare(scope: expected.scope, identity: expected.identity, access: access, memberID: member, roleCode: role)
        }
        XCTAssertFalse(ready("", "CLUB_OPERATOR")); XCTAssertFalse(ready("41", ""))
        XCTAssertFalse(ready("99", "CLUB_OPERATOR")); XCTAssertFalse(ready("41", "EVENT_LEAD"))
        XCTAssertTrue(ready("41", "CLUB_OPERATOR"))
        access.authorizationGeneration = UUID(); XCTAssertFalse(ready("41", "CLUB_OPERATOR"))
    }
    func testLeavingCancelsPublicationAndOldCallbacksCannotDispatchOnReopen() async throws {
        let access = Access(), model = ClubRoleAssignmentReadModel(), expected = context(access)
        access.held = .members
        let permit = try activate(model, expected), started = expectation(description: "members")
        access.entered = { started.fulfill() }
        let task = Task { await model.load(permit, access: access) }; await fulfillment(of: [started], timeout: 1)
        model.leave(expected); _ = model.activate(expected)
        access.pending[0].resume(returning: try access.response(.members)); await task.value
        await model.load(permit, access: access)
        XCTAssertEqual(access.resources, [.roles, .members]); XCTAssertNil(model.options); XCTAssertFalse(model.loading)
    }
    func testReadFailureAndRetryDoNotCreateSyntheticOptions() async throws {
        let access = Access(), model = ClubRoleAssignmentReadModel(), expected = context(access)
        let permit = try activate(model, expected); await model.load(permit, access: access)
        access.failure = .malformed; await model.load(permit, access: access)
        XCTAssertNil(model.options); XCTAssertEqual(model.failure, .malformed)
        access.failure = nil; await model.load(permit, access: access)
        XCTAssertNotNil(model.accepted(expected, access: access)); XCTAssertNil(model.failure)
    }
    func testRealExistingCoordinatorCanPrepareChosenCommandAndCancelWithoutSend() async throws {
        let access = Access(), model = ClubRoleAssignmentReadModel(), expected = context(access, activityID: 205)
        let permit = try activate(model, expected); await model.load(permit, access: access)
        XCTAssertTrue(model.canPrepare(scope: expected.scope, identity: expected.identity, access: access, memberID: "41", roleCode: "EVENT_LEAD"))
        var draft = ClubGovernanceFormDraft(operation: .assignRole, scope: expected.scope)
        draft.text["targetMemberId"] = "41"; draft.text["roleCode"] = "EVENT_LEAD"
        let coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(draft.command())
        XCTAssertEqual(review.command.fields["activityId"], .integer(205))
        XCTAssertEqual(review.command.fields["targetMemberId"], .integer(41))
        let proof = try XCTUnwrap(review.supportingMembers?.value.array?.first)
        XCTAssertEqual(proof["isOwner"], .bool(false))
        coordinator.cancelReview()
        XCTAssertEqual(access.resources, [.roles, .members, .roles, .members]); XCTAssertEqual(access.sends, 0)
        XCTAssertFalse(access.canDispatch(review.command))
    }
}

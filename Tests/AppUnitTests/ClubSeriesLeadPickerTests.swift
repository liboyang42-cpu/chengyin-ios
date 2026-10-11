import XCTest
@testable import Questify

@MainActor final class ClubSeriesLeadPickerTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "synthetic-series-lead"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var resources: [ClubGovernanceRead] = []
        var sends = 0, memberID = 41
        var allowed = true, held = false
        var failure: ClubGovernanceFailure?
        var entered: (() -> Void)?
        var pending: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        func response(_ operation: ClubGovernanceRead = .members, scope: ClubGovernanceScope = .init(clubID: 81, topicID: 91)) throws -> ClubGovernanceSnapshot {
            let permission = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
                "roleCodes": .array([]), "permissions": .array(allowed ? [.string("club:activity:manage")] : []), "canManageRoles": .bool(false)]), scope: scope)
            let value: ClubGovernanceValue = operation == .eventTopics ? .array([.object(["id": .integer(91)])]) :
                .array([.object(["memberId": .integer(memberID), "nickname": .string("Lead"), "isOwner": .bool(true)])])
            return .init(operation: operation, scope: scope, permissions: permission, value: value)
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            resources.append(operation); XCTAssertTrue(options.isEmpty)
            if let failure { throw failure }
            if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
            return try response(operation, scope: scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
    }
    private func context(_ access: Access, topicID: Int = 91) -> ClubSeriesLeadReadModel.Context {
        ClubSeriesLeadReadModel.context(scope: .init(clubID: 81, topicID: topicID), identity: access.identity, access: access)
    }
    private func activate(_ model: ClubSeriesLeadReadModel, _ context: ClubSeriesLeadReadModel.Context) throws -> ClubSeriesLeadReadModel.Permit {
        model.bind(context); return try XCTUnwrap(model.activate(context))
    }
    func testReadsActualMemberResourceAndRequiresExplicitChoiceWithoutWrites() async throws {
        let access = Access(), model = ClubSeriesLeadReadModel(), expected = context(access)
        let permit = try activate(model, expected); await model.load(permit, access: access)
        XCTAssertEqual(access.resources, [.members]); XCTAssertEqual(access.sends, 0)
        XCTAssertEqual(model.accepted(expected, access: access)?.members.map(\.id), [41])
        XCTAssertFalse(model.canPrepare(scope: expected.read.scope, identity: expected.read.identity, access: access, memberID: ""))
        XCTAssertTrue(model.canPrepare(scope: expected.read.scope, identity: expected.read.identity, access: access, memberID: "41"))
    }
    func testPermissionDeniedDoesNotPublishChoices() async throws {
        let access = Access(), model = ClubSeriesLeadReadModel(); access.allowed = false
        let permit = try activate(model, context(access)); await model.load(permit, access: access)
        XCTAssertEqual(model.failure, .forbidden); XCTAssertNil(model.options); XCTAssertEqual(access.sends, 0)
    }
    func testReadFailureRetryClearsOldOptionsAndRecoversWithoutSelecting() async throws {
        let access = Access(), model = ClubSeriesLeadReadModel(), expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access); access.failure = .malformed; await model.load(permit, access: access)
        XCTAssertNil(model.options); XCTAssertEqual(model.failure, .malformed)
        access.failure = nil; await model.load(permit, access: access)
        XCTAssertNotNil(model.accepted(expected, access: access)); XCTAssertNil(model.failure)
        XCTAssertFalse(model.canPrepare(scope: expected.read.scope, identity: expected.read.identity, access: access, memberID: ""))
    }
    func testRefreshRemovedMemberInvalidatesSelectionAndOldRenderedRow() async throws {
        let access = Access(), model = ClubSeriesLeadReadModel(), expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access); let old = try XCTUnwrap(model.options), nonce = model.snapshotID
        access.memberID = 43; await model.load(permit, access: access)
        XCTAssertFalse(model.canSelect(old, snapshotID: nonce, permit: permit, access: access))
        XCTAssertFalse(model.canPrepare(scope: expected.read.scope, identity: expected.read.identity, access: access, memberID: "41"))
        XCTAssertTrue(model.canPrepare(scope: expected.read.scope, identity: expected.read.identity, access: access, memberID: "43"))
    }
    func testIdentityChangesDuringReadCannotPublish() async throws {
        let access = Access(), model = ClubSeriesLeadReadModel(); access.held = true
        let expected = context(access), permit = try activate(model, expected), entered = expectation(description: "read")
        access.entered = { entered.fulfill() }; let task = Task { await model.load(permit, access: access) }
        await fulfillment(of: [entered], timeout: 1); access.identity = .init(accountID: 702, epoch: 2)
        access.pending[0].resume(returning: try access.response()); await task.value
        XCTAssertNil(model.accepted(expected, access: access)); XCTAssertNil(model.options)
    }
    func testNamespaceAndAuthorityChangesInvalidateAcceptedSelection() async throws {
        let access = Access(), model = ClubSeriesLeadReadModel(), expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access); let rows = try XCTUnwrap(model.options), nonce = model.snapshotID
        access.storageNamespace = "new-realm"; XCTAssertFalse(model.canSelect(rows, snapshotID: nonce, permit: permit, access: access))
        access.storageNamespace = expected.namespace; access.authorizationGeneration = UUID()
        XCTAssertFalse(model.canSelect(rows, snapshotID: nonce, permit: permit, access: access))
    }
    func testNewerReadWinsAndOlderCompletionCannotReplaceNames() async throws {
        let access = Access(), model = ClubSeriesLeadReadModel(), expected = context(access), permit = try activate(model, expected)
        access.held = true; let first = expectation(description: "first"), second = expectation(description: "second")
        access.entered = { access.pending.count == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await model.load(permit, access: access) }; await fulfillment(of: [first], timeout: 1)
        let new = Task { await model.load(permit, access: access) }; await fulfillment(of: [second], timeout: 1)
        access.memberID = 43; access.pending[1].resume(returning: try access.response()); await new.value
        access.memberID = 41; access.pending[0].resume(returning: try access.response()); await old.value
        XCTAssertEqual(model.options?.members.map(\.id), [43]); XCTAssertFalse(model.loading)
    }
    func testLeaveAndReopenRetireOldPermitAndQueuedRetry() async throws {
        let access = Access(), model = ClubSeriesLeadReadModel(), expected = context(access), old = try activate(model, expected)
        await model.load(old, access: access); model.leave(expected); _ = model.activate(expected)
        let reads = access.resources.count; await model.load(old, access: access)
        XCTAssertEqual(access.resources.count, reads); XCTAssertNil(model.options)
    }
    func testScopeOrReaderReplacementCannotReuseOptions() async throws {
        let access = Access(), model = ClubSeriesLeadReadModel(), expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access)
        let other = Access(); other.authorizationGeneration = access.authorizationGeneration
        XCTAssertNil(model.accepted(expected, access: other))
        _ = try activate(model, context(access, topicID: 92)); XCTAssertNil(model.accepted(expected, access: access))
        let count = access.resources.count; await model.load(permit, access: access); XCTAssertEqual(access.resources.count, count)
    }
    func testExistingCoordinatorReviewsChosenOwnerAsLeadThenCancelsWithZeroWrites() async throws {
        let access = Access(), model = ClubSeriesLeadReadModel(), expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access)
        var draft = ClubGovernanceFormDraft(operation: .createSeries, scope: expected.read.scope)
        draft.text["defaultLeadMemberId"] = "41"
        let now = ISO8601DateFormatter().date(from: "2026-10-11T01:00:00Z")!
        var schedule = ClubSeriesScheduleDraft(form: draft, now: now); schedule.startDate = "2026-10-12"
        draft = try schedule.applying(to: draft, now: now)
        XCTAssertTrue(model.canPrepare(scope: draft.scope, identity: expected.read.identity, access: access, memberID: "41"))
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(draft.command())
        XCTAssertEqual(review.command.fields["defaultLeadMemberId"], .integer(41))
        let proof = try XCTUnwrap(review.supportingMembers?.value.array?.first); XCTAssertEqual(proof["isOwner"], .bool(true))
        coordinator.cancelReview(); XCTAssertEqual(access.resources, [.members, .eventTopics, .members]); XCTAssertEqual(access.sends, 0)
        XCTAssertFalse(access.canDispatch(review.command))
    }
}

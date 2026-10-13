import XCTest
@testable import Questify

@MainActor final class ClubCaseSubmissionReturnTests: XCTestCase {
    private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "synthetic-case-return"
        var authorizationGeneration: UUID? = UUID()
        var journalRealm: String { storageNamespace }
        var allowsOfflineWrites = true
        var reads = 0, sends = 0
        var readFailure: ClubGovernanceFailure?
        var sendFailure: ClubGovernanceFailure?
        var heldSend: CheckedContinuation<ClubGovernanceValue, Error>?
        var holdSend = false
        var entered: (() -> Void)?
        func snapshot(_ scope: ClubGovernanceScope) throws -> ClubGovernanceSnapshot {
            let permissions = try ClubGovernancePermissions(value: .object([
                "active": .bool(true), "club": .object(["id": .integer(scope.clubID ?? 81)]),
                "roleCodes": .array([]), "permissions": .array([]), "canManageRoles": .bool(false)
            ]), scope: scope)
            return .init(operation: .cases, scope: scope, permissions: permissions, value: .array([]))
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope,
                  options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            XCTAssertEqual(operation, .cases); XCTAssertTrue(options.isEmpty); reads += 1
            if let readFailure { throw readFailure }
            return try snapshot(scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1
            if let sendFailure { throw sendFailure }
            if holdSend { return try await withCheckedThrowingContinuation { heldSend = $0; entered?() } }
            return .null
        }
    }
    private let scope = ClubGovernanceScope(clubID: 81)
    private func context(_ access: Access, revision: UInt64 = 3) -> ClubGovernanceReadContext {
        .init(operation: .cases, scope: scope, identity: access.identity, viewerRevision: revision,
              authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
    }
    private func source(_ access: Access, generation: UInt64 = 4) throws -> ClubCaseSubmissionReturn.Source {
        try XCTUnwrap(.init(context: context(access), snapshot: access.snapshot(scope), generation: generation, access: access))
    }
    private func command(_ operation: ClubGovernanceMutation, request: String = "case-request-A") throws -> ClubGovernanceCommand {
        var values: [String: ClubGovernanceValue] = ["reason": .string("Synthetic reason"), "requestId": .string(request)]
        if operation == .report { values["targetType"] = .string("CLUB"); values["targetId"] = .integer(81) }
        return try .init(operation: operation, scope: scope, values: values)
    }
    private func fixture(_ operation: ClubGovernanceMutation = .report) async throws ->
        (Access, ClubCaseSubmissionReturn, ClubCaseSubmissionReturn.Source, ClubCaseSubmissionReturn.Item, ClubGovernanceCoordinator, ClubGovernanceReview) {
        let access = Access(), owner = ClubCaseSubmissionReturn(), source = try source(access)
        owner.open(operation, source: source, visible: true, active: true)
        let item = try XCTUnwrap(owner.item), coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(command(operation))
        XCTAssertTrue(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
        return (access, owner, source, item, coordinator, review)
    }
    private func acknowledge(_ f: (Access, ClubCaseSubmissionReturn, ClubCaseSubmissionReturn.Source, ClubCaseSubmissionReturn.Item, ClubGovernanceCoordinator, ClubGovernanceReview)) async throws {
        let (access, owner, source, item, coordinator, review) = f
        let result = try await coordinator.confirm(review)
        XCTAssertEqual(result, .null)
        owner.acknowledge(review, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertFalse(owner.isPresented); XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
        XCTAssertEqual(access.sends, 1)
    }
    func testReportAndAppealNullAcknowledgementReturnOnceWithoutUnlockOrAnotherSend() async throws {
        for operation in [ClubGovernanceMutation.report, .appeal] {
            let f = try await fixture(operation), (access, owner, source, item, coordinator, review) = f
            try await acknowledge(f)
            XCTAssertNil(owner.consume(source: source, visible: true, active: true))
            XCTAssertTrue(owner.dismissed(item, source: source, active: true))
            XCTAssertEqual(owner.consume(source: source, visible: true, active: true), source)
            XCTAssertNil(owner.consume(source: source, visible: true, active: true)); XCTAssertNil(owner.item)
            XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity)); XCTAssertEqual(access.sends, 1)
        }
    }
    func testDismissBeforeParentVisibleRetainsTicketUntilVisible() async throws {
        let f = try await fixture(), (_, owner, source, item, _, _) = f
        try await acknowledge(f); XCTAssertTrue(owner.dismissed(item, source: source, active: true))
        XCTAssertNil(owner.consume(source: source, visible: false, active: true)); XCTAssertNotNil(owner.item)
        XCTAssertEqual(owner.consume(source: source, visible: true, active: true), source)
    }
    func testParentVisibleBeforeDismissCannotConsumeEarly() async throws {
        let f = try await fixture(), (_, owner, source, item, _, _) = f
        try await acknowledge(f)
        XCTAssertNil(owner.consume(source: source, visible: true, active: true))
        owner.dismissed(item, source: source, active: true)
        XCTAssertEqual(owner.consume(source: source, visible: true, active: true), source)
    }
    func testCancelBeforeConfirmationNeverReturnsAndStartsNoSend() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        owner.binding(item, source: { source }, active: { true }).wrappedValue = false
        coordinator.cancelReview(); owner.dismissed(item, source: source, active: true)
        XCTAssertNil(owner.item); XCTAssertNil(owner.consume(source: source, visible: true, active: true))
        XCTAssertEqual(access.sends, 0); XCTAssertFalse(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testUnknownAfterSendCannotDismissReturnOrUnlock() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        access.sendFailure = .unknown(message: nil)
        do { _ = try await coordinator.confirm(review); XCTFail("Expected unknown") } catch {}
        owner.acknowledge(review, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.consume(source: source, visible: true, active: true))
        XCTAssertEqual(access.sends, 1); XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testReadPreflightFailureCannotBecomeAcknowledgement() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        access.readFailure = .forbidden
        do { _ = try await coordinator.confirm(review); XCTFail("Expected forbidden") } catch {}
        owner.acknowledge(review, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertEqual(coordinator.state, .rejected); XCTAssertEqual(access.sends, 0)
        XCTAssertFalse(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testRejectedConflictAndUnknownStatesCannotConsumeSuccessfulReturn() async throws {
        let (_, owner, source, item, _, review) = try await fixture()
        for state in [ClubGovernanceWriteState.rejected, .conflict, .unknown, .submitting, .reviewing] {
            owner.acknowledge(review, state: state, item: item, source: source, active: true)
            XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.consume(source: source, visible: true, active: true))
        }
    }
    func testOtherReviewRequestCannotAcknowledgeCurrentSubmission() async throws {
        let (access, owner, source, item, _, review) = try await fixture()
        let other = ClubGovernanceCoordinator(access: access)
        let replacement = try await other.prepare(command(.report, request: "case-request-B"))
        XCTAssertNotEqual(replacement.id, review.id)
        owner.acknowledge(replacement, state: .acknowledged, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.consume(source: source, visible: true, active: true))
    }
    func testReopenRejectsOldGetterSetterDismissAndAcknowledgement() async throws {
        let (_, owner, source, item, _, review) = try await fixture()
        let old = owner.binding(item, source: { source }, active: { true })
        old.wrappedValue = false; owner.dismissed(item, source: source, active: true)
        owner.open(.report, source: source, visible: true, active: true); let next = try XCTUnwrap(owner.item)
        XCTAssertNotEqual(next.id, item.id); XCTAssertFalse(old.wrappedValue)
        old.wrappedValue = false; owner.dismissed(item, source: source, active: true)
        owner.acknowledge(review, state: .acknowledged, item: item, source: source, active: true)
        XCTAssertEqual(owner.item?.id, next.id); XCTAssertTrue(owner.isPresented)
    }
    func testHiddenInactiveOtherOperationAndMissingSourceDoNotOpen() throws {
        let access = Access(), owner = ClubCaseSubmissionReturn(), source = try source(access)
        owner.open(.report, source: source, visible: false, active: true); XCTAssertNil(owner.item)
        owner.open(.appeal, source: source, visible: true, active: false); XCTAssertNil(owner.item)
        owner.open(.unban, source: source, visible: true, active: true); XCTAssertNil(owner.item)
        owner.open(.report, source: nil, visible: true, active: true); XCTAssertNil(owner.item)
        XCTAssertEqual(access.sends, 0); XCTAssertEqual(access.reads, 0)
    }
    func testGenerationReplacementInvalidatesOwnerAndPendingReturn() async throws {
        let f = try await fixture(), (access, owner, source, item, _, _) = f
        try await acknowledge(f); owner.dismissed(item, source: source, active: true)
        let replaced = try self.source(access, generation: source.generation + 1)
        owner.invalidateUnlessCurrent(source: replaced, active: true)
        XCTAssertNil(owner.item); XCTAssertNil(owner.consume(source: replaced, visible: true, active: true))
    }
    func testChangedIdentityAuthorizationNamespaceOrReaderRejectsOldSource() async throws {
        let (access, owner, source, item, _, review) = try await fixture()
        access.identity = .init(accountID: 799, epoch: 2)
        let changed = try self.source(access)
        owner.acknowledge(review, state: .acknowledged, item: item, source: changed, active: true)
        XCTAssertTrue(owner.isPresented); owner.invalidateUnlessCurrent(source: changed, active: true); XCTAssertNil(owner.item)
        let oldContext = source.context
        XCTAssertNil(ClubCaseSubmissionReturn.Source(context: oldContext, snapshot: source.snapshot, generation: 4, access: access))
        access.identity = oldContext.identity; access.authorizationGeneration = UUID()
        XCTAssertNil(ClubCaseSubmissionReturn.Source(context: oldContext, snapshot: source.snapshot, generation: 4, access: access))
        let another = Access(); another.identity = oldContext.identity; another.authorizationGeneration = oldContext.authorizationGeneration
        XCTAssertNil(ClubCaseSubmissionReturn.Source(context: oldContext, snapshot: source.snapshot, generation: 4, access: another))
        access.authorizationGeneration = oldContext.authorizationGeneration; access.storageNamespace = "replacement"
        XCTAssertNotEqual(try self.source(access), source)
    }
    func testLateAcknowledgementAfterParentRetiresCannotTouchReopenedForm() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        access.holdSend = true
        let entered = expectation(description: "send entered"); access.entered = { entered.fulfill() }
        let task = Task { try await coordinator.confirm(review) }
        await fulfillment(of: [entered], timeout: 1)
        owner.retire(); owner.open(.appeal, source: source, visible: true, active: true)
        let next = try XCTUnwrap(owner.item)
        access.heldSend?.resume(returning: .null); access.heldSend = nil; _ = try await task.value
        owner.acknowledge(review, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertEqual(owner.item?.id, next.id); XCTAssertTrue(owner.isPresented); XCTAssertEqual(access.sends, 1)
        XCTAssertNil(owner.consume(source: source, visible: true, active: true))
    }
    func testSignedOutUnconfiguredOrWrongSnapshotScopeHasNoSource() throws {
        let access = Access(), original = context(access), snapshot = try access.snapshot(scope)
        access.isConfigured = false
        XCTAssertNil(ClubCaseSubmissionReturn.Source(context: original, snapshot: snapshot, generation: 4, access: access))
        access.isConfigured = true; access.identity = nil
        XCTAssertNil(ClubCaseSubmissionReturn.Source(context: original, snapshot: snapshot, generation: 4, access: access))
        access.identity = original.identity
        let otherSnapshot = try access.snapshot(.init(clubID: 82))
        XCTAssertNil(ClubCaseSubmissionReturn.Source(context: original, snapshot: otherSnapshot, generation: 4, access: access))
    }
}

extension ClubCaseSubmissionReturnTests {
    func testConsumptionReservesReadUntilOnlyItsExactCompletion() async throws {
        let f = try await fixture(), (_, owner, source, item, _, _) = f
        try await acknowledge(f); owner.dismissed(item, source: source, active: true)
        XCTAssertEqual(owner.consume(source: source, visible: true, active: true), source)
        let readID = try XCTUnwrap(owner.readID)
        owner.open(.appeal, source: source, visible: true, active: true); XCTAssertNil(owner.item)
        owner.finishRead(UUID()); XCTAssertEqual(owner.readID, readID)
        XCTAssertNil(owner.consume(source: source, visible: true, active: true))
        owner.finishRead(readID); XCTAssertNil(owner.readID)
        owner.open(.appeal, source: source, visible: true, active: true); XCTAssertNotNil(owner.item)
    }
    func testOldReadCompletionCannotClearSuccessorReadAfterParentReturn() async throws {
        let f = try await fixture(), (access, owner, source, item, coordinator, _) = f
        try await acknowledge(f); owner.dismissed(item, source: source, active: true)
        _ = owner.consume(source: source, visible: true, active: true); let old = try XCTUnwrap(owner.readID)
        owner.retire(); owner.open(.appeal, source: source, visible: true, active: true)
        let next = try XCTUnwrap(owner.item), review = try await coordinator.prepare(command(.appeal))
        XCTAssertTrue(owner.begin(review, state: coordinator.state, item: next, source: source, active: true))
        _ = try await coordinator.confirm(review)
        owner.acknowledge(review, state: coordinator.state, item: next, source: source, active: true)
        owner.dismissed(next, source: source, active: true); _ = owner.consume(source: source, visible: true, active: true)
        let current = try XCTUnwrap(owner.readID); XCTAssertNotEqual(old, current)
        owner.finishRead(old); XCTAssertEqual(owner.readID, current); XCTAssertEqual(access.sends, 2)
    }
}

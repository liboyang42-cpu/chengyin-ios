import XCTest
@testable import Questify

@MainActor final class ClubRoleManagementReturnTests: XCTestCase {
    private typealias Owner = ClubRoleManagementReturn
    private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var storageNamespace = "synthetic-role-return"
        var isConfigured = true
        let allowsOfflineWrites = true
        var canManage = true
        var revoked = false, assigned = false
        var reads = 0, sends = 0
        var readFailure: ClubGovernanceFailure?, sendFailure: ClubGovernanceFailure?
        var holdReads = false, holdSend = false
        var heldReads: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        var heldSend: CheckedContinuation<ClubGovernanceValue, Error>?
        var readEntered: ((Int) -> Void)?, sendEntered: (() -> Void)?
        func snapshot(_ scope: ClubGovernanceScope, operation: ClubGovernanceRead = .roles) throws -> ClubGovernanceSnapshot {
            let permission = try ClubGovernancePermissions(value: .object(["active": .bool(true),
                "club": .object(["id": .integer(scope.clubID ?? 81)]), "roleCodes": .array([.string("CLUB_OWNER")]),
                "permissions": .array([]), "canManageRoles": .bool(canManage)]), scope: scope)
            if operation == .members {
                return .init(operation: operation, scope: scope, permissions: permission,
                    value: .array([.object(["memberId": .integer(41), "isOwner": .bool(false)]),
                                   .object(["memberId": .integer(42), "isOwner": .bool(false)])]))
            }
            let code = scope.activityID == nil ? "CLUB_OPERATOR" : "EVENT_CHECKIN"
            let kind = scope.activityID == nil ? "CLUB" : "EVENT"
            func row(_ id: Int, _ member: Int) -> ClubGovernanceValue {
                .object(["id": .integer(id), "targetMemberId": .integer(member), "version": .integer(4),
                         "roleCode": .string(code), "scopeType": .string(kind), "scopeId": .integer(scope.activityID ?? scope.clubID ?? 81)])
            }
            var assignments: [ClubGovernanceValue] = revoked ? [] : [row(91, 41)]
            if assigned { assignments.append(row(92, 42)) }
            return .init(operation: .roles, scope: scope, permissions: permission, value: .object([
                "roles": .array([.object(["roleCode": .string(code), "scopeType": .string(kind),
                                          "name": .string("Synthetic role"), "permissions": .array([])])]),
                "assignments": .array(assignments)]))
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope,
                  options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            XCTAssertTrue([ClubGovernanceRead.roles, .members].contains(operation)); XCTAssertTrue(options.isEmpty)
            reads += 1
            if let readFailure { throw readFailure }
            if holdReads { return try await withCheckedThrowingContinuation { heldReads.append($0); readEntered?(reads) } }
            return try snapshot(scope, operation: operation)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1
            if let sendFailure { throw sendFailure }
            if holdSend { return try await withCheckedThrowingContinuation { heldSend = $0; sendEntered?() } }
            if review.command.operation == .assignRole { assigned = true } else { revoked = true }
            return .null
        }
    }
    private func source(_ access: Access, activity: Int? = nil, generation: UInt64 = 3) throws -> Owner.Source {
        let scope = ClubGovernanceScope(clubID: 81, activityID: activity)
        let context = ClubGovernanceReadContext(operation: .roles, scope: scope, identity: access.identity, viewerRevision: 0,
            authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
        return try XCTUnwrap(.init(context: context, snapshot: access.snapshot(scope), generation: generation, access: access))
    }
    private func seed(_ operation: ClubGovernanceMutation) -> [String: ClubGovernanceValue] {
        operation == .revokeRole ? ["assignmentId": .integer(91), "version": .integer(4)] : [:]
    }
    private func command(_ operation: ClubGovernanceMutation, scope: ClubGovernanceScope, request: String = "role-request-A") throws -> ClubGovernanceCommand {
        var fields = seed(operation); fields["requestId"] = .string(request)
        if operation == .assignRole {
            fields["targetMemberId"] = .integer(42)
            fields["roleCode"] = .string(scope.activityID == nil ? "CLUB_OPERATOR" : "EVENT_CHECKIN")
        } else { fields["reason"] = .string("Remove synthetic delegation") }
        return try .init(operation: operation, scope: scope, values: fields)
    }
    private func fixture(_ operation: ClubGovernanceMutation = .assignRole, activity: Int? = nil) async throws ->
        (Access, Owner, Owner.Source, Owner.Item, ClubGovernanceCoordinator, ClubGovernanceReview) {
        let access = Access(), owner = Owner(), source = try source(access, activity: activity)
        owner.appear(); owner.open(operation, seed: seed(operation), source: source, active: true)
        let item = try XCTUnwrap(owner.item), coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(command(operation, scope: source.context.scope))
        XCTAssertTrue(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
        return (access, owner, source, item, coordinator, review)
    }
    private func acknowledge(_ f: (Access, Owner, Owner.Source, Owner.Item, ClubGovernanceCoordinator, ClubGovernanceReview)) async throws {
        let (_, owner, source, item, coordinator, review) = f
        let receipt = try await coordinator.confirm(review); XCTAssertEqual(receipt, .null)
        owner.acknowledge(review, receipt: receipt, state: coordinator.state, item: item, source: source, active: true)
    }
    func testAssignAndRevokeBothClubAndEventReturnOnlyTheirOwnFreshListOnce() async throws {
        for operation in [ClubGovernanceMutation.assignRole, .revokeRole] {
            for activity in [Optional<Int>.none, 205] {
                let f = try await fixture(operation, activity: activity), (access, owner, source, item, coordinator, review) = f
                try await acknowledge(f); XCTAssertFalse(owner.isPresented)
                owner.dismissed(item, source: source, active: true)
                let ticket = try XCTUnwrap(owner.consume(source: source, active: true))
                let reader = ClubRoleListRead()
                let result = try await reader.load(context: ticket.source.context, access: access, check: {})
                XCTAssertEqual(result.scope, source.context.scope)
                XCTAssertEqual(result.value["assignments"].array?.count, operation == .assignRole ? 2 : 0)
                XCTAssertEqual(access.sends, 1); XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
                owner.finishRead(ticket); XCTAssertNil(owner.consume(source: source, active: true))
            }
        }
    }
    func testNullAcknowledgementNeedsNoInventedAssignmentID() async throws {
        let f = try await fixture(.revokeRole), (_, owner, source, item, _, _) = f
        try await acknowledge(f); owner.dismissed(item, source: source, active: true)
        XCTAssertNotNil(owner.consume(source: source, active: true))
    }
    func testCancelNeverConsumesSuccessOrSends() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        owner.binding(item, source: { source }, active: { true }).wrappedValue = false
        coordinator.cancelReview(); owner.dismissed(item, source: source, active: true)
        XCTAssertNil(owner.item); XCTAssertNil(owner.consume(source: source, active: true))
        XCTAssertEqual(access.sends, 0); XCTAssertFalse(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testUnknownSendDoesNotAutomaticallyReturnOrUnlock() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture(.revokeRole)
        access.sendFailure = .unknown(message: nil)
        do { _ = try await coordinator.confirm(review); XCTFail("Expected unknown") } catch {}
        owner.acknowledge(review, receipt: .null, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.consume(source: source, active: true))
        owner.binding(item, source: { source }, active: { true }).wrappedValue = false
        owner.dismissed(item, source: source, active: true)
        XCTAssertNil(owner.consume(source: source, active: true)); XCTAssertEqual(access.sends, 1)
        XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testPreflightFailureLeavesOriginalFailureWithoutSending() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        access.readFailure = .forbidden
        do { _ = try await coordinator.confirm(review); XCTFail("Expected forbidden") } catch {}
        owner.acknowledge(review, receipt: .null, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertEqual(access.sends, 0); XCTAssertEqual(coordinator.state, .rejected)
    }
    func testReturnReadFailureDoesNotUndoAcknowledgementOrResend() async throws {
        let f = try await fixture(), (access, owner, source, item, coordinator, review) = f
        try await acknowledge(f); owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, active: true)); access.readFailure = .forbidden
        do { _ = try await ClubRoleListRead().load(context: ticket.source.context, access: access, check: {}); XCTFail("Expected read failure") } catch {}
        owner.finishRead(ticket); XCTAssertEqual(access.sends, 1); XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testWrongReviewRequestAndMutationCannotAcknowledgeCurrentRoute() async throws {
        let (access, owner, source, item, _, original) = try await fixture(.revokeRole)
        let coordinator = ClubGovernanceCoordinator(access: access)
        let other = try await coordinator.prepare(command(.assignRole, scope: source.context.scope, request: "role-request-B"))
        XCTAssertNotEqual(other.id, original.id)
        XCTAssertFalse(owner.begin(other, state: coordinator.state, item: item, source: source, active: true))
        owner.acknowledge(other, receipt: .null, state: .acknowledged, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented)
    }
    func testRevokeEntryRequiresExactCurrentAssignmentAndVersion() throws {
        let access = Access(), owner = Owner(), source = try source(access); owner.appear()
        for seed: [String: ClubGovernanceValue] in [[:], ["assignmentId": .integer(92), "version": .integer(4)], ["assignmentId": .integer(91), "version": .integer(5)]] {
            owner.open(.revokeRole, seed: seed, source: source, active: true); XCTAssertNil(owner.item)
        }
        owner.open(.assignRole, seed: ["targetMemberId": .integer(42)], source: source, active: true); XCTAssertNil(owner.item)
        XCTAssertEqual(access.sends, 0); XCTAssertEqual(access.reads, 0)
    }
    func testBothDismissAndVisibleOrdersConsumeExactlyOnce() async throws {
        for hidden in [false, true] {
            let f = try await fixture(), (_, owner, source, item, _, _) = f
            if hidden { owner.hide() }
            try await acknowledge(f); XCTAssertNil(owner.consume(source: source, active: true))
            owner.dismissed(item, source: source, active: true)
            if hidden { XCTAssertNil(owner.consume(source: source, active: true)); owner.appear() }
            XCTAssertNotNil(owner.consume(source: source, active: true)); XCTAssertNil(owner.consume(source: source, active: true))
        }
    }
    func testOldBindingDismissalAndAckCannotConsumeReopenedRoute() async throws {
        let (_, owner, source, item, _, review) = try await fixture()
        let old = owner.binding(item, source: { source }, active: { true }); owner.retire()
        owner.open(.revokeRole, seed: seed(.revokeRole), source: source, active: true)
        let fresh = try XCTUnwrap(owner.item); XCTAssertNotEqual(fresh.id, item.id); XCTAssertFalse(old.wrappedValue)
        old.wrappedValue = false; owner.dismissed(item, source: source, active: true)
        owner.acknowledge(review, receipt: .null, state: .acknowledged, item: item, source: source, active: true)
        XCTAssertEqual(owner.item?.id, fresh.id); XCTAssertTrue(owner.isPresented)
    }
    func testLateSendAfterRealDepartureCannotTouchNewOwner() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        access.holdSend = true; let entered = expectation(description: "send")
        access.sendEntered = { entered.fulfill() }
        let task = Task { try await coordinator.confirm(review) }
        await fulfillment(of: [entered], timeout: 1)
        owner.depart(try XCTUnwrap(owner.attachment), reads: ClubRoleListRead()) {}
        owner.appear(); owner.open(.revokeRole, seed: seed(.revokeRole), source: source, active: true)
        let fresh = try XCTUnwrap(owner.item)
        access.heldSend?.resume(returning: .null); access.heldSend = nil; let receipt = try await task.value
        owner.acknowledge(review, receipt: receipt, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertEqual(owner.item?.id, fresh.id); XCTAssertTrue(owner.isPresented); XCTAssertEqual(access.sends, 1)
    }
    func testHiddenInactiveUnconfiguredAndWrongIdentitySourcesCannotOpen() throws {
        let access = Access(), owner = Owner(), source = try source(access)
        owner.open(.assignRole, seed: [:], source: source, active: true); XCTAssertNil(owner.item)
        owner.appear(); owner.hide(); owner.open(.assignRole, seed: [:], source: source, active: true); XCTAssertNil(owner.item)
        owner.appear(); owner.open(.assignRole, seed: [:], source: source, active: false); XCTAssertNil(owner.item)
        access.isConfigured = false
        XCTAssertNil(Owner.Source(context: source.context, snapshot: source.snapshot, generation: 3, access: access))
        access.isConfigured = true; access.identity = .init(accountID: 799, epoch: 2)
        XCTAssertNil(Owner.Source(context: source.context, snapshot: source.snapshot, generation: 3, access: access))
    }
    func testRevokedManagementOrWrongActivitySnapshotCannotSupplySource() throws {
        let access = Access(), source = try source(access, activity: 205)
        access.canManage = false
        XCTAssertNil(Owner.Source(context: source.context, snapshot: try access.snapshot(source.context.scope), generation: 3, access: access))
        access.canManage = true
        XCTAssertNil(Owner.Source(context: source.context, snapshot: try access.snapshot(.init(clubID: 81, activityID: 206)), generation: 3, access: access))
    }
    func testChangedGenerationRejectsPendingSuccess() async throws {
        let f = try await fixture(), (_, owner, source, item, _, _) = f
        try await acknowledge(f); owner.dismissed(item, source: source, active: true)
        owner.invalidateUnlessCurrent(source: nil, active: true)
        XCTAssertNil(owner.item); XCTAssertNil(owner.consume(source: source, active: true))
    }
    func testLoadingContextReplacementStartsFreshWhileOldReadIsHeld() async throws {
        let access = Access(), reader = ClubRoleListRead(), first = try source(access).context
        access.holdReads = true
        let a = expectation(description: "old read"), b = expectation(description: "new read")
        access.readEntered = { n in if n == 1 { a.fulfill() } else { b.fulfill() } }
        let old = Task { try await reader.load(context: first, access: access, check: {}) }
        await fulfillment(of: [a], timeout: 1)
        access.identity = .init(accountID: 799, epoch: 2); let second = try source(access).context
        XCTAssertTrue(reader.synchronize(second)); XCTAssertFalse(reader.loading)
        let next = Task { try await reader.load(context: second, access: access, check: {}) }
        await fulfillment(of: [b], timeout: 1)
        access.heldReads[0].resume(returning: try access.snapshot(first.scope))
        do { _ = try await old.value; XCTFail("Old read") } catch {}
        XCTAssertTrue(reader.loading); XCTAssertEqual(reader.context, second)
        access.heldReads[1].resume(returning: try access.snapshot(second.scope)); _ = try await next.value
        XCTAssertFalse(reader.loading); XCTAssertEqual(access.reads, 2); XCTAssertEqual(access.sends, 0)
    }
    func testActualDepartureRetiresLoadingAndOldAttachmentCannotRetireReplacement() async throws {
        let access = Access(), reader = ClubRoleListRead(), owner = Owner(), context = try source(access).context
        owner.appear(); let oldAttachment = try XCTUnwrap(owner.attachment)
        access.holdReads = true
        let a = expectation(description: "old read"), b = expectation(description: "new read")
        access.readEntered = { n in if n == 1 { a.fulfill() } else { b.fulfill() } }
        let old = Task { try await reader.load(context: context, access: access, check: {}) }
        await fulfillment(of: [a], timeout: 1)
        var resets = 0; owner.depart(oldAttachment, reads: reader) { resets += 1 }
        XCTAssertEqual(resets, 1); XCTAssertFalse(reader.loading); owner.appear()
        let next = Task { try await reader.load(context: context, access: access, check: {}) }
        await fulfillment(of: [b], timeout: 1)
        owner.depart(oldAttachment, reads: reader) { resets += 1 }
        XCTAssertEqual(resets, 1); XCTAssertTrue(reader.loading)
        access.heldReads[0].resume(throwing: ClubGovernanceFailure.forbidden)
        do { _ = try await old.value; XCTFail("Old read") } catch {}
        XCTAssertTrue(reader.loading)
        access.heldReads[1].resume(returning: try access.snapshot(context.scope)); _ = try await next.value
        XCTAssertFalse(reader.loading); XCTAssertEqual(access.sends, 0)
    }
    func testForegroundFreshReadDoesNotReviveRetiredReviewAndKeepsCurrentScope() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture(.revokeRole, activity: 205)
        let reader = ClubRoleListRead(); reader.synchronize(source.context)
        owner.retire(); reader.retire()
        XCTAssertTrue(owner.visible); XCTAssertFalse(owner.retainsReturn)
        let fresh = try await reader.load(context: source.context, access: access, check: {})
        XCTAssertEqual(fresh.scope, source.context.scope); XCTAssertFalse(reader.loading)
        owner.acknowledge(review, receipt: .null, state: .acknowledged, item: item, source: source, active: true)
        XCTAssertNil(owner.item); XCTAssertNil(owner.consume(source: source, active: true))
        XCTAssertEqual(access.sends, 0); XCTAssertFalse(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testForegroundCheckCannotReadFromHiddenOrDepartedParent() async throws {
        let access = Access(), owner = Owner(), reader = ClubRoleListRead(), context = try source(access).context
        owner.appear(); owner.hide(); owner.retire(); reader.retire()
        func foregroundRead() async throws {
            guard owner.visible, !owner.retainsReturn else { return }
            _ = try await reader.load(context: context, access: access, check: {})
        }
        try await foregroundRead(); XCTAssertEqual(access.reads, 0)
        owner.depart(try XCTUnwrap(owner.attachment), reads: reader) {}
        try await foregroundRead(); XCTAssertEqual(access.reads, 0); XCTAssertEqual(access.sends, 0)
        owner.appear(); try await foregroundRead(); XCTAssertEqual(access.reads, 1)
    }

}

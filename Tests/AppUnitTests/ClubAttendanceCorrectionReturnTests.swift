import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ClubAttendanceCorrectionReturnTests: XCTestCase {
    private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "synthetic-attendance-return"
        var authorizationGeneration: UUID? = UUID()
        let allowsOfflineWrites = true
        var reads = 0, sends = 0, version = 4
        var arrived = false
        var allowed = true
        var readFailure: ClubGovernanceFailure?
        var sendFailure: ClubGovernanceFailure?
        var holdSend = false
        var holdReads = false
        var readEntered: ((Int) -> Void)?
        var heldReads: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        var entered: (() -> Void)?
        var heldSend: CheckedContinuation<ClubGovernanceValue, Error>?
        func response(_ scope: ClubGovernanceScope) throws -> ClubGovernanceSnapshot {
            let permissions = try ClubGovernancePermissions(value: .object([
                "active": .bool(true), "club": .object(["id": .integer(scope.clubID ?? 81)]),
                "roleCodes": .array([]), "permissions": .array(allowed ? [.string("club:event:checkin")] : []),
                "canManageRoles": .bool(false)
            ]), scope: scope)
            let member: ClubGovernanceValue = .object(["memberId": .integer(41), "nickname": .string("Member"), "correctionVersion": .integer(version)])
            return .init(operation: .roster, scope: scope, permissions: permissions, value: .object([
                "phoneIncluded": .bool(false), "registered": .array(arrived ? [] : [member]),
                "arrived": .array(arrived ? [member] : []), "noShow": .array([]), "waitlist": .array([])
            ]))
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope,
                  options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            XCTAssertEqual(operation, .roster); XCTAssertTrue(options.isEmpty); reads += 1
            if let readFailure { throw readFailure }
            if holdReads { return try await withCheckedThrowingContinuation { heldReads.append($0); readEntered?(reads) } }
            return try response(scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1
            if let sendFailure { throw sendFailure }
            if holdSend { return try await withCheckedThrowingContinuation { heldSend = $0; entered?() } }
            arrived = review.command.fields["arrived"] == .bool(true); version += 1
            return .object(["id": .integer(211)])
        }
    }
    private typealias Owner = ClubAttendanceCorrectionReturn
    private let scope = ClubGovernanceScope(clubID: 81, activityID: 205)
    private func source(_ access: Access, generation: UInt64 = 3, bucket: ClubRosterBucket = .registered) throws -> Owner.Source {
        let context = ClubGovernanceReadContext(operation: .roster, scope: scope, identity: access.identity, viewerRevision: 0,
            authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
        return try XCTUnwrap(.init(context: context, snapshot: access.response(scope), generation: generation, bucket: bucket, access: access))
    }
    private func target(_ source: Owner.Source) throws -> ClubRosterCorrectionRoute {
        let roster = try ClubRosterPresentation(snapshot: source.snapshot, context: source.context)
        return try XCTUnwrap(roster.correctionRoute(memberID: 41, bucket: source.bucket,
            context: source.context, snapshotGeneration: source.generation, namespace: source.namespace))
    }
    private func open(_ owner: Owner, _ access: Access, _ source: Owner.Source) throws -> Owner.Item {
        owner.open(try target(source), source: source, access: access, active: true)
        return try XCTUnwrap(owner.item)
    }
    private func command(_ item: Owner.Item, request: String = "attendance-request-A") throws -> ClubGovernanceCommand {
        try .init(operation: .correctAttendance, scope: item.route.scope,
            values: ["expectedVersion": .integer(4), "arrived": .bool(true),
                     "reason": .string("Correct attendance"), "requestId": .string(request)])
    }
    private func fixture() async throws -> (Access, Owner, Owner.Source, Owner.Item, ClubGovernanceCoordinator, ClubGovernanceReview) {
        let access = Access(), owner = Owner(), source = try source(access)
        owner.appear(); let item = try open(owner, access, source), coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(command(item))
        XCTAssertTrue(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
        return (access, owner, source, item, coordinator, review)
    }
    private func acknowledge(_ f: (Access, Owner, Owner.Source, Owner.Item, ClubGovernanceCoordinator, ClubGovernanceReview)) async throws {
        let (_, owner, source, item, coordinator, review) = f
        let receipt = try await coordinator.confirm(review)
        owner.acknowledge(review, receipt: receipt, state: coordinator.state, item: item, source: source, active: true)
    }
    func testFullAcknowledgedFlowReadsSameActivityKeepsBucketAndNeverUnlocks() async throws {
        let f = try await fixture(), (access, owner, source, item, coordinator, review) = f
        try await acknowledge(f)
        XCTAssertFalse(owner.isPresented); XCTAssertTrue(owner.dismissed(item, source: source, active: true))
        let ticket = try XCTUnwrap(owner.consume(source: source, active: true))
        XCTAssertEqual(ticket.reason, .acknowledged); XCTAssertEqual(ticket.source.bucket, .registered)
        XCTAssertTrue(owner.isReading(ticket, context: source.context, active: true))
        let result = try await access.read(.roster, scope: ticket.source.context.scope, options: [:])
        let roster = try ClubRosterPresentation(snapshot: result, context: source.context)
        XCTAssertEqual(roster.count(in: .registered), 0); XCTAssertEqual(roster.members(in: .arrived).map(\.id), [41])
        XCTAssertEqual(result.scope, scope); XCTAssertEqual(access.reads, 3); XCTAssertEqual(access.sends, 1)
        XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
        owner.finishRead(ticket); XCTAssertNil(owner.readTicket); XCTAssertNil(owner.consume(source: source, active: true))
    }
    func testDismissBeforeParentVisibleWaitsForActualParentReturn() async throws {
        let f = try await fixture(), (_, owner, source, item, _, _) = f
        owner.hide(); try await acknowledge(f); owner.dismissed(item, source: source, active: true)
        XCTAssertNil(owner.consume(source: source, active: true)); XCTAssertNotNil(owner.item)
        owner.appear(); XCTAssertEqual(owner.consume(source: source, active: true)?.reason, .acknowledged)
    }
    func testParentVisibleBeforeDismissDoesNotReadTwice() async throws {
        let f = try await fixture(), (_, owner, source, item, _, _) = f
        try await acknowledge(f); owner.appear(); XCTAssertNil(owner.consume(source: source, active: true))
        owner.dismissed(item, source: source, active: true)
        XCTAssertNotNil(owner.consume(source: source, active: true)); XCTAssertNil(owner.consume(source: source, active: true))
    }
    func testCancellationPreservesOrdinaryReadButNeverClaimsAcknowledgementOrSends() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        owner.binding(item, source: { source }, active: { true }).wrappedValue = false
        coordinator.cancelReview(); owner.dismissed(item, source: source, active: true)
        XCTAssertEqual(owner.consume(source: source, active: true)?.reason, .dismissed)
        XCTAssertEqual(access.sends, 0); XCTAssertFalse(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testUnknownStaysOpenUntilExplicitCloseThenOnlyOrdinaryReadAndLockPersists() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        access.sendFailure = .unknown(message: nil)
        do { _ = try await coordinator.confirm(review); XCTFail("Expected unknown") } catch {}
        owner.acknowledge(review, receipt: .object(["id": .integer(211)]), state: coordinator.state, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.consume(source: source, active: true))
        owner.binding(item, source: { source }, active: { true }).wrappedValue = false
        owner.dismissed(item, source: source, active: true)
        XCTAssertEqual(owner.consume(source: source, active: true)?.reason, .dismissed)
        XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity)); XCTAssertEqual(access.sends, 1)
    }
    func testPreflightFailureCannotReturnAsSuccessOrSend() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        access.readFailure = .forbidden
        do { _ = try await coordinator.confirm(review); XCTFail("Expected forbidden") } catch {}
        owner.acknowledge(review, receipt: .object(["id": .integer(211)]), state: coordinator.state, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertEqual(access.sends, 0); XCTAssertEqual(coordinator.state, .rejected)
    }
    func testReadFailureAfterAcknowledgementDoesNotResubmitOrUnlock() async throws {
        let f = try await fixture(), (access, owner, source, item, coordinator, review) = f
        try await acknowledge(f); owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, active: true)); access.readFailure = .forbidden
        do { _ = try await access.read(.roster, scope: ticket.source.context.scope, options: [:]); XCTFail("Expected read failure") } catch {}
        owner.finishRead(ticket); XCTAssertNil(owner.consume(source: source, active: true))
        XCTAssertEqual(access.sends, 1); XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testMissingMalformedAndZeroReceiptIDsNeverAutoClose() async throws {
        let (_, owner, source, item, _, review) = try await fixture()
        for receipt in [ClubGovernanceValue.null, .object([:]), .object(["id": .integer(0)]), .object(["id": .string("unknown")])] {
            owner.acknowledge(review, receipt: receipt, state: .acknowledged, item: item, source: source, active: true)
            XCTAssertTrue(owner.isPresented)
        }
    }
    func testOtherReviewAndRequestCannotConsumeCurrentAcknowledgement() async throws {
        let (access, owner, source, item, _, original) = try await fixture()
        let other = ClubGovernanceCoordinator(access: access), review = try await other.prepare(command(item, request: "attendance-request-B"))
        XCTAssertNotEqual(original.id, review.id)
        owner.acknowledge(review, receipt: .object(["id": .integer(211)]), state: .acknowledged, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented)
    }
    func testRejectedConflictAndInFlightStatesDoNotAutoClose() async throws {
        let (_, owner, source, item, _, review) = try await fixture()
        for state in [ClubGovernanceWriteState.rejected, .conflict, .unknown, .submitting, .preflighting, .reviewing] {
            owner.acknowledge(review, receipt: .object(["id": .integer(211)]), state: state, item: item, source: source, active: true)
            XCTAssertTrue(owner.isPresented)
        }
    }
    func testOldBindingDismissalAndAckCannotTouchReopenedRoute() async throws {
        let (access, owner, source, item, _, review) = try await fixture()
        let old = owner.binding(item, source: { source }, active: { true })
        owner.retire(); let next = try open(owner, access, source)
        XCTAssertNotEqual(item.id, next.id); XCTAssertFalse(old.wrappedValue)
        old.wrappedValue = false; XCTAssertFalse(owner.dismissed(item, source: source, active: true))
        owner.acknowledge(review, receipt: .object(["id": .integer(211)]), state: .acknowledged, item: item, source: source, active: true)
        XCTAssertEqual(owner.item?.id, next.id); XCTAssertTrue(owner.isPresented)
    }
    func testRealDepartureBeforeLateSendReplyCannotCloseNewOwner() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        access.holdSend = true
        let entered = expectation(description: "send entered"); access.entered = { entered.fulfill() }
        let task = Task { try await coordinator.confirm(review) }
        await fulfillment(of: [entered], timeout: 1)
        owner.depart(try XCTUnwrap(owner.attachment)); owner.appear(); let next = try open(owner, access, source)
        access.heldSend?.resume(returning: .object(["id": .integer(211)])); access.heldSend = nil
        let receipt = try await task.value
        owner.acknowledge(review, receipt: receipt, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertEqual(owner.item?.id, next.id); XCTAssertTrue(owner.isPresented); XCTAssertEqual(access.sends, 1)
    }
    func testRowRecyclingDoesNotRetireWholePagePresentation() async throws {
        let (_, owner, source, item, _, _) = try await fixture()
        XCTAssertTrue(owner.current(item, source: source, active: true))
        owner.hide() // An own modal can cover the page; it is not a departure.
        XCTAssertTrue(owner.binding(item, source: { source }, active: { true }).wrappedValue)
        owner.appear(); XCTAssertEqual(owner.item?.id, item.id)
    }
    func testHiddenDetachedOrInactivePageCannotOpenFromOldRow() throws {
        let access = Access(), owner = Owner(), source = try source(access), target = try target(source)
        owner.open(target, source: source, access: access, active: true); XCTAssertNil(owner.item)
        owner.appear(); owner.hide(); owner.open(target, source: source, access: access, active: true); XCTAssertNil(owner.item)
        owner.appear(); owner.open(target, source: source, access: access, active: false); XCTAssertNil(owner.item)
        owner.depart(try XCTUnwrap(owner.attachment)); owner.open(target, source: source, access: access, active: true); XCTAssertNil(owner.item)
        XCTAssertEqual(access.reads, 0); XCTAssertEqual(access.sends, 0)
    }
    func testChangedFilterOrSnapshotGenerationRejectsOldReturn() async throws {
        let (access, owner, source, item, _, review) = try await fixture()
        let changedFilter = try XCTUnwrap(Owner.Source(context: source.context, snapshot: source.snapshot,
            generation: source.generation, bucket: .arrived, access: access))
        owner.acknowledge(review, receipt: .object(["id": .integer(211)]), state: .acknowledged,
                          item: item, source: changedFilter, active: true)
        XCTAssertTrue(owner.isPresented)
        let changedGeneration = try XCTUnwrap(Owner.Source(context: source.context, snapshot: source.snapshot,
            generation: source.generation + 1, bucket: source.bucket, access: access))
        owner.invalidateUnlessCurrent(source: changedGeneration, active: true)
        XCTAssertNil(owner.item); XCTAssertNil(owner.consume(source: source, active: true))
    }
    func testSourceRequiresCurrentReaderIdentityAuthorizationAndPermission() throws {
        let access = Access(), source = try source(access)
        access.identity = .init(accountID: 799, epoch: 2)
        XCTAssertNil(Owner.Source(context: source.context, snapshot: source.snapshot, generation: 3, bucket: .registered, access: access))
        access.identity = source.context.identity; access.authorizationGeneration = UUID()
        XCTAssertNil(Owner.Source(context: source.context, snapshot: source.snapshot, generation: 3, bucket: .registered, access: access))
        access.authorizationGeneration = source.context.authorizationGeneration; access.allowed = false
        XCTAssertNil(Owner.Source(context: source.context, snapshot: try access.response(scope), generation: 3, bucket: .registered, access: access))
        access.allowed = true; access.isConfigured = false
        XCTAssertNil(Owner.Source(context: source.context, snapshot: source.snapshot, generation: 3, bucket: .registered, access: access))
    }
    func testReadTicketFencesOldCompletionHiddenPageAndDifferentContext() async throws {
        let f = try await fixture(), (_, owner, source, item, _, _) = f
        try await acknowledge(f); owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, active: true))
        owner.hide(); XCTAssertFalse(owner.isReading(ticket, context: source.context, active: true))
        owner.appear(); XCTAssertTrue(owner.isReading(ticket, context: source.context, active: true))
        owner.depart(ticket.attachment); owner.appear(); owner.finishRead(ticket)
        XCTAssertNil(owner.readTicket); XCTAssertFalse(owner.isReading(ticket, context: source.context, active: true))
    }
    func testOldAttachmentDepartureCannotRetireNewPresentation() throws {
        let access = Access(), owner = Owner(), source = try source(access)
        owner.appear(); let old = try XCTUnwrap(owner.attachment); owner.depart(old)
        owner.appear(); let item = try open(owner, access, source); owner.depart(old)
        XCTAssertEqual(owner.item?.id, item.id); XCTAssertTrue(owner.visible)
    }
    private func exerciseReplacedLoadingContext(oldFails: Bool, changeAuthorization: Bool) async throws {
        let access = Access(), reader = ClubAttendanceRosterRead(), first = try source(access).context
        access.holdReads = true
        let oldEntered = expectation(description: "old roster read entered")
        let newEntered = expectation(description: "replacement roster read entered")
        access.readEntered = { count in if count == 1 { oldEntered.fulfill() } else if count == 2 { newEntered.fulfill() } }
        let old = Task { try await reader.load(context: first, access: access, check: {}) }
        await fulfillment(of: [oldEntered], timeout: 1); XCTAssertTrue(reader.loading)
        if changeAuthorization { access.authorizationGeneration = UUID() }
        else { access.identity = .init(accountID: 799, epoch: 2) }
        let second = try source(access).context
        XCTAssertTrue(reader.synchronize(second)); XCTAssertFalse(reader.loading)
        let next = Task { try await reader.load(context: second, access: access, check: {}) }
        await fulfillment(of: [newEntered], timeout: 1); XCTAssertTrue(reader.loading)
        XCTAssertEqual(access.reads, 2)
        if oldFails { access.heldReads[0].resume(throwing: ClubGovernanceFailure.forbidden) }
        else { access.heldReads[0].resume(returning: try access.response(scope)) }
        do { _ = try await old.value; XCTFail("Retired roster read must not publish") } catch {}
        XCTAssertTrue(reader.loading); XCTAssertEqual(reader.context, second)
        access.heldReads[1].resume(returning: try access.response(scope))
        let result = try await next.value
        XCTAssertEqual(result.scope, scope); XCTAssertFalse(reader.loading); XCTAssertEqual(reader.context, second)
        XCTAssertEqual(access.reads, 2); XCTAssertEqual(access.sends, 0)
    }
    func testActualRosterLoadingOwnerStartsNewAccountReadWhileOldResponseIsPending() async throws {
        try await exerciseReplacedLoadingContext(oldFails: false, changeAuthorization: false)
    }
    func testOldReadFailureCannotClearNewAuthorizationReadLoading() async throws {
        try await exerciseReplacedLoadingContext(oldFails: true, changeAuthorization: true)
    }
    func testRetiredHiddenReadCanRestartSameContextAndOldCompletionCannotClearNewLoading() async throws {
        let access = Access(), reader = ClubAttendanceRosterRead(), context = try source(access).context
        access.holdReads = true
        let firstEntered = expectation(description: "first read"), secondEntered = expectation(description: "second read")
        access.readEntered = { count in if count == 1 { firstEntered.fulfill() } else { secondEntered.fulfill() } }
        let first = Task { try await reader.load(context: context, access: access, check: {}) }
        await fulfillment(of: [firstEntered], timeout: 1)
        let owner = Owner(); owner.appear(); var resets = 0
        owner.depart(try XCTUnwrap(owner.attachment), reads: reader) { resets += 1 }
        XCTAssertEqual(resets, 1); XCTAssertFalse(reader.loading); XCTAssertFalse(owner.visible)
        owner.appear()
        let second = Task { try await reader.load(context: context, access: access, check: {}) }
        await fulfillment(of: [secondEntered], timeout: 1)
        access.heldReads[0].resume(returning: try access.response(scope))
        do { _ = try await first.value; XCTFail("Retired read") } catch {}
        XCTAssertTrue(reader.loading)
        access.heldReads[1].resume(returning: try access.response(scope)); _ = try await second.value
        XCTAssertFalse(reader.loading); XCTAssertEqual(access.reads, 2); XCTAssertEqual(access.sends, 0)
    }
    func testRosterReadOwnerRejectsMismatchedResponseAndClosesOnlyItsOwnLoading() async throws {
        let access = Access(), reader = ClubAttendanceRosterRead(), context = try source(access).context
        access.holdReads = true; let entered = expectation(description: "read")
        access.readEntered = { _ in entered.fulfill() }
        let task = Task { try await reader.load(context: context, access: access, check: {}) }
        await fulfillment(of: [entered], timeout: 1)
        access.heldReads[0].resume(returning: try access.response(.init(clubID: 81, activityID: 206)))
        do { _ = try await task.value; XCTFail("Mismatched activity") }
        catch { XCTAssertEqual(error as? ClubGovernanceFailure, .targetChanged) }
        XCTAssertFalse(reader.loading); XCTAssertEqual(access.sends, 0)
    }

    func testOldAttachmentDepartureCannotRetireReplacementReadOrResetParent() async throws {
        let access = Access(), reader = ClubAttendanceRosterRead(), owner = Owner(), context = try source(access).context
        owner.appear(); let old = try XCTUnwrap(owner.attachment)
        owner.depart(old, reads: reader) {}; owner.appear()
        access.holdReads = true; let entered = expectation(description: "new read")
        access.readEntered = { _ in entered.fulfill() }
        let task = Task { try await reader.load(context: context, access: access, check: {}) }
        await fulfillment(of: [entered], timeout: 1)
        var resets = 0
        owner.depart(old, reads: reader) { resets += 1 }
        XCTAssertEqual(resets, 0); XCTAssertTrue(owner.visible); XCTAssertTrue(reader.loading)
        access.heldReads[0].resume(returning: try access.response(scope)); _ = try await task.value
        XCTAssertFalse(reader.loading); XCTAssertEqual(access.sends, 0)
    }
    func testForegroundFreshReadDoesNotReviveRetiredReviewAndKeepsCurrentScope() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        let reader = ClubAttendanceRosterRead(); reader.synchronize(source.context)
        owner.retire(); reader.retire()
        XCTAssertTrue(owner.visible); XCTAssertFalse(owner.retainsReturn)
        let fresh = try await reader.load(context: source.context, access: access, check: {})
        XCTAssertEqual(fresh.scope, source.context.scope); XCTAssertFalse(reader.loading)
        owner.acknowledge(review, receipt: .object(["id": .integer(901)]), state: .acknowledged, item: item, source: source, active: true)
        XCTAssertNil(owner.item); XCTAssertNil(owner.consume(source: source, active: true))
        XCTAssertEqual(access.sends, 0); XCTAssertFalse(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testForegroundCheckCannotReadFromHiddenOrDepartedParent() async throws {
        let access = Access(), owner = Owner(), reader = ClubAttendanceRosterRead(), context = try source(access).context
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

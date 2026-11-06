import XCTest
@testable import Questify

@MainActor final class ClubBanRemovalReturnTests: XCTestCase {
    private typealias Owner = ClubBanRemovalReturn
    private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var storageNamespace = "synthetic-ban-return"
        var isConfigured = true
        let allowsOfflineWrites = true
        var removed = false, reads = 0, sends = 0
        var readFailure: ClubGovernanceFailure?, sendFailure: ClubGovernanceFailure?
        var holdReads = false
        var pending: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        var entered: ((Int) -> Void)?
        func snapshot(_ scope: ClubGovernanceScope) throws -> ClubGovernanceSnapshot {
            let permissions = try ClubGovernancePermissions(value: ClubGovernanceFixtures.permissions, scope: scope)
            var rows = ClubGovernanceFixtures.value(.bans).array!
            if removed { rows = [] }
            return .init(operation: .bans, scope: scope, permissions: permissions, value: .array(rows))
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            XCTAssertEqual(operation, .bans); XCTAssertTrue(options.isEmpty); reads += 1
            if let readFailure { throw readFailure }
            if holdReads { return try await withCheckedThrowingContinuation { pending.append($0); entered?(reads) } }
            return try snapshot(scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            XCTAssertEqual(review.command.operation, .unban); sends += 1
            if let sendFailure { throw sendFailure }
            removed = true; return .null
        }
    }
    private func source(_ access: Access, generation: UInt64 = 3) throws -> Owner.Source {
        let scope = ClubGovernanceScope(clubID: 81)
        let context = ClubGovernanceReadContext(operation: .bans, scope: scope, identity: access.identity, viewerRevision: 0,
            authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
        return try XCTUnwrap(.init(context: context, snapshot: access.snapshot(scope), generation: generation, access: access))
    }
    private var seed: [String: ClubGovernanceValue] { ["banId": .integer(161), "version": .integer(2)] }
    private func command(request: String = "ban-request-A", version: Int = 2) throws -> ClubGovernanceCommand {
        try .init(operation: .unban, scope: .init(clubID: 81), values: ["banId": .integer(161), "version": .integer(version), "reason": .string("Reviewed synthetic record"), "requestId": .string(request)])
    }
    private func fixture() async throws -> (Access, Owner, Owner.Source, Owner.Item, ClubGovernanceCoordinator, ClubGovernanceReview) {
        let access = Access(), owner = Owner(), source = try source(access)
        owner.appear(); owner.open(seed: seed, source: source, active: true)
        let item = try XCTUnwrap(owner.item), coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(command())
        XCTAssertTrue(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
        return (access, owner, source, item, coordinator, review)
    }
    private func ack(_ f: (Access, Owner, Owner.Source, Owner.Item, ClubGovernanceCoordinator, ClubGovernanceReview)) async throws {
        let (_, owner, source, item, coordinator, review) = f
        let receipt = try await coordinator.confirm(review)
        owner.acknowledge(review, receipt: receipt, state: coordinator.state, item: item, source: source, active: true)
    }
    func testExactAckReturnsToFreshSameClubListAndKeepsPermanentLock() async throws {
        let f = try await fixture(), (access, owner, source, item, coordinator, review) = f
        try await ack(f); XCTAssertFalse(owner.isPresented)
        owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, active: true))
        let result = try await ClubBanListRead().load(context: ticket.source.context, access: access, check: {})
        XCTAssertEqual(result.operation, .bans); XCTAssertEqual(result.scope, .init(clubID: 81)); XCTAssertEqual(result.value.array, [])
        XCTAssertEqual(access.sends, 1); XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
        owner.finishRead(ticket); XCTAssertNil(owner.consume(source: source, active: true))
    }
    func testAckDoesNotOptimisticallyRemoveRowFromOriginalSnapshot() async throws {
        let f = try await fixture(), (_, owner, source, item, _, _) = f
        try await ack(f)
        XCTAssertEqual(source.snapshot.value.array?.first?["status"], .string("ACTIVE"))
        owner.dismissed(item, source: source, active: true)
        XCTAssertEqual(owner.consume(source: source, active: true)?.source.snapshot, source.snapshot)
    }
    func testUnknownSendNeverReturnsOrUnlocksAndManualCancelDoesNotResend() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        access.sendFailure = .unknown(message: nil)
        do { _ = try await coordinator.confirm(review); XCTFail("Expected unknown") } catch {}
        owner.acknowledge(review, receipt: .null, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.consume(source: source, active: true))
        owner.binding(item, source: { source }, active: { true }).wrappedValue = false
        owner.dismissed(item, source: source, active: true)
        XCTAssertNil(owner.consume(source: source, active: true)); XCTAssertEqual(access.sends, 1)
        XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testCancelledReviewNeverConsumesSuccessOrSends() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        owner.binding(item, source: { source }, active: { true }).wrappedValue = false
        coordinator.cancelReview(); owner.dismissed(item, source: source, active: true)
        XCTAssertNil(owner.item); XCTAssertNil(owner.consume(source: source, active: true)); XCTAssertEqual(access.sends, 0)
        XCTAssertFalse(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testReadPreflightFailurePreservesOriginalFailureWithoutSending() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture(); access.readFailure = .forbidden
        do { _ = try await coordinator.confirm(review); XCTFail("Expected read failure") } catch {}
        owner.acknowledge(review, receipt: .null, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertEqual(coordinator.state, .rejected); XCTAssertTrue(owner.isPresented); XCTAssertEqual(access.sends, 0)
    }
    func testFailedReturnReadCannotUndoAckOrPretendListIsEmpty() async throws {
        let f = try await fixture(), (access, owner, source, item, coordinator, review) = f
        try await ack(f); owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, active: true)); access.readFailure = .forbidden
        do { _ = try await ClubBanListRead().load(context: ticket.source.context, access: access, check: {}); XCTFail("Expected forbidden") } catch {}
        owner.finishRead(ticket); XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity)); XCTAssertEqual(access.sends, 1)
    }
    func testDifferentRequestReviewCannotAcknowledgeCurrentSubmission() async throws {
        let (access, owner, source, item, _, original) = try await fixture()
        let another = ClubGovernanceCoordinator(access: access)
        let review = try await another.prepare(command(request: "ban-request-B"))
        XCTAssertNotEqual(review.id, original.id)
        owner.acknowledge(review, receipt: .null, state: .acknowledged, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.consume(source: source, active: true))
    }
    func testEntryRequiresOnlyExactActiveClubBanIdVersionSeed() throws {
        let access = Access(), owner = Owner(), source = try source(access); owner.appear()
        for seed: [String: ClubGovernanceValue] in [[:], ["banId": .integer(162), "version": .integer(2)], ["banId": .integer(161), "version": .integer(3)], ["banId": .integer(161), "version": .integer(2), "targetMemberId": .integer(99)]] {
            owner.open(seed: seed, source: source, active: true); XCTAssertNil(owner.item)
        }
        XCTAssertEqual(access.sends, 0); XCTAssertEqual(access.reads, 0)
    }
    func testBothDismissAndParentVisibilityOrdersConsumeOnlyOnce() async throws {
        for hidden in [false, true] {
            let f = try await fixture(), (_, owner, source, item, _, _) = f
            if hidden { owner.hide() }; try await ack(f); owner.dismissed(item, source: source, active: true)
            if hidden { XCTAssertNil(owner.consume(source: source, active: true)); owner.appear() }
            XCTAssertNotNil(owner.consume(source: source, active: true)); XCTAssertNil(owner.consume(source: source, active: true))
        }
    }
    func testOldBindingDismissAndAckCannotTouchSameBanReopen() async throws {
        let (_, owner, source, item, _, review) = try await fixture()
        let binding = owner.binding(item, source: { source }, active: { true }); owner.retire(); owner.open(seed: seed, source: source, active: true)
        let fresh = try XCTUnwrap(owner.item); XCTAssertNotEqual(item.id, fresh.id)
        binding.wrappedValue = false; owner.dismissed(item, source: source, active: true)
        owner.acknowledge(review, receipt: .null, state: .acknowledged, item: item, source: source, active: true)
        XCTAssertEqual(owner.item?.id, fresh.id); XCTAssertTrue(owner.isPresented); XCTAssertFalse(binding.wrappedValue)
    }
    func testIdentityAuthorityAndReaderReplacementRejectSource() throws {
        let access = Access(), source = try source(access)
        let other = Access(); other.authorizationGeneration = access.authorizationGeneration
        XCTAssertNil(Owner.Source(context: source.context, snapshot: source.snapshot, generation: 3, access: other))
        access.authorizationGeneration = UUID()
        XCTAssertNil(Owner.Source(context: source.context, snapshot: source.snapshot, generation: 3, access: access))
        access.authorizationGeneration = source.context.authorizationGeneration; access.identity = .init(accountID: 799, epoch: 2)
        XCTAssertNil(Owner.Source(context: source.context, snapshot: source.snapshot, generation: 3, access: access))
    }
    func testHiddenInactiveAndDepartedOwnerCannotOpenOrConsume() async throws {
        let access = Access(), owner = Owner(), source = try source(access)
        owner.open(seed: seed, source: source, active: true); XCTAssertNil(owner.item)
        owner.appear(); owner.open(seed: seed, source: source, active: false); XCTAssertNil(owner.item)
        owner.hide(); owner.open(seed: seed, source: source, active: true); XCTAssertNil(owner.item)
        let f = try await fixture(), (_, live, accepted, item, _, _) = f
        try await ack(f); live.depart(try XCTUnwrap(live.attachment))
        XCTAssertFalse(live.dismissed(item, source: accepted, active: true)); XCTAssertNil(live.consume(source: accepted, active: true))
    }
    func testContextSwitchWhileReadHeldStartsReplacementAndRejectsOldReceipt() async throws {
        let access = Access(), reader = ClubBanListRead(), first = try source(access).context
        access.holdReads = true; let a = expectation(description: "old"), b = expectation(description: "new")
        access.entered = { n in if n == 1 { a.fulfill() } else { b.fulfill() } }
        let old = Task { try await reader.load(context: first, access: access, check: {}) }
        await fulfillment(of: [a], timeout: 1); access.identity = .init(accountID: 799, epoch: 2)
        let next = try source(access).context; XCTAssertTrue(reader.synchronize(next)); XCTAssertFalse(reader.loading)
        let fresh = Task { try await reader.load(context: next, access: access, check: {}) }
        await fulfillment(of: [b], timeout: 1)
        access.pending[0].resume(returning: try access.snapshot(first.scope))
        do { _ = try await old.value; XCTFail("Old read") } catch {}
        XCTAssertTrue(reader.loading); access.pending[1].resume(returning: try access.snapshot(next.scope)); _ = try await fresh.value
        XCTAssertFalse(reader.loading); XCTAssertEqual(reader.context, next); XCTAssertEqual(access.sends, 0)
    }
    func testActualDepartureRetiresLoadingAndOldAttachmentCannotClearNewRead() async throws {
        let access = Access(), owner = Owner(), reader = ClubBanListRead(), context = try source(access).context
        owner.appear(); let attachment = try XCTUnwrap(owner.attachment)
        access.holdReads = true; let a = expectation(description: "old"), b = expectation(description: "new")
        access.entered = { n in if n == 1 { a.fulfill() } else { b.fulfill() } }
        let old = Task { try await reader.load(context: context, access: access, check: {}) }
        await fulfillment(of: [a], timeout: 1)
        var resets = 0; owner.depart(attachment, reads: reader) { resets += 1 }; XCTAssertFalse(reader.loading)
        owner.appear(); let fresh = Task { try await reader.load(context: context, access: access, check: {}) }
        await fulfillment(of: [b], timeout: 1); owner.depart(attachment, reads: reader) { resets += 1 }
        XCTAssertEqual(resets, 1); XCTAssertTrue(reader.loading)
        access.pending[0].resume(throwing: ClubGovernanceFailure.forbidden)
        do { _ = try await old.value; XCTFail("Old read") } catch {}
        XCTAssertTrue(reader.loading); access.pending[1].resume(returning: try access.snapshot(context.scope)); _ = try await fresh.value
        XCTAssertFalse(reader.loading)
    }
}

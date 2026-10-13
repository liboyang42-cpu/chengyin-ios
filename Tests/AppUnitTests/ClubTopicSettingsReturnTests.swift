import XCTest
@testable import Questify

@MainActor final class ClubTopicSettingsReturnTests: XCTestCase {
    private typealias Owner = ClubTopicSettingsReturn
    private let scope = ClubGovernanceScope(clubID: 81, topicID: 91)
    private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var storageNamespace = "synthetic-topic-settings-return"
        var isConfigured = true
        let allowsOfflineWrites = true
        var canManage = true
        var flags: [String: ClubGovernanceValue] = ["coopOpen": .bool(false), "pinned": .bool(false), "memberOnly": .bool(true)]
        var receiptOverride: ClubGovernanceValue?
        var readFailure: ClubGovernanceFailure?, sendFailure: ClubGovernanceFailure?
        var reads = 0, sends = 0
        var holdReads = false, holdSend = false
        var heldReads: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        var heldSend: CheckedContinuation<ClubGovernanceValue, Error>?
        var readEntered: ((Int) -> Void)?, sendEntered: (() -> Void)?
        var settings: ClubGovernanceValue {
            .object(flags.merging(["topicName": .string("Synthetic topic"), "canManage": .bool(canManage),
                "chapters": .array([.object(["chapterId": .integer(151), "name": .string("First"), "recruiting": .bool(false)])])]) { _, new in new })
        }
        func snapshot(_ scope: ClubGovernanceScope) throws -> ClubGovernanceSnapshot {
            let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true),
                "club": .object(["id": .integer(scope.clubID ?? 81)]), "roleCodes": .array([.string("CLUB_OWNER")]),
                "permissions": .array([]), "canManageRoles": .bool(false)]), scope: scope)
            return .init(operation: .topicSettings, scope: scope, permissions: permissions, value: settings)
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope,
                  options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            XCTAssertEqual(operation, .topicSettings); XCTAssertTrue(options.isEmpty); reads += 1
            if let readFailure { throw readFailure }
            if holdReads { return try await withCheckedThrowingContinuation { heldReads.append($0); readEntered?(reads) } }
            return try snapshot(scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            XCTAssertEqual(review.command.operation, .saveTopicSettings); sends += 1
            if let sendFailure { throw sendFailure }
            if holdSend { return try await withCheckedThrowingContinuation { heldSend = $0; sendEntered?() } }
            for key in ["coopOpen", "pinned", "memberOnly"] { flags[key] = review.command.fields[key] }
            return receiptOverride ?? settings
        }
    }
    private func source(_ access: Access, scope: ClubGovernanceScope? = nil, generation: UInt64 = 3) throws -> Owner.Source {
        let scope = scope ?? self.scope
        let context = ClubGovernanceReadContext(operation: .topicSettings, scope: scope, identity: access.identity, viewerRevision: 0,
            authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
        return try XCTUnwrap(.init(context: context, snapshot: access.snapshot(scope), generation: generation, access: access))
    }
    private func command(scope: ClubGovernanceScope? = nil, flags: [String: ClubGovernanceValue]? = nil) throws -> ClubGovernanceCommand {
        try .init(operation: .saveTopicSettings, scope: scope ?? self.scope,
            values: flags ?? ["coopOpen": .bool(true), "pinned": .bool(true), "memberOnly": .bool(false)])
    }
    private func fixture() async throws -> (Access, Owner, Owner.Source, Owner.Item, ClubGovernanceCoordinator, ClubGovernanceReview) {
        let access = Access(), owner = Owner(), source = try source(access)
        owner.appear(); owner.open(seed: access.flags, source: source, active: true)
        let item = try XCTUnwrap(owner.item), coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(command())
        XCTAssertTrue(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
        return (access, owner, source, item, coordinator, review)
    }
    private func acknowledge(_ f: (Access, Owner, Owner.Source, Owner.Item, ClubGovernanceCoordinator, ClubGovernanceReview)) async throws {
        let (_, owner, source, item, coordinator, review) = f
        let receipt = try await coordinator.confirm(review)
        owner.acknowledge(review, receipt: receipt, state: coordinator.state, item: item, source: source, active: true)
    }
    func testNormalSavePreservesAllThreeFlagsAndReturnsAuthoritativeFreshSnapshotOnce() async throws {
        let f = try await fixture(), (access, owner, source, item, coordinator, review) = f
        XCTAssertEqual(Set(review.command.fields.keys), Set(["clubId", "topicId", "coopOpen", "pinned", "memberOnly"]))
        XCTAssertNil(review.command.fields["requestId"])
        try await acknowledge(f); XCTAssertFalse(owner.isPresented)
        owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, active: true))
        access.flags["pinned"] = .bool(false)
        let fresh = try await ClubTopicSettingsRead().load(context: ticket.source.context, access: access, check: {})
        XCTAssertEqual(fresh.scope, scope); XCTAssertEqual(fresh.value["coopOpen"], .bool(true))
        XCTAssertEqual(fresh.value["pinned"], .bool(false)); XCTAssertEqual(fresh.value["memberOnly"], .bool(false))
        XCTAssertNotEqual(fresh.value["pinned"], review.command.fields["pinned"])
        XCTAssertEqual(fresh.value["chapters"], source.snapshot.value["chapters"])
        owner.finishRead(ticket); XCTAssertNil(owner.consume(source: source, active: true))
        XCTAssertEqual(access.sends, 1); XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testOnlyCurrentBooleanSeedCanOpenEditor() throws {
        let access = Access(), owner = Owner(), source = try source(access); owner.appear()
        for seed: [String: ClubGovernanceValue] in [[:], ["coopOpen": .bool(false), "pinned": .bool(false)],
                     ["coopOpen": .bool(true), "pinned": .bool(false), "memberOnly": .bool(true)],
                     ["coopOpen": .bool(false), "pinned": .bool(false), "memberOnly": .bool(true), "requestId": .string("x")]] {
            owner.open(seed: seed, source: source, active: true); XCTAssertNil(owner.item)
        }
        owner.open(seed: access.flags, source: source, active: true)
        XCTAssertEqual(owner.item?.route.operation, .saveTopicSettings); XCTAssertEqual(access.sends, 0)
    }
    func testCancelNeverReturnsAsAcknowledgedOrSends() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        owner.binding(item, source: { source }, active: { true }).wrappedValue = false
        coordinator.cancelReview(); owner.dismissed(item, source: source, active: true)
        XCTAssertNil(owner.item); XCTAssertNil(owner.consume(source: source, active: true)); XCTAssertEqual(access.sends, 0)
        XCTAssertFalse(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testUnknownSendKeepsOriginalOutcomeLockAndDoesNotReturn() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        access.sendFailure = .unknown(message: nil)
        do { _ = try await coordinator.confirm(review); XCTFail("Expected unknown") } catch {}
        owner.acknowledge(review, receipt: access.settings, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.consume(source: source, active: true))
        XCTAssertEqual(access.sends, 1); XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testPreflightFailureCannotReturnOrDispatch() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture(); access.readFailure = .forbidden
        do { _ = try await coordinator.confirm(review); XCTFail("Expected forbidden") } catch {}
        owner.acknowledge(review, receipt: access.settings, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertEqual(coordinator.state, .rejected); XCTAssertEqual(access.sends, 0)
    }
    func testMissingOrMalformedReceiptDoesNotConsumeTheOriginalAcknowledgement() async throws {
        for value: ClubGovernanceValue in [.null, .object([:]), .object(["coopOpen": .bool(true), "pinned": .bool(false), "memberOnly": .bool(true), "chapters": .array([])])] {
            let (access, owner, source, item, coordinator, review) = try await fixture(); access.receiptOverride = value
            let receipt = try await coordinator.confirm(review)
            XCTAssertEqual(coordinator.state, .acknowledged)
            owner.acknowledge(review, receipt: receipt, state: coordinator.state, item: item, source: source, active: true)
            XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.consume(source: source, active: true))
            XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity)); XCTAssertEqual(access.sends, 1)
        }
    }
    func testReturnReadFailureCannotUndoAcknowledgementOrResend() async throws {
        let f = try await fixture(), (access, owner, source, item, coordinator, review) = f
        try await acknowledge(f); owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, active: true)); access.readFailure = .forbidden
        do { _ = try await ClubTopicSettingsRead().load(context: ticket.source.context, access: access, check: {}); XCTFail("Expected read failure") } catch {}
        owner.finishRead(ticket); XCTAssertNil(owner.readTicket)
        XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity)); XCTAssertEqual(access.sends, 1)
    }
    func testDifferentReviewUUIDAndFlagsCannotAcknowledgeCurrentSubmission() async throws {
        let (access, owner, source, item, _, review) = try await fixture()
        let other = ClubGovernanceCoordinator(access: access)
        let second = try await other.prepare(command(flags: access.flags)); XCTAssertNotEqual(second.id, review.id)
        owner.acknowledge(second, receipt: access.settings, state: .acknowledged, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertEqual(access.sends, 0)
    }
    func testDifferentTopicOrClubReviewCannotBindToCurrentEditor() async throws {
        for scope in [ClubGovernanceScope(clubID: 81, topicID: 92), .init(clubID: 82, topicID: 91)] {
            let (access, owner, source, item, _, _) = try await fixture()
            let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command(scope: scope))
            XCTAssertFalse(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
            XCTAssertTrue(owner.isPresented); XCTAssertEqual(access.sends, 0)
        }
    }
    func testChangedServerSnapshotCannotBindOldEditorSeedForAutomaticReturn() async throws {
        let (access, owner, source, item, _, _) = try await fixture(); access.flags["pinned"] = .bool(true)
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command())
        XCTAssertFalse(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
        XCTAssertTrue(owner.isPresented); XCTAssertEqual(access.sends, 0)
    }
    func testBothVisibleAndDismissOrderingsConsumeOnce() async throws {
        for hidden in [false, true] {
            let f = try await fixture(), (_, owner, source, item, _, _) = f
            if hidden { owner.hide() }; try await acknowledge(f)
            owner.dismissed(item, source: source, active: true)
            if hidden { XCTAssertNil(owner.consume(source: source, active: true)); owner.appear() }
            XCTAssertNotNil(owner.consume(source: source, active: true)); XCTAssertNil(owner.consume(source: source, active: true))
        }
    }
    func testOldBindingDismissalAndAcknowledgementCannotCloseReopenedEditor() async throws {
        let (access, owner, source, item, _, review) = try await fixture()
        let old = owner.binding(item, source: { source }, active: { true }); owner.retire()
        owner.open(seed: access.flags, source: source, active: true); let fresh = try XCTUnwrap(owner.item)
        XCTAssertFalse(old.wrappedValue); old.wrappedValue = false; owner.dismissed(item, source: source, active: true)
        owner.acknowledge(review, receipt: access.settings, state: .acknowledged, item: item, source: source, active: true)
        XCTAssertEqual(owner.item?.id, fresh.id); XCTAssertTrue(owner.isPresented)
    }
    func testLateSendAfterActualDepartureCannotCloseReopenedOwner() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        access.holdSend = true; let entered = expectation(description: "send")
        access.sendEntered = { entered.fulfill() }; let task = Task { try await coordinator.confirm(review) }
        await fulfillment(of: [entered], timeout: 1)
        owner.depart(try XCTUnwrap(owner.attachment), reads: ClubTopicSettingsRead()) {}; owner.appear()
        owner.open(seed: access.flags, source: source, active: true); let fresh = try XCTUnwrap(owner.item)
        access.heldSend?.resume(returning: access.settings); access.heldSend = nil; let receipt = try await task.value
        owner.acknowledge(review, receipt: receipt, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertEqual(owner.item?.id, fresh.id); XCTAssertTrue(owner.isPresented); XCTAssertEqual(access.sends, 1)
    }
    func testSourceRejectsChangedIdentityAuthorizationPermissionAndMissingScope() throws {
        let access = Access(), source = try source(access)
        access.identity = .init(accountID: 701, epoch: 2)
        XCTAssertNil(Owner.Source(context: source.context, snapshot: source.snapshot, generation: 3, access: access))
        access.identity = source.context.identity; access.authorizationGeneration = UUID()
        XCTAssertNil(Owner.Source(context: source.context, snapshot: source.snapshot, generation: 3, access: access))
        access.authorizationGeneration = source.context.authorizationGeneration; access.canManage = false
        XCTAssertNil(Owner.Source(context: source.context, snapshot: try access.snapshot(scope), generation: 3, access: access))
        access.canManage = true; access.isConfigured = false
        XCTAssertNil(Owner.Source(context: source.context, snapshot: source.snapshot, generation: 3, access: access))
        access.isConfigured = true
        let missing = ClubGovernanceReadContext(operation: .topicSettings, scope: .init(clubID: 81), identity: access.identity,
            viewerRevision: 0, authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
        XCTAssertNil(Owner.Source(context: missing, snapshot: try access.snapshot(missing.scope), generation: 3, access: access))
    }
    func testContextReplacementReadsWhileOldResponseCannotClearNewLoading() async throws {
        let access = Access(), reader = ClubTopicSettingsRead(), first = try source(access).context
        access.holdReads = true; let a = expectation(description: "old read"), b = expectation(description: "new read")
        access.readEntered = { n in if n == 1 { a.fulfill() } else { b.fulfill() } }
        let old = Task { try await reader.load(context: first, access: access, check: {}) }
        await fulfillment(of: [a], timeout: 1)
        access.identity = .init(accountID: 799, epoch: 2); let second = try source(access).context
        XCTAssertTrue(reader.synchronize(second)); XCTAssertFalse(reader.loading)
        let next = Task { try await reader.load(context: second, access: access, check: {}) }
        await fulfillment(of: [b], timeout: 1)
        access.heldReads[0].resume(returning: try access.snapshot(scope))
        do { _ = try await old.value; XCTFail("Old read") } catch {}
        XCTAssertTrue(reader.loading); XCTAssertEqual(reader.context, second)
        access.heldReads[1].resume(returning: try access.snapshot(scope)); _ = try await next.value
        XCTAssertFalse(reader.loading); XCTAssertEqual(access.reads, 2); XCTAssertEqual(access.sends, 0)
    }
    func testActualDepartureRetiresReadButOldAttachmentCannotRetireReplacement() async throws {
        let access = Access(), reader = ClubTopicSettingsRead(), owner = Owner(), context = try source(access).context
        owner.appear(); let oldAttachment = try XCTUnwrap(owner.attachment); access.holdReads = true
        let a = expectation(description: "old read"), b = expectation(description: "new read")
        access.readEntered = { n in if n == 1 { a.fulfill() } else { b.fulfill() } }
        let old = Task { try await reader.load(context: context, access: access, check: {}) }
        await fulfillment(of: [a], timeout: 1)
        var resets = 0; owner.depart(oldAttachment, reads: reader) { resets += 1 }
        XCTAssertEqual(resets, 1); XCTAssertFalse(reader.loading); owner.appear()
        let next = Task { try await reader.load(context: context, access: access, check: {}) }
        await fulfillment(of: [b], timeout: 1)
        owner.depart(oldAttachment, reads: reader) { resets += 1 }; XCTAssertEqual(resets, 1); XCTAssertTrue(reader.loading)
        access.heldReads[0].resume(throwing: ClubGovernanceFailure.forbidden)
        do { _ = try await old.value; XCTFail("Old read") } catch {}
        XCTAssertTrue(reader.loading)
        access.heldReads[1].resume(returning: try access.snapshot(scope)); _ = try await next.value
        XCTAssertFalse(reader.loading); XCTAssertEqual(access.sends, 0)
    }
    func testReadRejectsDifferentTopicResponseAndPreservesNoInventedSnapshot() async throws {
        let access = Access(), reader = ClubTopicSettingsRead(), context = try source(access).context
        access.holdReads = true; let entered = expectation(description: "read"); access.readEntered = { _ in entered.fulfill() }
        let task = Task { try await reader.load(context: context, access: access, check: {}) }
        await fulfillment(of: [entered], timeout: 1)
        access.heldReads[0].resume(returning: try access.snapshot(.init(clubID: 81, topicID: 92)))
        do { _ = try await task.value; XCTFail("Different topic") } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .targetChanged) }
        XCTAssertFalse(reader.loading); XCTAssertEqual(access.sends, 0)
    }
    func testForegroundReadDoesNotReviveRetiredReviewAndHiddenParentCannotRead() async throws {
        let (access, owner, source, item, _, review) = try await fixture(); let reader = ClubTopicSettingsRead()
        owner.retire(); reader.retire(); owner.hide()
        func foregroundRead() async throws {
            guard owner.visible, !owner.retainsReturn else { return }
            _ = try await reader.load(context: source.context, access: access, check: {})
        }
        let count = access.reads; try await foregroundRead(); XCTAssertEqual(access.reads, count)
        owner.appear(); try await foregroundRead(); XCTAssertEqual(access.reads, count + 1)
        owner.acknowledge(review, receipt: access.settings, state: .acknowledged, item: item, source: source, active: true)
        XCTAssertNil(owner.item); XCTAssertNil(owner.consume(source: source, active: true)); XCTAssertEqual(access.sends, 0)
    }
}

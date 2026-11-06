import XCTest
@testable import Questify

@MainActor final class ClubInvitationFeedbackViewTests: XCTestCase {
    private func activate(_ model: ClubInvitationFeedbackReadModel, _ context: ClubInvitationFeedbackContext) throws -> ClubInvitationFeedbackReadModel.Permit {
        model.bind(context); return try XCTUnwrap(model.activate(context))
    }
    private func load(_ model: ClubInvitationFeedbackReadModel, _ f: FeedbackFixture, _ permit: ClubInvitationFeedbackReadModel.Permit) async {
        await model.load(permit, clubReader: f.club, reader: f.flow, access: f.access)
    }
    private func accepted(_ model: ClubInvitationFeedbackReadModel, _ f: FeedbackFixture) -> ClubInvitationFeedbackSnapshot? {
        model.accepted(f.context, clubReader: f.club, reader: f.flow, access: f.access)
    }
    func testNormalOwnerReadUsesExistingThreeReadersAndNoWrites() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), permit = try activate(model, f.context)
        f.flow.value = f.value(received: [f.row(1)], sent: [f.row(2)])
        await load(model, f, permit)
        XCTAssertEqual(f.club.reads, 1); XCTAssertEqual(f.access.resources, [.topics]); XCTAssertEqual(f.flow.resources, [.invitations])
        XCTAssertEqual(accepted(model, f)?.rows.count, 2); XCTAssertEqual(f.access.sends, 0)
    }
    func testFreshOwnerLossStopsBeforeTopicsAndInvitationReads() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), permit = try activate(model, f.context)
        f.club.returned = FeedbackClubReader.record(owner: false); await load(model, f, permit)
        XCTAssertEqual(model.phase, .denied); XCTAssertNil(model.snapshot); XCTAssertTrue(f.access.resources.isEmpty); XCTAssertTrue(f.flow.resources.isEmpty)
    }
    func testTopicFailureIsNotEmptyAndRetryRecoversCoherentSnapshot() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), permit = try activate(model, f.context)
        f.access.failure = .malformed; await load(model, f, permit)
        XCTAssertEqual(model.phase, .failed); XCTAssertNil(model.snapshot); XCTAssertTrue(f.flow.resources.isEmpty)
        f.access.failure = nil; await load(model, f, permit)
        XCTAssertEqual(model.phase, .ready); XCTAssertTrue(accepted(model, f)?.rows.isEmpty == true)
    }
    func testMissingSentArrayCannotPublishReceivedAsCompleteEmptyFeedback() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), permit = try activate(model, f.context)
        f.flow.value = .object(["received": .array([f.row(1)])]); await load(model, f, permit)
        XCTAssertEqual(model.phase, .failed); XCTAssertNil(model.snapshot)
    }
    func testReturnRefreshRetiresOldRowAndReappliesFreshTopicFilter() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), scope = f.context, permit = try activate(model, scope)
        f.flow.value = f.value(sent: [f.row(2)]); await load(model, f, permit)
        let before = try XCTUnwrap(accepted(model, f)), nonce = model.snapshotID
        let target = try XCTUnwrap(before.target(key: before.rows[0].id, context: scope, snapshotID: nonce))
        f.access.topicIDs = [92]; await load(model, f, permit)
        XCTAssertTrue(accepted(model, f)?.rows.isEmpty == true)
        XCTAssertFalse(target.isCurrent(snapshot: accepted(model, f), context: scope, snapshotID: model.snapshotID))
        XCTAssertEqual(f.access.resources, [.topics, .topics]); XCTAssertEqual(f.flow.resources, [.invitations, .invitations]); XCTAssertEqual(f.access.sends, 0)
    }
    func testLeaveAndReappearRejectsQueuedOldRetryAndPrivateRows() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), scope = f.context, old = try activate(model, scope)
        f.flow.value = f.value(received: [f.row(1)]); await load(model, f, old)
        model.leave(scope); _ = model.activate(scope); await load(model, f, old)
        XCTAssertEqual(f.club.reads, 1); XCTAssertNil(model.snapshot)
    }
    func testAccountEpochChangesDuringReadCannotPublish() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), permit = try activate(model, f.context)
        f.flow.held = true; let entered = expectation(description: "invitations"); f.flow.entered = { entered.fulfill() }
        let task = Task { await self.load(model, f, permit) }; await fulfillment(of: [entered], timeout: 1)
        f.club.clubIdentity = .init(accountID: 701, epoch: 2); f.flow.pending[0].resume(returning: f.value(received: [f.row(1)])); await task.value
        XCTAssertNil(model.snapshot); XCTAssertNil(accepted(model, f))
    }
    func testNamespaceAuthorityAndReaderReplacementHideAcceptedData() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), scope = f.context, permit = try activate(model, scope)
        f.flow.value = f.value(received: [f.row(1)]); await load(model, f, permit)
        f.access.storageNamespace = "new-realm"; XCTAssertNil(model.accepted(scope, clubReader: f.club, reader: f.flow, access: f.access))
        f.access.storageNamespace = scope.namespace; f.access.authorizationGeneration = UUID(); XCTAssertNil(model.accepted(scope, clubReader: f.club, reader: f.flow, access: f.access))
        f.access.authorizationGeneration = scope.authorizationGeneration
        let other = FeedbackFlowReader(); XCTAssertNil(model.accepted(scope, clubReader: f.club, reader: other, access: f.access))
    }
    func testLatestReadWinsEvenIfOlderTransportDoesNotCancel() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), permit = try activate(model, f.context)
        f.flow.held = true; let first = expectation(description: "first"), second = expectation(description: "second")
        f.flow.entered = { f.flow.pending.count == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await self.load(model, f, permit) }; await fulfillment(of: [first], timeout: 1)
        let new = Task { await self.load(model, f, permit) }; await fulfillment(of: [second], timeout: 1)
        f.flow.pending[1].resume(returning: f.value(received: [f.row(2)])); await new.value
        f.flow.pending[0].resume(returning: f.value(received: [f.row(1)])); await old.value
        XCTAssertEqual(accepted(model, f)?.rows.map { $0.id.invitationID }, [2])
    }
    func testCancelledScreenAndUnconfiguredContextNeverDispatchQueuedRead() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), scope = f.context, permit = try activate(model, scope)
        model.leave(scope); await load(model, f, permit); XCTAssertEqual(f.club.reads, 0)
        f.access.isConfigured = false; let unavailable = f.context; model.bind(unavailable); XCTAssertNil(model.activate(unavailable)); XCTAssertTrue(f.flow.resources.isEmpty)
        f.access.isConfigured = true; let active = try activate(model, f.context)
        f.flow.held = true; let entered = expectation(description: "cancellable read"); f.flow.entered = { entered.fulfill() }
        let task = Task { await self.load(model, f, active) }; await fulfillment(of: [entered], timeout: 1)
        task.cancel(); f.flow.pending[0].resume(returning: f.value(received: [f.row(1)])); await task.value
        XCTAssertEqual(model.phase, .idle); XCTAssertNil(model.snapshot)
    }
}
@MainActor private final class FeedbackClubReader: ClubReading {
    var isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 701, epoch: 1)
    var returned = FeedbackClubReader.record()
    var reads = 0
    static func record(id: Int = 81, owner: Bool = true) -> ClubRecord {
        try! JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":\(id),\"isOwner\":\(owner)}".utf8))
    }
    func clubDetail(id: Int) async throws -> ClubRecord { reads += 1; return returned }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw CoopFlowFailure.unavailable }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
}
@MainActor private final class FeedbackFlowReader: CoopFlowReading {
    var session: CoopFlowSession? = try! .init(accountID: 701, epoch: 1, token: "synthetic")
    var resources: [CoopFlowRead] = []
    var value: CoopFlowJSON = .object(["received": .array([]), "sent": .array([])])
    var held = false
    var entered: (() -> Void)?
    var pending: [CheckedContinuation<CoopFlowJSON, Error>] = []
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
        resources.append(resource)
        if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
        return value
    }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.unavailable }
}
@MainActor private final class FeedbackAccess: ClubGovernanceAccess {
    var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
    var isConfigured = true
    var storageNamespace = "synthetic-club-feedback"
    let allowsOfflineWrites = false
    var authorizationGeneration: UUID? = UUID()
    var resources: [ClubGovernanceRead] = []
    var sends = 0
    var failure: ClubGovernanceFailure?
    var topicIDs = [91, 92]
    func topics() -> ClubGovernanceSnapshot { .init(operation: .topics, scope: .init(clubID: 81), permissions: nil, value: .array(topicIDs.map { .object(["id": .integer($0)]) })) }
    func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
        resources.append(operation); XCTAssertEqual(scope, .init(clubID: 81)); XCTAssertTrue(options.isEmpty)
        if let failure { throw failure }; return topics()
    }
    func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
}
@MainActor private final class FeedbackFixture {
    let club = FeedbackClubReader(), flow = FeedbackFlowReader(), access = FeedbackAccess()
    var context: ClubInvitationFeedbackContext { .init(club: club.returned, clubReader: club, reader: flow, access: access) }
    func row(_ id: Int, topic: Int = 91, clubID: Int = 81, status: CoopFlowJSON = .id(0)) -> CoopFlowJSON {
        .object(["id": .id(id), "topicId": .id(topic), "toType": .string("club"), "toId": .id(clubID), "status": status,
            "partner": .object(["name": .string("Partner \(id)")]), "topicName": .string("Topic \(topic)"), "createTime": .string("2026-10-11 09:00"), "message": .string("Invitation note")])
    }
    func value(received: [CoopFlowJSON] = [], sent: [CoopFlowJSON] = []) -> CoopFlowJSON { .object(["received": .array(received), "sent": .array(sent)]) }
    func snapshot(received: [CoopFlowJSON] = [], sent: [CoopFlowJSON] = []) throws -> ClubInvitationFeedbackSnapshot {
        try .init(context: context, topics: access.topics(), invitations: value(received: received, sent: sent))
    }
    func replacing(_ row: CoopFlowJSON, _ fields: [String: CoopFlowJSON]) -> CoopFlowJSON {
        guard case .object(let object) = row else { return row }; return .object(object.merging(fields) { _, new in new })
    }
}

extension ClubInvitationFeedbackViewTests {
    func testInvitationTermsPreserveMissingValuesWithoutInventingAmounts() throws {
        let f = FeedbackFixture()
        let terms = try ClubInvitationFeedbackTerms(f.row(1))
        XCTAssertNil(terms.shareMode); XCTAssertNil(terms.shareRate); XCTAssertNil(terms.fixedFee)
        XCTAssertNil(terms.handleReason); XCTAssertFalse(terms.termsFrozen)
        for mode in [1, 2, 99] {
            let missing = try ClubInvitationFeedbackTerms(f.replacing(f.row(1), ["shareMode": .id(mode)]))
            XCTAssertEqual(missing.shareMode, mode)
            XCTAssertNil(missing.shareRate); XCTAssertNil(missing.fixedFee)
        }
    }
    func testInvitationTermsPreserveProvidedModesAmountsAndVerbatimReason() throws {
        let f = FeedbackFixture()
        let terms = try ClubInvitationFeedbackTerms(f.replacing(f.row(1), [
            "shareMode": .id(1), "shareRate": .number(12.5), "fixedFee": .number(8.25),
            "handleReason": .string("  Recorded reply\nSecond line  "), "termsFrozen": .bool(true)]))
        XCTAssertEqual(terms.shareMode, 1); XCTAssertEqual(terms.shareRate, 12.5)
        XCTAssertEqual(terms.fixedFee, 8.25); XCTAssertEqual(terms.handleReason, "  Recorded reply\nSecond line  ")
        XCTAssertTrue(terms.termsFrozen)
        let traffic = try ClubInvitationFeedbackTerms(f.replacing(f.row(1), ["shareMode": .id(0)]))
        XCTAssertEqual(traffic.shareMode, 0); XCTAssertNil(traffic.fixedFee)
        let zero = try ClubInvitationFeedbackTerms(f.replacing(f.row(1), ["shareMode": .id(2), "fixedFee": .id(0)]))
        XCTAssertEqual(zero.fixedFee, 0)
    }
    func testInvitationTermsRejectMalformedProvidedTypesWithoutReadingUnrelatedFields() throws {
        let f = FeedbackFixture()
        for (field, value) in [("shareMode", CoopFlowJSON.string("1")), ("shareRate", .bool(true)),
                               ("fixedFee", .string("unknown")), ("handleReason", .id(7)),
                               ("termsFrozen", .string("yes"))] {
            XCTAssertThrowsError(try ClubInvitationFeedbackTerms(f.replacing(f.row(1), [field: value])), field)
        }
        let terms = try ClubInvitationFeedbackTerms(f.replacing(f.row(1), ["partner": .bool(false), "depositAmount": .string("not displayed")]))
        XCTAssertNil(terms.fixedFee); XCTAssertNil(terms.handleReason)
    }
    func testInvitationTermsKeepSameNumericIDSeparatedByDirection() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), permit = try activate(model, f.context)
        f.flow.value = f.value(received: [f.replacing(f.row(7), ["shareMode": .id(1), "shareRate": .id(15), "handleReason": .string("Received reply")])],
                              sent: [f.replacing(f.row(7), ["shareMode": .id(2), "fixedFee": .number(8.25), "handleReason": .string("Sent reply")])])
        await load(model, f, permit)
        let snapshot = try XCTUnwrap(accepted(model, f))
        for row in snapshot.rows {
            let target = try XCTUnwrap(snapshot.target(key: row.id, context: f.context, snapshotID: model.snapshotID))
            let terms = try XCTUnwrap(model.terms(for: target, in: f.context, clubReader: f.club, reader: f.flow, access: f.access))
            XCTAssertEqual(terms.handleReason, row.id.direction == .received ? "Received reply" : "Sent reply")
            XCTAssertEqual(terms.shareMode, row.id.direction == .received ? 1 : 2)
        }
        XCTAssertEqual(f.flow.resources, [.invitations]); XCTAssertEqual(f.access.sends, 0)
    }
    func testInvitationTermsProjectOnlyRowsInTheAcceptedClubScope() throws {
        let f = FeedbackFixture()
        let payload = f.value(received: [f.row(1), f.row(1, clubID: 82)], sent: [f.row(2), f.row(3, topic: 999)])
        let snapshot = try ClubInvitationFeedbackSnapshot(context: f.context, topics: f.access.topics(), invitations: payload)
        let terms = try ClubInvitationFeedbackTerms.project(snapshot, invitations: payload)
        XCTAssertEqual(terms.count, 2)
        XCTAssertEqual(Set(terms.keys), Set(snapshot.rows.map(\.id)))
        XCTAssertThrowsError(try ClubInvitationFeedbackTerms.project(snapshot, invitations: f.value()))
    }
    func testInvitationTermsMalformedReadFailsWithoutPublishingPartialSnapshot() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), permit = try activate(model, f.context)
        f.flow.value = f.value(received: [f.replacing(f.row(1), ["fixedFee": .string("invalid")])])
        await load(model, f, permit)
        XCTAssertEqual(model.phase, .failed); XCTAssertNil(accepted(model, f)); XCTAssertNil(model.snapshot)
        XCTAssertEqual(f.access.sends, 0)
    }
    func testInvitationTermsReloadRejectsOldTargetAndPublishesNewReply() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), permit = try activate(model, f.context)
        f.flow.value = f.value(received: [f.replacing(f.row(1), ["handleReason": .string("First")])])
        await load(model, f, permit)
        let first = try XCTUnwrap(accepted(model, f))
        let old = try XCTUnwrap(first.target(key: first.rows[0].id, context: f.context, snapshotID: model.snapshotID))
        f.flow.value = f.value(received: [f.replacing(f.row(1), ["handleReason": .string("Updated")])])
        await load(model, f, permit)
        XCTAssertNil(model.terms(for: old, in: f.context, clubReader: f.club, reader: f.flow, access: f.access))
        let second = try XCTUnwrap(accepted(model, f))
        let current = try XCTUnwrap(second.target(key: second.rows[0].id, context: f.context, snapshotID: model.snapshotID))
        XCTAssertEqual(model.terms(for: current, in: f.context, clubReader: f.club, reader: f.flow, access: f.access)?.handleReason, "Updated")
        XCTAssertEqual(f.access.sends, 0)
    }
    func testInvitationTermsRejectAuthorityReaderAccountAndLeaveChanges() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), scope = f.context, permit = try activate(model, scope)
        f.flow.value = f.value(received: [f.replacing(f.row(1), ["handleReason": .string("Reply")])])
        await load(model, f, permit)
        let snapshot = try XCTUnwrap(accepted(model, f))
        let target = try XCTUnwrap(snapshot.target(key: snapshot.rows[0].id, context: scope, snapshotID: model.snapshotID))
        XCTAssertNotNil(model.terms(for: target, in: scope, clubReader: f.club, reader: f.flow, access: f.access))
        f.access.authorizationGeneration = UUID()
        XCTAssertNil(model.terms(for: target, in: scope, clubReader: f.club, reader: f.flow, access: f.access))
        f.access.authorizationGeneration = scope.authorizationGeneration
        f.access.storageNamespace = "changed"
        XCTAssertNil(model.terms(for: target, in: scope, clubReader: f.club, reader: f.flow, access: f.access))
        f.access.storageNamespace = scope.namespace
        XCTAssertNil(model.terms(for: target, in: scope, clubReader: f.club, reader: FeedbackFlowReader(), access: f.access))
        f.club.clubIdentity = .init(accountID: 702, epoch: 1)
        XCTAssertNil(model.terms(for: target, in: scope, clubReader: f.club, reader: f.flow, access: f.access))
        f.club.clubIdentity = scope.identity
        model.leave(scope); _ = model.activate(scope)
        XCTAssertNil(model.terms(for: target, in: scope, clubReader: f.club, reader: f.flow, access: f.access))
        XCTAssertEqual(f.access.sends, 0)
    }
    func testInvitationTermsLateOlderReadCannotReplaceNewerTerms() async throws {
        let f = FeedbackFixture(), model = ClubInvitationFeedbackReadModel(), permit = try activate(model, f.context)
        f.flow.held = true
        let first = expectation(description: "old terms"), second = expectation(description: "new terms")
        f.flow.entered = { f.flow.pending.count == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await self.load(model, f, permit) }; await fulfillment(of: [first], timeout: 1)
        let new = Task { await self.load(model, f, permit) }; await fulfillment(of: [second], timeout: 1)
        f.flow.pending[1].resume(returning: f.value(received: [f.replacing(f.row(1), ["handleReason": .string("New")])]))
        await new.value
        f.flow.pending[0].resume(returning: f.value(received: [f.replacing(f.row(1), ["handleReason": .string("Old")])]))
        await old.value
        let snapshot = try XCTUnwrap(accepted(model, f))
        let target = try XCTUnwrap(snapshot.target(key: snapshot.rows[0].id, context: f.context, snapshotID: model.snapshotID))
        XCTAssertEqual(model.terms(for: target, in: f.context, clubReader: f.club, reader: f.flow, access: f.access)?.handleReason, "New")
        XCTAssertEqual(f.access.sends, 0)
    }
}

extension ClubInvitationFeedbackViewTests {
    func testDetailParentReadTriggerIsConsumedOnceAndRejectsAnOlderRevision() throws {
        let f = FeedbackFixture(), owner = ClubInvitationFeedbackPresentation()
        owner.appear(f.context, active: true)
        let first = ClubInvitationFeedbackPresentation.ReadTrigger(context: f.context, revision: owner.readRevision)
        XCTAssertTrue(owner.consumeRead(first)); XCTAssertFalse(owner.consumeRead(first))
        owner.requestRead(f.context)
        XCTAssertFalse(owner.consumeRead(first))
        XCTAssertTrue(owner.consumeRead(.init(context: f.context, revision: owner.readRevision)))
    }
    func testDetailCoverageDoesNotRetireTheRouteOrReadTheHiddenParent() throws {
        let f = FeedbackFixture(), owner = ClubInvitationFeedbackPresentation()
        owner.appear(f.context, active: true)
        XCTAssertTrue(owner.consumeRead(.init(context: f.context, revision: owner.readRevision)))
        let snapshot = try f.snapshot(received: [f.row(1)])
        owner.open(key: snapshot.rows[0].id, in: f.context)
        let route = try XCTUnwrap(owner.route)
        owner.disappear(f.context)
        XCTAssertTrue(owner.owns(route, in: f.context)); XCTAssertTrue(owner.binding(for: route).wrappedValue)
        owner.requestRead(f.context)
        XCTAssertFalse(owner.consumeRead(.init(context: f.context, revision: owner.readRevision)))
        owner.finish(route, in: f.context)
        XCTAssertFalse(owner.consumeRead(.init(context: f.context, revision: owner.readRevision)))
        owner.appear(f.context, active: true)
        XCTAssertTrue(owner.consumeRead(.init(context: f.context, revision: owner.readRevision)))
        XCTAssertFalse(owner.consumeRead(.init(context: f.context, revision: owner.readRevision)))
    }
    func testDetailOldBindingAndDismissCannotCloseReopenedSameInvitation() throws {
        let f = FeedbackFixture(), owner = ClubInvitationFeedbackPresentation()
        owner.appear(f.context, active: true)
        let snapshot = try f.snapshot(received: [f.row(1)]), key = snapshot.rows[0].id
        owner.open(key: key, in: f.context)
        let first = try XCTUnwrap(owner.route), oldBinding = owner.binding(for: first)
        oldBinding.wrappedValue = false
        XCTAssertFalse(owner.isPresented); owner.finish(first, in: f.context)
        owner.open(key: key, in: f.context)
        let second = try XCTUnwrap(owner.route)
        XCTAssertNotEqual(first.id, second.id)
        oldBinding.wrappedValue = false; owner.finish(first, in: f.context)
        XCTAssertEqual(owner.route?.id, second.id); XCTAssertTrue(owner.isPresented)
        XCTAssertFalse(oldBinding.wrappedValue); XCTAssertTrue(owner.binding(for: second).wrappedValue)
    }
    func testDetailContextReplacementAndInactiveSceneRejectOldOwnerCallbacks() throws {
        let f = FeedbackFixture(), owner = ClubInvitationFeedbackPresentation(), firstContext = f.context
        owner.appear(firstContext, active: true)
        let snapshot = try f.snapshot(received: [f.row(1)])
        owner.open(key: snapshot.rows[0].id, in: firstContext)
        let first = try XCTUnwrap(owner.route)
        f.access.authorizationGeneration = UUID(); let nextContext = f.context
        owner.bind(nextContext)
        XCTAssertNil(owner.route); XCTAssertFalse(owner.owns(first, in: nextContext))
        owner.finish(first, in: firstContext)
        owner.open(key: snapshot.rows[0].id, in: nextContext)
        let second = try XCTUnwrap(owner.route)
        owner.setActive(false, in: nextContext)
        XCTAssertNil(owner.route); XCTAssertFalse(owner.owns(second, in: nextContext))
        XCTAssertFalse(owner.consumeRead(.init(context: nextContext, revision: owner.readRevision)))
        owner.setActive(true, in: nextContext)
        XCTAssertTrue(owner.consumeRead(.init(context: nextContext, revision: owner.readRevision)))
    }
    func testDetailActualDepartureRequiresVisibleReentryBeforeAnotherRead() {
        let f = FeedbackFixture(), owner = ClubInvitationFeedbackPresentation()
        owner.appear(f.context, active: true)
        let old = ClubInvitationFeedbackPresentation.ReadTrigger(context: f.context, revision: owner.readRevision)
        XCTAssertTrue(owner.consumeRead(old)); owner.disappear(f.context)
        owner.requestRead(f.context)
        XCTAssertFalse(owner.consumeRead(.init(context: f.context, revision: owner.readRevision)))
        owner.appear(f.context, active: true)
        XCTAssertFalse(owner.consumeRead(old))
        XCTAssertTrue(owner.consumeRead(.init(context: f.context, revision: owner.readRevision)))
    }
    func testFreshDetailUsesSeparateReadModelAndCurrentServerRow() async throws {
        let f = FeedbackFixture(), parent = ClubInvitationFeedbackReadModel(), detail = ClubInvitationFeedbackReadModel()
        f.flow.value = f.value(received: [f.replacing(f.row(1), ["handleReason": .string("List reply")])])
        let parentPermit = try activate(parent, f.context); await load(parent, f, parentPermit)
        let parentSnapshot = try XCTUnwrap(accepted(parent, f)), parentID = parent.snapshotID, key = parentSnapshot.rows[0].id
        XCTAssertNil(detail.snapshot)
        f.flow.value = f.value(received: [f.replacing(f.row(1, status: .id(2)), ["handleReason": .string("Fresh reply"), "shareMode": .id(2), "fixedFee": .number(6.25)])])
        let detailPermit = try activate(detail, f.context); await load(detail, f, detailPermit)
        let fresh = try XCTUnwrap(accepted(detail, f))
        let target = try XCTUnwrap(fresh.target(key: key, context: f.context, snapshotID: detail.snapshotID))
        XCTAssertEqual(target.row.status, 2)
        XCTAssertEqual(detail.terms(for: target, in: f.context, clubReader: f.club, reader: f.flow, access: f.access)?.handleReason, "Fresh reply")
        XCTAssertEqual(detail.terms(for: target, in: f.context, clubReader: f.club, reader: f.flow, access: f.access)?.fixedFee, 6.25)
        XCTAssertEqual(parent.snapshotID, parentID); XCTAssertEqual(accepted(parent, f), parentSnapshot)
        XCTAssertEqual(f.club.reads, 2); XCTAssertEqual(f.access.resources, [.topics, .topics])
        XCTAssertEqual(f.flow.resources, [.invitations, .invitations]); XCTAssertEqual(f.access.sends, 0)
    }
    func testFreshDetailValidEmptyReadDoesNotReuseTheListTarget() async throws {
        let f = FeedbackFixture(), detail = ClubInvitationFeedbackReadModel()
        let list = try f.snapshot(received: [f.row(1)]), key = list.rows[0].id
        let permit = try activate(detail, f.context); await load(detail, f, permit)
        let fresh = try XCTUnwrap(accepted(detail, f))
        XCTAssertEqual(detail.phase, .ready)
        XCTAssertNil(fresh.target(key: key, context: f.context, snapshotID: detail.snapshotID))
        XCTAssertTrue(fresh.rows.isEmpty); XCTAssertEqual(f.access.sends, 0)
    }
    func testFreshDetailLosingOwnershipDoesNotLoadOrRevealInvitationTerms() async throws {
        let f = FeedbackFixture(), detail = ClubInvitationFeedbackReadModel(), permit = try activate(detail, f.context)
        f.club.returned = FeedbackClubReader.record(owner: false)
        await load(detail, f, permit)
        XCTAssertEqual(detail.phase, .denied); XCTAssertNil(detail.snapshot)
        XCTAssertTrue(f.access.resources.isEmpty); XCTAssertTrue(f.flow.resources.isEmpty); XCTAssertEqual(f.access.sends, 0)
    }
    func testFreshDetailLeaveFencesLateReplyAndReentryGetsANewPermit() async throws {
        let f = FeedbackFixture(), detail = ClubInvitationFeedbackReadModel(), scope = f.context
        let oldPermit = try activate(detail, scope)
        f.flow.held = true; let entered = expectation(description: "detail held")
        f.flow.entered = { entered.fulfill() }
        let old = Task { await self.load(detail, f, oldPermit) }
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertEqual(detail.phase, .loading); XCTAssertNil(detail.snapshot)
        detail.leave(scope)
        let newPermit = try activate(detail, scope)
        XCTAssertNotEqual(oldPermit.visibility, newPermit.visibility)
        f.flow.pending[0].resume(returning: f.value(received: [f.replacing(f.row(1), ["handleReason": .string("Old reply")])]))
        await old.value
        XCTAssertNil(detail.snapshot)
        f.flow.held = false; f.flow.value = f.value(received: [f.replacing(f.row(1), ["handleReason": .string("New reply")])])
        await load(detail, f, newPermit)
        let fresh = try XCTUnwrap(accepted(detail, f))
        let target = try XCTUnwrap(fresh.target(key: fresh.rows[0].id, context: scope, snapshotID: detail.snapshotID))
        XCTAssertEqual(detail.terms(for: target, in: scope, clubReader: f.club, reader: f.flow, access: f.access)?.handleReason, "New reply")
        XCTAssertEqual(f.access.sends, 0)
    }
}

extension ClubInvitationFeedbackViewTests {
    func testDetailCancelledTaskCannotConsumeThePendingVisibleRead() async {
        let f = FeedbackFixture(), owner = ClubInvitationFeedbackPresentation()
        owner.appear(f.context, active: true)
        let trigger = ClubInvitationFeedbackPresentation.ReadTrigger(context: f.context, revision: owner.readRevision)
        let cancelled = Task { owner.consumeRead(trigger) }
        cancelled.cancel()
        let consumed = await cancelled.value
        XCTAssertFalse(consumed)
        XCTAssertTrue(owner.consumeRead(trigger))
    }
}

@MainActor private final class DetailFirstReadGate: ClubReading {
    var isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 701, epoch: 1)
    var reads = 0
    var entered: (() -> Void)?
    var pending: CheckedContinuation<ClubRecord, Error>?
    func clubDetail(id: Int) async throws -> ClubRecord {
        reads += 1
        return try await withCheckedThrowingContinuation { pending = $0; entered?() }
    }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw CoopFlowFailure.unavailable }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
}

@MainActor private final class DetailTopicsReadGate: ClubGovernanceAccess {
    var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
    var isConfigured = true
    var storageNamespace = "synthetic-detail-topics"
    let allowsOfflineWrites = false
    var authorizationGeneration: UUID? = UUID()
    var resources: [ClubGovernanceRead] = []
    var entered: (() -> Void)?
    var pending: CheckedContinuation<ClubGovernanceSnapshot, Error>?
    func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
        resources.append(operation)
        return try await withCheckedThrowingContinuation { pending = $0; entered?() }
    }
    func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { throw ClubGovernanceFailure.notConfigured }
}

extension ClubInvitationFeedbackViewTests {
    func testDetailCloseDuringFirstReadStopsLaterReadsWithoutLeaveOrTaskCancellation() async throws {
        try await assertDetailFirstReadRetirement(background: false)
    }
    func testDetailBackgroundDuringFirstReadStopsLaterReadsWithoutLeaveOrTaskCancellation() async throws {
        try await assertDetailFirstReadRetirement(background: true)
    }
    private func assertDetailFirstReadRetirement(background: Bool) async throws {
        let f = FeedbackFixture(), club = DetailFirstReadGate(), model = ClubInvitationFeedbackReadModel()
        let owner = ClubInvitationFeedbackPresentation()
        let scope = ClubInvitationFeedbackContext(club: FeedbackClubReader.record(), clubReader: club, reader: f.flow, access: f.access)
        let list = try ClubInvitationFeedbackSnapshot(context: scope, topics: f.access.topics(), invitations: f.value(received: [f.row(1)]))
        owner.appear(scope, active: true); owner.open(key: list.rows[0].id, in: scope)
        let item = try XCTUnwrap(owner.route), permit = try activate(model, scope)
        let entered = expectation(description: "held first detail read")
        club.entered = { entered.fulfill() }
        let task = Task {
            await model.load(permit, clubReader: club, reader: f.flow, access: f.access,
                             isCurrent: { owner.owns(item, in: scope) && owner.isPresented })
            XCTAssertFalse(Task.isCancelled)
        }
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertEqual(club.reads, 1)
        if background { owner.setActive(false, in: scope) }
        else { owner.binding(for: item).wrappedValue = false }
        // No model.leave(), dismissal callback or task cancellation occurs here.
        club.pending?.resume(returning: FeedbackClubReader.record()); club.pending = nil
        await task.value
        XCTAssertTrue(f.access.resources.isEmpty); XCTAssertTrue(f.flow.resources.isEmpty)
        XCTAssertNil(model.snapshot); XCTAssertEqual(f.access.sends, 0)
    }
    func testDetailCloseDuringTopicsReadStopsInvitationReadWithoutLeave() async throws {
        let f = FeedbackFixture(), access = DetailTopicsReadGate(), owner = ClubInvitationFeedbackPresentation()
        let model = ClubInvitationFeedbackReadModel()
        let scope = ClubInvitationFeedbackContext(club: f.club.returned, clubReader: f.club, reader: f.flow, access: access)
        let list = try ClubInvitationFeedbackSnapshot(context: scope, topics: f.access.topics(), invitations: f.value(received: [f.row(1)]))
        owner.appear(scope, active: true); owner.open(key: list.rows[0].id, in: scope)
        let item = try XCTUnwrap(owner.route), permit = try activate(model, scope)
        let entered = expectation(description: "held detail topics")
        access.entered = { entered.fulfill() }
        let task = Task {
            await model.load(permit, clubReader: f.club, reader: f.flow, access: access,
                             isCurrent: { owner.owns(item, in: scope) && owner.isPresented })
        }
        await fulfillment(of: [entered], timeout: 1)
        owner.binding(for: item).wrappedValue = false
        access.pending?.resume(returning: f.access.topics()); access.pending = nil
        await task.value
        XCTAssertEqual(f.club.reads, 1); XCTAssertEqual(access.resources, [.topics])
        XCTAssertTrue(f.flow.resources.isEmpty); XCTAssertNil(model.snapshot)
    }
    func testDetailOldQueuedRetryCannotStartFirstReadAfterOwnerClose() async throws {
        let f = FeedbackFixture(), owner = ClubInvitationFeedbackPresentation(), model = ClubInvitationFeedbackReadModel()
        let scope = f.context, list = try f.snapshot(received: [f.row(1)])
        owner.appear(scope, active: true); owner.open(key: list.rows[0].id, in: scope)
        let item = try XCTUnwrap(owner.route), permit = try activate(model, scope)
        owner.binding(for: item).wrappedValue = false
        await model.load(permit, clubReader: f.club, reader: f.flow, access: f.access,
                         isCurrent: { owner.owns(item, in: scope) && owner.isPresented })
        XCTAssertEqual(f.club.reads, 0); XCTAssertTrue(f.access.resources.isEmpty)
        XCTAssertTrue(f.flow.resources.isEmpty); XCTAssertNil(model.snapshot)
    }
    func testDetailCloseDuringInvitationReadCannotPublishReplyWithoutLeave() async throws {
        let f = FeedbackFixture(), owner = ClubInvitationFeedbackPresentation(), model = ClubInvitationFeedbackReadModel()
        let scope = f.context, list = try f.snapshot(received: [f.row(1)])
        owner.appear(scope, active: true); owner.open(key: list.rows[0].id, in: scope)
        let item = try XCTUnwrap(owner.route), permit = try activate(model, scope)
        f.flow.held = true; let entered = expectation(description: "held detail invitation")
        f.flow.entered = { entered.fulfill() }
        let task = Task {
            await model.load(permit, clubReader: f.club, reader: f.flow, access: f.access,
                             isCurrent: { owner.owns(item, in: scope) && owner.isPresented })
        }
        await fulfillment(of: [entered], timeout: 1)
        owner.binding(for: item).wrappedValue = false
        f.flow.pending[0].resume(returning: f.value(received: [f.replacing(f.row(1), ["handleReason": .string("Late reply")])]))
        await task.value
        XCTAssertEqual(f.flow.resources, [.invitations]); XCTAssertNil(model.snapshot)
        XCTAssertNil(model.accepted(scope, clubReader: f.club, reader: f.flow, access: f.access))
        XCTAssertEqual(f.access.sends, 0)
    }
}

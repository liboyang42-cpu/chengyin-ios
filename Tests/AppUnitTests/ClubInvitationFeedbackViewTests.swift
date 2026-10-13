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

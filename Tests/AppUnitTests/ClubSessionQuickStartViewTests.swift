import XCTest
@testable import Questify

@MainActor final class ClubSessionQuickStartViewTests: XCTestCase {
    private func permit(_ m: ClubSessionQuickStartModel, _ f: QuickStartFixture) throws -> ClubSessionQuickStartModel.Permit {
        m.bind(f.context); return try XCTUnwrap(m.activate(f.context))
    }
    private func read(_ m: ClubSessionQuickStartModel, _ f: QuickStartFixture, _ p: ClubSessionQuickStartModel.Permit, _ id: Int? = nil) async -> ClubSessionQuickStartTarget? {
        await m.read(p, selecting: id, reader: f.reader, access: f.access, viewerRevision: { f.revision })
    }
    private func accepted(_ m: ClubSessionQuickStartModel, _ f: QuickStartFixture) -> ClubSessionQuickStartTopics? {
        m.accepted(f.context, reader: f.reader, access: f.access, viewerRevision: f.revision)
    }
    func testInitialReadLoadsRealChoicesWithoutOpeningOrSending() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
        let result = await read(m, f, p)
        XCTAssertNil(result); XCTAssertEqual(m.phase, .ready); XCTAssertEqual(accepted(m, f)?.rows.map(\.id), [91, 92])
        XCTAssertEqual(f.reader.reads, 1); XCTAssertEqual(f.access.resources, [.eventTopics]); XCTAssertEqual(f.access.sends, 0)
    }
    func testSelectionRechecksBothSourcesThenUsesRealCreateSeriesRoute() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
        _ = await read(m, f, p); let result = await read(m, f, p, 92), target = try XCTUnwrap(result)
        let route = ClubGovernanceFormRoute(operation: .createSeries, scope: target.scope, seed: target.seed)
        XCTAssertEqual(route.operation, .createSeries); XCTAssertEqual(route.scope, .init(clubID: 81, topicID: 92)); XCTAssertEqual(route.seed, ["recurrenceType": .string("ONCE")])
        XCTAssertEqual(f.reader.reads, 2); XCTAssertEqual(f.access.resources, [.eventTopics, .eventTopics]); XCTAssertEqual(f.access.sends, 0)
        XCTAssertTrue(m.isCurrent(target, context: f.context, reader: f.reader, access: f.access, viewerRevision: f.revision))
    }
    func testFreshOwnerLossOrWrongClubDeniesBeforeTopicRead() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
        f.reader.club = QuickStartReader.record(owner: false); _ = await read(m, f, p, 91); XCTAssertEqual(m.phase, .denied)
        f.reader.club = QuickStartReader.record(id: 82); _ = await read(m, f, p, 91); XCTAssertEqual(m.phase, .denied)
        XCTAssertTrue(f.access.resources.isEmpty); XCTAssertNil(m.target)
    }
    func testRemovedAndForgedTopicsCannotReachFormAndFreshChoicesRemain() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
        _ = await read(m, f, p); f.access.rows.removeLast()
        let removed = await read(m, f, p, 92); XCTAssertNil(removed); XCTAssertEqual(m.phase, .topicUnavailable)
        XCTAssertEqual(accepted(m, f)?.rows.map(\.id), [91]); XCTAssertNil(m.target)
        let forged = await read(m, f, p, 999); XCTAssertNil(forged); XCTAssertEqual(m.phase, .topicUnavailable)
    }
    func testPermissionFailureAndMalformedResponseNeverBecomeEmptySuccess() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
        f.access.permitted = false; _ = await read(m, f, p, 91); XCTAssertEqual(m.phase, .failed); XCTAssertNil(accepted(m, f))
        f.access.permitted = true; f.access.rows = [.null]; _ = await read(m, f, p); XCTAssertEqual(m.phase, .failed); XCTAssertNil(m.target)
    }
    func testFailedRefreshClearsStaleChoicesAndRetryRecovers() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
        _ = await read(m, f, p, 91); f.access.failure = true; _ = await read(m, f, p)
        XCTAssertEqual(m.phase, .failed); XCTAssertNil(m.topics); XCTAssertNil(m.target)
        f.access.failure = false; _ = await read(m, f, p); XCTAssertEqual(m.phase, .ready); XCTAssertNotNil(accepted(m, f))
    }
    func testCancelRetiresOldRetryPermitEvenAfterSameContextReentry() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), old = try permit(m, f)
        m.leave(f.context); _ = try permit(m, f); _ = await read(m, f, old, 91)
        XCTAssertEqual(f.reader.reads, 0); XCTAssertNil(m.target); XCTAssertEqual(m.phase, .idle)
    }
    func testAccountSwitchDuringOwnerReadCannotReachTopicsOrForm() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
        f.reader.held = true; let entered = expectation(description: "owner"); f.reader.entered = { entered.fulfill() }
        let task = Task { await self.read(m, f, p, 91) }; await fulfillment(of: [entered], timeout: 1)
        f.reader.clubIdentity = .init(accountID: 702, epoch: 2); f.reader.pending[0].resume(returning: f.reader.club)
        let result = await task.value; XCTAssertNil(result); XCTAssertTrue(f.access.resources.isEmpty); XCTAssertNil(m.target)
    }
    func testAuthorityNamespaceRevisionAndConfigurationChangesRetireHeldTopicRead() async throws {
        for mode in 0..<4 {
            let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
            f.access.held = true; let entered = expectation(description: "topics\(mode)"); f.access.entered = { entered.fulfill() }
            let task = Task { await self.read(m, f, p, 91) }; await fulfillment(of: [entered], timeout: 1)
            let snapshot = try f.access.snapshot()
            switch mode { case 0: f.access.authorizationGeneration = UUID(); case 1: f.access.storageNamespace = "other"; case 2: f.revision += 1; default: f.access.isConfigured = false }
            f.access.pending[0].resume(returning: snapshot); let result = await task.value
            XCTAssertNil(result); XCTAssertNil(m.target); XCTAssertNil(accepted(m, f)); XCTAssertEqual(f.access.sends, 0)
        }
    }
    func testLatestSelectionWinsAgainstOlderNonCancellingResponse() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
        f.access.held = true; let first = expectation(description: "first"), second = expectation(description: "second")
        f.access.entered = { f.access.pending.count == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await self.read(m, f, p, 91) }; await fulfillment(of: [first], timeout: 1)
        let new = Task { await self.read(m, f, p, 92) }; await fulfillment(of: [second], timeout: 1)
        f.access.pending[1].resume(returning: try f.access.snapshot()); _ = await new.value
        f.access.pending[0].resume(returning: try f.access.snapshot()); let oldResult = await old.value
        XCTAssertNil(oldResult); XCTAssertEqual(m.target?.topic.id, 92); XCTAssertEqual(f.access.sends, 0)
    }
    func testCanceledReadClearsLoadingAndRetryCanProceed() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
        f.access.held = true; let entered = expectation(description: "topics"); f.access.entered = { entered.fulfill() }
        let task = Task { await self.read(m, f, p, 91) }; await fulfillment(of: [entered], timeout: 1)
        task.cancel(); f.access.pending[0].resume(returning: try f.access.snapshot()); _ = await task.value
        XCTAssertEqual(m.phase, .idle); XCTAssertNil(m.target)
        f.access.held = false; _ = await read(m, f, p); XCTAssertEqual(m.phase, .ready)
    }
    func testLeavingDuringReadCannotApplyLateResult() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
        f.access.held = true; let entered = expectation(description: "topics"); f.access.entered = { entered.fulfill() }
        let task = Task { await self.read(m, f, p, 91) }; await fulfillment(of: [entered], timeout: 1)
        m.leave(f.context); f.access.pending[0].resume(returning: try f.access.snapshot()); _ = await task.value
        XCTAssertNil(m.target); XCTAssertNil(m.topics); XCTAssertEqual(m.phase, .idle)
    }
    func testReturnRefreshRetiresOldFormAndUsesCurrentTopics() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
        let result = await read(m, f, p, 92), target = try XCTUnwrap(result)
        f.access.rows.removeLast(); _ = await read(m, f, p)
        XCTAssertNil(m.target); XCTAssertEqual(accepted(m, f)?.rows.map(\.id), [91])
        XCTAssertFalse(m.isCurrent(target, context: f.context, reader: f.reader, access: f.access, viewerRevision: f.revision))
    }
    func testNewBoundContextImmediatelyRetiresOldPresentationAndPermit() async throws {
        let f = QuickStartFixture(), m = ClubSessionQuickStartModel(), p = try permit(m, f)
        let result = await read(m, f, p, 91), target = try XCTUnwrap(result), old = f.context
        f.revision += 1; m.bind(f.context)
        XCTAssertNil(m.permit(in: old)); XCTAssertNil(accepted(m, f))
        XCTAssertFalse(m.isCurrent(target, context: f.context, reader: f.reader, access: f.access, viewerRevision: f.revision))
        _ = await read(m, f, p, 91); XCTAssertEqual(f.reader.reads, 1)
    }
}
@MainActor private final class QuickStartReader: ClubReading {
    var isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 701, epoch: 1)
    var club = QuickStartReader.record()
    var reads = 0
    var held = false
    var failure = false
    var entered: (() -> Void)?
    var pending: [CheckedContinuation<ClubRecord, Error>] = []
    static func record(id: Int = 81, owner: Bool = true, admin: Bool = false) -> ClubRecord {
        try! JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":\(id),\"isOwner\":\(owner),\"viewerIsAdmin\":\(admin)}".utf8))
    }
    func clubDetail(id: Int) async throws -> ClubRecord {
        reads += 1; XCTAssertEqual(id, 81)
        if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
        if failure { throw ClubGovernanceFailure.malformed }; return club
    }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw ClubGovernanceFailure.notConfigured }
    func clubHome() async throws -> ClubHome { throw ClubGovernanceFailure.notConfigured }
    func clubOwned() async throws -> [ClubRecord] { throw ClubGovernanceFailure.notConfigured }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw ClubGovernanceFailure.notConfigured }
}
@MainActor private final class QuickStartAccess: ClubGovernanceAccess {
    var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
    var isConfigured = true
    var storageNamespace = "synthetic-session-start"
    let allowsOfflineWrites = false
    var authorizationGeneration: UUID? = UUID()
    var resources: [ClubGovernanceRead] = []
    var sends = 0
    var permitted = true
    var failure = false
    var held = false
    var entered: (() -> Void)?
    var pending: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
    var rows: [ClubGovernanceValue] = [.object(["id": .integer(91), "clubId": .integer(81), "name": .string(" Own topic ")]),
                                     .object(["id": .integer(92), "clubId": .integer(82), "name": .string("Cooperative topic")])]
    func snapshot(operation: ClubGovernanceRead = .eventTopics, scope: ClubGovernanceScope = .init(clubID: 81)) throws -> ClubGovernanceSnapshot {
        let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
            "roleCodes": .array([]), "permissions": .array(permitted ? [.string("club:activity:manage")] : []), "canManageRoles": .bool(false)]), scope: .init(clubID: 81))
        return .init(operation: operation, scope: scope, permissions: permissions, value: .array(rows))
    }
    func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
        resources.append(operation); XCTAssertEqual(operation, .eventTopics); XCTAssertEqual(scope, .init(clubID: 81)); XCTAssertTrue(options.isEmpty)
        if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
        if failure { throw ClubGovernanceFailure.malformed }; return try snapshot()
    }
    func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
}
@MainActor private final class QuickStartFixture {
    let reader = QuickStartReader(), access = QuickStartAccess()
    var revision: UInt64 = 7
    var context: ClubSessionQuickStartContext { .init(club: reader.club, reader: reader, access: access, viewerRevision: revision) }
    func topics() throws -> ClubSessionQuickStartTopics { try .init(context: context, snapshot: access.snapshot()) }
}

@MainActor final class ClubQuickStartCreationReturnTests: XCTestCase {
    func testHiddenBeforeOwnerReadStartsNoRequest() async throws {
        let fixture = QuickStartFixture(), model = ClubSessionQuickStartModel()
        model.bind(fixture.context); let permit = try XCTUnwrap(model.activate(fixture.context))
        let target = await model.read(permit, selecting: 91, reader: fixture.reader, access: fixture.access,
                                     viewerRevision: { fixture.revision }, isCurrent: { false })
        XCTAssertNil(target); XCTAssertEqual(fixture.reader.reads, 0); XCTAssertEqual(fixture.access.resources, [])
    }
    func testHiddenWhileOwnerSuspendsCannotStartTopicsWithoutLeave() async throws {
        let fixture = QuickStartFixture(), model = ClubSessionQuickStartModel()
        model.bind(fixture.context); let permit = try XCTUnwrap(model.activate(fixture.context))
        fixture.reader.held = true; var visible = true
        let entered = expectation(description: "held owner"); fixture.reader.entered = { entered.fulfill() }
        let task = Task { await model.read(permit, selecting: 91, reader: fixture.reader, access: fixture.access,
                                          viewerRevision: { fixture.revision }, isCurrent: { visible }) }
        await fulfillment(of: [entered], timeout: 1); visible = false
        fixture.reader.pending[0].resume(returning: fixture.reader.club)
        let result = await task.value
        XCTAssertNil(result); XCTAssertEqual(fixture.access.resources, []); XCTAssertNil(model.target)
    }
    func testInactiveDuringTopicsCannotPublishFormWithoutLeave() async throws {
        let fixture = QuickStartFixture(), model = ClubSessionQuickStartModel()
        model.bind(fixture.context); let permit = try XCTUnwrap(model.activate(fixture.context))
        fixture.access.held = true; var active = true
        let entered = expectation(description: "held topics"); fixture.access.entered = { entered.fulfill() }
        let task = Task { await model.read(permit, selecting: 91, reader: fixture.reader, access: fixture.access,
                                          viewerRevision: { fixture.revision }, isCurrent: { active }) }
        await fulfillment(of: [entered], timeout: 1); active = false
        fixture.access.pending[0].resume(returning: try fixture.access.snapshot())
        let result = await task.value
        XCTAssertNil(result); XCTAssertNil(model.target); XCTAssertNil(model.accepted(fixture.context,
            reader: fixture.reader, access: fixture.access, viewerRevision: fixture.revision))
    }
    func testFreshQuickStartSelectionUsesSameCreationOwnerWithoutGrantOrSending() async throws {
        let fixture = QuickStartFixture(), model = ClubSessionQuickStartModel(), owner = ClubSeriesCreationReturn()
        model.bind(fixture.context); let permit = try XCTUnwrap(model.activate(fixture.context))
        let loaded = await model.read(permit, selecting: 92, reader: fixture.reader, access: fixture.access,
                                      viewerRevision: { fixture.revision }, isCurrent: { true })
        let target = try XCTUnwrap(loaded), source = try XCTUnwrap(ClubSeriesCreationReturn.Source.quickStart(target, access: fixture.access))
        owner.open(source, visible: true, active: true)
        let item = try XCTUnwrap(owner.item)
        XCTAssertEqual(item.route.operation, .createSeries); XCTAssertEqual(item.route.scope, .init(clubID: 81, topicID: 92))
        XCTAssertEqual(item.route.seed, target.seed); XCTAssertEqual(target.topic.originClubID, 82)
        XCTAssertTrue(model.isCurrent(target, context: fixture.context, reader: fixture.reader, access: fixture.access, viewerRevision: fixture.revision))
        XCTAssertEqual(fixture.reader.reads, 1); XCTAssertEqual(fixture.access.resources, [.eventTopics]); XCTAssertEqual(fixture.access.sends, 0)
    }
    func testRetiredQuickStartTargetCannotSupplyReopenedSource() async throws {
        let fixture = QuickStartFixture(), model = ClubSessionQuickStartModel(), owner = ClubSeriesCreationReturn()
        model.bind(fixture.context); let permit = try XCTUnwrap(model.activate(fixture.context))
        let loaded = await model.read(permit, selecting: 91, reader: fixture.reader, access: fixture.access,
                                      viewerRevision: { fixture.revision })
        let target = try XCTUnwrap(loaded), source = try XCTUnwrap(ClubSeriesCreationReturn.Source.quickStart(target, access: fixture.access))
        owner.open(source, visible: true, active: true)
        let item = try XCTUnwrap(owner.item)
        model.leave(fixture.context)
        let current = model.isCurrent(target, context: fixture.context, reader: fixture.reader, access: fixture.access, viewerRevision: fixture.revision)
        owner.invalidateForm(item, source: current ? source : nil, active: true)
        XCTAssertNil(owner.item); XCTAssertNil(owner.destination); XCTAssertEqual(fixture.access.sends, 0)
    }

    @MainActor private final class CreationAccess: ClubGovernanceAccess {
        let base = QuickStartAccess()
        var identity: ClubReadIdentity? { base.identity }
        var isConfigured: Bool { base.isConfigured }
        var storageNamespace: String { base.storageNamespace }
        var authorizationGeneration: UUID? { base.authorizationGeneration }
        let allowsOfflineWrites = true
        var sends = 0
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            if operation == .members {
                let proof = try base.snapshot(operation: operation, scope: scope)
                return .init(operation: operation, scope: scope, permissions: proof.permissions,
                             value: .array([.object(["memberId": .integer(41)])]))
            }
            return try base.snapshot(operation: operation, scope: scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1
            return .object(["id": .integer(404), "clubId": .integer(81), "topicId": .integer(92),
                            "createdByMemberId": .integer(701), "requestId": review.command.fields["requestId"] ?? .null])
        }
    }
    func testFreshQuickStartThroughRealCoordinatorMatchesCreateAndDefersUntilVisible() async throws {
        let reader = QuickStartReader(), access = CreationAccess(), model = ClubSessionQuickStartModel()
        let context = ClubSessionQuickStartContext(club: reader.club, reader: reader, access: access, viewerRevision: 7)
        model.bind(context); let permit = try XCTUnwrap(model.activate(context))
        let selected = await model.read(permit, selecting: 92, reader: reader, access: access, viewerRevision: { 7 })
        let target = try XCTUnwrap(selected), source = try XCTUnwrap(ClubSeriesCreationReturn.Source.quickStart(target, access: access))
        let owner = ClubSeriesCreationReturn(); owner.open(source, visible: true, active: true)
        let item = try XCTUnwrap(owner.item)
        var draft = ClubGovernanceFormDraft(operation: .createSeries, scope: item.route.scope,
                                            seed: ["defaultLeadMemberId": .integer(41)])
        draft.text["startDate"] = "2099-01-01"
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(draft.command())
        XCTAssertTrue(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
        let value = try await coordinator.confirm(review)
        owner.acknowledge(review, value: value, state: coordinator.state, item: item, source: source, active: true)
        owner.dismissed(item, source: source, active: true)
        XCTAssertNil(owner.consume(source: source, visible: false, active: true))
        let destination = try XCTUnwrap(owner.consume(source: source, visible: true, active: true))
        XCTAssertEqual(destination.receipt.scope, .init(clubID: 81, topicID: 92, seriesID: 404))
        XCTAssertTrue(owner.destinationIsCurrent(destination, context: context.topicsContext, access: access))
        XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity)); XCTAssertEqual(access.sends, 1)
    }
}

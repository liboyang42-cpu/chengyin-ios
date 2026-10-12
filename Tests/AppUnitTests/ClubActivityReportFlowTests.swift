import XCTest
@testable import Questify

@MainActor final class ClubActivityReportFlowTests: XCTestCase {
    private final class Reader: ClubReading {
        var isClubConfigured = true
        var clubIdentity = ClubReadIdentity(accountID: 701, epoch: 2)
        var joined = true, clubID = 81, reads = 0
        var held = false
        var continuation: CheckedContinuation<ClubRecord, Error>?
        func value() throws -> ClubRecord { try JSONDecoder().decode(ClubRecord.self, from: JSONSerialization.data(withJSONObject: ["id": clubID, "isJoined": joined])) }
        func clubDetail(id: Int) async throws -> ClubRecord {
            reads += 1; XCTAssertEqual(id, 81)
            if held { return try await withCheckedThrowingContinuation { continuation = $0 } }
            return try value()
        }
        func clubHome() async throws -> ClubHome { throw APIError.notConfigured }
        func clubOwned() async throws -> [ClubRecord] { throw APIError.notConfigured }
        func clubDirectory(name: String?) async throws -> [ClubRecord] { throw APIError.notConfigured }
        func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw APIError.notConfigured }
    }
    private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 2)
        var isConfigured = true, allowsOfflineWrites = false
        var storageNamespace = "synthetic-activity-report"
        var authorizationGeneration: UUID? = UUID()
        var author = 702, topic = 91, activities = [41, 42]
        var activityLabels: [String: ClubGovernanceValue] = [:]
        var reads: [ClubGovernanceRead] = [], sends = 0
        var error: ClubGovernanceFailure?
        var afterRead: ((ClubGovernanceRead) -> Void)?
        var sendError: ClubGovernanceFailure?
        func context() -> ClubGovernanceReadContext {
            .init(operation: .topics, scope: .init(clubID: 81), identity: identity, viewerRevision: 5, authorizationGeneration: authorizationGeneration, accessIdentity: ObjectIdentifier(self))
        }
        func response(_ op: ClubGovernanceRead, scope: ClubGovernanceScope) throws -> ClubGovernanceSnapshot {
            let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array([.string("CLUB_MEMBER")]), "permissions": .array([])]), scope: scope)
            let value: ClubGovernanceValue
            if op == .topics { value = .array([.object(["id": .integer(topic), "memberId": .integer(author), "clubId": .integer(81)])]) }
            else if op == .topicOverview { value = .object(["id": .integer(topic), "name": .string("Synthetic topic"), "memberId": .integer(author), "activityList": .array(activities.map { .object(["id": ClubGovernanceValue.integer($0), "topicId": .integer(topic), "name": .string("Synthetic session")].merging(activityLabels, uniquingKeysWith: { _, current in current })) })]) }
            else if op == .cases { value = .array([]) }
            else { throw ClubGovernanceFailure.invalidRequest }
            return .init(operation: op, scope: scope, permissions: permissions, value: value)
        }
        func read(_ op: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            reads.append(op); XCTAssertTrue(options.isEmpty)
            if let error { throw error }; let value = try response(op, scope: scope); afterRead?(op); return value
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1; if let sendError { throw sendError }
            XCTAssertEqual(review.command.fields["targetType"], .string("ACTIVITY")); XCTAssertEqual(review.command.fields["targetId"], .integer(41))
            return .object(["id": .integer(501)])
        }
    }
    private final class Life { var current = true }
    private func setup(_ reader: Reader, _ access: Access, _ life: Life = Life()) throws -> ClubActivityReportFlow {
        let source = try XCTUnwrap(ClubActivityReportSource(topicID: 91, club: reader.value(), snapshot: access.response(.topics, scope: .init(clubID: 81)), context: access.context(), generation: 7))
        return .init(source: source, reader: reader, access: access, sourceIsCurrent: { life.current })
    }
    private func expectFailure(_ operation: () async throws -> Void) async { do { try await operation(); XCTFail("Expected rejection") } catch {} }
    func testMultipleRequiresExplicitChoiceAndReadsFreshAgain() async throws {
        let r = Reader(), a = Access(), f = try setup(r, a); await f.load()
        XCTAssertNil(f.target); XCTAssertEqual(f.choices.map(\.id), [41, 42]); let choice = f.choices[0]
        await f.select(choice); XCTAssertEqual(f.target?.choice.id, 41); XCTAssertEqual(r.reads, 2)
        XCTAssertEqual(a.reads, [.topics, .topicOverview, .topics, .topicOverview]); XCTAssertEqual(a.sends, 0)
    }
    func testSingletonDirectAndEmptyDoesNotInventTarget() async throws {
        let r = Reader(), a = Access(); a.activities = [41]; let f = try setup(r, a); await f.load()
        XCTAssertEqual(f.target?.choice.id, 41)
        let other = Access(); other.activities = []; let empty = try setup(r, other); await empty.load()
        XCTAssertTrue(empty.choices.isEmpty); XCTAssertNil(empty.target)
    }
    func testRemovedChoiceDoesNotFallBackToRemainingActivity() async throws {
        let r = Reader(), a = Access(), f = try setup(r, a); await f.load(); let choice = f.choices[0]; a.activities = [42]
        await f.select(choice); XCTAssertNil(f.target); XCTAssertTrue(f.choices.isEmpty); XCTAssertNotNil(f.failure)
    }
    func testFreshMembershipAndAuthorGateEveryRead() async throws {
        let r = Reader(), a = Access(), f = try setup(r, a); r.joined = false; await f.load()
        XCTAssertTrue(a.reads.isEmpty); XCTAssertNil(f.target)
        r.joined = true; a.author = 701; await f.load(); XCTAssertEqual(a.reads, [.topics]); XCTAssertTrue(f.choices.isEmpty)
    }
    func testWrongTopicAndDuplicateActivitiesDenied() async throws {
        let r = Reader(), a = Access(), f = try setup(r, a); a.topic = 92; await f.load(); XCTAssertNil(f.target)
        a.topic = 91; a.activities = [41, 41]; await f.load(); XCTAssertTrue(f.choices.isEmpty)
    }
    func testFailureClearsChoicesAndRetryRecovers() async throws {
        let r = Reader(), a = Access(), f = try setup(r, a); await f.load(); a.error = .forbidden; await f.load()
        XCTAssertTrue(f.choices.isEmpty); XCTAssertNotNil(f.failure); a.error = nil; await f.load(); XCTAssertEqual(f.choices.count, 2)
    }
    func testRefreshEpochAuthorizationNamespaceAndSourceClose() async throws {
        for field in 0...3 {
            let r = Reader(), a = Access(), life = Life(), f = try setup(r, a, life)
            if field == 0 { r.clubIdentity = .init(accountID: 701, epoch: 3) }
            if field == 1 { a.authorizationGeneration = UUID() }
            if field == 2 { a.storageNamespace = "other" }
            if field == 3 { life.current = false }
            await f.load(); XCTAssertTrue(f.choices.isEmpty); XCTAssertTrue(a.reads.isEmpty); XCTAssertFalse(f.isCurrent)
        }
    }
    func testMutationDuringReadCannotPublishOldSuccess() async throws {
        let r = Reader(), a = Access(), f = try setup(r, a); a.afterRead = { _ in a.authorizationGeneration = UUID() }
        await f.load(); XCTAssertNil(f.target); XCTAssertTrue(f.choices.isEmpty)
    }
    func testCloseWhileHeldReadNeverPublishes() async throws {
        let r = Reader(), a = Access(), f = try setup(r, a); r.held = true
        let work = Task { await f.load() }
        while r.continuation == nil { await Task.yield() }
        f.close(); r.continuation?.resume(returning: try r.value()); await work.value
        XCTAssertFalse(f.isCurrent); XCTAssertNil(f.target); XCTAssertTrue(a.reads.isEmpty)
    }
    func testDoubleLoadAndOldChoiceDoNotDispatch() async throws {
        let r = Reader(), a = Access(), f = try setup(r, a); await f.load(); let old = f.choices[0]
        await f.select(old); await f.select(old); XCTAssertEqual(r.reads, 2); XCTAssertEqual(a.sends, 0)
    }
    func testPreflightRechecksTargetAndKeepsDraftTargetOnTemporaryFailure() async throws {
        let r = Reader(), a = Access(); a.activities = [41]; let f = try setup(r, a); await f.load(); let target = try XCTUnwrap(f.target)
        a.error = .forbidden; await expectFailure { try await f.validate(target) }
        XCTAssertEqual(f.target, target); XCTAssertTrue(f.choices.isEmpty)
        a.error = nil; try await f.validate(target); XCTAssertEqual(f.target, target)
        a.activities = [42]; await expectFailure { try await f.validate(target) }; XCTAssertEqual(a.sends, 0)
    }
    func testReadOnlyProductionGateCannotSendReport() async throws {
        let r = Reader(), a = Access(); a.activities = [41]; let f = try setup(r, a); await f.load(); let target = try XCTUnwrap(f.target)
        var draft = ClubGovernanceFormDraft(operation: .report, scope: target.scope, seed: target.seed); draft.text["reason"] = "Synthetic facts"
        try await f.validate(target); let owner = ClubGovernanceCoordinator(access: a), review = try await owner.prepare(draft.command())
        try await f.validate(target); await expectFailure { _ = try await owner.confirm(review) }; XCTAssertEqual(a.sends, 0)
    }
    func testFakeReviewReceiptThenClosePreservesExactTarget() async throws {
        let r = Reader(), a = Access(); a.activities = [41]; a.allowsOfflineWrites = true
        let f = try setup(r, a); await f.load(); let target = try XCTUnwrap(f.target)
        var draft = ClubGovernanceFormDraft(operation: .report, scope: target.scope, seed: target.seed); draft.text["reason"] = "Synthetic facts"
        let owner = ClubGovernanceCoordinator(access: a); try await f.validate(target)
        let review = try await owner.prepare(draft.command()); try await f.validate(target)
        let receipt = try await owner.confirm(review); XCTAssertEqual(receipt["id"], .integer(501)); XCTAssertEqual(a.sends, 1)
        f.close(); XCTAssertNil(f.target); XCTAssertFalse(f.isCurrent)
        await expectFailure { _ = try await owner.confirm(review) }; XCTAssertEqual(a.sends, 1)
    }
    func testFakeUnknownOutcomeCannotResubmit() async throws {
        let r = Reader(), a = Access(); a.activities = [41]; a.allowsOfflineWrites = true; a.sendError = .unknown(message: nil)
        let f = try setup(r, a); await f.load(); let target = try XCTUnwrap(f.target)
        var draft = ClubGovernanceFormDraft(operation: .report, scope: target.scope, seed: target.seed); draft.text["reason"] = "Synthetic facts"
        let owner = ClubGovernanceCoordinator(access: a), command = try draft.command(), review = try await owner.prepare(command)
        try await f.validate(target); await expectFailure { _ = try await owner.confirm(review) }
        XCTAssertEqual(owner.state, .unknown); XCTAssertTrue(owner.isLocked(command, identity: target.source.context.identity!))
        await expectFailure { _ = try await owner.prepare(command) }; XCTAssertEqual(a.sends, 1)
    }

    private func assertChangedActivityLabelCannotConfirm(_ key: String, replacement: String) async throws {
        let reader = Reader(), access = Access()
        access.activities = [41]; access.allowsOfflineWrites = true
        access.activityLabels = ["name": .string("Reviewed session"), "startDate": .string("2026-11-01"), "startTime": .string("19:00")]
        let flow = try setup(reader, access)
        await flow.load()
        let target = try XCTUnwrap(flow.target)
        XCTAssertEqual(target.choice.id, 41)
        XCTAssertEqual(target.choice.name, "Reviewed session")
        XCTAssertEqual(target.choice.startDate, "2026-11-01")
        XCTAssertEqual(target.choice.startTime, "19:00")
        var draft = ClubGovernanceFormDraft(operation: .report, scope: target.scope, seed: target.seed)
        draft.text["reason"] = "Synthetic facts"
        let coordinator = ClubGovernanceCoordinator(access: access)
        try await flow.validate(target)
        let review = try await coordinator.prepare(draft.command())
        access.activityLabels[key] = .string(replacement)
        do {
            // This is the production ordering: failed validation must stop before confirm.
            try await flow.validate(target)
            _ = try await coordinator.confirm(review)
            XCTFail("Changed displayed activity evidence must not confirm")
        } catch let failure as ClubGovernanceFailure {
            XCTAssertEqual(failure, .targetChanged)
        } catch { XCTFail("Expected targetChanged, received \(error)") }
        XCTAssertEqual(access.sends, 0)
        XCTAssertEqual(coordinator.state, .reviewing)
        XCTAssertEqual(flow.failure, .targetChanged)
        XCTAssertEqual(flow.target, target)
        XCTAssertTrue(flow.choices.isEmpty)
    }
    func testSameActivityIDChangedNameCannotConfirmReviewedTarget() async throws {
        try await assertChangedActivityLabelCannotConfirm("name", replacement: "Renamed session")
    }
    func testSameActivityIDChangedStartDateCannotConfirmReviewedTarget() async throws {
        try await assertChangedActivityLabelCannotConfirm("startDate", replacement: "2026-11-02")
    }
    func testSameActivityIDChangedStartTimeCannotConfirmReviewedTarget() async throws {
        try await assertChangedActivityLabelCannotConfirm("startTime", replacement: "20:00")
    }

    private func reportHost(_ reader: Reader, _ access: Access) throws -> ClubActivityReportPresentation.Host {
        .init(context: access.context(), readerID: ObjectIdentifier(reader), club: try reader.value())
    }
    func testHiddenDismissQueuesButNeverReadsUntilVisibleReturn() async throws {
        let reader = Reader(), access = Access(), owner = ClubActivityReportPresentation()
        let host = try reportHost(reader, access), flow = try setup(reader, access)
        owner.appear(host, active: true)
        XCTAssertTrue(owner.open(flow, host: host))
        let item = try XCTUnwrap(owner.presented)
        owner.disappear()
        XCTAssertTrue(owner.isCurrent(item)) // Cover alone does not invalidate the child's flow.
        XCTAssertTrue(owner.dismissed(item.id))
        XCTAssertNil(owner.beginRead(host, returning: true))
        XCTAssertTrue(owner.hasPendingReturn)
        XCTAssertTrue(access.reads.isEmpty)
        owner.appear(host, active: true)
        let ticket = try XCTUnwrap(owner.beginRead(host, returning: true))
        let model = ClubEventCalendarReadModel()
        if owner.canRead(ticket) { model.resume(); await model.load(ticket.host.context, access: access) }
        owner.endRead(ticket)
        XCTAssertEqual(access.reads, [.topics])
        XCTAssertNil(model.failure); XCTAssertEqual(model.context, host.context)
        XCTAssertNil(owner.beginRead(host, returning: true))
        XCTAssertFalse(owner.hasPendingReturn)
        XCTAssertEqual(access.sends, 0)
    }
    func testParentAppearsBeforeSheetDismissStillConsumesOneReturn() throws {
        let reader = Reader(), access = Access(), owner = ClubActivityReportPresentation()
        let host = try reportHost(reader, access)
        owner.appear(host, active: true)
        XCTAssertTrue(owner.open(try setup(reader, access), host: host))
        let item = try XCTUnwrap(owner.presented)
        owner.disappear(); owner.appear(host, active: true)
        XCTAssertNil(owner.beginRead(host)) // Do not reload under the still-current sheet.
        XCTAssertTrue(owner.dismissed(item.id))
        let ticket = try XCTUnwrap(owner.beginRead(host, returning: true))
        XCTAssertTrue(owner.canRead(ticket)); owner.endRead(ticket)
        XCTAssertNil(owner.beginRead(host, returning: true))
    }
    func testChangedReaderOrScopeRejectsLateDismissWithoutReading() throws {
        for changeReader in [true, false] {
            let reader = Reader(), access = Access(), owner = ClubActivityReportPresentation()
            let host = try reportHost(reader, access), otherReader = Reader()
            owner.appear(host, active: true)
            XCTAssertTrue(owner.open(try setup(reader, access), host: host))
            let item = try XCTUnwrap(owner.presented)
            let changed = ClubActivityReportPresentation.Host(
                context: changeReader ? host.context : .init(operation: .topics, scope: .init(clubID: 82), identity: access.identity,
                    viewerRevision: 5, authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access)),
                readerID: changeReader ? ObjectIdentifier(otherReader) : host.readerID, club: host.club)
            XCTAssertTrue(owner.bind(changed, active: true))
            XCTAssertFalse(owner.dismissed(item.id))
            XCTAssertNil(owner.beginRead(changed, returning: true))
            XCTAssertNil(owner.presented); XCTAssertFalse(owner.hasPendingReturn)
            XCTAssertTrue(access.reads.isEmpty); XCTAssertEqual(access.sends, 0)
        }
    }
    func testOldSheetBindingAndDismissCannotCancelNewReportReview() async throws {
        let reader = Reader(), access = Access(), owner = ClubActivityReportPresentation()
        let host = try reportHost(reader, access), coordinator = ClubGovernanceCoordinator(access: access)
        owner.appear(host, active: true)
        XCTAssertTrue(owner.open(try setup(reader, access), host: host))
        let old = try XCTUnwrap(owner.presented)
        let sheet = ClubActivityReportSheetOwner(item: old, presentation: owner, coordinator: coordinator, dismissed: { _ in })
        let oldBinding = sheet.presentationBinding
        XCTAssertTrue(owner.dismissed(old.id))
        let ticket = try XCTUnwrap(owner.beginRead(host, returning: true)); owner.endRead(ticket)
        XCTAssertTrue(owner.open(try setup(reader, access), host: host))
        let current = try XCTUnwrap(owner.presented)
        var draft = ClubGovernanceFormDraft(operation: .report, scope: .init(clubID: 81),
            seed: ["targetType": .string("ACTIVITY"), "targetId": .integer(41)])
        draft.text["reason"] = "Synthetic facts"
        _ = try await coordinator.prepare(draft.command())
        oldBinding.wrappedValue = false
        var cancellations = 0
        if owner.dismissed(old.id) { cancellations += 1; coordinator.cancelReview() }
        XCTAssertEqual(cancellations, 0)
        XCTAssertEqual(coordinator.state, .reviewing)
        XCTAssertEqual(owner.presented?.id, current.id)
        XCTAssertTrue(owner.isCurrent(current)); XCTAssertFalse(oldBinding.wrappedValue)
        XCTAssertFalse(owner.hasPendingReturn); XCTAssertEqual(access.sends, 0)
    }
    func testQueuedCalendarReadCannotStartAfterParentLeaves() async throws {
        let reader = Reader(), access = Access(), owner = ClubActivityReportPresentation()
        let host = try reportHost(reader, access), model = ClubEventCalendarReadModel()
        owner.appear(host, active: true)
        let ticket = try XCTUnwrap(owner.beginRead(host))
        owner.disappear()
        if owner.canRead(ticket) { model.resume(); await model.load(ticket.host.context, access: access) }
        owner.endRead(ticket)
        XCTAssertTrue(access.reads.isEmpty); XCTAssertNil(model.context)
        XCTAssertFalse(owner.canRead(ticket))
    }
    func testSceneInactivityRetiresReportAndPendingDismissal() throws {
        let reader = Reader(), access = Access(), owner = ClubActivityReportPresentation()
        let host = try reportHost(reader, access)
        owner.appear(host, active: true)
        XCTAssertTrue(owner.open(try setup(reader, access), host: host))
        let old = try XCTUnwrap(owner.presented)
        XCTAssertTrue(owner.bind(host, active: false))
        XCTAssertFalse(owner.dismissed(old.id))
        XCTAssertNil(owner.beginRead(host, returning: true))
        owner.bind(host, active: true)
        XCTAssertFalse(owner.hasPendingReturn); XCTAssertFalse(owner.isCurrent(old))
        XCTAssertTrue(access.reads.isEmpty); XCTAssertEqual(access.sends, 0)
    }
}

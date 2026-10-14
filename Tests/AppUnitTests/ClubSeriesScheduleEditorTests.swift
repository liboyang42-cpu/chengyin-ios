import XCTest
@testable import Questify

@MainActor final class ClubSeriesScheduleEditorTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "synthetic-schedule"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var resources: [ClubGovernanceRead] = []
        var sends = 0
        var allowed = true
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            resources.append(operation)
            let permission = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
                "roleCodes": .array([]), "permissions": .array(allowed ? [.string("club:activity:manage")] : []), "canManageRoles": .bool(false)]), scope: scope)
            let value: ClubGovernanceValue
            switch operation {
            case .eventTopics: value = .array([.object(["id": .integer(91)])])
            case .seriesDetail: value = .object(["version": .integer(7), "topicId": .integer(91)])
            case .members: value = .array([.object(["memberId": .integer(41)])])
            default: throw ClubGovernanceFailure.invalidRequest
            }
            return .init(operation: operation, scope: scope, permissions: permission, value: value)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
    }
    private let now = ISO8601DateFormatter().date(from: "2026-10-11T01:00:00Z")!
    private func form(_ operation: ClubGovernanceMutation = .createSeries, club: Int = 81) -> ClubGovernanceFormDraft {
        .init(operation: operation, scope: .init(clubID: club, topicID: 91, seriesID: operation == .updateSeries ? 101 : nil),
              seed: ["defaultLeadMemberId": .integer(41), "version": .integer(7), "futureDates": .array([.string("2026-10-12")])])
    }
    private func session(_ form: ClubGovernanceFormDraft, _ access: Access) throws -> ClubSeriesScheduleSession {
        try XCTUnwrap(.init(form: form, identity: access.identity, access: access, now: now))
    }
    func testOrdinaryConfiguredReaderCreatesSessionWithoutReadOrWrite() throws {
        let access = Access(), draft = form(), value = try session(form(), access)
        XCTAssertEqual(value.operation, .createSeries); XCTAssertEqual(value.context.scope, draft.scope)
        XCTAssertEqual(value.context.accessIdentity, ObjectIdentifier(access)); XCTAssertEqual(access.resources, []); XCTAssertEqual(access.sends, 0)
    }
    func testSignedOutUnconfiguredAndWrongIdentityCannotOpen() {
        let access = Access(), draft = form()
        XCTAssertNil(ClubSeriesScheduleSession(form: draft, identity: nil, access: access, now: now))
        XCTAssertNil(ClubSeriesScheduleSession(form: draft, identity: .init(accountID: 702, epoch: 1), access: access, now: now))
        access.isConfigured = false; XCTAssertNil(ClubSeriesScheduleSession(form: draft, identity: access.identity, access: access, now: now))
    }
    func testCancelAndReopenRejectOldSheetEvenForSameDraft() throws {
        let access = Access(), draft = form(), old = try session(draft, access), next = try session(draft, access)
        XCTAssertTrue(old.isCurrent(activeID: old.id, form: draft, identity: access.identity, access: access))
        XCTAssertFalse(old.isCurrent(activeID: nil, form: draft, identity: access.identity, access: access))
        XCTAssertFalse(old.isCurrent(activeID: next.id, form: draft, identity: access.identity, access: access))
    }
    func testIdentityEpochAndAuthorizationReplacementRejectDelayedApply() throws {
        let access = Access(), draft = form(), value = try session(draft, access), original = access.identity
        access.identity = .init(accountID: 701, epoch: 2)
        XCTAssertFalse(value.isCurrent(activeID: value.id, form: draft, identity: original, access: access))
        access.identity = original; access.authorizationGeneration = UUID()
        XCTAssertFalse(value.isCurrent(activeID: value.id, form: draft, identity: original, access: access))
    }
    func testChangedReaderNamespaceAndTargetRejectApply() throws {
        let access = Access(), draft = form(), value = try session(draft, access), other = Access()
        other.authorizationGeneration = access.authorizationGeneration
        XCTAssertFalse(value.isCurrent(activeID: value.id, form: draft, identity: other.identity, access: other))
        access.storageNamespace = "another-scope"
        XCTAssertFalse(value.isCurrent(activeID: value.id, form: draft, identity: access.identity, access: access))
        access.storageNamespace = value.namespace
        XCTAssertFalse(value.isCurrent(activeID: value.id, form: form(club: 82), identity: access.identity, access: access))
    }
    func testParentDraftEditInvalidatesSheetBeforeItCanOverwritePolicy() throws {
        let access = Access(); var draft = form(); let value = try session(draft, access)
        draft.text["capacity"] = "20"
        XCTAssertFalse(value.isCurrent(activeID: value.id, form: draft, identity: access.identity, access: access))
    }
    func testAppliedCreateAndUpdateCanUseExistingReviewAndCancelWithoutDispatch() async throws {
        for operation in [ClubGovernanceMutation.createSeries, .updateSeries] {
            let access = Access(), draft = form(operation), value = try session(draft, access)
            var schedule = value.initial; schedule.startDate = "2026-10-12"; schedule.recurrence = "WEEKLY"; schedule.occurrenceCount = 2
            let command = try schedule.applying(to: draft, now: now).command()
            let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command)
            XCTAssertEqual(review.command.fields["startDate"], .string("2026-10-12"))
            XCTAssertEqual(review.command.fields["occurrenceCount"], .integer(2))
            XCTAssertEqual(access.resources, [operation.reviewRead, .members]); XCTAssertFalse(access.canDispatch(command))
            coordinator.cancelReview(); XCTAssertEqual(access.sends, 0)
        }
    }
    func testExistingPermissionPreflightStillRejectsAndNeverReadsMembersOrSends() async throws {
        let access = Access(), draft = form(), value = try session(draft, access); access.allowed = false
        var schedule = value.initial; schedule.startDate = "2026-10-12"
        let coordinator = ClubGovernanceCoordinator(access: access)
        do { _ = try await coordinator.prepare(schedule.applying(to: draft, now: now).command()); XCTFail("Expected forbidden") }
        catch { XCTAssertEqual(error as? ClubGovernanceFailure, .forbidden) }
        XCTAssertEqual(access.resources, [.eventTopics]); XCTAssertEqual(access.sends, 0)
    }
}

@MainActor final class ClubSeriesUpdateReturnTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "series-return-fixture"
        var journalRealm = "series-return-realm"
        var authorizationGeneration: UUID? = UUID()
        let allowsOfflineWrites = true
        var reads: [ClubGovernanceRead] = []
        var sends = 0
        var failure: ClubGovernanceFailure?
        var value: ClubGovernanceValue = .object(["id": .integer(101), "topicId": .integer(91), "version": .integer(7)])
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            reads.append(operation)
            return try snapshot(operation, scope: scope)
        }
        func snapshot(_ operation: ClubGovernanceRead = .seriesDetail, scope: ClubGovernanceScope) throws -> ClubGovernanceSnapshot {
            let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
                "roleCodes": .array([]), "permissions": .array([.string("club:activity:manage")])]), scope: scope)
            return .init(operation: operation, scope: scope, permissions: permissions,
                         value: operation == .members ? .array([.object(["memberId": .integer(41)])]) : value)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1
            if let failure { throw failure }
            return .object(["id": .integer(101)])
        }
    }
    private let scope = ClubGovernanceScope(clubID: 81, topicID: 91, seriesID: 101)
    private func source(_ access: Access, generation: UInt64 = 5, context: ClubGovernanceReadContext? = nil) throws -> ClubSeriesUpdateReturn.Source {
        let context = context ?? .init(operation: .seriesDetail, scope: scope, identity: access.identity,
            viewerRevision: 0, authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
        return try XCTUnwrap(.init(context: context, snapshot: access.snapshot(scope: scope), generation: generation, access: access))
    }
    private func command() throws -> ClubGovernanceCommand {
        var draft = ClubGovernanceFormDraft(operation: .updateSeries, scope: scope,
            seed: ["version": .integer(7), "defaultLeadMemberId": .integer(41)])
        draft.text["startDate"] = "2099-01-01"; draft.text["capacity"] = "20"
        return try draft.command()
    }
    private func opened(_ owner: ClubSeriesUpdateReturn, _ source: ClubSeriesUpdateReturn.Source) throws -> ClubSeriesUpdateReturn.Item {
        owner.open(source, visible: true, active: true)
        return try XCTUnwrap(owner.item)
    }
    private func acknowledged(_ owner: ClubSeriesUpdateReturn, _ access: Access,
                              _ source: ClubSeriesUpdateReturn.Source) async throws -> (ClubSeriesUpdateReturn.Item, ClubGovernanceCoordinator, ClubGovernanceReview) {
        let item = try opened(owner, source), coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(command())
        XCTAssertTrue(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
        let receipt = try await coordinator.confirm(review)
        owner.acknowledge(review, receipt: receipt, state: coordinator.state, item: item, source: source, active: true)
        return (item, coordinator, review)
    }
    func testActualAcknowledgementReturnsOnceAndKeepsCoordinatorLock() async throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access)
        let (item, coordinator, review) = try await acknowledged(owner, access, source)
        XCTAssertFalse(owner.isPresented); XCTAssertNil(owner.consume(source: source, visible: true, active: true))
        XCTAssertTrue(owner.dismissed(item, source: source, active: true))
        XCTAssertEqual(owner.consume(source: source, visible: true, active: true), source)
        XCTAssertNil(owner.consume(source: source, visible: true, active: true))
        XCTAssertEqual(access.sends, 1); XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
        do { _ = try await coordinator.prepare(review.command); XCTFail("The return must not unlock the write") }
        catch { XCTAssertEqual(error as? ClubGovernanceFailure, .outcomeLocked) }
    }
    func testDismissBeforeVisibleKeepsPendingUntilVisible() async throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access)
        let (item, _, _) = try await acknowledged(owner, access, source)
        owner.dismissed(item, source: source, active: true)
        XCTAssertNil(owner.consume(source: source, visible: false, active: true)); XCTAssertNotNil(owner.item)
        XCTAssertEqual(owner.consume(source: source, visible: true, active: true), source)
    }
    func testVisibleBeforeDismissDoesNotConsumeEarly() async throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access)
        let (item, _, _) = try await acknowledged(owner, access, source)
        XCTAssertNil(owner.consume(source: source, visible: true, active: true))
        owner.dismissed(item, source: source, active: true)
        XCTAssertEqual(owner.consume(source: source, visible: true, active: true), source)
    }
    func testCancelSendsNothingAndNeverCreatesReturn() throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access), item = try opened(owner, source)
        owner.binding(item, source: { source }, active: { true }).wrappedValue = false
        owner.dismissed(item, source: source, active: true)
        XCTAssertNil(owner.item); XCTAssertNil(owner.consume(source: source, visible: true, active: true))
        XCTAssertEqual(access.reads, []); XCTAssertEqual(access.sends, 0)
    }
    func testUnknownWriteStaysPresentedLockedAndCannotReturn() async throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access), item = try opened(owner, source)
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command())
        XCTAssertTrue(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
        access.failure = .unknown(message: nil)
        do { _ = try await coordinator.confirm(review); XCTFail("Expected unknown") } catch {}
        owner.acknowledge(review, receipt: .object(["id": .integer(101)]), state: coordinator.state, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
        XCTAssertNil(owner.consume(source: source, visible: true, active: true)); XCTAssertEqual(access.sends, 1)
    }
    func testRejectedAttemptCanPrepareAgainWithoutInventingSuccess() async throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access), item = try opened(owner, source)
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command())
        XCTAssertTrue(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
        access.failure = .rejected(code: nil, message: nil)
        do { _ = try await coordinator.confirm(review); XCTFail("Expected rejected") } catch {}
        XCTAssertNil(owner.consume(source: source, visible: true, active: true)); XCTAssertTrue(owner.isPresented)
        let next = try await coordinator.prepare(command())
        XCTAssertNotEqual(next.id, review.id)
        XCTAssertTrue(owner.begin(next, state: coordinator.state, item: item, source: source, active: true))
    }
    func testWrongReceiptIDDoesNotCloseOrRefresh() async throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access), item = try opened(owner, source)
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command())
        XCTAssertTrue(owner.begin(review, state: .reviewing, item: item, source: source, active: true))
        owner.acknowledge(review, receipt: .object(["id": .integer(102)]), state: .acknowledged, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.consume(source: source, visible: true, active: true))
    }
    func testEveryNonAcknowledgedStateRejectsReturn() async throws {
        for state in [ClubGovernanceWriteState.idle, .reviewing, .preflighting, .submitting, .rejected, .conflict, .unknown] {
            let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access), item = try opened(owner, source)
            let review = try await ClubGovernanceCoordinator(access: access).prepare(command())
            XCTAssertTrue(owner.begin(review, state: .reviewing, item: item, source: source, active: true))
            owner.acknowledge(review, receipt: .object(["id": .integer(101)]), state: state, item: item, source: source, active: true)
            XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.consume(source: source, visible: true, active: true))
        }
    }
    func testDifferentSubmissionReviewCannotAcknowledgeCurrentSheet() async throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access), item = try opened(owner, source)
        let coordinator = ClubGovernanceCoordinator(access: access), old = try await coordinator.prepare(command())
        let current = try await coordinator.prepare(command())
        XCTAssertTrue(owner.begin(current, state: .reviewing, item: item, source: source, active: true))
        owner.acknowledge(old, receipt: .object(["id": .integer(101)]), state: .acknowledged, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented)
    }
    func testOldBindingCancelAndDismissCannotTouchReopenedOwner() throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access), old = try opened(owner, source)
        let oldBinding = owner.binding(old, source: { source }, active: { true })
        oldBinding.wrappedValue = false; owner.dismissed(old, source: source, active: true)
        let current = try opened(owner, source)
        XCTAssertFalse(oldBinding.wrappedValue); oldBinding.wrappedValue = false
        XCTAssertFalse(owner.dismissed(old, source: source, active: true))
        XCTAssertEqual(owner.item?.id, current.id); XCTAssertTrue(owner.isPresented)
    }
    func testOldAcknowledgementCannotCloseReopenedOwner() async throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access), old = try opened(owner, source)
        let review = try await ClubGovernanceCoordinator(access: access).prepare(command())
        XCTAssertTrue(owner.begin(review, state: .reviewing, item: old, source: source, active: true))
        owner.retire(); let current = try opened(owner, source)
        owner.acknowledge(review, receipt: .object(["id": .integer(101)]), state: .acknowledged, item: old, source: source, active: true)
        XCTAssertEqual(owner.item?.id, current.id); XCTAssertTrue(owner.isPresented)
    }
    func testBackgroundCannotConsumeAndRetirementCannotRevive() async throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access)
        let (item, _, _) = try await acknowledged(owner, access, source)
        owner.dismissed(item, source: source, active: true)
        XCTAssertNil(owner.consume(source: source, visible: true, active: false))
        owner.invalidateUnlessCurrent(source: source, active: false)
        XCTAssertNil(owner.consume(source: source, visible: true, active: true)); XCTAssertNil(owner.item)
    }
    func testSourceRefreshGenerationCannotConsumeOldReceipt() async throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access)
        let (item, _, _) = try await acknowledged(owner, access, source)
        owner.dismissed(item, source: source, active: true)
        let next = try self.source(access, generation: 6)
        XCTAssertNil(owner.consume(source: next, visible: true, active: true))
        owner.invalidateUnlessCurrent(source: next, active: true); XCTAssertNil(owner.item)
    }
    func testSameVersionChangedSourceBytesRejectCurrentOwner() throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access), item = try opened(owner, source)
        access.value = .object(["id": .integer(101), "topicId": .integer(91), "version": .integer(7), "defaultCapacity": .integer(99)])
        XCTAssertFalse(owner.current(item, source: try self.source(access), active: true))
    }
    func testIdentityAuthorizationNamespaceAndReaderChangesInvalidateSource() throws {
        let access = Access(), original = try source(access), owner = ClubSeriesUpdateReturn(), item = try opened(owner, original)
        access.identity = .init(accountID: 702, epoch: 1)
        XCTAssertFalse(owner.current(item, source: try source(access), active: true))
        access.identity = original.context.identity; access.authorizationGeneration = UUID()
        XCTAssertFalse(owner.current(item, source: try source(access), active: true))
        access.authorizationGeneration = original.context.authorizationGeneration; access.storageNamespace = "other"
        XCTAssertFalse(owner.current(item, source: try source(access), active: true))
        let other = Access(); other.authorizationGeneration = original.context.authorizationGeneration
        XCTAssertFalse(owner.current(item, source: try source(other), active: true))
    }
    func testHiddenInactiveAndMissingSourceCannotOpen() throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), source = try source(access)
        owner.open(source, visible: false, active: true); XCTAssertNil(owner.item)
        owner.open(source, visible: true, active: false); XCTAssertNil(owner.item)
        owner.open(nil, visible: true, active: true); XCTAssertNil(owner.item)
    }
    func testInvalidTargetVersionAndPermissionCannotCreateSource() throws {
        let access = Access(), source = try source(access)
        let invalid: [ClubGovernanceValue] = [.object(["id": .integer(102), "topicId": .integer(91), "version": .integer(7)]),
                                            .object(["id": .integer(101), "topicId": .integer(92), "version": .integer(7)]),
                                            .object(["id": .integer(101), "topicId": .integer(91)])]
        for value in invalid {
            let snapshot = ClubGovernanceSnapshot(operation: .seriesDetail, scope: scope, permissions: source.snapshot.permissions, value: value)
            XCTAssertNil(ClubSeriesUpdateReturn.Source(context: source.context, snapshot: snapshot, generation: 5, access: access))
        }
        let denied = ClubGovernanceSnapshot(operation: .seriesDetail, scope: scope, permissions: nil, value: access.value)
        XCTAssertNil(ClubSeriesUpdateReturn.Source(context: source.context, snapshot: denied, generation: 5, access: access))
    }
    func testCurrentBindingRejectsInvalidSourceBeforeViewObserverRuns() throws {
        let access = Access(), owner = ClubSeriesUpdateReturn(), original = try source(access), item = try opened(owner, original)
        var current: ClubSeriesUpdateReturn.Source? = original
        let binding = owner.binding(item, source: { current }, active: { true })
        XCTAssertTrue(binding.wrappedValue); current = nil
        XCTAssertFalse(binding.wrappedValue); binding.wrappedValue = false
        XCTAssertTrue(owner.isPresented)
        owner.invalidateUnlessCurrent(source: nil, active: true); XCTAssertNil(owner.item)
    }
}

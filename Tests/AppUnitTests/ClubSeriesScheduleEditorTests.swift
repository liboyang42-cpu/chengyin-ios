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
              seed: ["startTime": .string("09:00"), "defaultLeadMemberId": .integer(41), "version": .integer(7), "futureDates": .array([.string("2026-10-12")])])
    }
    private func session(_ form: ClubGovernanceFormDraft, _ access: Access) throws -> ClubSeriesScheduleSession {
        try XCTUnwrap(.init(form: form, identity: access.identity, access: access, now: now))
    }
    func testOrdinaryConfiguredReaderCreatesSessionWithoutReadOrWrite() throws {
        let access = Access(), draft = form(), value = try session(form(), access)
        XCTAssertEqual(value.operation, .createSeries); XCTAssertEqual(value.context.scope, draft.scope)
        XCTAssertEqual(value.context.accessIdentity, ObjectIdentifier(access)); XCTAssertEqual(access.resources, []); XCTAssertEqual(access.sends, 0)
    }
    func testUnknownUpdateSessionCannotApplyUntilExplicitTimeAndCancelPreservesDraft() throws {
        let access = Access()
        let draft = ClubGovernanceFormDraft(operation: .updateSeries,
            scope: .init(clubID: 81, topicID: 91, seriesID: 101),
            seed: ["defaultLeadMemberId": .integer(41), "version": .integer(7),
                   "futureDates": .array([.string("2026-10-12")]), "startTime": .null])
        let value = try session(draft, access)
        XCTAssertEqual(value.initial.startTime, "")
        XCTAssertEqual(value.initial.issue(now: now), .time)
        XCTAssertThrowsError(try value.initial.applying(to: draft, now: now))
        var edited = value.initial; edited.startTime = "09:00"
        XCTAssertNoThrow(try edited.applying(to: draft, now: now).command())
        XCTAssertEqual(draft.text["startTime"], "")
        XCTAssertFalse(value.isCurrent(activeID: nil, form: draft, identity: access.identity, access: access))
        XCTAssertEqual(access.sends, 0)
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
            seed: ["startTime": .string("09:00"), "version": .integer(7), "defaultLeadMemberId": .integer(41)])
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

@MainActor final class ClubSeriesOfferWindowTests: XCTestCase {
    private func draft(_ operation: ClubGovernanceMutation = .createSeries) -> ClubGovernanceFormDraft {
        var value = ClubGovernanceFormDraft(operation: operation,
            scope: .init(clubID: 81, topicID: 91, seriesID: operation == .updateSeries ? 101 : nil),
            seed: ["startTime": .string("09:00"), "version": .integer(7), "defaultLeadMemberId": .integer(41)])
        value.text["startDate"] = "2099-01-01"
        return value
    }
    func testMinuteBoundsAndHourRemaindersPreserveExactValue() {
        for value in [5, 59, 60, 90, 1439, 1440] {
            XCTAssertEqual(ClubSeriesOfferWindowPresentation(raw: String(value)).minutes, value)
        }
    }
    func testEmptyPartialFractionalOverflowAndOutOfRangeHaveNoDuration() {
        for raw in ["", " ", "+", "-", ".", "5.", "5.0", "1.5", "1e2", "NaN", "4", "0", "-5", "1441", "9999999999999999999999999999"] {
            let presentation = ClubSeriesOfferWindowPresentation(raw: raw)
            XCTAssertNil(presentation.minutes)
            XCTAssertNil(presentation.duration(locale: Locale(identifier: "en")))
            XCTAssertNil(presentation.duration(locale: Locale(identifier: "zh-Hans")))
        }
    }
    func testEnglishDurationUsesDayHoursAndMinutesWithoutRounding() throws {
        let locale = Locale(identifier: "en_US")
        for (raw, expected) in [("5", ["5", "minute"]), ("60", ["1", "hour"]), ("90", ["1", "hour", "30", "minute"]), ("1440", ["1", "day"])] {
            let text = try XCTUnwrap(ClubSeriesOfferWindowPresentation(raw: raw).duration(locale: locale))
            for token in expected { XCTAssertTrue(text.contains(token), text) }
        }
    }
    func testChineseDurationUsesDayHoursAndMinutesWithoutRounding() throws {
        let locale = Locale(identifier: "zh_Hans_CN")
        for (raw, expected) in [("5", ["5", "分钟"]), ("60", ["1", "小时"]), ("90", ["1", "小时", "30", "分钟"]), ("1440", ["1", "天"])] {
            let text = try XCTUnwrap(ClubSeriesOfferWindowPresentation(raw: raw).duration(locale: locale))
            for token in expected { XCTAssertTrue(text.contains(token), text) }
        }
    }
    func testFieldBindingRetainsPartialTextAndChangesOnlyOfferDraftIdentity() {
        var value = draft(.updateSeries)
        let original = value, id = value.requestID
        let field = ClubSeriesOfferWindowField(minutes: .init(get: { value.text["offerMinutes"] ?? "" }, set: { value.text["offerMinutes"] = $0 }))
        field.minutes = "5."
        XCTAssertEqual(value.text["offerMinutes"], "5."); XCTAssertNotEqual(value.requestID, id)
        XCTAssertEqual(value.text.filter { $0.key != "offerMinutes" }, original.text.filter { $0.key != "offerMinutes" })
        XCTAssertEqual(value.flags, original.flags); XCTAssertEqual(value.anchors, original.anchors)
        XCTAssertEqual(value.scope, original.scope); XCTAssertEqual(value.operation, original.operation)
        XCTAssertNil(ClubSeriesOfferWindowPresentation(raw: field.minutes).minutes)
        XCTAssertThrowsError(try value.command())
    }
    func testFixingRawInputKeepsWireMinutesAndNeverWritesBackFormatting() throws {
        var value = draft(.updateSeries)
        let field = ClubSeriesOfferWindowField(minutes: .init(get: { value.text["offerMinutes"] ?? "" }, set: { value.text["offerMinutes"] = $0 }))
        field.minutes = " 90 "
        let id = value.requestID, before = value.text
        XCTAssertEqual(ClubSeriesOfferWindowPresentation(raw: field.minutes).minutes, 90)
        _ = ClubSeriesOfferWindowPresentation(raw: field.minutes).duration(locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(value.text, before); XCTAssertEqual(value.requestID, id)
        XCTAssertEqual(try value.command().fields["offerMinutes"], .integer(90))
        XCTAssertEqual(try value.command().fields["expectedVersion"], .integer(7))
    }
    func testCreateAndUpdateSubmissionKeepTheAuthoritativeRangeValidation() {
        for operation in [ClubGovernanceMutation.createSeries, .updateSeries] {
            for raw in ["", "4", "5.0", "1441"] {
                var value = draft(operation); value.text["offerMinutes"] = raw
                XCTAssertThrowsError(try value.command()) { error in
                    XCTAssertEqual(error as? ClubGovernanceFailure, .invalidRequest)
                }
            }
            for raw in ["5", "60", "90", "1440"] {
                var value = draft(operation); value.text["offerMinutes"] = raw
                XCTAssertEqual(try value.command().fields["offerMinutes"], .integer(Int(raw)!))
            }
        }
    }
    func testWaitlistOffDoesNotBypassMinuteValidationAndOtherFieldsStayExact() throws {
        var value = draft(.updateSeries)
        value.flags["waitlistEnabled"] = false; value.text["offerMinutes"] = "4"
        XCTAssertThrowsError(try value.command())
        value.text["offerMinutes"] = "1440"
        let command = try value.command()
        XCTAssertEqual(command.fields["waitlistEnabled"], .bool(false))
        XCTAssertEqual(command.fields["offerMinutes"], .integer(1440))
        XCTAssertEqual(command.fields["startTime"], .string("09:00"))
        XCTAssertEqual(command.fields["defaultLeadMemberId"], .integer(41))
    }
}

@MainActor final class ClubSeriesCreationReturnTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "created-series-fixture"
        var journalRealm = "created-series-realm"
        var authorizationGeneration: UUID? = UUID()
        let allowsOfflineWrites = true
        var reads: [ClubGovernanceRead] = []
        var sends = 0
        var failure: ClubGovernanceFailure?
        func snapshot(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope) throws -> ClubGovernanceSnapshot {
            let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
                "roleCodes": .array([]), "permissions": .array([.string("club:activity:manage")])]), scope: scope)
            let value: ClubGovernanceValue
            switch operation {
            case .eventTopics: value = .array([.object(["id": .integer(91), "name": .string("Topic")])])
            case .members: value = .array([.object(["memberId": .integer(41)])])
            case .seriesDetail: value = .object(["id": .integer(303), "clubId": .integer(81), "topicId": .integer(91)])
            default: throw ClubGovernanceFailure.invalidRequest
            }
            return .init(operation: operation, scope: scope, permissions: permissions, value: value)
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            reads.append(operation); return try snapshot(operation, scope: scope)
        }
        func receipt(_ review: ClubGovernanceReview) -> ClubGovernanceValue {
            .object(["id": .integer(303), "clubId": .integer(81), "topicId": .integer(91),
                     "createdByMemberId": .integer(701), "requestId": review.command.fields["requestId"] ?? .null])
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1; if let failure { throw failure }; return receipt(review)
        }
    }
    private func source(_ access: Access, generation: UInt64 = 1) throws -> ClubSeriesCreationReturn.Source {
        let scope = ClubGovernanceScope(clubID: 81)
        let context = ClubGovernanceReadContext(operation: .eventTopics, scope: scope, identity: access.identity,
            viewerRevision: 3, authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
        return try XCTUnwrap(.topics(context: context, snapshot: access.snapshot(.eventTopics, scope: scope),
            generation: generation, topicID: 91, access: access))
    }
    private func command() throws -> ClubGovernanceCommand {
        var draft = ClubGovernanceFormDraft(operation: .createSeries, scope: .init(clubID: 81, topicID: 91),
                                            seed: ["defaultLeadMemberId": .integer(41)])
        draft.text["startDate"] = "2099-01-01"
        return try draft.command()
    }
    private func fixture() async throws -> (Access, ClubSeriesCreationReturn, ClubSeriesCreationReturn.Source, ClubSeriesCreationReturn.Item, ClubGovernanceCoordinator, ClubGovernanceReview) {
        let access = Access(), owner = ClubSeriesCreationReturn(), source = try source(access)
        owner.open(source, visible: true, active: true)
        let item = try XCTUnwrap(owner.item), coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(command())
        XCTAssertTrue(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
        return (access, owner, source, item, coordinator, review)
    }
    func testExactNewReceiptNavigatesToFreshSameClubTopicSeriesReadAndKeepsLock() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        let value = try await coordinator.confirm(review)
        owner.acknowledge(review, value: value, state: coordinator.state, item: item, source: source, active: true)
        owner.dismissed(item, source: source, active: true)
        let target = try XCTUnwrap(owner.consume(source: source, visible: true, active: true))
        XCTAssertEqual(target.receipt.seriesID, 303); XCTAssertEqual(target.receipt.scope, .init(clubID: 81, topicID: 91, seriesID: 303))
        let fresh = try await access.read(.seriesDetail, scope: target.receipt.scope, options: [:])
        XCTAssertTrue(target.receipt.accepts(fresh)); XCTAssertEqual(access.reads.last, .seriesDetail)
        XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity)); XCTAssertEqual(access.sends, 1)
        XCTAssertNil(owner.consume(source: source, visible: true, active: true))
    }
    func testMissingEachRequiredReceiptFieldKeepsAcknowledgedFormWithoutReplay() async throws {
        for key in ["id", "clubId", "topicId", "createdByMemberId", "requestId"] {
            let (access, owner, source, item, coordinator, review) = try await fixture()
            let receipt = try await coordinator.confirm(review)
            var value = try XCTUnwrap(receipt.object)
            value.removeValue(forKey: key)
            owner.acknowledge(review, value: .object(value), state: coordinator.state, item: item, source: source, active: true)
            XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.destination)
            XCTAssertEqual(coordinator.state, .acknowledged); XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
            XCTAssertEqual(access.sends, 1)
        }
    }
    func testWrongReceiptScopePrincipalRequestAndNonpositiveIDCannotNavigate() async throws {
        let (access, _, _, _, _, review) = try await fixture()
        for (key, bad) in [("id", ClubGovernanceValue.integer(0)), ("id", .integer(-1)), ("id", .integer(9_007_199_254_740_992)),
                           ("clubId", .integer(82)), ("topicId", .integer(92)), ("createdByMemberId", .integer(702)),
                           ("requestId", .string("different")), ("requestId", .integer(1))] {
            var value = try XCTUnwrap(access.receipt(review).object); value[key] = bad
            XCTAssertNil(ClubCreatedSeriesReceipt(review: review, value: .object(value)))
        }
    }
    func testRequestIDMustMatchOriginalBytesWithoutTrimmingOrCaseFolding() async throws {
        let (access, _, _, _, _, review) = try await fixture(), request = try XCTUnwrap(review.command.fields["requestId"]?.string)
        for altered in [" " + request, request + " ", request.uppercased()] {
            var value = try XCTUnwrap(access.receipt(review).object); value["requestId"] = .string(altered)
            XCTAssertNil(ClubCreatedSeriesReceipt(review: review, value: .object(value)))
        }
        let proof = try XCTUnwrap(ClubCreatedSeriesReceipt(review: review, value: access.receipt(review)))
        XCTAssertEqual(Array(proof.requestID.utf8), Array(request.utf8))
    }
    func testIdOnlyReceiptIsStillOriginalSuccessButHasNoReturnProof() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        _ = try await coordinator.confirm(review)
        owner.acknowledge(review, value: .object(["id": .integer(303)]), state: coordinator.state, item: item, source: source, active: true)
        XCTAssertEqual(coordinator.state, .acknowledged); XCTAssertTrue(owner.isPresented)
        XCTAssertNil(owner.consume(source: source, visible: true, active: true)); XCTAssertEqual(access.sends, 1)
    }
    func testUnknownCannotCreateReturnAndOriginalLockRemains() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture(); access.failure = .unknown(message: nil)
        do { _ = try await coordinator.confirm(review); XCTFail("Expected unknown") } catch {}
        owner.acknowledge(review, value: access.receipt(review), state: coordinator.state, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.destination)
        XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity)); XCTAssertEqual(access.sends, 1)
    }
    func testNonAcknowledgedStatesCannotUseEvenACompleteReceipt() async throws {
        let (access, owner, source, item, _, review) = try await fixture()
        for state in [ClubGovernanceWriteState.idle, .reviewing, .preflighting, .submitting, .rejected, .conflict, .unknown] {
            owner.acknowledge(review, value: access.receipt(review), state: state, item: item, source: source, active: true)
            XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.destination)
        }
    }
    func testDismissBeforeAppearDefersNavigationUntilVisibleOnce() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        let value = try await coordinator.confirm(review)
        owner.acknowledge(review, value: value, state: coordinator.state, item: item, source: source, active: true)
        owner.dismissed(item, source: source, active: true)
        let reads = access.reads
        XCTAssertNil(owner.consume(source: source, visible: false, active: true)); XCTAssertEqual(access.reads, reads)
        XCTAssertNotNil(owner.consume(source: source, visible: true, active: true))
        XCTAssertNil(owner.consume(source: source, visible: true, active: true))
    }
    func testAppearBeforeDismissCannotNavigateUntilCurrentDismissal() async throws {
        let (_, owner, source, item, coordinator, review) = try await fixture()
        let value = try await coordinator.confirm(review)
        owner.acknowledge(review, value: value, state: coordinator.state, item: item, source: source, active: true)
        XCTAssertNil(owner.consume(source: source, visible: true, active: true))
        owner.dismissed(item, source: source, active: true)
        XCTAssertNotNil(owner.consume(source: source, visible: true, active: true))
    }
    func testCancelAndLateOldDismissalCannotNavigateOrCloseNewOwner() async throws {
        let (access, owner, source, old, _, _) = try await fixture()
        let binding = owner.binding(old, source: { source }, active: { true })
        binding.wrappedValue = false; owner.dismissed(old, source: source, active: true)
        XCTAssertNil(owner.consume(source: source, visible: true, active: true)); owner.open(source, visible: true, active: true)
        let next = try XCTUnwrap(owner.item)
        binding.wrappedValue = false; XCTAssertFalse(binding.wrappedValue)
        XCTAssertFalse(owner.dismissed(old, source: source, active: true))
        XCTAssertEqual(owner.item?.id, next.id); XCTAssertTrue(owner.isPresented); XCTAssertEqual(access.sends, 0)
    }
    func testDifferentReviewCannotAcknowledgeTheCurrentSubmission() async throws {
        let (access, owner, source, item, coordinator, first) = try await fixture()
        let second = try await coordinator.prepare(command())
        XCTAssertTrue(owner.begin(second, state: coordinator.state, item: item, source: source, active: true))
        owner.acknowledge(first, value: access.receipt(first), state: .acknowledged, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.destination)
    }
    func testHiddenInactiveAndRetiredSourcesCannotOpenOrConsume() async throws {
        let access = Access(), source = try source(access), owner = ClubSeriesCreationReturn()
        owner.open(source, visible: false, active: true); XCTAssertNil(owner.item)
        owner.open(source, visible: true, active: false); XCTAssertNil(owner.item)
        let (_, active, loaded, item, coordinator, review) = try await fixture()
        let value = try await coordinator.confirm(review)
        active.acknowledge(review, value: value, state: coordinator.state, item: item, source: loaded, active: true)
        active.dismissed(item, source: loaded, active: true)
        XCTAssertNil(active.consume(source: loaded, visible: true, active: false))
        active.retire(); XCTAssertNil(active.consume(source: loaded, visible: true, active: true))
    }
    func testRefreshIdentityAuthorizationNamespaceAndReaderChangesRejectOldSource() async throws {
        let (access, owner, old, item, _, _) = try await fixture()
        XCTAssertFalse(owner.current(item, source: try source(access, generation: 2), active: true))
        access.identity = .init(accountID: 702, epoch: 1)
        XCTAssertFalse(owner.current(item, source: try source(access), active: true))
        access.identity = old.context.identity; access.authorizationGeneration = UUID()
        XCTAssertFalse(owner.current(item, source: try source(access), active: true))
        access.authorizationGeneration = old.context.authorizationGeneration; access.storageNamespace = "new"
        XCTAssertFalse(owner.current(item, source: try source(access), active: true))
        let other = Access(); other.authorizationGeneration = old.context.authorizationGeneration
        XCTAssertFalse(owner.current(item, source: try source(other), active: true))
    }
    func testPushedDestinationRetainsItsIdentityWithoutSourceSnapshot() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        let value = try await coordinator.confirm(review)
        owner.acknowledge(review, value: value, state: coordinator.state, item: item, source: source, active: true)
        owner.dismissed(item, source: source, active: true)
        let target = try XCTUnwrap(owner.consume(source: source, visible: true, active: true))
        XCTAssertNil(owner.item); XCTAssertTrue(owner.holdsSource)
        XCTAssertTrue(owner.destinationIsCurrent(target, context: source.context, access: access))
        access.authorizationGeneration = UUID()
        XCTAssertFalse(owner.destinationIsCurrent(target, context: source.context, access: access))
    }
    func testOldDestinationNilSetterCannotPopNewDestination() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        let value = try await coordinator.confirm(review)
        owner.acknowledge(review, value: value, state: coordinator.state, item: item, source: source, active: true)
        owner.dismissed(item, source: source, active: true)
        let old = try XCTUnwrap(owner.consume(source: source, visible: true, active: true))
        let binding = owner.destinationBinding(old, current: { owner.destinationIsCurrent(old, context: source.context, access: access) })
        owner.retireDestination(old); owner.open(source, visible: true, active: true)
        let next = try XCTUnwrap(owner.item)
        XCTAssertTrue(owner.begin(review, state: .reviewing, item: next, source: source, active: true))
        owner.acknowledge(review, value: value, state: .acknowledged, item: next, source: source, active: true)
        owner.dismissed(next, source: source, active: true)
        let current = try XCTUnwrap(owner.consume(source: source, visible: true, active: true))
        binding.wrappedValue = false; XCTAssertFalse(binding.wrappedValue)
        XCTAssertEqual(owner.destination?.id, current.id)
    }
    func testFreshDetailMustMatchCreatedSeriesClubAndTopic() async throws {
        let (access, _, _, _, _, review) = try await fixture()
        let proof = try XCTUnwrap(ClubCreatedSeriesReceipt(review: review, value: access.receipt(review)))
        let fresh = try access.snapshot(.seriesDetail, scope: proof.scope)
        XCTAssertTrue(proof.accepts(fresh))
        for key in ["id", "clubId", "topicId"] {
            var value = try XCTUnwrap(fresh.value.object); value[key] = .integer(999)
            XCTAssertFalse(proof.accepts(.init(operation: .seriesDetail, scope: proof.scope, permissions: fresh.permissions, value: .object(value))))
        }
    }
}

@MainActor final class ClubOccurrenceCancellationReturnTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "cancel-readback-fixture"
        var journalRealm = "cancel-readback-realm"
        var authorizationGeneration: UUID? = UUID()
        let allowsOfflineWrites = true
        var sends = 0
        var reads = 0
        var cancelled = false
        var readFailure: ClubGovernanceFailure?
        var sendFailure: ClubGovernanceFailure?
        var held = false
        var entered: (() -> Void)?
        var pending: CheckedContinuation<ClubGovernanceSnapshot, Error>?
        func snapshot(scope: ClubGovernanceScope) throws -> ClubGovernanceSnapshot {
            let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
                "roleCodes": .array([]), "permissions": .array([.string("club:activity:manage")])]), scope: scope)
            return .init(operation: .occurrenceStatus, scope: scope, permissions: permissions,
                value: .object(["activityId": .integer(401), "occurrenceStatus": .string(cancelled ? "CANCELLED" : "ACTIVE"),
                                "activityCancelled": .bool(cancelled), "publishStatus": .integer(cancelled ? 0 : 1)]))
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            XCTAssertEqual(operation, .occurrenceStatus); XCTAssertTrue(options.isEmpty); reads += 1
            if let readFailure { throw readFailure }
            if held { return try await withCheckedThrowingContinuation { pending = $0; entered?() } }
            return try snapshot(scope: scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1; if let sendFailure { throw sendFailure }
            return .object(["activityId": .integer(401), "refundStatus": .string("PENDING")])
        }
    }
    private func source(_ access: Access, generation: UInt64 = 1) throws -> ClubOccurrenceCancellationReturn.Source {
        let scope = ClubGovernanceScope(clubID: 81, activityID: 401)
        let context = ClubGovernanceReadContext(operation: .occurrenceStatus, scope: scope, identity: access.identity,
            viewerRevision: 2, authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
        return try XCTUnwrap(.init(context: context, snapshot: access.snapshot(scope: scope), generation: generation, access: access))
    }
    private func command(_ scope: ClubGovernanceScope) throws -> ClubGovernanceCommand {
        var draft = ClubGovernanceFormDraft(operation: .cancelOccurrence, scope: scope)
        draft.text["reason"] = "Schedule changed"
        return try draft.command()
    }
    private func fixture() async throws -> (Access, ClubOccurrenceCancellationReturn, ClubOccurrenceCancellationReturn.Source, ClubOccurrenceCancellationReturn.Item, ClubGovernanceCoordinator, ClubGovernanceReview) {
        let access = Access(), owner = ClubOccurrenceCancellationReturn(), source = try source(access)
        owner.open(source, visible: true, active: true)
        let item = try XCTUnwrap(owner.item), coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(command(source.context.scope))
        XCTAssertTrue(owner.begin(review, state: coordinator.state, item: item, source: source, active: true))
        return (access, owner, source, item, coordinator, review)
    }
    private func acknowledge(_ owner: ClubOccurrenceCancellationReturn, source: ClubOccurrenceCancellationReturn.Source,
                             item: ClubOccurrenceCancellationReturn.Item, coordinator: ClubGovernanceCoordinator,
                             review: ClubGovernanceReview) async throws {
        let receipt = try await coordinator.confirm(review)
        owner.acknowledge(review, value: receipt, state: coordinator.state, item: item, source: source, active: true)
    }
    func testOnlyIndependentCancelledStateConfirmsAcknowledgedCancellationAndKeepsLock() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        try await acknowledge(owner, source: source, item: item, coordinator: coordinator, review: review)
        XCTAssertFalse(owner.confirmed); owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, visible: true, active: true)); access.cancelled = true
        let fresh = try await access.read(.occurrenceStatus, scope: source.context.scope, options: [:])
        XCTAssertTrue(owner.observe(fresh, for: ticket, context: source.context, access: access, visible: true, active: true))
        XCTAssertEqual(ticket.reviewID, review.id); XCTAssertEqual(ticket.receipt["refundStatus"], .string("PENDING"))
        XCTAssertTrue(owner.confirmed); XCTAssertEqual(access.sends, 1)
        XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
        XCTAssertNil(owner.consume(source: source, visible: true, active: true))
    }
    func testActiveReadbackStaysUnconfirmedAndRepeatedReadsNeverSendAgain() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        try await acknowledge(owner, source: source, item: item, coordinator: coordinator, review: review)
        owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, visible: true, active: true))
        for _ in 0..<2 {
            let fresh = try await access.read(.occurrenceStatus, scope: source.context.scope, options: [:])
            XCTAssertFalse(owner.observe(fresh, for: ticket, context: source.context, access: access, visible: true, active: true))
        }
        XCTAssertEqual(owner.readback?.id, ticket.id); XCTAssertFalse(owner.confirmed); XCTAssertEqual(access.sends, 1)
        XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
    }
    func testMissingOrWrongActivityReceiptPreservesOriginalAckPage() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        _ = try await coordinator.confirm(review)
        let values: [ClubGovernanceValue] = [.object(["activityId": .integer(999), "refundStatus": .string("PENDING")]),
                                           .object(["refundStatus": .string("PENDING")]), .object(["activityId": .integer(401)])]
        for value in values {
            owner.acknowledge(review, value: value, state: coordinator.state, item: item, source: source, active: true)
            XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.readback)
        }
        XCTAssertEqual(coordinator.state, .acknowledged); XCTAssertEqual(access.sends, 1)
    }
    func testUnknownAckCannotReturnReadbackOrUnlock() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture(); access.sendFailure = .unknown(message: nil)
        do { _ = try await coordinator.confirm(review); XCTFail("Expected unknown") } catch {}
        owner.acknowledge(review, value: .object(["activityId": .integer(401), "refundStatus": .string("PENDING")]),
                          state: coordinator.state, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.readback); XCTAssertFalse(owner.confirmed)
        XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity)); XCTAssertEqual(access.sends, 1)
    }
    func testEveryNonAckStateDeclinesReturn() async throws {
        let (_, owner, source, item, _, review) = try await fixture()
        for state in [ClubGovernanceWriteState.idle, .reviewing, .preflighting, .submitting, .rejected, .conflict, .unknown] {
            owner.acknowledge(review, value: .object(["activityId": .integer(401), "refundStatus": .string("PENDING")]),
                              state: state, item: item, source: source, active: true)
            XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.readback)
        }
    }
    func testBothDismissAndAppearOrdersConsumeOnlyOnceWhenVisible() async throws {
        for dismissFirst in [true, false] {
            let (_, owner, source, item, coordinator, review) = try await fixture()
            try await acknowledge(owner, source: source, item: item, coordinator: coordinator, review: review)
            if dismissFirst {
                owner.dismissed(item, source: source, active: true)
                XCTAssertNil(owner.consume(source: source, visible: false, active: true))
            } else {
                XCTAssertNil(owner.consume(source: source, visible: true, active: true))
                owner.dismissed(item, source: source, active: true)
            }
            XCTAssertNotNil(owner.consume(source: source, visible: true, active: true))
            XCTAssertNil(owner.consume(source: source, visible: true, active: true))
        }
    }
    func testCancelledSheetAndOldBindingCannotCloseReopenedOwnerOrRead() async throws {
        let (access, owner, source, old, _, _) = try await fixture()
        let binding = owner.binding(old, source: { source }, active: { true })
        binding.wrappedValue = false; owner.dismissed(old, source: source, active: true)
        XCTAssertNil(owner.consume(source: source, visible: true, active: true)); owner.open(source, visible: true, active: true)
        let current = try XCTUnwrap(owner.item)
        binding.wrappedValue = false; XCTAssertFalse(binding.wrappedValue)
        XCTAssertFalse(owner.dismissed(old, source: source, active: true))
        XCTAssertEqual(owner.item?.id, current.id); XCTAssertTrue(owner.isPresented); XCTAssertEqual(access.sends, 0)
    }
    func testDifferentReviewAndParentRevisionCannotAcknowledge() async throws {
        let (_, owner, source, item, coordinator, old) = try await fixture()
        let current = try await coordinator.prepare(command(source.context.scope))
        XCTAssertTrue(owner.begin(current, state: coordinator.state, item: item, source: source, active: true))
        owner.acknowledge(old, value: .object(["activityId": .integer(401), "refundStatus": .string("PENDING")]),
                          state: .acknowledged, item: item, source: source, active: true)
        XCTAssertTrue(owner.isPresented); XCTAssertNil(owner.readback)
        owner.invalidateForm(source: nil, active: true); XCTAssertNil(owner.item)
    }
    func testWrongOrInconsistentStatusNeverConfirms() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        try await acknowledge(owner, source: source, item: item, coordinator: coordinator, review: review)
        owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, visible: true, active: true)); access.cancelled = true
        let fresh = try access.snapshot(scope: source.context.scope)
        for (key, bad) in [("activityId", ClubGovernanceValue.integer(999)), ("occurrenceStatus", .string("ACTIVE")),
                           ("activityCancelled", .bool(false)), ("publishStatus", .integer(1))] {
            var value = try XCTUnwrap(fresh.value.object); value[key] = bad
            XCTAssertFalse(owner.observe(.init(operation: .occurrenceStatus, scope: source.context.scope, permissions: fresh.permissions,
                value: .object(value)), for: ticket, context: source.context, access: access, visible: true, active: true))
            XCTAssertFalse(owner.confirmed)
        }
    }
    func testHiddenOrInactiveReadPredicateBlocksBeforeDispatch() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        try await acknowledge(owner, source: source, item: item, coordinator: coordinator, review: review)
        owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, visible: true, active: true)), prior = access.reads
        for (visible, active) in [(false, true), (true, false)] {
            do {
                _ = try await access.read(.occurrenceStatus, scope: source.context.scope, options: [:]) {
                    guard owner.readIsCurrent(ticket, context: source.context, access: access, visible: visible, active: active) else { throw CancellationError() }
                }
                XCTFail("Retired visibility must stop the read")
            } catch {}
        }
        XCTAssertEqual(access.reads, prior); XCTAssertEqual(access.sends, 1)
    }
    func testHiddenDuringHeldStatusReadCannotConsumeLateResponseWithoutRetire() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        try await acknowledge(owner, source: source, item: item, coordinator: coordinator, review: review)
        owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, visible: true, active: true))
        access.held = true; access.cancelled = true; var visible = true
        let entered = expectation(description: "held status"); access.entered = { entered.fulfill() }
        let task = Task { () -> ClubGovernanceSnapshot? in
            try? await access.read(.occurrenceStatus, scope: source.context.scope, options: [:]) {
                guard owner.readIsCurrent(ticket, context: source.context, access: access, visible: visible, active: true) else { throw CancellationError() }
            }
        }
        await fulfillment(of: [entered], timeout: 1); visible = false
        access.pending?.resume(returning: try access.snapshot(scope: source.context.scope))
        let result = await task.value
        XCTAssertNil(result); XCTAssertFalse(owner.confirmed); XCTAssertEqual(owner.readback?.id, ticket.id)
        XCTAssertEqual(access.sends, 1)
    }
    func testIdentityAuthorizationAndOldReadbackCannotAffectNewOwner() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        try await acknowledge(owner, source: source, item: item, coordinator: coordinator, review: review)
        owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, visible: true, active: true))
        access.identity = .init(accountID: 702, epoch: 1)
        XCTAssertFalse(owner.readIsCurrent(ticket, context: source.context, access: access, visible: true, active: true))
        access.identity = source.context.identity; access.authorizationGeneration = UUID()
        XCTAssertFalse(owner.readIsCurrent(ticket, context: source.context, access: access, visible: true, active: true))
        access.authorizationGeneration = source.context.authorizationGeneration; owner.retire(); owner.open(source, visible: true, active: true)
        let current = try XCTUnwrap(owner.item); access.cancelled = true
        XCTAssertFalse(owner.observe(try access.snapshot(scope: source.context.scope), for: ticket,
            context: source.context, access: access, visible: true, active: true))
        XCTAssertEqual(owner.item?.id, current.id); XCTAssertNil(owner.readback); XCTAssertFalse(owner.confirmed)
    }
    func testReadFailureRetainsPendingReceiptAndOriginalPermanentLock() async throws {
        let (access, owner, source, item, coordinator, review) = try await fixture()
        try await acknowledge(owner, source: source, item: item, coordinator: coordinator, review: review)
        owner.dismissed(item, source: source, active: true)
        let ticket = try XCTUnwrap(owner.consume(source: source, visible: true, active: true)); access.readFailure = .malformed
        do { _ = try await access.read(.occurrenceStatus, scope: source.context.scope, options: [:]); XCTFail("Expected read failure") } catch {}
        XCTAssertEqual(owner.readback?.id, ticket.id); XCTAssertFalse(owner.confirmed); XCTAssertEqual(access.sends, 1)
        XCTAssertTrue(coordinator.isLocked(review.command, identity: review.identity))
    }
}

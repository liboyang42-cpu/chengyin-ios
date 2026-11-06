import XCTest
@testable import Questify

@MainActor final class ClubSeriesOccurrenceBrowserTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "synthetic-occurrences"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var resources: [ClubGovernanceRead] = []
        var scopes: [ClubGovernanceScope] = []
        var sends = 0, activityID = 101
        var allowed = true, held = false, empty = false
        var failure: ClubGovernanceFailure?
        var entered: (() -> Void)?
        var pending: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        func response(_ operation: ClubGovernanceRead = .occurrences, scope: ClubGovernanceScope = .init(clubID: 81, topicID: 91, seriesID: 111)) throws -> ClubGovernanceSnapshot {
            let permission = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
                "roleCodes": .array([]), "permissions": .array(allowed ? [.string("club:activity:manage")] : []), "canManageRoles": .bool(false)]), scope: scope)
            return .init(operation: operation, scope: scope, permissions: permission, value: .array(empty ? [] : [.object([
                "occurrenceId": .integer(112), "activityId": .integer(activityID), "occurrenceAt": .string("2026-10-08 09:00:00"), "signupCount": .null])]))
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            resources.append(operation); scopes.append(scope); XCTAssertTrue(options.isEmpty)
            if let failure { throw failure }
            if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
            return try response(operation, scope: scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
    }
    private func context(_ access: Access, seriesID: Int = 111) -> ClubSeriesOccurrenceReadModel.Context {
        ClubSeriesOccurrenceReadModel.context(scope: .init(clubID: 81, topicID: 91, seriesID: seriesID), identity: access.identity, access: access)
    }
    private func activate(_ model: ClubSeriesOccurrenceReadModel, _ context: ClubSeriesOccurrenceReadModel.Context) throws -> ClubSeriesOccurrenceReadModel.Permit {
        model.bind(context); return try XCTUnwrap(model.activate(context))
    }
    func testExpansionUsesRealReadContractAndActualReturnedActivityWithoutWrites() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access)
        model.bind(expected); XCTAssertTrue(access.resources.isEmpty)
        let permit = try XCTUnwrap(model.activate(expected)); await model.load(permit, access: access, current: { true })
        XCTAssertEqual(access.resources, [.occurrences]); XCTAssertEqual(access.scopes, [expected.read.scope]); XCTAssertEqual(access.sends, 0)
        let value = try XCTUnwrap(model.accepted(expected, access: access)), route = try XCTUnwrap(value.route(rowID: 0, context: expected.read, snapshotID: model.snapshotID))
        XCTAssertEqual(route.scope.activityID, 101); XCTAssertTrue(model.canOpen(route, context: expected, access: access))
    }
    func testEmptyPermissionDeniedAndRetryAreSeparateStates() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), permit = try activate(model, expected)
        access.empty = true; await model.load(permit, access: access, current: { true }); XCTAssertEqual(model.options?.rows.count, 0); XCTAssertNil(model.failure)
        access.allowed = false; await model.load(permit, access: access, current: { true }); XCTAssertEqual(model.failure, .forbidden); XCTAssertNil(model.options)
        access.allowed = true; access.failure = .malformed; await model.load(permit, access: access, current: { true }); XCTAssertEqual(model.failure, .malformed)
        access.failure = nil; access.empty = false; await model.load(permit, access: access, current: { true }); XCTAssertNil(model.failure); XCTAssertEqual(model.options?.rows.count, 1)
        XCTAssertEqual(access.sends, 0)
    }
    func testCollapseAndReopenRetireOldSelectionPermitAndQueuedRetry() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), old = try activate(model, expected)
        await model.load(old, access: access, current: { true })
        let value = try XCTUnwrap(model.options), route = try XCTUnwrap(value.route(rowID: 0, context: expected.read, snapshotID: model.snapshotID))
        model.leave(expected); _ = model.activate(expected); let count = access.resources.count
        await model.load(old, access: access, current: { true }); XCTAssertEqual(access.resources.count, count)
        XCTAssertNil(model.options); XCTAssertFalse(model.canOpen(route, context: expected, access: access))
    }
    func testClosedOrRetiredParentPreventsReadAndLatePublication() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access, current: { false }); XCTAssertTrue(access.resources.isEmpty)
        access.held = true; var visible = true; let entered = expectation(description: "read")
        access.entered = { entered.fulfill() }; let task = Task { await model.load(permit, access: access, current: { visible }) }
        await fulfillment(of: [entered], timeout: 1); visible = false
        access.pending[0].resume(returning: try access.response()); await task.value
        XCTAssertNil(model.options); XCTAssertNil(model.failure)
    }
    func testAccountEpochChangesDuringReadCannotPublish() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(); access.held = true
        let expected = context(access), permit = try activate(model, expected), entered = expectation(description: "read")
        access.entered = { entered.fulfill() }; let task = Task { await model.load(permit, access: access, current: { true }) }
        await fulfillment(of: [entered], timeout: 1); access.identity = .init(accountID: 702, epoch: 2)
        access.pending[0].resume(returning: try access.response()); await task.value
        XCTAssertNil(model.accepted(expected, access: access)); XCTAssertNil(model.options)
    }
    func testNamespaceAuthorityAndReaderReplacementRetireRoute() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access, current: { true })
        let value = try XCTUnwrap(model.options), route = try XCTUnwrap(value.route(rowID: 0, context: expected.read, snapshotID: model.snapshotID))
        access.storageNamespace = "new-realm"; XCTAssertFalse(model.canOpen(route, context: expected, access: access))
        access.storageNamespace = expected.namespace; access.authorizationGeneration = UUID(); XCTAssertFalse(model.canOpen(route, context: expected, access: access))
        let other = Access(); other.authorizationGeneration = expected.read.authorizationGeneration
        XCTAssertFalse(model.canOpen(route, context: expected, access: other))
    }
    func testNewerReadWinsEvenIfPreviousRequestIgnoresCancellation() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), permit = try activate(model, expected)
        access.held = true; let first = expectation(description: "first"), second = expectation(description: "second")
        access.entered = { access.pending.count == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await model.load(permit, access: access, current: { true }) }; await fulfillment(of: [first], timeout: 1)
        let new = Task { await model.load(permit, access: access, current: { true }) }; await fulfillment(of: [second], timeout: 1)
        access.activityID = 102; access.pending[1].resume(returning: try access.response()); await new.value
        access.activityID = 101; access.pending[0].resume(returning: try access.response()); await old.value
        XCTAssertEqual(model.options?.rows.first?.activityID, 102); XCTAssertFalse(model.loading)
    }
    func testSwitchingExpandedSeriesRejectsPreviousCompletion() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), permit = try activate(model, expected)
        access.held = true; let entered = expectation(description: "first"); access.entered = { entered.fulfill() }
        let old = Task { await model.load(permit, access: access, current: { true }) }; await fulfillment(of: [entered], timeout: 1)
        let next = context(access, seriesID: 113), nextPermit = try activate(model, next)
        access.held = false; access.activityID = 102; await model.load(nextPermit, access: access, current: { true })
        access.activityID = 101; access.pending[0].resume(returning: try access.response()); await old.value
        XCTAssertNil(model.accepted(expected, access: access)); XCTAssertEqual(model.accepted(next, access: access)?.rows.first?.activityID, 102)
    }
    func testReturningFromWorkbenchRefreshesReadAndRetiresOldRoute() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access, current: { true })
        let old = try XCTUnwrap(model.options), route = try XCTUnwrap(old.route(rowID: 0, context: expected.read, snapshotID: model.snapshotID))
        await model.load(permit, access: access, current: { true })
        XCTAssertFalse(model.canOpen(route, context: expected, access: access)); XCTAssertEqual(access.resources, [.occurrences, .occurrences]); XCTAssertEqual(access.sends, 0)
        XCTAssertNotNil(model.accepted(expected, access: access))
    }
    func testSignedOutAndUnconfiguredReadersCannotDispatchRead() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(); access.identity = nil
        var expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access, current: { true }); XCTAssertEqual(model.failure, .signedOut); XCTAssertTrue(access.resources.isEmpty)
        access.identity = .init(accountID: 701, epoch: 2); access.isConfigured = false
        expected = context(access); permit = try activate(model, expected)
        await model.load(permit, access: access, current: { true }); XCTAssertEqual(model.failure, .notConfigured); XCTAssertTrue(access.resources.isEmpty)
    }
}

extension ClubSeriesOccurrenceBrowserTests {
    private func parentSource(_ access: Access, generation: UInt64 = 1, seriesID: Int = 111) throws -> ClubSeriesOccurrenceHost.Source {
        let scope = ClubGovernanceScope(clubID: 81)
        let context = ClubGovernanceReadContext(operation: .series, scope: scope, identity: access.identity, viewerRevision: 0,
            authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
        var row = ClubGovernanceFixtures.value(.seriesDetail).object!
        row["id"] = .integer(seriesID)
        let permission = try ClubGovernancePermissions(value: ClubGovernanceFixtures.permissions, scope: scope)
        let snapshot = ClubGovernanceSnapshot(operation: .series, scope: scope, permissions: permission, value: .array([.object(row)]))
        return try XCTUnwrap(.init(snapshot: snapshot, context: context, generation: generation, seriesID: seriesID, access: access))
    }
    private func expand(_ host: ClubSeriesOccurrenceHost, _ access: Access, _ source: ClubSeriesOccurrenceHost.Source) async {
        host.appear(); host.toggle(source, current: source, active: true)
        await host.loadIfNeeded(access: access, current: { source }, active: { true })
    }
    private func select(_ host: ClubSeriesOccurrenceHost, _ access: Access, _ source: ClubSeriesOccurrenceHost.Source) throws -> ClubSeriesOccurrenceHost.Selection {
        let value = try XCTUnwrap(host.model.accepted(source.occurrences, access: access))
        let route = try XCTUnwrap(value.route(rowID: 0, context: source.occurrences.read, snapshotID: host.model.snapshotID))
        host.open(route, source: source, current: source, access: access, active: true)
        return try XCTUnwrap(host.selected)
    }
    func testStableHostPreservesRealEventWhileParentIsCovered() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        await expand(host, access, source); let item = try select(host, access, source)
        host.hide()
        XCTAssertTrue(host.retainsDestination); XCTAssertTrue(host.isCurrent(item, current: source, access: access))
        XCTAssertTrue(host.binding(item, current: { source }, access: access).wrappedValue)
        XCTAssertEqual(item.route.scope, .init(clubID: 81, topicID: 91, activityID: 101))
        XCTAssertEqual(access.resources, [.occurrences]); XCTAssertEqual(access.sends, 0)
    }
    func testConcreteCloseRefreshesSameSeriesExactlyOnceWhenVisible() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        await expand(host, access, source); let item = try select(host, access, source)
        host.hide(); host.binding(item, current: { source }, access: access).wrappedValue = false
        XCTAssertTrue(host.closed(item, current: source, access: access)); XCTAssertFalse(host.closed(item, current: source, access: access))
        await host.loadIfNeeded(access: access, current: { source }, active: { true }); XCTAssertEqual(access.resources.count, 1)
        host.appear(); await host.loadIfNeeded(access: access, current: { source }, active: { true })
        await host.loadIfNeeded(access: access, current: { source }, active: { true })
        XCTAssertEqual(access.resources, [.occurrences, .occurrences]); XCTAssertEqual(access.scopes, [source.scope, source.scope])
        XCTAssertFalse(host.retainsDestination); XCTAssertFalse(host.needsRefresh); XCTAssertEqual(access.sends, 0)
    }
    func testOldDismissAndBindingCannotCloseReopenedEvent() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        await expand(host, access, source); let old = try select(host, access, source)
        let binding = host.binding(old, current: { source }, access: access)
        binding.wrappedValue = false; XCTAssertTrue(host.closed(old, current: source, access: access))
        await host.loadIfNeeded(access: access, current: { source }, active: { true })
        let fresh = try select(host, access, source)
        XCTAssertNotEqual(old.id, fresh.id); binding.wrappedValue = false; host.retire(old)
        XCTAssertFalse(host.closed(old, current: source, access: access)); XCTAssertEqual(host.selected?.id, fresh.id)
        XCTAssertTrue(host.isPresented); XCTAssertFalse(binding.wrappedValue)
    }
    func testActualDepartureAndOldAttachmentCannotTouchNewSession() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        await expand(host, access, source); let old = try select(host, access, source)
        XCTAssertTrue(host.depart(old.attachment)); XCTAssertNil(host.source); XCTAssertNil(host.selected); XCTAssertNil(host.model.options)
        await expand(host, access, source); let fresh = try select(host, access, source)
        XCTAssertFalse(host.depart(old.attachment)); XCTAssertEqual(host.selected?.id, fresh.id)
        XCTAssertFalse(host.closed(old, current: source, access: access))
    }
    func testRetiredOrHiddenOldSeriesButtonsCannotOpenOrRead() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        host.toggle(source, current: source, active: true); XCTAssertNil(host.source)
        host.appear(); host.toggle(source, current: source, active: false); XCTAssertNil(host.source)
        let newer = try parentSource(access, generation: 2)
        host.toggle(source, current: newer, active: true); XCTAssertNil(host.source)
        await expand(host, access, source); host.hide()
        XCTAssertFalse(host.requestReload(source, current: source, active: true))
        await host.loadIfNeeded(access: access, current: { source }, active: { true })
        XCTAssertEqual(access.resources.count, 1)
    }
    func testParentSnapshotRevisionRefreshRetiresOpenChildAndOldActions() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        await expand(host, access, source); let item = try select(host, access, source)
        let newer = try parentSource(access, generation: 2)
        XCTAssertFalse(host.isCurrent(item, current: newer, access: access)); host.invalidateUnlessCurrent(newer)
        XCTAssertNil(host.selected); XCTAssertNil(host.source); XCTAssertNil(host.model.options)
        XCTAssertFalse(host.closed(item, current: newer, access: access)); XCTAssertEqual(access.sends, 0)
    }
    func testBackgroundClosesChildAndForegroundExplicitReadCannotResend() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        await expand(host, access, source); let item = try select(host, access, source)
        host.background()
        XCTAssertNil(host.selected); XCTAssertTrue(host.needsRefresh); XCTAssertNil(host.model.options)
        XCTAssertFalse(host.closed(item, current: source, access: access))
        await host.loadIfNeeded(access: access, current: { source }, active: { false }); XCTAssertEqual(access.resources.count, 1)
        await host.loadIfNeeded(access: access, current: { source }, active: { true })
        XCTAssertEqual(access.resources.count, 2); XCTAssertFalse(host.needsRefresh); XCTAssertEqual(access.sends, 0)
    }
    func testReturnReadFailureIsRetryableWithoutOptimisticNewRows() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        await expand(host, access, source); let item = try select(host, access, source)
        host.binding(item, current: { source }, access: access).wrappedValue = false
        XCTAssertTrue(host.closed(item, current: source, access: access))
        access.failure = .malformed; await host.loadIfNeeded(access: access, current: { source }, active: { true })
        XCTAssertTrue(host.needsRefresh); XCTAssertNil(host.model.options); XCTAssertEqual(host.model.failure, .malformed)
        access.failure = nil; XCTAssertTrue(host.requestReload(source, current: source, active: true))
        await host.loadIfNeeded(access: access, current: { source }, active: { true })
        XCTAssertFalse(host.needsRefresh); XCTAssertNotNil(host.model.options); XCTAssertEqual(access.sends, 0)
    }
    func testHeldReturnBackgroundRestartRejectsLateOldRead() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        await expand(host, access, source); let item = try select(host, access, source)
        host.binding(item, current: { source }, access: access).wrappedValue = false
        _ = host.closed(item, current: source, access: access)
        access.held = true; let entered = expectation(description: "old return read"); access.entered = { entered.fulfill() }
        let old = Task { await host.loadIfNeeded(access: access, current: { source }, active: { true }) }
        await fulfillment(of: [entered], timeout: 1)
        host.background(); access.held = false; access.activityID = 102
        await host.loadIfNeeded(access: access, current: { source }, active: { true })
        XCTAssertEqual(host.model.options?.rows.first?.activityID, 102)
        access.activityID = 101; access.pending[0].resume(returning: try access.response()); await old.value
        XCTAssertEqual(host.model.options?.rows.first?.activityID, 102); XCTAssertFalse(host.needsRefresh); XCTAssertFalse(host.model.loading)
    }
    func testHeldReadLeavingParentCannotRepopulateOnLateReturn() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        host.appear(); host.toggle(source, current: source, active: true)
        access.held = true; let entered = expectation(description: "depart read"); access.entered = { entered.fulfill() }
        let old = Task { await host.loadIfNeeded(access: access, current: { source }, active: { true }) }
        await fulfillment(of: [entered], timeout: 1)
        let attachment = try XCTUnwrap(host.attachment); XCTAssertTrue(host.depart(attachment))
        access.pending[0].resume(returning: try access.response()); await old.value
        XCTAssertNil(host.source); XCTAssertNil(host.model.options); XCTAssertFalse(host.model.loading)
    }
    func testCurrentAuthorizationAndSameSeriesAreRequiredAtReturn() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        await expand(host, access, source); let item = try select(host, access, source)
        access.authorizationGeneration = UUID()
        XCTAssertFalse(host.isCurrent(item, current: source, access: access))
        XCTAssertFalse(host.closed(item, current: source, access: access))
        let replacement = try parentSource(access)
        host.invalidateUnlessCurrent(replacement); XCTAssertNil(host.source)
        await expand(host, access, replacement)
        let wrongSeries = try parentSource(access, seriesID: 113)
        XCTAssertFalse(host.requestReload(replacement, current: wrongSeries, active: true))
    }
    func testReadOwnerSurvivesRecycledRowWithoutAnyRowLifecycleCallback() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        await expand(host, access, source)
        let permit = try XCTUnwrap(host.model.permit(in: source.occurrences)), snapshotID = host.model.snapshotID
        // Row views only observe this owner; constructing a replacement row does not activate or retire it.
        _ = ClubSeriesOccurrenceBrowser(source: source, access: access, host: host, model: host.model,
            currentSource: { source }, active: { true }, reload: {})
        XCTAssertEqual(host.model.permit(in: source.occurrences), permit); XCTAssertEqual(host.model.snapshotID, snapshotID)
        XCTAssertNotNil(host.model.accepted(source.occurrences, access: access)); XCTAssertEqual(access.resources.count, 1)
    }
}

extension ClubSeriesOccurrenceBrowserTests {
    func testCapturedParentSourceRejectsChangedAccountAndAccessObject() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        await expand(host, access, source); let item = try select(host, access, source)
        access.identity = .init(accountID: 701, epoch: 2)
        XCTAssertFalse(host.isCurrent(item, current: source, access: access))
        XCTAssertNil(ClubSeriesOccurrenceHost.Source(snapshot: source.parent, context: source.context, generation: 1, seriesID: 111, access: access))
        let replacement = Access(); replacement.authorizationGeneration = source.context.authorizationGeneration
        XCTAssertNil(ClubSeriesOccurrenceHost.Source(snapshot: source.parent, context: source.context, generation: 1, seriesID: 111, access: replacement))
        XCTAssertFalse(host.closed(item, current: source, access: access))
    }
    func testHiddenReturnReadCanRestartBeforeSuspendedOldTransportReturns() async throws {
        let access = Access(), host = ClubSeriesOccurrenceHost(), source = try parentSource(access)
        await expand(host, access, source); let item = try select(host, access, source)
        host.binding(item, current: { source }, access: access).wrappedValue = false
        _ = host.closed(item, current: source, access: access)
        access.held = true; let entered = expectation(description: "hidden return"); access.entered = { entered.fulfill() }
        let old = Task { await host.loadIfNeeded(access: access, current: { source }, active: { true }) }
        await fulfillment(of: [entered], timeout: 1); host.hide()
        XCTAssertFalse(host.model.loading); XCTAssertTrue(host.needsRefresh)
        access.held = false; host.appear(); access.activityID = 102
        await host.loadIfNeeded(access: access, current: { source }, active: { true })
        access.activityID = 101; access.pending[0].resume(returning: try access.response()); await old.value
        XCTAssertEqual(host.model.options?.rows.first?.activityID, 102); XCTAssertFalse(host.needsRefresh)
    }
}

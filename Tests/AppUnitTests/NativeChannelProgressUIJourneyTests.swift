import XCTest
import SwiftUI
@testable import Questify

/// Actual view-owned lifecycle/selection/confirmation helpers. Apple execution is
/// required; the accompanying Python check does not execute these regressions.
@MainActor final class NativeChannelProgressUIJourneyTests: XCTestCase {
    func testLateFactoryAfterExitCannotInstallOrActivateCoordinator() async throws {
        let owner = NativeChannelProgressVisitOwner(), route = NativeChannelManagementRouteState()
        route.isPresented = true
        let binding = route.binding, started = expectation(description: "factory suspended")
        let (oldFlow, access) = try makeFlow()
        var continuation: CheckedContinuation<NativeChannelProgressCoordinator?, Never>?
        var oldCurrent: (@MainActor () -> Bool)?
        let load = try XCTUnwrap(owner.open(parentCurrent: { binding.wrappedValue }) { current in
            oldCurrent = current
            return await withCheckedContinuation { continuation = $0; started.fulfill() }
        })
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(try XCTUnwrap(oldCurrent)())
        route.isPresented = false; owner.retire()
        continuation?.resume(returning: oldFlow); await load.value
        XCTAssertFalse(try XCTUnwrap(oldCurrent)()); XCTAssertNil(owner.model)
        XCTAssertFalse(oldFlow.isCurrent); XCTAssertEqual(access.definitionsReads, 0)
    }

    func testForegroundCreatesNewOwnerAndOldSourceNeverRevives() async throws {
        let owner = NativeChannelProgressVisitOwner(), route = NativeChannelManagementRouteState()
        route.isPresented = true; let binding = route.binding
        let (first, firstAccess) = try makeFlow(), (second, secondAccess) = try makeFlow()
        var firstSource: (@MainActor () -> Bool)?, secondSource: (@MainActor () -> Bool)?
        let load = try XCTUnwrap(owner.open(parentCurrent: { binding.wrappedValue }) { current in firstSource = current; return first })
        await load.value
        let oldVisit = owner.visitID
        owner.retire()
        XCTAssertFalse(first.isCurrent); XCTAssertFalse(try XCTUnwrap(firstSource)())
        let reload = try XCTUnwrap(owner.open(parentCurrent: { binding.wrappedValue }) { current in secondSource = current; return second })
        await reload.value
        XCTAssertTrue(owner.model === second); XCTAssertNotEqual(owner.visitID, oldVisit)
        XCTAssertFalse(try XCTUnwrap(firstSource)()); XCTAssertTrue(try XCTUnwrap(secondSource)())
        XCTAssertEqual(firstAccess.definitionsReads, 1); XCTAssertEqual(secondAccess.definitionsReads, 1)
    }

    func testChildPushDoesNotRetireParentButClosedBindingBlocksReopen() async throws {
        let owner = NativeChannelProgressVisitOwner(), route = NativeChannelManagementRouteState()
        route.isPresented = true; let binding = route.binding
        let (flow, access) = try makeFlow()
        let load = try XCTUnwrap(owner.open(parentCurrent: { binding.wrappedValue }) { _ in flow }); await load.value
        let visit = owner.visitID
        // A child appearance requests the same still-live parent visit, not a new coordinator.
        let same = owner.open(parentCurrent: { binding.wrappedValue }) { _ in XCTFail("child push restarted factory"); return nil }
        await same?.value
        XCTAssertEqual(owner.visitID, visit); XCTAssertTrue(flow.isCurrent); XCTAssertEqual(access.definitionsReads, 1)
        route.isPresented = false
        XCTAssertNil(owner.open(parentCurrent: { binding.wrappedValue }) { _ in XCTFail("closed route reopened"); return nil })
        XCTAssertNil(owner.model)
        route.isPresented = true // ABA on the real route must not revive the retained binding.
        XCTAssertFalse(binding.wrappedValue)
    }

    func testDroppedEntryOwnerIsNotRetainedByItsCapturedSource() async throws {
        var owner: NativeChannelProgressVisitOwner? = .init()
        weak var weakOwner = owner
        let route = NativeChannelManagementRouteState(); route.isPresented = true; let binding = route.binding
        var source: (@MainActor () -> Bool)?
        let load = try XCTUnwrap(owner?.open(parentCurrent: { binding.wrappedValue }) { current in source = current; return nil })
        await load.value; owner = nil
        XCTAssertNil(weakOwner); XCTAssertFalse(try XCTUnwrap(source)())
    }

    func testStandalonePrivacyVisitUsesNewFactoryAfterRetirement() async throws {
        let owner = NativeChannelProgressVisitOwner()
        let (first, oldAccess) = try makeFlow(privacyOnly: true), (second, newAccess) = try makeFlow(privacyOnly: true)
        let load = try XCTUnwrap(owner.open(parentCurrent: { true }, privacyOnly: true) { _ in first }); await load.value
        owner.retire()
        let reopen = try XCTUnwrap(owner.open(parentCurrent: { true }, privacyOnly: true) { _ in second }); await reopen.value
        XCTAssertEqual(oldAccess.privacyReads, 1); XCTAssertEqual(newAccess.privacyReads, 1)
        XCTAssertEqual(oldAccess.definitionsReads, 0); XCTAssertFalse(first.isCurrent); XCTAssertTrue(second.isCurrent)
    }

    func testChannelAndProviderInputChangesRetireLateFactory() async throws {
        let owner = NativeChannelProgressVisitOwner(), provider = NativeChannelProgressUIContextProvider()
        let otherProvider = NativeChannelProgressUIContextProvider()
        let firstIdentity = NativeChannelProgressEntryIdentity(channelID: try .init("5"), provider: provider)
        let nextIdentity = NativeChannelProgressEntryIdentity(channelID: try .init("6"), provider: provider)
        let finalIdentity = NativeChannelProgressEntryIdentity(channelID: try .init("6"), provider: otherProvider)
        let began = expectation(description: "old input waiting")
        var release: CheckedContinuation<NativeChannelProgressCoordinator?, Never>?
        var oldCurrent: (@MainActor () -> Bool)?
        let (oldFlow, oldAccess) = try makeFlow(), (newFlow, _) = try makeFlow()
        let old = try XCTUnwrap(owner.open(parentCurrent: { true }, identity: firstIdentity) { current in
            oldCurrent = current
            return await withCheckedContinuation { release = $0; began.fulfill() }
        })
        await fulfillment(of: [began], timeout: 1)
        let replacement = try XCTUnwrap(owner.open(parentCurrent: { true }, identity: nextIdentity) { _ in newFlow })
        await replacement.value
        release?.resume(returning: oldFlow); await old.value
        XCTAssertTrue(owner.model === newFlow); XCTAssertEqual(owner.entryIdentity, nextIdentity)
        XCTAssertFalse(try XCTUnwrap(oldCurrent)()); XCTAssertEqual(oldAccess.definitionsReads, 0)
        let final = try XCTUnwrap(owner.open(parentCurrent: { true }, identity: finalIdentity) { _ in nil })
        await final.value
        XCTAssertFalse(newFlow.isCurrent); XCTAssertEqual(owner.entryIdentity, finalIdentity); XCTAssertNil(owner.model)
    }

    func testRunningOldSelectionCannotOverwriteFreshVisitQueue() async throws {
        let queue = NativeChannelProgressSelectionQueue(); queue.activate()
        let began = expectation(description: "old operation suspended"), fresh = expectation(description: "new operation")
        var release: CheckedContinuation<Void, Never>?
        let old = try XCTUnwrap(queue.enqueue(try query("ALL"), isCurrent: { true }, isBusy: { false }) { _ in
            await withCheckedContinuation { release = $0; began.fulfill() }
        })
        await fulfillment(of: [began], timeout: 1)
        queue.retire(); queue.activate()
        let expected = try query("MONTH", completed: true)
        queue.enqueue(expected, isCurrent: { true }, isBusy: { true }) { _ in XCTFail("busy intent should wait") }
        release?.resume(); await old.value
        XCTAssertEqual(queue.pending, expected)
        queue.resume(isCurrent: { true }, isBusy: { false }) { query in XCTAssertEqual(query, expected); fresh.fulfill() }
        await fulfillment(of: [fresh], timeout: 1)
    }

    func testBusySelectionKeepsOnlyNewestPeriodAndFilterIntent() async throws {
        let queue = NativeChannelProgressSelectionQueue(); queue.activate()
        var busy = true, selected: [NativeChannelProgressQuery] = []
        let final = expectation(description: "latest selection")
        let a = try query("ALL"), b = try query("WEEK", completed: true), c = try query("MONTH", completed: false, team: 17)
        let select: @MainActor (NativeChannelProgressQuery) async -> Void = { selected.append($0); final.fulfill() }
        for intent in [a, b, c] { queue.enqueue(intent, isCurrent: { true }, isBusy: { busy }, select: select) }
        XCTAssertEqual(queue.pending, c); XCTAssertTrue(selected.isEmpty)
        busy = false; queue.resume(isCurrent: { true }, isBusy: { busy }, select: select)
        await fulfillment(of: [final], timeout: 1)
        XCTAssertEqual(selected, [c]); XCTAssertFalse(queue.hasPendingSelection)
    }

    func testRunningSelectionFinishesThenDispatchesLatestWithoutRetryingIntermediate() async throws {
        let queue = NativeChannelProgressSelectionQueue(); queue.activate()
        let started = expectation(description: "first selection started"), finished = expectation(description: "latest selection performed")
        var release: CheckedContinuation<Void, Never>?, selected: [NativeChannelProgressQuery] = []
        let a = try query("ALL"), b = try query("WEEK"), c = try query("MONTH", completed: true)
        let select: @MainActor (NativeChannelProgressQuery) async -> Void = { query in
            selected.append(query)
            if query == a { await withCheckedContinuation { release = $0; started.fulfill() } }
            else { finished.fulfill() }
        }
        queue.enqueue(a, isCurrent: { true }, isBusy: { false }, select: select)
        await fulfillment(of: [started], timeout: 1)
        queue.enqueue(b, isCurrent: { true }, isBusy: { false }, select: select)
        queue.enqueue(c, isCurrent: { true }, isBusy: { false }, select: select)
        release?.resume(); await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(selected, [a, c]); XCTAssertFalse(queue.hasPendingSelection)
    }

    func testSelectionChecksBusyAgainAtTaskExecution() async throws {
        let queue = NativeChannelProgressSelectionQueue(); queue.activate()
        var busy = false, calls = 0
        let a = try query("ALL"), done = expectation(description: "event-driven resume")
        let select: @MainActor (NativeChannelProgressQuery) async -> Void = { _ in calls += 1; done.fulfill() }
        let attempt = try XCTUnwrap(queue.enqueue(a, isCurrent: { true }, isBusy: { busy }, select: select))
        busy = true
        await attempt.value
        XCTAssertEqual(calls, 0); XCTAssertEqual(queue.pending, a)
        busy = false; queue.resume(isCurrent: { true }, isBusy: { busy }, select: select)
        await fulfillment(of: [done], timeout: 1); XCTAssertEqual(calls, 1)
    }

    func testRetiredSelectionCannotDrainIntoNewVisit() async throws {
        let queue = NativeChannelProgressSelectionQueue(); queue.activate()
        let a = try query("ALL"), b = try query("MONTH")
        var calls: [NativeChannelProgressQuery] = []
        queue.enqueue(a, isCurrent: { true }, isBusy: { true }) { calls.append($0) }
        queue.retire(); queue.activate()
        let final = expectation(description: "fresh visit")
        queue.enqueue(b, isCurrent: { true }, isBusy: { false }) { calls.append($0); final.fulfill() }
        await fulfillment(of: [final], timeout: 1)
        XCTAssertEqual(calls, [b])
    }

    func testQueuedChildActionDoesNotRunAfterExitOrReappearance() async throws {
        let lifetime = NativeChannelProgressActionLifetime(); lifetime.activate()
        var calls = 0
        let old = try XCTUnwrap(lifetime.run { calls += 1 })
        lifetime.retire(); lifetime.activate()
        await old.value; XCTAssertEqual(calls, 0)
        let fresh = try XCTUnwrap(lifetime.run { calls += 1 }); await fresh.value
        XCTAssertEqual(calls, 1)
    }

    func testPrivacyReviewRejectsChangedRevisionAndChangedDraft() throws {
        let review = NativeChannelProgressPrivacyConfirmation(); review.enter()
        let current = try privacy(), values = try privacyValues()
        review.prepare(current: current, draft: values, canSave: true)
        XCTAssertNil(review.consume(current: try privacy(revision: 1), draft: values, canSave: true))
        review.prepare(current: current, draft: values, canSave: true)
        var edited = values; edited.leaderboardScope = .included
        XCTAssertNil(review.consume(current: current, draft: edited, canSave: true))
    }

    func testPrivacyReviewRejectsSameRevisionDifferentCurrentSettings() throws {
        let review = NativeChannelProgressPrivacyConfirmation(); review.enter()
        let current = try privacy(), values = try privacyValues()
        review.prepare(current: current, draft: values, canSave: true)
        XCTAssertNil(review.consume(current: try privacy(aggregate: "SELF"), draft: values, canSave: true))
    }

    func testConsumedPrivacyReviewRechecksAtActualDispatch() throws {
        let confirmation = NativeChannelProgressPrivacyConfirmation(); confirmation.enter()
        let current = try privacy(), values = try privacyValues()
        confirmation.prepare(current: current, draft: values, canSave: true)
        let original = try XCTUnwrap(confirmation.consume(current: current, draft: values, canSave: true))
        XCTAssertTrue(confirmation.validates(original, current: current, draft: values, canSave: true))
        XCTAssertFalse(confirmation.validates(original, current: try privacy(revision: 1), draft: values, canSave: true))
        XCTAssertFalse(confirmation.validates(original, current: current, draft: values, canSave: false))
        confirmation.leave(); confirmation.enter()
        XCTAssertFalse(confirmation.validates(original, current: current, draft: values, canSave: true))
    }

    func testPrivacyEditABAAndRefreshCannotReuseOriginalConfirmation() throws {
        let confirmation = NativeChannelProgressPrivacyConfirmation(); confirmation.enter()
        let current = try privacy(), values = try privacyValues()
        confirmation.prepare(current: current, draft: values, canSave: true)
        let original = try XCTUnwrap(confirmation.consume(current: current, draft: values, canSave: true))
        confirmation.invalidate() // A draft change or read begins, even if it later returns identical values.
        XCTAssertFalse(confirmation.validates(original, current: current, draft: values, canSave: true))
        XCTAssertNil(confirmation.consume(current: current, draft: values, canSave: true))
    }

    func testCurrentPrivacyReviewRetainsExactValuesAndIsConsumedOnlyOnce() throws {
        let confirmation = NativeChannelProgressPrivacyConfirmation(); confirmation.enter()
        let current = try privacy(revision: 9), values = try privacyValues()
        confirmation.prepare(current: current, draft: values, canSave: true)
        let selected = try XCTUnwrap(confirmation.consume(current: current, draft: values, canSave: true))
        XCTAssertEqual(selected.current.revision, 9); XCTAssertEqual(selected.values, values)
        XCTAssertNil(confirmation.consume(current: current, draft: values, canSave: true))
    }

    func testTeamOptionsCannotInventInvalidIdentifiersOrNames() throws {
        XCTAssertThrowsError(try NativeChannelProgressTeamOption(id: 0, name: "Team"))
        XCTAssertThrowsError(try NativeChannelProgressTeamOption(id: 17, name: ""))
        XCTAssertEqual(try NativeChannelProgressTeamOption(id: 17, name: "Original team").id, 17)
    }

    private func query(_ period: String, completed: Bool? = nil, team: Int64? = nil) throws -> NativeChannelProgressQuery {
        let board: NativeChannelProgressBoard = try decode(#"{"board_key":"completion","title":"Completion","metric":"PERCENT","period":"ALL","scope":"CHANNEL","subject_type":"MEMBER","team_rollup":null,"row_limit":30,"visible":true,"revision":2,"topic_id":17,"activity_id":23,"filter_schema_json":{"completed":"boolean","team_id":"int"}}"#)
        return try .init(board: board, period: period, completed: completed, teamID: team)
    }
    private func privacyValues() throws -> NativeChannelProgressPrivacyValues {
        try .init(aggregateScope: .onlyMe, detailScope: .onlyMe, photoScope: .onlyMe, leaderboardScope: .out)
    }
    private func privacy(revision: Int64 = 0, aggregate: String = "PUBLIC") throws -> NativeChannelProgressPrivacy {
        try decode("""
        {"aggregate_scope":"\(aggregate)","detail_scope":"TEAM","photo_scope":"TEAM","leaderboard_scope":"IN","revision":\(revision),"applies_to":"CHANNEL_PROGRESS"}
        """)
    }
    private func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
    private func makeFlow(privacyOnly: Bool = false) throws -> (NativeChannelProgressCoordinator, NativeChannelProgressUIAccess) {
        let access = try NativeChannelProgressUIAccess(privacyOnly: privacyOnly), store = NativeChannelProgressUIStorage()
        return (try .init(access: access, journal: .init(identity: try XCTUnwrap(access.authority).identity, storage: store)), access)
    }
}

@MainActor private final class NativeChannelProgressUIStorage: NativeChannelProgressJournalStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class NativeChannelProgressUIAccess: NativeChannelProgressAccess {
    var authority: NativeChannelProgressAuthoritySnapshot?
    var definitionsReads = 0, privacyReads = 0
    init(privacyOnly: Bool = false) throws {
        let identity = try NativeChannelProgressIdentity(actorID: 101, namespace: "TEST", origin: URL(string: "https://example.test")!, sessionEpoch: "7")
        authority = try .init(identity: identity, channelID: privacyOnly ? nil : 5, authorizationVersion: "synthetic-policy", metadataVersion: 2,
                              permissionVersion: 3, endpointApprovalRevision: UUID(), viewerRevision: 4,
                              operations: privacyOnly ? [.privacy, .savePrivacy, .receipt] : [.definitions, .overview, .privacy, .savePrivacy, .receipt])
    }
    func retireOperations() {}
    func definitions() async throws -> NativeChannelProgressDefinitions { definitionsReads += 1; return try decode(#"{"visible":true,"list":[]}"#) }
    func overview() async throws -> NativeChannelProgressOverview { try decode(#"{"visible":false}"#) }
    func privacy() async throws -> NativeChannelProgressPrivacy {
        privacyReads += 1
        return try decode(#"{"aggregate_scope":"SELF","detail_scope":"SELF","photo_scope":"SELF","leaderboard_scope":"OUT","revision":0,"applies_to":"CHANNEL_PROGRESS"}"#)
    }
    func page(_ query: NativeChannelProgressQuery, detail: Bool, cursor: String?) async throws -> NativeChannelProgressPage { throw NativeChannelProgressError.closed }
    func best(_ query: NativeChannelProgressQuery) async throws -> NativeChannelProgressRow { throw NativeChannelProgressError.closed }
    func recent(_ query: NativeChannelProgressQuery, cursor: String?) async throws -> NativeChannelProgressPage { throw NativeChannelProgressError.closed }
    func version(_ boardKey: String) async throws -> NativeChannelProgressVersion { throw NativeChannelProgressError.closed }
    func meter(_ board: NativeChannelProgressBoard) async throws -> NativeChannelProgressMeter { throw NativeChannelProgressError.closed }
    func save(_ command: NativeChannelProgressPrivacyCommand) async throws -> NativeChannelProgressPrivacy { XCTFail("UI lifecycle must never save"); throw NativeChannelProgressError.closed }
    func receipt(_ command: NativeChannelProgressPrivacyCommand) async throws -> NativeChannelProgressPrivacy? { nil }
    private func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
}

@MainActor private final class NativeChannelProgressUIContextProvider: NativeChannelManagementIntegrationContextProviding {
    func currentChannelContext(channelID: NativeChannelManagementID) async throws -> NativeChannelManagementIntegrationContext { throw NativeChannelManagementError.invalidSource }
    func contextIsCurrent(_ context: NativeChannelManagementIntegrationContext) -> Bool { false }
}

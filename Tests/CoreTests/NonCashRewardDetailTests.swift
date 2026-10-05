import XCTest
@testable import QuestifyCore

private func detailItem(id: String = "reward", context: NonCashReward.Context = .map,
                        contextID: String = "map", release: String = "release", instance: String = "season",
                        rules: String = "rules", merchant: String = "7", store: String = "8", title: String = " Item ",
                        quantity: Int = 1, from: Double = 100, until: Double = 200, terms: String = " Frozen store terms ",
                        state: NonCashReward.State = .awarded, awarded: Double = 100, asOf: Double = 150,
                        validity: NonCashReward.Validity? = nil) -> NonCashReward {
    NonCashReward(awardId: id, contextType: context, contextId: contextID, releaseId: release, instanceId: instance,
                  rulesVersion: rules, merchantId: merchant, storeId: store, rewardTitle: title, quantity: quantity,
                  validFrom: Date(timeIntervalSince1970: from), validUntil: Date(timeIntervalSince1970: until),
                  redemptionConditions: terms, state: state, awardedAt: Date(timeIntervalSince1970: awarded),
                  asOf: Date(timeIntervalSince1970: asOf), validityStatus: validity)
}
@MainActor private final class DetailReader: NonCashRewardReading {
    var scope = UUID(), isConfigured = true, isAuthenticated = true
    var isOfflineExample: Bool { false }
    var references: [NonCashRewardReference] = []
    var pending: [Int: CheckedContinuation<NonCashReward, Error>] = [:]
    var rows = [detailItem()]
    func rewards(cursor: String?) async throws -> NonCashRewardPage {
        NonCashRewardPage(items: rows, nextCursor: nil, asOf: Date(timeIntervalSince1970: 150))
    }
    func reward(_ reference: NonCashRewardReference) async throws -> NonCashReward {
        let index = references.count; references.append(reference)
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func waitFor(_ count: Int) async { while references.count < count { await Task.yield() } }
    func finish(_ index: Int, _ value: NonCashReward) { pending.removeValue(forKey: index)?.resume(returning: value) }
    func fail(_ index: Int, _ error: Error) { pending.removeValue(forKey: index)?.resume(throwing: error) }
    func model() -> NonCashRewardDetailModel { .init(selection: .init(reference: .init(rows[0]), ownerScope: scope)) }
}
@MainActor final class NonCashRewardDetailTests: XCTestCase {
    func testOriginKeepsThemeRunAndMapSeasonWithoutFallback() throws {
        for context in [NonCashReward.Context.theme, .map] {
            let reward = detailItem(context: context, contextID: "exact-context", release: "exact-release", instance: "exact-instance", rules: "exact-rules")
            let p = try NonCashRewardDetailProjection(reward: reward, previous: .init(reward))
            XCTAssertEqual(p.origin.contextType, context); XCTAssertEqual(p.origin.contextId, "exact-context")
            XCTAssertEqual(p.origin.releaseId, "exact-release"); XCTAssertEqual(p.origin.instanceId, "exact-instance")
            XCTAssertEqual(p.origin.rulesVersion, "exact-rules")
        }
    }
    func testRecordedAwardDoesNotInventEligibilityClaimOrAllocation() throws {
        let reward = detailItem(), p = try NonCashRewardDetailProjection(reward: reward, previous: .init(reward))
        XCTAssertEqual(p.qualification, .notProvided); XCTAssertEqual(p.claimProgress, .notProvided)
        XCTAssertEqual(p.allocation, .notProvided); XCTAssertEqual(p.sourceEvent, .notProvided)
        XCTAssertEqual(p.reward.state, .awarded); XCTAssertEqual(p.reward.rewardKind, "PHYSICAL")
    }
    func testEveryFrozenSourceTermRejectsMutation() {
        let previous = NonCashRewardReference(detailItem())
        let mutations = [detailItem(id: "other"), detailItem(context: .theme), detailItem(contextID: "other"),
            detailItem(release: "other"), detailItem(instance: "other"), detailItem(rules: "other"),
            detailItem(merchant: "9"), detailItem(store: "9"), detailItem(title: "changed"), detailItem(quantity: 2),
            detailItem(from: 101), detailItem(until: 201), detailItem(terms: "new merchant terms"), detailItem(awarded: 101)]
        for value in mutations { XCTAssertThrowsError(try NonCashRewardDetailProjection(reward: value, previous: previous)) }
    }
    func testQuantityAndServerAsOfHalfOpenValidityAreValidated() throws {
        for value in [detailItem(quantity: 2), detailItem(from: 200, until: 200), detailItem(validity: .elapsed)] {
            XCTAssertThrowsError(try NonCashRewardDetailProjection(reward: value, previous: .init(value)))
        }
        for (time, status) in [(99.0, NonCashReward.Validity.upcoming), (100, .inWindow), (199, .inWindow), (200, .elapsed)] {
            let value = detailItem(asOf: time), p = try NonCashRewardDetailProjection(reward: value, previous: .init(value))
            XCTAssertEqual(p.reward.validityStatus, status); XCTAssertEqual(p.reward.state, .awarded)
        }
    }
    func testTerminalStatesNeverResurrectOrCrossToAnotherTerminalState() throws {
        for terminal in [NonCashReward.State.redeemed, .expired, .reversed] {
            let previous = NonCashRewardReference(detailItem(state: terminal))
            for other in [NonCashReward.State.awarded, .redeemed, .expired, .reversed] where other != terminal {
                XCTAssertThrowsError(try NonCashRewardDetailProjection(reward: detailItem(state: other, asOf: 151), previous: previous))
            }
            XCTAssertEqual(try NonCashRewardDetailProjection(reward: detailItem(state: terminal, asOf: 151), previous: previous).reward.state, terminal)
        }
    }
    func testOlderObservationCannotReplaceAcceptedDetail() {
        XCTAssertThrowsError(try NonCashRewardDetailProjection(reward: detailItem(asOf: 149), previous: .init(detailItem())))
    }
    func testFreshReadIsRequiredBeforeSnapshotBecomesVisible() async {
        let reader = DetailReader(), model = reader.model()
        XCTAssertNil(model.visibleValue(scope: reader.scope))
        let task = Task { await model.refresh(reader: reader) }; await reader.waitFor(1)
        XCTAssertTrue(model.isLoading); XCTAssertNil(model.visibleValue(scope: reader.scope))
        reader.finish(0, detailItem(state: .redeemed, asOf: 151)); await task.value
        XCTAssertEqual(model.visibleValue(scope: reader.scope)?.reward.state, .redeemed)
        XCTAssertFalse(model.isLoading); XCTAssertNil(model.visibleIssue(scope: reader.scope))
    }
    func testNewerRefreshDiscardsOlderSuccess() async {
        let reader = DetailReader(), model = reader.model()
        let old = Task { await model.refresh(reader: reader) }; await reader.waitFor(1)
        let newer = Task { await model.refresh(reader: reader) }; await reader.waitFor(2)
        reader.finish(1, detailItem(state: .redeemed, asOf: 152)); await newer.value
        reader.finish(0, detailItem(asOf: 151)); await old.value
        XCTAssertEqual(model.visibleValue(scope: reader.scope)?.reward.state, .redeemed)
    }
    func testBackOrCloseCancelsPendingSuccessAndClearsAcceptedValue() async {
        let reader = DetailReader(), model = reader.model()
        let task = Task { await model.refresh(reader: reader) }; await reader.waitFor(1); model.cancelPending()
        reader.finish(0, detailItem()); await task.value
        XCTAssertNil(model.visibleValue(scope: reader.scope)); XCTAssertNil(model.loadedScope); XCTAssertFalse(model.isLoading)
    }
    func testRetainedSelectionCannotBeReboundBeforeConstruction() async {
        let reader = DetailReader(), scopeA = reader.scope
        let selected = NonCashRewardDetailSelection(reference: .init(detailItem()), ownerScope: scopeA)
        reader.scope = UUID()
        let model = NonCashRewardDetailModel(selection: selected)
        await model.refresh(reader: reader)
        XCTAssertTrue(reader.references.isEmpty); XCTAssertEqual(model.selection.ownerScope, scopeA)
        XCTAssertNil(model.visibleValue(scope: reader.scope)); XCTAssertNotEqual(selected.id, NonCashRewardDetailSelection(reference: selected.reference, ownerScope: reader.scope).id)
    }
    func testPushedSessionChangeImmediatelyHidesOldValueAndDoesNotDispatchAgain() async {
        let reader = DetailReader(), model = reader.model(), oldScope = reader.scope
        let first = Task { await model.refresh(reader: reader) }; await reader.waitFor(1); reader.finish(0, detailItem()); await first.value
        XCTAssertNotNil(model.visibleValue(scope: oldScope)); reader.scope = UUID()
        XCTAssertNil(model.visibleValue(scope: reader.scope)); await model.refresh(reader: reader)
        XCTAssertEqual(reader.references.count, 1); XCTAssertNil(model.visibleValue(scope: oldScope))
    }
    func testAuthenticationAndConfigurationGatesDispatchNothing() async {
        let reader = DetailReader(), model = reader.model()
        reader.isAuthenticated = false; await model.refresh(reader: reader); XCTAssertEqual(model.visibleIssue(scope: reader.scope), .login)
        reader.isAuthenticated = true; reader.isConfigured = false; await model.refresh(reader: reader)
        XCTAssertEqual(model.visibleIssue(scope: reader.scope), .notConfigured); XCTAssertTrue(reader.references.isEmpty)
    }
    func testLatestAcceptedTerminalReferenceSurvivesRefreshAndPreventsResurrection() async {
        let reader = DetailReader(), model = reader.model()
        let first = Task { await model.refresh(reader: reader) }; await reader.waitFor(1); reader.finish(0, detailItem(state: .redeemed)); await first.value
        let next = Task { await model.refresh(reader: reader) }; await reader.waitFor(2)
        XCTAssertEqual(reader.references[1].snapshot.state, .redeemed)
        reader.finish(1, detailItem(asOf: 151)); await next.value
        XCTAssertNil(model.visibleValue(scope: reader.scope)); XCTAssertNotNil(model.visibleIssue(scope: reader.scope))
    }
    func testFailureHidesSnapshotAndRetryKeepsLastAcceptedFrozenReference() async {
        let reader = DetailReader(), model = reader.model()
        let first = Task { await model.refresh(reader: reader) }; await reader.waitFor(1); reader.finish(0, detailItem(state: .expired, asOf: 200)); await first.value
        let failure = Task { await model.refresh(reader: reader) }; await reader.waitFor(2); reader.fail(1, APIError.httpStatus(503)); await failure.value
        XCTAssertNil(model.visibleValue(scope: reader.scope))
        let retry = Task { await model.refresh(reader: reader) }; await reader.waitFor(3)
        XCTAssertEqual(reader.references[2].snapshot.state, .expired)
        reader.finish(2, detailItem(state: .expired, asOf: 201)); await retry.value
        XCTAssertEqual(model.visibleValue(scope: reader.scope)?.reward.state, .expired)
    }
    func testCollectionCapturesAcceptedRowScopeBeforeDeferredNavigation() async throws {
        let reader = DetailReader(), collection = NonCashRewardCollectionModel(), scopeA = reader.scope
        await collection.refresh(reader: reader)
        let retained = try XCTUnwrap(collection.visibleSelections(scope: scopeA).first)
        reader.scope = UUID()
        XCTAssertTrue(collection.visibleSelections(scope: reader.scope).isEmpty)
        let model = NonCashRewardDetailModel(selection: retained); await model.refresh(reader: reader)
        XCTAssertEqual(model.selection.ownerScope, scopeA); XCTAssertTrue(reader.references.isEmpty)
    }
}

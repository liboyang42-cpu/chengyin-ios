import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class ChapterInlineKitSelectionTests: XCTestCase {
    func testReentrySkipsCompletedFirstKit() throws {
        let state = try inlineState(kit: ["qa": .object(["finished": .bool(true)]), "note": .object(["done": .bool(false)])])
        var selection = ChapterInlineKitSelection()
        selection.reconcile(state, preservingDraft: false)
        XCTAssertEqual(selection.selected, .note)
    }

    func testCurrentReceiptRemainsUntilExplicitNext() throws {
        var selection = ChapterInlineKitSelection()
        selection.reconcile(try inlineState(kit: ["qa": .object([:]), "note": .object([:])]), preservingDraft: false)
        let acknowledged = try inlineState(kit: ["qa": .object(["finished": .bool(true), "passed": .bool(false)]), "note": .object([:])], version: 2)
        selection.reconcile(acknowledged, preservingDraft: false)
        XCTAssertEqual(selection.selected, .qa)
        XCTAssertTrue(ChapterInlineKitSelection.complete(.qa, in: acknowledged))
        let next = try XCTUnwrap(ChapterInlineKitSelection.preferred(in: acknowledged, excluding: .qa))
        XCTAssertEqual(next, .note)
        XCTAssertTrue(selection.select(next, in: acknowledged))
        XCTAssertEqual(selection.selected, .note)
        var reentry = ChapterInlineKitSelection()
        reentry.reconcile(acknowledged, preservingDraft: false)
        XCTAssertEqual(reentry.selected, .note)
    }

    func testProofOnlyStepsDoesNotHideLaterInteractiveTask() throws {
        let state = try inlineState(kit: ["steps": .object(["reached": .bool(false)]), "slowTask": .object(["started": .bool(true), "claimed": .bool(false)]), "dailySign": .object([:])])
        XCTAssertEqual(ChapterInlineKitSelection.preferred(in: state), .slowTask)
        XCTAssertEqual(ChapterInlineKitSelection.preferred(in: state, excluding: .slowTask), .dailySign)
    }

    func testAmbientWithoutCompletionBitDoesNotHideInteractiveTask() throws {
        let state = try inlineState(kit: ["silentOrder": .object([:]), "musicCorner": .object([:]), "timeWindow": .object([:]), "dailySign": .object([:])])
        var selection = ChapterInlineKitSelection()
        selection.reconcile(state, preservingDraft: false)
        XCTAssertEqual(selection.selected, .dailySign)
        for ambient in [PlayKitScreenKind.silentOrder, .musicCorner, .timeWindow] {
            XCTAssertFalse(ChapterInlineKitSelection.complete(ambient, in: state))
            XCTAssertTrue(selection.select(ambient, in: state))
            selection.reconcile(state, preservingDraft: false)
            XCTAssertEqual(selection.selected, ambient)
        }
    }

    func testOnlyAmbientAndProgressKindsRemainReachable() throws {
        let state = try inlineState(kit: ["silentOrder": .object([:]), "steps": .object([:]), "walk": .object([:]), "musicCorner": .object([:]), "timeWindow": .object([:]), "bingo": .object([:])])
        var selection = ChapterInlineKitSelection()
        selection.reconcile(state, preservingDraft: false)
        XCTAssertEqual(selection.selected, .silentOrder)
        for kind in PlayKitScreenKind.present(in: state) {
            XCTAssertTrue(selection.select(kind, in: state))
            XCTAssertEqual(selection.selected, kind)
        }
    }

    func testAllCompleteRetainsSourceFirstAndAllowsExplicitReceipts() throws {
        let state = try inlineState(kit: ["qa": .object(["finished": .bool(true)]), "note": .object(["done": .bool(true)]), "diceRoll": .object(["rolled": .bool(true)])])
        var selection = ChapterInlineKitSelection()
        selection.reconcile(state, preservingDraft: false)
        XCTAssertEqual(selection.selected, .qa)
        XCTAssertNil(ChapterInlineKitSelection.preferred(in: state, excluding: .qa))
        XCTAssertTrue(selection.select(.diceRoll, in: state))
        selection.reconcile(state, preservingDraft: false)
        XCTAssertEqual(selection.selected, .diceRoll)
    }

    func testAbsentAndUnknownOnlyKindsDoNotInventAPlayableScreen() throws {
        let cases: [[String: PlayWireValue]] = [[:], ["unknownFutureKit": .object([:])], ["qa": .null]]
        for kit in cases {
            let state = try inlineState(kit: kit)
            var selection = ChapterInlineKitSelection()
            selection.reconcile(state, preservingDraft: false)
            XCTAssertTrue(PlayKitScreenKind.present(in: state).isEmpty)
            XCTAssertNil(selection.selected)
            XCTAssertNil(ChapterInlineKitSelection.preferred(in: state))
            XCTAssertFalse(selection.select(.walk, in: state))
        }
    }

    func testMechanicalBranchAndRandomShareScreenNormalization() throws {
        let config: PlayWireValue = .object(["branch": .object(["enabled": .bool(true)]), "random": .object(["enabled": .bool(true), "drawCount": .int(2), "deckName": .string("Fixture")])])
        let branch: PlayWireValue = .object(["currentStep": .object(["terminal": .bool(true)])])
        let state = try inlineState(kit: [:], config: config, branch: branch, draws: [.string("one")])
        XCTAssertEqual(PlayKitScreenKind.present(in: state), [.branch, .random])
        XCTAssertEqual(ChapterInlineKitSelection.segment(.branch, in: state), branch)
        XCTAssertTrue(ChapterInlineKitSelection.complete(.branch, in: state))
        XCTAssertEqual(ChapterInlineKitSelection.preferred(in: state), .random)
        let segment = ChapterInlineKitSelection.segment(.random, in: state)
        XCTAssertEqual(segment["drawn"].array, [.string("one")])
        XCTAssertEqual(segment["drawCount"].integer, 2)
        XCTAssertEqual(segment["deckName"].text, "Fixture")
        let completed = try inlineState(kit: [:], config: config, branch: branch, draws: [.string("one"), .string("two")])
        XCTAssertTrue(ChapterInlineKitSelection.complete(.random, in: completed))
        XCTAssertNil(ChapterInlineKitSelection.preferred(in: completed, excluding: .branch))
    }

    func testPlayKitSegmentTakesPrecedenceOverMechanicalFallback() throws {
        let state = try inlineState(kit: ["branch": .object(["ended": .bool(false)]), "random": .object(["drawn": .array([]), "drawCount": .int(1)])],
            config: .object(["random": .object(["enabled": .bool(true), "drawCount": .int(1)])]),
            branch: .object(["ended": .bool(true)]), draws: [.string("fallback")])
        XCTAssertFalse(ChapterInlineKitSelection.complete(.branch, in: state))
        XCTAssertFalse(ChapterInlineKitSelection.complete(.random, in: state))
        XCTAssertEqual(ChapterInlineKitSelection.segment(.random, in: state), state.playKit["random"])
    }

    func testAbsentMechanicalBranchesNeedExplicitEnabledConfiguration() throws {
        let state = try inlineState(kit: [:], config: .object(["branch": .object(["enabled": .bool(false)]), "random": .object([:])]), branch: .object([:]), draws: [.string("old")])
        XCTAssertTrue(PlayKitScreenKind.present(in: state).isEmpty)
        XCTAssertNil(ChapterInlineKitSelection.preferred(in: state))
    }

    func testDisappearingSegmentDoesNotSilentlyDiscardDraft() throws {
        var selection = ChapterInlineKitSelection()
        selection.reconcile(try inlineState(kit: ["qa": .object([:]), "note": .object([:])]), preservingDraft: false)
        let readback = try inlineState(kit: ["note": .object([:])], version: 2)
        selection.reconcile(readback, preservingDraft: true)
        XCTAssertEqual(selection.selected, .qa)
        // After explicit discard, the only remaining kind must still be selectable.
        XCTAssertTrue(selection.select(.note, in: readback))
        XCTAssertEqual(selection.selected, .note)
    }

    func testAbsentSelectionReconcilesWhenNoDraftOrPendingRemains() throws {
        var selection = ChapterInlineKitSelection()
        selection.reconcile(try inlineState(kit: ["qa": .object([:])]), preservingDraft: false)
        selection.reconcile(try inlineState(kit: ["note": .object([:])], version: 2), preservingDraft: false)
        XCTAssertEqual(selection.selected, .note)
    }

    func testNewSessionCannotReusePreviousSelectionOrDraft() throws {
        var selection = ChapterInlineKitSelection()
        selection.reconcile(try inlineState(kit: ["qa": .object([:])]), preservingDraft: false)
        let replacement = try inlineState(kit: ["note": .object([:])], sessionID: 2)
        XCTAssertFalse(selection.select(.note, in: replacement))
        selection.reconcile(replacement, preservingDraft: true)
        XCTAssertEqual(selection.sessionID, 2)
        XCTAssertEqual(selection.selected, .note)
    }

    func testMissingTargetNeverChangesCurrentSelection() throws {
        let state = try inlineState(kit: ["note": .object([:])])
        var selection = ChapterInlineKitSelection()
        selection.reconcile(state, preservingDraft: false)
        XCTAssertFalse(selection.select(.qa, in: state))
        XCTAssertEqual(selection.selected, .note)
    }
}

@available(macOS 14.0, *)
@MainActor final class ChapterInlinePendingSelectionTests: XCTestCase {
    func testUnknownActionReadbackKeepsRecoveryPresentationAndFrozenPending() async throws {
        let session = try PlayExperienceSession(accountID: 1, epoch: 1, namespace: "inline-fixture", token: "synthetic-token")
        let initial = inlineRaw(kit: ["qa": .object(["finished": .bool(true)]), "note": .object([:])])
        let readback = inlineRaw(kit: ["qa": .object(["finished": .bool(true)])], version: 2)
        let transport = ChapterInlineSelectionTransport { request in
            if request.url?.path.hasSuffix("action") == true { throw URLError(.timedOut) }
            let value = request.url?.path.hasSuffix("state") == true ? readback : initial
            return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": value])), 200)
        }
        let model = PlayAdvancedCoordinator(activityID: 41, topicID: 71, nodeID: 701,
            service: .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport, enabled: [.reads, .advanced]), currentSession: { session })
        await model.start()
        var selection = ChapterInlineKitSelection()
        selection.reconcile(try XCTUnwrap(model.state), preservingDraft: false)
        XCTAssertEqual(selection.selected, .note)
        let review = try model.review(kind: "note", action: "SUBMIT_NOTE", detail: ["text": .string("Fixture note")])
        let accepted = await model.submit(review)
        XCTAssertFalse(accepted)
        let pending = try XCTUnwrap(model.pending)
        await model.recover()
        XCTAssertEqual(model.phase, "retryable")
        XCTAssertEqual(model.pending, pending)
        let state = try XCTUnwrap(model.state)
        XCTAssertNil(state.playKit["note"].object)
        selection.reconcile(state, preservingDraft: model.pending != nil)
        XCTAssertEqual(selection.selected, .note)
        XCTAssertEqual(model.pending, pending)
        XCTAssertEqual(transport.requests.filter { $0.url?.path.hasSuffix("action") == true }.count, 1)
    }
}

private func inlineRaw(kit: [String: PlayWireValue], sessionID: Int = 1, version: Int = 1, config: PlayWireValue = .null, branch: PlayWireValue = .null, draws: [PlayWireValue] = []) -> PlayWireValue {
    .object(["sessionId": .int(sessionID), "activityId": .int(41), "topicId": .int(71), "nodeId": .int(701), "version": .int(version), "status": .string("RUNNING"), "present": .string("inline"), "playKit": .object(kit), "config": config, "branch": branch, "draws": .array(draws)])
}
private func inlineState(kit: [String: PlayWireValue], sessionID: Int = 1, version: Int = 1, config: PlayWireValue = .null, branch: PlayWireValue = .null, draws: [PlayWireValue] = []) throws -> PlayAdvancedState {
    try PlayAdvancedState(inlineRaw(kit: kit, sessionID: sessionID, version: version, config: config, branch: branch, draws: draws))
}
private final class ChapterInlineSelectionTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try await operation(request) }
}

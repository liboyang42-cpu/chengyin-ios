import Foundation
import XCTest
@testable import QuestifyCore

final class OpsDegradedStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func target(_ layer: OpsKillSwitchLayer, _ id: String?) -> OpsKillSwitchTarget { OpsKillSwitchTarget(layer: layer, identifier: id)! }
    private func readout(_ target: OpsKillSwitchTarget, _ state: OpsKillSwitchState, age: TimeInterval = 1) -> OpsKillSwitchReadout {
        .init(target: target, state: state, observedAt: now.addingTimeInterval(-age))
    }
    private func decide(_ kind: OpsOperationKind, _ chain: [OpsKillSwitchTarget], _ readouts: [OpsKillSwitchReadout]) -> OpsGateDecision {
        OpsKillSwitchResolver.decision(kind: kind, chain: chain, readouts: readouts, now: now, maximumAge: 60)
    }

    func testTargetsRequireExactIdentifiersExceptGlobal() {
        XCTAssertNil(OpsKillSwitchTarget(layer: .global, identifier: "1"))
        for layer in OpsKillSwitchLayer.allCases where layer != .global {
            XCTAssertNil(OpsKillSwitchTarget(layer: layer, identifier: nil))
            XCTAssertNil(OpsKillSwitchTarget(layer: layer, identifier: ""))
            XCTAssertNil(OpsKillSwitchTarget(layer: layer, identifier: "a b"))
            XCTAssertNil(OpsKillSwitchTarget(layer: layer, identifier: String(repeating: "x", count: 129)))
            XCTAssertNotNil(OpsKillSwitchTarget(layer: layer, identifier: "42"))
        }
    }

    func testPreservedServicesAreNeverGatedEvenByActiveGlobalSwitch() {
        let active = readout(.global, .active(.init(blocksNewOperations: true, affectsExisting: true), incident: .serviceDegraded))
        XCTAssertEqual(decide(.preservedService, [], [active]), .preserved)
        XCTAssertEqual(decide(.preservedService, [], []), .preserved)
    }

    func testActiveSwitchBlocksNewOperationsOnlyForItsExactTarget() {
        let theme = target(.theme, "12"), other = target(.theme, "13")
        let readouts = [readout(.global, .inactive),
                        readout(theme, .active(.init(blocksNewOperations: true, affectsExisting: false), incident: .aiDisabled))]
        XCTAssertEqual(decide(.newOperation, [theme], readouts), .blocked(theme, .aiDisabled))
        // A switch on another theme never applies, and the missing readout keeps it unverified.
        XCTAssertEqual(decide(.newOperation, [other], readouts), .unverified([.theme]))
        // Existing operations continue when the switch explicitly does not affect them.
        XCTAssertEqual(decide(.continuation, [theme], readouts), .proceed)
    }

    func testContinuationIsBlockedOnlyWhenTheServerSaysSoAndUnstatedImpactIsUnverified() {
        let node = target(.node, "7")
        let affects = [readout(.global, .inactive), readout(node, .active(.init(blocksNewOperations: true, affectsExisting: true), incident: .nodeUnsafeOrClosed))]
        XCTAssertEqual(decide(.continuation, [node], affects), .blocked(node, .nodeUnsafeOrClosed))
        let unstated = [readout(.global, .inactive), readout(node, .active(.init(blocksNewOperations: true, affectsExisting: nil), incident: .nodeUnsafeOrClosed))]
        XCTAssertEqual(decide(.continuation, [node], unstated), .unverified([.node]))
        XCTAssertEqual(decide(.newOperation, [node], unstated), .blocked(node, .nodeUnsafeOrClosed))
    }

    func testMissingUnknownStaleFutureAndDuplicateReadoutsAreNeverInactive() {
        let merchant = target(.merchant, "5")
        XCTAssertEqual(decide(.newOperation, [merchant], []), .unverified([.global, .merchant]))
        XCTAssertEqual(decide(.newOperation, [merchant], [readout(.global, .unknown), readout(merchant, .inactive)]), .unverified([.global]))
        XCTAssertEqual(decide(.newOperation, [merchant], [readout(.global, .inactive, age: 61), readout(merchant, .inactive)]), .unverified([.global]))
        XCTAssertEqual(decide(.newOperation, [merchant], [readout(.global, .inactive, age: -5), readout(merchant, .inactive)]), .unverified([.global]))
        XCTAssertEqual(decide(.newOperation, [merchant], [readout(.global, .inactive), readout(merchant, .inactive), readout(merchant, .inactive)]), .unverified([.merchant]))
        XCTAssertEqual(decide(.newOperation, [merchant], [readout(.global, .inactive), readout(merchant, .inactive)]), .proceed)
        XCTAssertEqual(OpsKillSwitchResolver.decision(kind: .newOperation, chain: [], readouts: [readout(.global, .inactive)], now: now, maximumAge: 0), .unverified([.global]))
    }

    func testBroadestActiveLayerWinsInChainOrder() {
        let theme = target(.theme, "1"), sku = target(.sku, "2")
        let readouts = [readout(.global, .inactive),
                        readout(theme, .active(.init(blocksNewOperations: true, affectsExisting: false), incident: .serviceDegraded)),
                        readout(sku, .active(.init(blocksNewOperations: true, affectsExisting: false), incident: .inventoryPaused))]
        XCTAssertEqual(decide(.newOperation, [theme, sku], readouts), .blocked(theme, .serviceDegraded))
        let notBlocking = [readout(.global, .inactive),
                           readout(theme, .active(.init(blocksNewOperations: false, affectsExisting: false), incident: .serviceDegraded)),
                           readout(sku, .active(.init(blocksNewOperations: true, affectsExisting: false), incident: .inventoryPaused))]
        XCTAssertEqual(decide(.newOperation, [theme, sku], notBlocking), .blocked(sku, .inventoryPaused))
    }

    func testProposedDecoderKeepsUnknownRowsUnknownAndRejectsBadEnvelopes() throws {
        let json = """
        {"code":200,"data":{"switches":[
          {"layer":"global","active":false},
          {"layer":"theme","targetId":"12","active":true,"blocksNew":true,"affectsExisting":false,"incident":"aiDisabled"},
          {"layer":"sku","targetId":"9","active":true,"blocksNew":true,"incident":"somethingNew"},
          {"layer":"node","targetId":"3"},
          {"layer":"planet","targetId":"1","active":true},
          {"layer":"global","targetId":"1","active":false},
          {"layer":"merchant","active":false}
        ]}}
        """
        let rows = try XCTUnwrap(OpsKillSwitchReadoutDecoder.decode(Data(json.utf8), observedAt: now))
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].state, .inactive)
        XCTAssertEqual(rows[1].state, .active(.init(blocksNewOperations: true, affectsExisting: false), incident: .aiDisabled))
        XCTAssertEqual(rows[2].state, .unknown)
        XCTAssertEqual(rows[3].state, .unknown)
        XCTAssertNil(OpsKillSwitchReadoutDecoder.decode(Data(#"{"code":500,"data":{"switches":[]}}"#.utf8), observedAt: now))
        XCTAssertNil(OpsKillSwitchReadoutDecoder.decode(Data(#"{"code":200}"#.utf8), observedAt: now))
        XCTAssertNil(OpsKillSwitchReadoutDecoder.decode(Data("not json".utf8), observedAt: now))
    }

    func testIncidentCopyOnlyPointsAtPreservedActions() {
        for incident in OpsIncidentKind.allCases {
            XCTAssertTrue(incident.copyKey.hasPrefix("opsSafety.incident."))
            XCTAssertFalse(incident.preservedActions.isEmpty)
        }
        XCTAssertEqual(OpsIncidentKind.paymentPendingEntitlement.preservedActions.first, .doNotPayAgain)
        XCTAssertTrue(OpsIncidentKind.inventoryPaused.preservedActions.contains(.afterSales))
    }

    func testDeadlinePolicyDefaultsOffAndRejectsOutOfBoundsValues() {
        XCTAssertNil(OpsDeadlinePolicy.disabled.limit(for: .aiGeneration))
        XCTAssertNil(OpsDeadlinePolicy.disabled.limit(for: .read))
        XCTAssertEqual(OpsDeadlinePolicy.planProposalAIOnly.limit(for: .aiGeneration), .seconds(8))
        XCTAssertNil(OpsDeadlinePolicy.planProposalAIOnly.limit(for: .write))
        XCTAssertNil(OpsDeadlinePolicy(read: .zero))
        XCTAssertNil(OpsDeadlinePolicy(write: .seconds(121)))
    }

    func testDeadlineWithoutLimitRunsUnchanged() async throws {
        let outcome = try await OpsDeadline.run(.write, policy: .disabled) { 7 }
        guard case .completed(7) = outcome else { return XCTFail("expected completion") }
    }

    func testTimedOutWriteIsUnknownNotFailedAndReadAndAIUseFallbacks() async throws {
        let policy = try XCTUnwrap(OpsDeadlinePolicy(aiGeneration: .milliseconds(20), read: .milliseconds(20), write: .milliseconds(20)))
        let slow: @Sendable () async throws -> Int = { try await Task.sleep(for: .seconds(5)); return 1 }
        guard case .writeOutcomeUnknown = try await OpsDeadline.run(.write, policy: policy, operation: slow) else { return XCTFail("write") }
        guard case .readTimedOut = try await OpsDeadline.run(.read, policy: policy, operation: slow) else { return XCTFail("read") }
        guard case .aiFallback = try await OpsDeadline.run(.aiGeneration, policy: policy, operation: slow) else { return XCTFail("ai") }
    }

    func testFastOperationAndThrownErrorsPassThroughWithinDeadline() async throws {
        let policy = try XCTUnwrap(OpsDeadlinePolicy(read: .seconds(5)))
        guard case .completed(3) = try await OpsDeadline.run(.read, policy: policy, operation: { 3 }) else { return XCTFail("value") }
        do {
            _ = try await OpsDeadline.run(.read, policy: policy) { () async throws -> Int in throw APIError.httpStatus(503) }
            XCTFail("expected error")
        } catch { XCTAssertEqual(error as? APIError, .httpStatus(503)) }
    }

    func testOptionalValuesAreNotMistakenForDeadline() async throws {
        let policy = try XCTUnwrap(OpsDeadlinePolicy(read: .seconds(5)))
        let outcome = try await OpsDeadline.run(.read, policy: policy) { () async throws -> Int? in nil }
        guard case .completed(nil) = outcome else { return XCTFail("nil value must complete") }
    }
}

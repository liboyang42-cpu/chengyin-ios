import SwiftUI
import XCTest
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor
final class HomeReturnAndCityDeltaSectionViewTests: XCTestCase {

    // MARK: - Helpers

    private let baseNow = Date(timeIntervalSince1970: 1_900_000_000)

    private func decodeHomeSnapshot(version: Int64 = 3, active: Bool = true) throws -> PrivateHomeSnapshot {
        let payload = active
            ? #"{"version":\#(version),"status":"ACTIVE","changedAt":1,"effectiveAt":1,"label":"Base","latitude":30.25,"longitude":120.15,"datum":"GCJ02"}"#
            : #"{"version":\#(version),"status":"DELETED"}"#
        return try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(payload.utf8))
    }

    private func decodePolicy() throws -> HomeReturnPolicy {
        let payload = #"{"policyVersion":"v1-policy","maxAccuracyMeters":45,"maxFixAgeSeconds":30}"#
        return try JSONDecoder().decode(HomeReturnPolicy.self, from: Data(payload.utf8))
    }

    private func decodeBoard(lifecycle: String = "OPEN", revision: Int64 = 4) throws -> CityReadBoard {
        let rulesHash = String(repeating: "a", count: 64)
        let payload = #"{"gameId":"g1","boardId":"b1","regionId":"r1","seasonId":"s1","rulesReleaseId":"rr1","rulesHash":"\#(rulesHash)","lifecycle":"\#(lifecycle)","title":"杭州常驻棋盘","revision":\#(revision)}"#
        return try JSONDecoder().decode(CityReadBoard.self, from: Data(payload.utf8))
    }

    private func decodeParticipation() throws -> CityParticipation {
        let payload = #"{"participationId":"part-1","membershipVersion":2}"#
        return try JSONDecoder().decode(CityParticipation.self, from: Data(payload.utf8))
    }

    private func decodeQuote(payer: String = "member-self", expiresAtMillis: Int64 = 2_000_000_000_000) throws -> CityActionQuote {
        let payload = #"{"quoteId":"quote-1","quoteVersion":2,"action":"ACQUIRE_PROPERTY","boardId":"b1","targetId":"prop-1","payerMemberId":"\#(payer)","ruleVersion":"r-v1","memberPointsCost":15,"actionCost":1,"beneficiaryMemberIds":["member-self"],"expiresAtMillis":\#(expiresAtMillis)}"#
        return try JSONDecoder().decode(CityActionQuote.self, from: Data(payload.utf8))
    }

    private func decodeDelta(sequence: Int64, boardVersion: Int64 = 4) throws -> CityDelta {
        let payload = #"{"eventId":"ev-\#(sequence)","boardId":"b1","seasonId":"s1","aggregate":"prop-1","type":"PROPERTY_UPDATED","sequence":\#(sequence),"boardVersion":\#(boardVersion)}"#
        return try JSONDecoder().decode(CityDelta.self, from: Data(payload.utf8))
    }

    // MARK: - Tests

    func testDefaultDisabledCoordinatorAndViewInstantiationRedactLocation() {
        let coordinator = HomeReturnAndCityDeltaCoordinator()
        let view = HomeReturnAndCityDeltaSectionView(coordinator: coordinator)
        _ = view.body

        XCTAssertEqual(coordinator.homeReturn.phase, .disabled)
        XCTAssertNil(coordinator.city)
        XCTAssertEqual(String(describing: coordinator), "HomeReturnAndCityDeltaCoordinator[redacted]")
        XCTAssertEqual(String(describing: coordinator.homeReturn), "HomeReturnRestoreCoordinator[redacted]")
        XCTAssertEqual(String(describing: coordinator.homeReturn.phase), "HomeReturnRestorePhase[redacted]")
    }

    func testHomeReturnRestoreLifecycleAndCooldownFailureTransitions() throws {
        let capabilities = ReformWorldCapabilities.syntheticFixture([.homeReturnRestore])
        let coordinator = HomeReturnAndCityDeltaCoordinator(capabilities: capabilities)
        let view = HomeReturnAndCityDeltaSectionView(coordinator: coordinator)

        XCTAssertEqual(coordinator.homeReturn.phase, .idle)
        XCTAssertThrowsError(
            try HomeReturnRestoreCoordinator.makeResourceScope(
                scopeType: "ALL_GAMES",
                resourceType: "stamina"
            )
        )
        let scope = try HomeReturnRestoreCoordinator.makeResourceScope(
            scopeType: "RUN",
            scopeId: "run-9",
            resourceType: "stamina"
        )
        let home = try decodeHomeSnapshot(version: 3, active: true)
        let policy = try decodePolicy()

        // 1. Settings-required failure (.servicesOff)
        let offResult = coordinator.homeReturn.evaluatePreflight(
            home: home,
            status: .servicesOff,
            policy: policy,
            scope: scope,
            now: baseNow,
            requestId: "req-preflight-off"
        )
        if case .failure(let presentation) = offResult {
            XCTAssertEqual(presentation.failure, .locationOff)
            XCTAssertTrue(presentation.requiresSettingsAction)
            XCTAssertFalse(presentation.retryableNow)
            XCTAssertEqual(String(describing: presentation), "HomeReturnFailurePresentation[redacted]")
        } else {
            XCTFail("Expected locationOff failure")
        }
        _ = view.body

        // 2. Successful preflight -> proofVerified -> restoring -> cooldown failure
        let checkResult = coordinator.homeReturn.evaluatePreflight(
            home: home,
            status: .fix(accuracyMeters: 10, capturedAt: baseNow),
            policy: policy,
            scope: scope,
            now: baseNow,
            requestId: "req-preflight-ok"
        )
        let check = try checkResult.get()
        XCTAssertEqual(coordinator.homeReturn.phase, .preflightReady(check))
        XCTAssertEqual(String(describing: check), "HomeReturnCheck[redacted]")
        _ = view.body

        let expiresMillis = Int64((baseNow.timeIntervalSince1970 + 60) * 1000)
        let proof = try coordinator.homeReturn.acceptProof(
            proofId: "proof-1",
            homeVersion: 3,
            scope: scope,
            expiresAtMillis: expiresMillis
        )
        XCTAssertEqual(coordinator.homeReturn.phase, .proofVerified(proof))
        _ = view.body

        let restoreReq = try coordinator.homeReturn.beginRestore(
            currentHomeVersion: 3,
            expectedAccountVersion: 7,
            deviceNow: baseNow,
            requestId: "req-restore-0001"
        )
        XCTAssertEqual(coordinator.homeReturn.phase, .restoring(restoreReq))
        _ = view.body

        let cooldownPayload = #"{"requestId":"req-restore-0001","proofId":"proof-1","decision":"COOLDOWN","current":4,"maximum":10,"accountVersion":7,"retryAfterSeconds":90}"#
        let cooldownReceipt = try JSONDecoder().decode(HomeRestoreReceipt.self, from: Data(cooldownPayload.utf8))
        let cooldownPhase = try coordinator.homeReturn.resolveRestore(cooldownReceipt)
        if case .failed(let presentation) = cooldownPhase {
            XCTAssertEqual(presentation.failure, .cooldown(retryAfterSeconds: 90))
            XCTAssertEqual(presentation.retryAfterSeconds, 90)
            XCTAssertFalse(presentation.retryableNow)
        } else {
            XCTFail("Expected cooldown failure phase")
        }
        _ = view.body

        // 3. Full restore to server maximum
        _ = coordinator.homeReturn.evaluatePreflight(
            home: home,
            status: .fix(accuracyMeters: 8, capturedAt: baseNow),
            policy: policy,
            scope: scope,
            now: baseNow,
            requestId: "req-preflight-2"
        )
        _ = try coordinator.homeReturn.acceptProof(
            proofId: "proof-2",
            homeVersion: 3,
            scope: scope,
            expiresAtMillis: expiresMillis
        )
        _ = try coordinator.homeReturn.beginRestore(
            currentHomeVersion: 3,
            expectedAccountVersion: 7,
            deviceNow: baseNow,
            requestId: "req-restore-0002"
        )
        let restoredPayload = #"{"requestId":"req-restore-0002","proofId":"proof-2","decision":"RESTORED","current":10,"maximum":10,"accountVersion":8}"#
        let restoredReceipt = try JSONDecoder().decode(HomeRestoreReceipt.self, from: Data(restoredPayload.utf8))
        let restoredPhase = try coordinator.homeReturn.resolveRestore(restoredReceipt)
        XCTAssertEqual(
            restoredPhase,
            .restored(current: 10, maximum: 10, accountVersion: 8, scope: scope)
        )
        _ = view.body
    }

    func testCityBoardLifecycleSelfPayerQuoteConfirmationAndDeltaStreamReload() throws {
        let capabilities = ReformWorldCapabilities.syntheticFixture([.homeReturnRestore, .cityActions])
        let coordinator = HomeReturnAndCityDeltaCoordinator(capabilities: capabilities)
        let board = try decodeBoard(lifecycle: "OPEN", revision: 4)
        let participation = try decodeParticipation()
        let city = try coordinator.configureCity(
            board: board,
            lifecycle: .open,
            participation: participation,
            initialSequence: 5
        )
        let view = HomeReturnAndCityDeltaSectionView(coordinator: coordinator)
        XCTAssertTrue(city.canAcceptNewActions)
        XCTAssertEqual(city.phase, .idle)
        _ = view.body

        // Stage quote and verify self-payer requirement
        let quote = try decodeQuote(payer: "member-self")
        try city.stageQuote(quote)
        XCTAssertEqual(city.phase, .awaitingQuoteConfirmation(quote))
        _ = view.body

        XCTAssertThrowsError(
            try city.confirmQuote(
                confirmingMemberId: "member-teammate",
                confirmed: true,
                deviceNow: baseNow
            )
        ) { error in
            XCTAssertEqual(error as? CityActionIssue, .payerMismatch)
        }

        let consent = try city.confirmQuote(
            confirmingMemberId: "member-self",
            confirmed: true,
            deviceNow: baseNow
        )
        XCTAssertEqual(city.confirmedConsent, consent)
        _ = view.body

        // Begin action and test unknown -> conflict resolution
        let intent = try city.beginAction(
            kind: .acquireProperty,
            targetId: "prop-1",
            roundSeq: 1,
            requestId: "req-city-0001"
        )
        XCTAssertEqual(city.phase, .inFlight(intent))
        XCTAssertFalse(city.canAcceptNewActions)
        _ = view.body

        XCTAssertEqual(try city.resolveAction(nil), .unknown)
        XCTAssertEqual(city.phase, .inFlight(intent))

        let conflictPayload = #"{"requestId":"req-city-0001","boardId":"b1","action":"ACQUIRE_PROPERTY","decision":"VERSION_CONFLICT","currentVersion":6,"taskAttemptKept":true}"#
        let conflictReceipt = try JSONDecoder().decode(CityActionReceipt.self, from: Data(conflictPayload.utf8))
        let outcome = try city.resolveAction(conflictReceipt)
        XCTAssertEqual(outcome, .refresh(taskAttemptKept: true))
        XCTAssertEqual(city.phase, .settled(.refresh(taskAttemptKept: true)))
        XCTAssertTrue(city.needsSnapshotReload)
        _ = view.body

        // Apply fresh snapshot and ingest contiguous vs gap deltas
        let updatedBoard = try decodeBoard(lifecycle: "OPEN", revision: 6)
        XCTAssertTrue(
            try city.applySnapshot(
                board: updatedBoard,
                lifecycle: .open,
                participation: participation,
                sequence: 10
            )
        )
        XCTAssertFalse(city.needsSnapshotReload)
        XCTAssertEqual(city.deltaStream.cursor.sequence, 10)

        let d11 = try decodeDelta(sequence: 11, boardVersion: 6)
        let d12 = try decodeDelta(sequence: 12, boardVersion: 7)
        XCTAssertEqual(city.ingestDeltas([d12, d11]), .applied([d11, d12]))
        XCTAssertEqual(city.deltaStream.cursor.sequence, 12)
        XCTAssertEqual(city.deltaStream.cursor.boardVersion, 7)
        XCTAssertEqual(city.lastAppliedDeltas.count, 2)
        try city.advanceChallenge(challengeId: "chal-1", to: .offered)
        _ = view.body

        let gapDelta = try decodeDelta(sequence: 15, boardVersion: 8)
        XCTAssertEqual(city.ingestDeltas([gapDelta]), .snapshotRequired)
        XCTAssertTrue(city.needsSnapshotReload)
        XCTAssertEqual(city.phase, .snapshotRequired)
        XCTAssertFalse(city.canAcceptNewActions)
        _ = view.body
    }
}

import XCTest
@testable import QuestifyCore

final class ClubOpsSettlementPresentationTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81)
    private func topic(_ id: Int, status: String = "settled", verified: Bool = true) -> ClubGovernanceValue {
        .object(["id": .integer(id), "topicId": .integer(90 + id), "name": .string("Topic"), "status": .string(status),
                 "amountStatus": .string(verified ? "verified" : "unverified"), "amountText": verified ? .string("¥10.00") : .null,
                 "originalAmountText": .string("¥10.00"), "executedAdjustmentText": .string("¥0.00"), "netAmountText": .string("¥10.00"),
                 "arrivedText": .string("arrived"), "paidText": .string("paid")])
    }
    func testVerifiedTotalIsServerTextAndOwnerRequiresExplicitTrue() throws {
        let value: ClubGovernanceValue = .object(["settledAmountStatus": .string("verified"), "settledAmountText": .string("¥12,480.00"),
            "unverifiedSettledCount": .integer(0), "isOwner": .bool(true), "topics": .array([topic(1)])])
        let summary = try ClubOpsSettlementSummary(value: value, scope: scope)
        XCTAssertEqual(summary.settledAmountText, "¥12,480.00"); XCTAssertTrue(summary.isOwner); XCTAssertTrue(summary.hasTopics)
        var other = value.object!; other["isOwner"] = .string("true")
        XCTAssertFalse(try ClubOpsSettlementSummary(value: .object(other), scope: scope).isOwner)
        other["isOwner"] = nil
        XCTAssertFalse(try ClubOpsSettlementSummary(value: .object(other), scope: scope).isOwner)
    }
    func testUnverifiedTotalNeverInventsAnAmount() throws {
        let summary = try ClubOpsSettlementSummary(value: ClubGovernanceFixtures.value(.settlement), scope: scope)
        XCTAssertNil(summary.settledAmountText); XCTAssertEqual(summary.unverifiedSettledCount, 1); XCTAssertFalse(summary.isOwner)
    }
    func testInconsistentSummaryFailsClosed() {
        let bad: ClubGovernanceValue = .object(["settledAmountStatus": .string("unverified"), "settledAmountText": .string("¥1"),
            "unverifiedSettledCount": .integer(1), "topics": .array([topic(1, verified: false)])])
        XCTAssertThrowsError(try ClubOpsSettlementSummary(value: bad, scope: scope))
    }
    func testWithdrawHintMatchesMiniProgramStates() {
        XCTAssertEqual(ClubOpsWithdrawHint(isOwner: true, availability: .zero), .zero)
        XCTAssertEqual(ClubOpsWithdrawHint(isOwner: true, availability: .unknown), .unknown)
        XCTAssertNil(ClubOpsWithdrawHint(isOwner: true, availability: .positive))
        for availability in [ClubOwnerFundsAvailability.zero, .unknown, .positive] {
            XCTAssertEqual(ClubOpsWithdrawHint(isOwner: false, availability: availability), .ownerOnly)
        }
        XCTAssertEqual(ClubOpsWithdrawHint.ownerOnly.localizationKey, "clubOps.settlement.withdraw.ownerOnly")
    }
}

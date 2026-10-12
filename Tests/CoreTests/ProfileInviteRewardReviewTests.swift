import XCTest
@testable import QuestifyCore

final class ProfileInviteRewardReviewTests: XCTestCase {
    private func scan(_ rows:String="[]",total:Int?=0) throws -> SocialRewardScan {
        let data="{\"rows\":\(rows),\"total\":\(total.map(String.init) ?? "null")}"
        return try JSONDecoder().decode(SocialRewardScan.self,from:Data(data.utf8))
    }
    private func member(_ id:Int) throws -> SocialInvitedMember {try JSONDecoder().decode(SocialInvitedMember.self,from:Data("{\"id\":\(id)}".utf8))}
    private let ledger = #"[{"eventType":5,"eventId":"0201","changePoints":"1.25"},{"eventType":5,"eventId":"201","changePoints":"1.25"},{"eventType":5,"eventId":"202","changePoints":"5.25"},{"eventType":5,"eventId":"999","changePoints":"3.25"}]"#
    func testCompleteCumulativeIncludesRewardsOutsideLoadedInvitePage() throws {let r=ProfileInviteRewardReview(scan:try scan(ledger,total:4));XCTAssertEqual(r.ledgerState,.complete);XCTAssertEqual(r.cumulativePoints,11)}
    func testMonthMatchesOnlyExactLoadedMemberIDs() throws {let r=ProfileInviteRewardReview(scan:try scan(ledger,total:4));let m=r.month(members:try [member(201),member(202)]);XCTAssertEqual(m.earnedPoints,Decimal(string:"7.75"));XCTAssertEqual(m.loadedMemberCount,2);XCTAssertFalse(m.isPartial)}
    func testDuplicateLoadedMembersDoNotDoubleCountRewardsOrPeople() throws {let r=ProfileInviteRewardReview(scan:try scan(ledger,total:4));let m=r.month(members:try [member(201),member(201)]);XCTAssertEqual(m.earnedPoints,Decimal(string:"2.50"));XCTAssertEqual(m.loadedMemberCount,1)}
    func testCompleteZeroIsKnownZero() throws {let r=ProfileInviteRewardReview(scan:try scan());XCTAssertEqual(r.ledgerState,.complete);XCTAssertEqual(r.cumulativePoints,0)}
    func testMissingScanIsNotZero() {let r=ProfileInviteRewardReview(scan:nil);XCTAssertEqual(r.ledgerState,.unavailable);XCTAssertNil(r.cumulativePoints)}
    func testPartialScanDoesNotClaimCumulativeTotal() throws {let r=ProfileInviteRewardReview(scan:try scan(ledger,total:201));XCTAssertEqual(r.ledgerState,.partial);XCTAssertNil(r.cumulativePoints)}
    func testPartialKnownMonthlySubtotalIsExplicitlyPartial() throws {let r=ProfileInviteRewardReview(scan:try scan(ledger,total:201));let m=r.month(members:[try member(201)]);XCTAssertTrue(m.isPartial);XCTAssertEqual(m.earnedPoints,Decimal(string:"2.5"))}
    func testContradictorySmallerLedgerTotalIsNotComplete() throws {let r=ProfileInviteRewardReview(scan:try scan(ledger,total:3));XCTAssertEqual(r.ledgerState,.invalid);XCTAssertNil(r.cumulativePoints);XCTAssertNil(r.month(members:[try member(201)]).earnedPoints)}
    func testMissingLedgerTotalIsPartial() throws {let r=ProfileInviteRewardReview(scan:try scan(ledger,total:nil));XCTAssertEqual(r.ledgerState,.partial);XCTAssertNil(r.cumulativePoints)}
    func testMonthWithoutRewardShowsLoadedPeopleNotInventedZeroPoints() throws {let r=ProfileInviteRewardReview(scan:try scan(ledger,total:4));let m=r.month(members:[try member(203)]);XCTAssertEqual(m.loadedMemberCount,1);XCTAssertFalse(m.displaysPoints)}
    func testUnavailableMonthStillCountsGenuineLoadedPeople() throws {let m=ProfileInviteRewardReview(scan:nil).month(members:[try member(201)]);XCTAssertEqual(m.loadedMemberCount,1);XCTAssertNil(m.earnedPoints);XCTAssertTrue(m.isPartial)}
    func testOtherEventsAndNegativeRewardsNeverContribute() throws {let rows = #"[{"eventType":6,"eventId":"201","changePoints":"99"},{"eventType":5,"eventId":"201","changePoints":"-3"}]"#;XCTAssertEqual(ProfileInviteRewardReview(scan:try scan(rows,total:2)).cumulativePoints,0)}
    func testDecimalSumPreservesFractionalValuesExactly() {XCTAssertEqual(ProfileInviteRewardReview.exactSum([Decimal(string:"0.1")!,Decimal(string:"0.2")!]),Decimal(string:"0.3"))}
    func testNaNAndNegativeArithmeticAreRejected() {XCTAssertNil(ProfileInviteRewardReview.exactSum([.nan]));XCTAssertNil(ProfileInviteRewardReview.exactSum([-1]))}
    func testOverflowDoesNotProduceDisplayableTotal() {
        let huge = NSDecimalNumber.maximum.decimalValue
        XCTAssertFalse(huge.isNaN)
        XCTAssertGreaterThan(huge, 0)
        var lhs = huge, rhs = huge, overflow = Decimal.zero
        XCTAssertEqual(NSDecimalAdd(&overflow, &lhs, &rhs, .plain), .overflow)
        XCTAssertNil(ProfileInviteRewardReview.exactSum([huge, huge]))
    }
    func testNewCompleteSnapshotReplacesPartialWithoutPersistentCache() throws {let a=ProfileInviteRewardReview(scan:try scan(ledger,total:201));let b=ProfileInviteRewardReview(scan:try scan(ledger,total:4));XCTAssertNil(a.cumulativePoints);XCTAssertEqual(b.cumulativePoints,11)}
}

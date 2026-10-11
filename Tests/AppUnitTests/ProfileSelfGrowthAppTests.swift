import XCTest
@testable import Questify

@MainActor final class ProfileSelfGrowthAppTests:XCTestCase {
    private func context(_ social:ProfileSelfGrowthFixturePublicReader,_ growth:ProfileSelfGrowthFixtureReader) throws->ProfileSelfGrowthContext {
        let access=ProfileSelfGrowthAccess(reader:growth,owner:social.identity)
        return try XCTUnwrap(ProfileSelfGrowthContext.capture(memberID:81,accountReader:social,growthReader:growth,owner:access.owner,ownerScope:access.scope,isCurrent:true))
    }
    func testNormalExistingReaderProvidesSixMetricProjection() async throws {
        let social=ProfileSelfGrowthFixturePublicReader(),growth=ProfileSelfGrowthFixtureReader()
        let scoped=ProfileSelfGrowthScopedReader(context:try context(social,growth),accountReader:social,growthReader:growth,isCurrent:{true})
        let result=try await scoped.overview(),summary=ProfileSelfGrowthSummary(result)
        XCTAssertEqual(summary.points,700);XCTAssertEqual(summary.checkins,12);XCTAssertEqual(summary.streakDays,2);XCTAssertEqual(summary.mileage,13.45)
    }
    func testCenterFailurePreservesKnownExplorationValues() async throws {
        let growth=ProfileSelfGrowthFixtureReader("partialCenter"),s=ProfileSelfGrowthSummary(try await growth.overview())
        XCTAssertNil(s.points);XCTAssertNotNil(s.centerIssue);XCTAssertEqual(s.checkins,12);XCTAssertNil(s.progressIssue)
    }
    func testProgressFailurePreservesKnownCenterValues() async throws {
        let growth=ProfileSelfGrowthFixtureReader("partialProgress"),s=ProfileSelfGrowthSummary(try await growth.overview())
        XCTAssertEqual(s.points,700);XCTAssertNil(s.checkins);XCTAssertNotNil(s.progressIssue)
    }
    func testZeroValuesAreReadableRecords() async throws {
        let growth=ProfileSelfGrowthFixtureReader("zero"),s=ProfileSelfGrowthSummary(try await growth.overview())
        XCTAssertEqual(s.points,0);XCTAssertEqual(s.checkins,0);XCTAssertEqual(s.mileage,0);XCTAssertNil(s.centerIssue)
    }
    func testExistingScreenModelFailureThenRetryUsesOnlyReads() async throws {
        let social=ProfileSelfGrowthFixturePublicReader(),growth=ProfileSelfGrowthFixtureReader("failure")
        let scoped=ProfileSelfGrowthScopedReader(context:try context(social,growth),accountReader:social,growthReader:growth,isCurrent:{true})
        let model=GrowthCenterScreenModel<GrowthCenterOverview>(),key=GrowthCenterLoadKey(scope:scoped.scope)
        await model.load(key:key,currentKey:{key},operation:{try await scoped.overview()});XCTAssertNotNil(model.issue(key:key));XCTAssertNil(model.value(key:key))
        await model.load(key:key,currentKey:{key},operation:{try await scoped.overview()});XCTAssertNil(model.issue(key:key));XCTAssertNotNil(model.value(key:key));XCTAssertEqual(growth.reads,2)
    }
    func testAccessCapturesOwnerAndScopeRatherThanFollowingReplacement() {
        let social=ProfileSelfGrowthFixturePublicReader(),growth=ProfileSelfGrowthFixtureReader(),access=ProfileSelfGrowthAccess(reader:ProfileSelfGrowthFixtureReader(),owner:.init(accountID:92,epoch:1))
        XCTAssertNil(ProfileSelfGrowthContext.capture(memberID:81,accountReader:social,growthReader:access.reader,owner:access.owner,ownerScope:access.scope,isCurrent:true))
        let owned=ProfileSelfGrowthAccess(reader:growth,owner:social.identity);growth.scope=UUID()
        XCTAssertNil(ProfileSelfGrowthContext.capture(memberID:81,accountReader:social,growthReader:growth,owner:owned.owner,ownerScope:owned.scope,isCurrent:true))
    }
    func testCenterAndLeaderboardBothRetireWithAccount() async throws {
        let social=ProfileSelfGrowthFixturePublicReader(),growth=ProfileSelfGrowthFixtureReader()
        let scoped=ProfileSelfGrowthScopedReader(context:try context(social,growth),accountReader:social,growthReader:growth,isCurrent:{true})
        social.presentationRevision += 1
        do {_ = try await scoped.overview();XCTFail()}catch{}
        do {_ = try await scoped.leaderboard(query:.init());XCTFail()}catch{}
        XCTAssertEqual(growth.reads,0);XCTAssertEqual(growth.boardReads,0)
    }
}

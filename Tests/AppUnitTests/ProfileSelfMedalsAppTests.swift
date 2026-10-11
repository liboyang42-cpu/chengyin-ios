import XCTest
@testable import Questify

@MainActor final class ProfileSelfMedalsAppTests: XCTestCase {
    func testOwnActualPublicAndPrivateReadersProduceMedalSectionState() async {
        let social=ProfileSelfMedalsFixturePublicReader(),reader=ProfileSelfMedalsFixtureReader(),model=ProfileSelfMedalsController()
        await model.load(memberID:81,accountReader:social,profileReader:reader)
        XCTAssertEqual(reader.reads,1);XCTAssertEqual(model.medals?.count,2);XCTAssertEqual(model.medals?.last?.isAchievement,true)
    }
    func testPartialThenRetryBecomesContentWithoutEmptyClaim() async {
        let social=ProfileSelfMedalsFixturePublicReader(),reader=ProfileSelfMedalsFixtureReader("partial"),model=ProfileSelfMedalsController()
        await model.load(memberID:81,accountReader:social,profileReader:reader);XCTAssertNil(model.medals);XCTAssertEqual(model.issue,.partial)
        await model.load(memberID:81,accountReader:social,profileReader:reader);XCTAssertEqual(model.medals?.count,2);XCTAssertNil(model.issue)
    }
    func testRefreshFailureKeepsRowsAndRetryClearsWarning() async {
        let social=ProfileSelfMedalsFixturePublicReader(),reader=ProfileSelfMedalsFixtureReader("refreshFailure"),model=ProfileSelfMedalsController()
        await model.load(memberID:81,accountReader:social,profileReader:reader);await model.load(memberID:81,accountReader:social,profileReader:reader)
        XCTAssertEqual(model.issue,.readFailed);XCTAssertEqual(model.medals?.count,2)
        await model.load(memberID:81,accountReader:social,profileReader:reader);XCTAssertNil(model.issue);XCTAssertEqual(reader.reads,3)
    }
    func testFreshEmptyClearsPreviouslyDisplayedMedals() async {
        let social=ProfileSelfMedalsFixturePublicReader(),reader=ProfileSelfMedalsFixtureReader("emptyRefresh"),model=ProfileSelfMedalsController()
        await model.load(memberID:81,accountReader:social,profileReader:reader);await model.load(memberID:81,accountReader:social,profileReader:reader);XCTAssertEqual(model.medals,[])
    }
    func testVisitorProfileDoesNotReadSignedInOwnersWall() async {
        let social=ProfileSelfMedalsFixturePublicReader(),reader=ProfileSelfMedalsFixtureReader(),model=ProfileSelfMedalsController()
        await model.load(memberID:92,accountReader:social,profileReader:reader);XCTAssertEqual(reader.reads,0);XCTAssertNil(model.context)
    }
    func testGuestDoesNotReadWall() async {
        let social=ProfileSelfMedalsFixturePublicReader(),reader=ProfileSelfMedalsFixtureReader(),model=ProfileSelfMedalsController()
        social.identity = .init(accountID:nil,epoch:1);await model.load(memberID:81,accountReader:social,profileReader:reader);XCTAssertEqual(reader.reads,0)
    }
    func testWallDestinationOwnerContextRetiresOnAccountChange() throws {
        let social=ProfileSelfMedalsFixturePublicReader(),reader=ProfileSelfMedalsFixtureReader()
        let context=try XCTUnwrap(ProfileSelfMedalsContext.capture(memberID:81,accountReader:social,profileReader:reader,isCurrent:true))
        reader.identity = .init(accountID:82,epoch:2)
        XCTAssertNotEqual(context,ProfileSelfMedalsContext.capture(memberID:81,accountReader:social,profileReader:reader,isCurrent:true))
    }
}

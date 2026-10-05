import XCTest
@testable import QuestifyCore

final class PlayKitLegacyTests: XCTestCase {
    private func wire(_ text: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self,from:Data(text.utf8)) }
    func testAllActiveLegacyKindsExist() {
        for kind in ["blindTaste","diyName","silentOrder","slowTask","musicCorner","timeWindow"] { XCTAssertNotNil(PlayKitScreenKind(rawValue:kind)) }
    }
    func testBlindTasteAcceptsOnlyPublishedOptionKeyAndAllowsRetryUntilSolved() throws {
        let source=try wire(#"{"options":[{"key":"a","label":"A"}],"solved":false,"attempts":3}"#)
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind:"blindTaste",action:"SUBMIT_BLIND_TASTE",payload:["key":.string("a")],segment:source))
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind:"blindTaste",action:"SUBMIT_BLIND_TASTE",payload:["key":.string("other")],segment:source))
        XCTAssertFalse(PlayKitScreenProjection(kind:.blindTaste,segment:source).complete)
    }
    func testSolvedBlindTasteCannotRepeatForMoreRewards() throws {
        let source=try wire(#"{"options":[{"key":"a","label":"A"}],"solved":true}"#)
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind:"blindTaste",action:"SUBMIT_BLIND_TASTE",payload:["key":.string("a")],segment:source))
    }
    func testDIYNameUsesNamePayloadAndBackendLengthUnit() throws {
        let source=try wire(#"{"maxLength":3}"#)
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind:"diyName",action:"SUBMIT_DIY_NAME",payload:["name":.string("ok")],segment:source))
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind:"diyName",action:"SUBMIT_DIY_NAME",payload:["name":.string("😀😀")],segment:source))
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind:"diyName",action:"SUBMIT_DIY_NAME",payload:["text":.string("ok")],segment:source))
    }
    func testSlowTaskStartAndClaimUseServerStateNotDeviceDate() throws {
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind:"slowTask",action:"START_SLOW_TASK",payload:[:],segment:wire(#"{"started":false,"daysLeft":1}"#)))
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind:"slowTask",action:"CLAIM_SLOW_TASK",payload:[:],segment:wire(#"{"started":true,"daysLeft":1}"#)))
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind:"slowTask",action:"CLAIM_SLOW_TASK",payload:[:],segment:wire(#"{"started":true,"daysLeft":0}"#)))
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind:"slowTask",action:"CLAIM_SLOW_TASK",payload:["daysLeft":.int(0)],segment:wire(#"{"started":true,"daysLeft":0}"#)))
    }
    func testMissingWaitStateAndAlreadyClaimedRemainBlocked() throws {
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind:"slowTask",action:"CLAIM_SLOW_TASK",payload:[:],segment:wire(#"{"started":true}"#)))
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind:"slowTask",action:"CLAIM_SLOW_TASK",payload:[:],segment:wire(#"{"started":true,"daysLeft":0,"claimed":true}"#)))
    }
    func testMusicSilentAndWindowNeverInventCompletionOrSubscriptionActions() throws {
        for kind in ["musicCorner","silentOrder","timeWindow"] {
            XCTAssertEqual(PlayKitActionCatalog.actions[kind],[])
            XCTAssertThrowsError(try PlayKitActionCatalog.payload(kind:kind,action:"COMPLETE",detail:[:]))
            XCTAssertFalse(PlayKitScreenProjection(kind:PlayKitScreenKind(rawValue:kind)!,segment:try wire("{}")).complete)
        }
    }
    func testUTF16LimiterKeepsWholeGraphemes() {
        XCTAssertEqual(PlayKitInputContract.limitText("a😀b",toUTF16:3),"a😀")
        XCTAssertEqual(PlayKitInputContract.limitText("a😀b",toUTF16:2),"a")
        XCTAssertEqual(PlayKitInputContract.limitText("abc",toUTF16:0),"")
    }
}

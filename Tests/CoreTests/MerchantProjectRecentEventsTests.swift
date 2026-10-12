import XCTest
@testable import QuestifyCore

final class MerchantProjectRecentEventsTests: XCTestCase {
    private func project(_ kind: String = "topic", id: Int = 7) throws -> MerchantProject {
        try JSONDecoder().decode(MerchantProject.self, from: Data("{\"id\":\(id),\"bizType\":\"\(kind)\"}".utf8))
    }
    private func event(_ ownership: String = "") throws -> MerchantEvent {
        try JSONDecoder().decode(MerchantEvent.self, from: Data(("{\"content\":\"exact  text\",\"time\":\"10-12 08:01\"" + ownership + "}").utf8))
    }
    func testTopicKey() throws { let key = try XCTUnwrap(MerchantProjectEventKey(project: project())); XCTAssertEqual(key.ownerType,"1"); XCTAssertEqual(key.ownerID,"7") }
    func testActivityKey() throws { XCTAssertEqual(try XCTUnwrap(MerchantProjectEventKey(project: project("activity"))).ownerType,"2") }
    func testUnknownTypeHasNoFallback() throws { for kind in ["unknown","TOPIC","", " topic "] { XCTAssertNil(try MerchantProjectEventKey(project: project(kind))) } }
    func testNumericMetadata() throws { let e = try event(",\"ownerType\":1,\"ownerId\":7"); XCTAssertTrue(try XCTUnwrap(MerchantProjectEventKey(project: project())).matches(e)) }
    func testStringMetadata() throws { let e = try event(",\"ownerType\":\"1\",\"ownerId\":\"7\""); XCTAssertTrue(try XCTUnwrap(MerchantProjectEventKey(project: project())).matches(e)) }
    func testSameIDOtherKindExcluded() throws { let e = try event(",\"ownerType\":2,\"ownerId\":7"); XCTAssertFalse(try XCTUnwrap(MerchantProjectEventKey(project: project())).matches(e)) }
    func testSameKindOtherIDExcluded() throws { let e = try event(",\"ownerType\":1,\"ownerId\":8"); XCTAssertFalse(try XCTUnwrap(MerchantProjectEventKey(project: project())).matches(e)) }
    func testMissingMetadataBackwardCompatible() throws { let e = try event(); XCTAssertEqual(e.content,"exact  text"); XCTAssertNil(e.projectOwnerID); XCTAssertFalse(try XCTUnwrap(MerchantProjectEventKey(project: project())).matches(e)) }
    func testMalformedMetadataDoesNotBreakLegacyEvent() throws { for raw in ["true","null","{}","[]","1.2"] { let e = try event(",\"ownerType\":"+raw+",\"ownerId\":7"); XCTAssertNil(e.projectOwnerType) } }
    func testNoncanonicalStringNotNormalized() throws { for raw in ["07"," 7","7 ","7.0"] { let e = try event(",\"ownerType\":1,\"ownerId\":\""+raw+"\""); XCTAssertFalse(try XCTUnwrap(MerchantProjectEventKey(project: project())).matches(e)) } }
    func testOrderAndDuplicatesPreserved() throws { let e = try event(",\"ownerType\":1,\"ownerId\":7"); let other = try event(",\"ownerType\":2,\"ownerId\":7"); XCTAssertEqual(try XCTUnwrap(MerchantProjectEventKey(project: project())).recentEvents(in:[e,other,e]),[e,e]) }
    func testLegacyInitializerPreserved() { let e = MerchantEvent(content:"x",time:"server"); XCTAssertEqual(e.time,"server"); XCTAssertNil(e.projectOwnerType) }
    func testUnsafeMiniIDRejected() throws { XCTAssertNil(try MerchantProjectEventKey(project: project(id:9_007_199_254_740_992))) }
    func testEmptyWindow() throws { XCTAssertEqual(try XCTUnwrap(MerchantProjectEventKey(project: project())).recentEvents(in:[]),[]) }
}

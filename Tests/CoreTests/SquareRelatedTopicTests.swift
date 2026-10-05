import XCTest
@testable import QuestifyCore

final class SquareRelatedTopicTests: XCTestCase {
    private func post(_ json: String, generation: SquareContentGeneration = .legacySquare) throws -> SquarePost {
        try JSONDecoder().decode(SquarePost.self, from: Data(json.utf8)).qualified(as: generation)
    }
    private func route(_ json: String, generation: SquareContentGeneration = .legacySquare) throws -> SquareRelatedTopicRoute? {
        let value = try post(json, generation: generation)
        return SquareRelatedTopicRoute(post: value, source: .init(id: value.id, generation: generation))
    }
    func testLegacyAssociationUsesExactPositiveTopicRatherThanPostID() throws {
        let result = try XCTUnwrap(route(#"{"id":701,"sportTopicId":"31","dataId":999,"dataType":1}"#))
        XCTAssertEqual(result.topicID, 31)
        XCTAssertEqual(result.source, .init(id: 701, generation: .legacySquare))
    }
    func testCommunityAssociationUsesOnlyExplicitTopicReference() throws {
        let result = try XCTUnwrap(route(#"{"post":{"id":701},"sportTopicId":88,"references":[{"reference_type":"TOPIC","reference_id":"32"}]}"#, generation: .communityV1))
        XCTAssertEqual(result.topicID, 32)
        XCTAssertEqual(result.source.generation, .communityV1)
    }
    func testEqualNumericPostIDsNeverCrossGenerations() throws {
        let json = #"{"id":701,"sportTopicId":31,"references":[{"referenceType":"TOPIC","referenceId":32}]}"#
        XCTAssertEqual(try route(json)?.topicID, 31)
        XCTAssertEqual(try route(json, generation: .communityV1)?.topicID, 32)
        let legacy = try post(json)
        XCTAssertNil(SquareRelatedTopicRoute(post: legacy, source: .init(id: 701, generation: .communityV1)))
    }
    func testUnknownOrMismatchedSourceCannotNavigate() throws {
        let value = try post(#"{"id":701,"sportTopicId":31}"#)
        XCTAssertNil(SquareRelatedTopicRoute(post: value, source: .init(id: 702, generation: .legacySquare)))
        XCTAssertNil(SquareRelatedTopicRoute(post: value, source: .init(id: 0, generation: .legacySquare)))
        XCTAssertNil(SquareRelatedTopicRoute(post: value, source: .init(id: 701, generation: .unknown)))
        XCTAssertNil(try route(#"{"id":701,"sportTopicId":31}"#, generation: .unknown))
    }
    func testLegacyCannotBorrowCommunityReferenceAndCommunityCannotBorrowLegacyID() throws {
        XCTAssertNil(try route(#"{"id":701,"references":[{"referenceType":"TOPIC","referenceId":32}]}"#))
        XCTAssertNil(try route(#"{"post":{"id":701},"sportTopicId":31}"#, generation: .communityV1))
    }
    func testInvalidAssociationIDsStayAbsentInsteadOfBeingTruncated() throws {
        for raw in ["null", "0", "-3", "true", "false", "31.5", "[]", "{}", #""31.5""#, #""1e2""#, #""+31""#, #""""#, #""999999999999999999999999999999""#] {
            XCTAssertNil(try route("{\"id\":701,\"sportTopicId\":\(raw)}"), raw)
            XCTAssertNil(try route("{\"post\":{\"id\":701},\"references\":[{\"referenceType\":\"TOPIC\",\"referenceId\":\(raw)}]}", generation: .communityV1), raw)
        }
    }
    func testActivityRouteAndUnknownReferencesNeverBecomeTopicDestinations() throws {
        for type in ["ACTIVITY", "ROUTE", "topic", "", "UNKNOWN"] {
            let json = "{\"post\":{\"id\":701,\"dataId\":31,\"dataType\":2},\"references\":[{\"referenceType\":\"\(type)\",\"referenceId\":32}]}"
            XCTAssertNil(try route(json, generation: .communityV1), type)
        }
        XCTAssertNil(try route(#"{"id":701,"dataId":31,"dataType":2,"sportName":"A named association"}"#))
    }
    func testOnlyTheDisplayedFirstReferenceIsNavigable() throws {
        let json = #"{"post":{"id":701},"references":[{"referenceType":"ACTIVITY","referenceId":88},{"referenceType":"TOPIC","referenceId":32}]}"#
        XCTAssertNil(try route(json, generation: .communityV1))
    }
    func testBothReadScopesFenceASelectedAssociation() throws {
        let related = try XCTUnwrap(route(#"{"id":701,"sportTopicId":31}"#))
        let square = UUID(), topic = UUID()
        let selection = SquareRelatedTopicSelection(route: related, squareScope: square, topicScope: topic)
        XCTAssertTrue(selection.isCurrent(squareScope: square, topicScope: topic))
        XCTAssertFalse(selection.isCurrent(squareScope: UUID(), topicScope: topic))
        XCTAssertFalse(selection.isCurrent(squareScope: square, topicScope: UUID()))
        XCTAssertFalse(selection.isCurrent(squareScope: UUID(), topicScope: UUID()))
        XCTAssertEqual(selection.route.topicID, 31)
    }
}

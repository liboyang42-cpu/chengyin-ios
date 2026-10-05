import XCTest
@testable import QuestifyCore

final class RoamContractTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    func testCoordinateRejectsNonFiniteAndOutOfRangeButNotRealZero() {
        XCTAssertNil(RoamCoordinate(latitude: .nan, longitude: 1))
        XCTAssertNil(RoamCoordinate(latitude: 0, longitude: .infinity))
        XCTAssertNil(RoamCoordinate(latitude: 91, longitude: 1))
        XCTAssertNil(RoamCoordinate(latitude: 1, longitude: -181))
        XCTAssertNotNil(RoamCoordinate(latitude: 0, longitude: 0))
    }
    func testPlaceDecimalStringsAndMissingCoordinatesNeverProducePhantomOrigin() throws {
        let place = try decode(RoamPlace.self, #"{"id":1,"name":"Place","lat":"31.23","lng":"121.47","type":2}"#)
        XCTAssertEqual(place.coordinate, RoamCoordinate(latitude: 31.23, longitude: 121.47))
        XCTAssertTrue(RoamPlaceFilter.merchant.includes(place))
        XCTAssertFalse(RoamPlaceFilter.city.includes(place))
        for json in [#"{"id":1}"#, #"{"id":1,"lat":null,"lng":2}"#, #"{"id":1,"lat":"bad","lng":2}"#, #"{"id":1,"lat":999,"lng":2}"#] {
            XCTAssertNil(try decode(RoamPlace.self, json).coordinate)
        }
        XCTAssertFalse(try decode(RoamPlace.self, #"{"id":1,"type":99}"#).isSupported)
    }
    func testRouteNodesKeepDistinctIDsAndOptionalUnknownDistance() throws {
        let route = try decode(RoamRouteNode.self, #"{"id":7,"nodeId":8,"topicId":9,"addressName":"Route","latitude":"1","longitude":"2"}"#)
        let place = try decode(RoamPlace.self, #"{"id":7,"lat":1,"lng":2}"#)
        XCTAssertEqual(route.nodeId, 8); XCTAssertEqual(route.topicId, 9)
        XCTAssertNil(route.distance)
        XCTAssertNotEqual(RoamMapItem.route(route).id, RoamMapItem.place(place).id)
        XCTAssertEqual(RoamMapItem.unique([.route(route), .place(place), .route(route)]).count, 2)
    }
    func testEventsDropRetiredHangoutsUnknownKindsAndInvalidIDsWithoutLosingTopics() throws {
        let events = try decode(RoamEvents.self, #"{"items":[{"id":1,"kind":"hangout","name":"retired"},{"id":2,"kind":"other"},{"id":0,"kind":"activity"},{"id":7,"kind":"activity","name":"Event","lat":"1","lng":"2"},{"id":7,"kind":"topic","name":"Theme","latitude":3,"longitude":4}],"suggestedRadius":5000,"suggestedCount":2}"#)
        XCTAssertEqual(events.items.map(\.id), ["activity-7", "topic-7"])
        XCTAssertEqual(events.items.first?.coordinate, RoamCoordinate(latitude: 1, longitude: 2))
        XCTAssertEqual(events.suggestedRadius, 5000)
        XCTAssertEqual(try decode(RoamEvents.self, #"{"items":null}"#).items, [])
    }
    func testEventCoordinateFallbackUsesNullRatherThanMalformedPrimary() throws {
        let nullable = try decode(RoamEvent.self, #"{"id":1,"kind":"topic","latitude":null,"longitude":null,"lat":1,"lng":2}"#)
        XCTAssertNotNil(nullable.coordinate)
        let malformed = try decode(RoamEvent.self, #"{"id":1,"kind":"topic","latitude":"bad","longitude":2,"lat":1,"lng":2}"#)
        XCTAssertNil(malformed.coordinate)
    }
    func testRunnerCoordinatePrivacyAndLimits() throws {
        let player = try decode(RoamPlayer.self, #"{"memberId":1,"nickname":"Walker","lat":"-1.234567","lng":2.987654,"explorePct":120,"shops":-1,"elapsedSec":-20,"realName":"Not retained","phone":"Not retained","conversationId":999}"#)
        XCTAssertEqual(player.approximateCoordinate, RoamCoordinate(latitude: -1.234, longitude: 2.987))
        XCTAssertEqual(player.explorePct, 99); XCTAssertEqual(player.shops, 0); XCTAssertEqual(player.elapsedSec, 0)
        XCTAssertTrue(player.isDisplayable)
        let coarse = try decode(RoamPlayer.self, #"{"memberId":1,"lat":1.001,"lng":-1.001}"#)
        XCTAssertEqual(coarse.approximateCoordinate, RoamCoordinate(latitude: 1.001, longitude: -1.001))
        let labels = Set(Mirror(reflecting: player).children.compactMap(\.label))
        XCTAssertFalse(labels.contains("realName")); XCTAssertFalse(labels.contains("phone")); XCTAssertFalse(labels.contains("conversationId"))
        XCTAssertFalse(try decode(RoamPlayer.self, #"{"memberId":1,"nickname":"No location"}"#).isDisplayable)
        XCTAssertFalse(try decode(RoamPlayer.self, #"{"memberId":0,"lat":1,"lng":2}"#).isDisplayable)
    }
    func testNodeStatusOneOnlyPublishedAndFlagsAreStrictBooleans() throws {
        for status in ["null", "0", "2", "99"] {
            let node = try decode(RoamNodeDetail.self, "{\"poiId\":1,\"status\":\(status),\"completed\":1,\"favorited\":\"true\"}")
            XCTAssertFalse(node.isPublished); XCTAssertFalse(node.completed); XCTAssertFalse(node.favorited)
        }
        let published = try decode(RoamNodeDetail.self, #"{"poiId":1,"status":1,"completed":true,"favorited":true}"#)
        XCTAssertTrue(published.isPublished); XCTAssertTrue(published.completed); XCTAssertTrue(published.favorited)
        XCTAssertThrowsError(try decode(RoamNodeDetail.self, "{}"))
        XCTAssertThrowsError(try decode(RoamNodeDetail.self, #"{"poiId":0}"#))
    }
    func testExploreDayRequiresIdentityAndNamePreservesUnknownDistance() throws {
        let event = try decode(RoamExploreDay.self, #"{"activityId":"4","title":" Day "}"#)
        XCTAssertTrue(event.isDisplayable); XCTAssertEqual(event.title, "Day"); XCTAssertNil(event.distanceM)
        XCTAssertFalse(try decode(RoamExploreDay.self, #"{"activityId":4,"title":" "}"#).isDisplayable)
        XCTAssertFalse(try decode(RoamExploreDay.self, #"{"activityId":0,"title":"Day"}"#).isDisplayable)
        XCTAssertFalse(try decode(RoamExploreDay.self, #"{"activityId":4.5,"title":"Day"}"#).isDisplayable)
    }
    func testMerchantFeaturedIsTopLevelAndSensitiveFieldsAreNotRetained() throws {
        let detail = try decode(RoamMerchantDetail.self, #"{"data":{"id":8,"name":"Public shop","tags":"[\"One\",3,\"Two\"]","capacity":"20","memberId":999,"phone":"Secret","featured":{"name":"Wrong nested item"}},"featured":{"name":"Top level","featuredType":"1","featuredId":"7"}}"#)
        XCTAssertEqual(detail.merchant.tags, ["One", "Two"])
        XCTAssertEqual(detail.merchant.capacity, 20)
        XCTAssertEqual(detail.featured?.name, "Top level")
        XCTAssertNil(detail.featured?.featuredType)
        XCTAssertEqual(detail.featured?.featuredId, 7)
        let labels = Set(Mirror(reflecting: detail.merchant).children.compactMap(\.label))
        XCTAssertFalse(labels.contains("memberId")); XCTAssertFalse(labels.contains("phone"))
        let nested = try decode(RoamMerchantDetail.self, #"{"data":{"id":8,"tags":"bad","featured":{"name":"Wrong"}}}"#)
        XCTAssertNil(nested.featured); XCTAssertTrue(nested.merchant.tags.isEmpty)
        XCTAssertNil(nested.merchant.businessStatus)
    }
}

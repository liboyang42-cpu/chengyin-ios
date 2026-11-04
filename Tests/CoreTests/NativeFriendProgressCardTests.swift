import XCTest
@testable import QuestifyCore

@MainActor private final class NativeFriendProgressFakeIndex: NativeFriendProgressIndexProviding {
    var authority: NativeFriendProgressAuthority?
    var projection: NativeFriendProgressProjection = .unconfirmed
    var beforeReturn: (() -> Void)?
    var retired = false
    init() throws { authority = try .init(identity: NativeChannelProgressFixtures.identity(), friendID: 202, relationshipVersion: "relation-v1", authorizationVersion: "projection-v1") }
    func friendProgressIndex() async throws -> NativeFriendProgressProjection { beforeReturn?(); return projection }
    func retireOperations() { retired = true }
}
final class NativeFriendProgressCardTests: XCTestCase {
    @MainActor func testMissingTrueFriendIndexIsExplicitlyUnclosed() async {
        let card = NativeFriendProgressCard(source: nil); await card.activate()
        XCTAssertEqual(card.state, .awaitingIndex)
        card.invalidate(); XCTAssertEqual(card.state, .closed)
    }
    @MainActor func testHiddenUnknownAndVisibleEmptyAreDistinct() async throws {
        let source = try NativeFriendProgressFakeIndex(), card = NativeFriendProgressCard(source: source)
        await card.activate(); XCTAssertEqual(card.state, .unconfirmed)
        source.projection = .hidden; await card.activate(); XCTAssertEqual(card.state, .hidden)
        source.projection = .visible([]); await card.activate(); XCTAssertEqual(card.state, .visible([]))
        source.authority = nil; XCTAssertEqual(card.state, .closed)
    }
    @MainActor func testRelationshipRevocationDiscardsLateProjection() async throws {
        let source = try NativeFriendProgressFakeIndex(), card = NativeFriendProgressCard(source: source)
        source.projection = .visible([]); source.beforeReturn = { source.authority = nil }
        await card.activate(); XCTAssertEqual(card.state, .closed)
        card.invalidate(); XCTAssertTrue(source.retired)
    }
    @MainActor func testOtherSubjectProjectionCannotEnterFriendCard() async throws {
        let source = try NativeFriendProgressFakeIndex(), card = NativeFriendProgressCard(source: source)
        let meter: NativeChannelProgressMeter = try NativeChannelProgressFixtures.decode(#"{"visible":true,"subject_id":999,"topic_id":17,"activity_id":23,"required":10,"done":5,"percent":50,"revision":"facts-1"}"#)
        source.projection = .visible([try .init(id: "topic17-activity23", title: "Original indexed topic", topicID: 17, activityID: 23, meter: meter)])
        await card.activate(); XCTAssertEqual(card.state, .unconfirmed)
    }
}

import XCTest
@testable import QuestifyCore

final class SquareJourneyIntegrationTests: XCTestCase {
    private func nodes(_ extra: String) throws -> PlayNodesResult {
        try JSONDecoder().decode(PlayNodesResult.self, from: Data("{\"nodes\":[{\"nodeId\":7}],\"topicId\":4,\"chapters\":[{\"chapterId\":1,\"audioUrl\":\"https://example.invalid/chapter.mp3\"}]\(extra)}".utf8))
    }
    func testMissingEggsPreserveMainNodeAndChapterAudio() throws {
        let result = try nodes("")
        XCTAssertTrue(result.eggs.isEmpty); XCTAssertEqual(result.nodes.first?.id, 7)
        XCTAssertEqual(result.chapters.first?.audioURL, "https://example.invalid/chapter.mp3")
    }
    func testMalformedAmbientPayloadDoesNotInvalidateNodes() throws {
        let result = try nodes(",\"eggs\":{\"bad\":true}")
        XCTAssertTrue(result.eggs.isEmpty); XCTAssertEqual(result.topicID, 4)
        XCTAssertEqual(result.nodes.count, 1)
    }
    func testNullAmbientPayloadPreservesChapters() throws {
        let result = try nodes(",\"eggs\":null")
        XCTAssertTrue(result.eggs.isEmpty); XCTAssertEqual(result.chapters.count, 1)
    }
    func testWorkspaceEpochFencesWithoutChangingPrivateOwnerKey() throws {
        let first = try SquareWorkspaceSession(accountID: 4, namespace: "CN.test", epoch: 1)
        let next = try SquareWorkspaceSession(accountID: 4, namespace: "CN.test", epoch: 2)
        let other = try SquareWorkspaceSession(accountID: 5, namespace: "CN.test", epoch: 2)
        XCTAssertNotEqual(first, next); XCTAssertEqual(first.ownerKey, next.ownerKey)
        XCTAssertNotEqual(next.ownerKey, other.ownerKey)
    }
    func testWorkspaceAndNPCGrantsRemainOff() {
        let workspace = SquareWorkspaceGrants(), npc = ShopNPCGrants()
        XCTAssertFalse(workspace.live); XCTAssertFalse(workspace.media); XCTAssertFalse(workspace.legal)
        XCTAssertFalse(npc.textAllowed); XCTAssertFalse(npc.voiceAllowed); XCTAssertFalse(npc.microphone)
    }
}

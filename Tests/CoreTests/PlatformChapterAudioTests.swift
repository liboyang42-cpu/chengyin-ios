import XCTest
@testable import QuestifyCore

final class PlatformChapterAudioTests: XCTestCase {
    private func snapshot(locked: Bool = false, playable: Bool = true, registered: Bool = true, hidden: Bool = false, chapterID: Int = 7) throws -> (PlaySnapshot, [Int: PlayNodeExtras]) {
        let raw = """
        {"topicId":10,"playable":\(playable),"registered":\(registered),"nodes":[{"nodeId":1,"chapterId":\(chapterID),"locked":\(locked),"routeNodeState":"\(hidden ? "HIDDEN" : "PLAYABLE")","audioUrl":"https://media.example.test/guide.mp3"}],"chapters":[{"chapterId":7,"name":"Chapter","audioUrl":"https://media.example.test/narration.mp3"}]}
        """
        let document = try JSONDecoder().decode(PlayExperienceDocument.self, from: Data(raw.utf8))
        return (try PlaySnapshot(scope: .topic(10), result: document.base), document.extras)
    }
    func testSameReadDecodesDistinctNarrationAndGuide() throws {
        let (snapshot, extras) = try snapshot()
        let selection = PlatformChapterAudioSelection.resolve(snapshot: snapshot, nodeID: 1, extras: extras, currentRead: true)
        XCTAssertEqual(selection?.chapterID, 7)
        XCTAssertEqual(selection?.narrationURL, "https://media.example.test/narration.mp3")
        XCTAssertEqual(selection?.guideURL, "https://media.example.test/guide.mp3")
    }
    func testLockVisibilitySessionAndIdentityMustAllMatch() throws {
        let variants = [try snapshot(locked: true), try snapshot(playable: false), try snapshot(registered: false), try snapshot(hidden: true), try snapshot(chapterID: 8)]
        for (snapshot, extras) in variants {
            XCTAssertNil(PlatformChapterAudioSelection.resolve(snapshot: snapshot, nodeID: 1, extras: extras, currentRead: true))
        }
        let (snapshot, extras) = try snapshot()
        XCTAssertNil(PlatformChapterAudioSelection.resolve(snapshot: snapshot, nodeID: 1, extras: extras, currentRead: false))
        XCTAssertNil(PlatformChapterAudioSelection.resolve(snapshot: snapshot, nodeID: 999, extras: extras, currentRead: true))
    }
    func testOldChapterWithoutAudioStillDecodes() throws {
        let chapter = try JSONDecoder().decode(PlayChapter.self, from: Data("{\"chapterId\":7,\"name\":\"Old\"}".utf8))
        XCTAssertNil(chapter.audioURL)
    }
}

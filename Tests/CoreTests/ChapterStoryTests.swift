import XCTest
@testable import QuestifyCore

final class ChapterStoryTests: XCTestCase {
    func testVariablesUseBoundedSourceGrammarFallbackAndLeaveMissingVisible() {
        let variables: [String: PlayWireValue] = ["name": .string("Ada"), "count": .integer(0), "yes": .bool(false), "empty": .string("")]
        XCTAssertEqual(ChapterStoryProjection.substitute("{name} {count} {yes} {lost} {lost|friend} {empty|} {name_too_long_123456}", variables: variables),
                       "Ada 0 false {lost} friend {empty|} {name_too_long_123456}")
        XCTAssertEqual(ChapterStoryProjection.substitute("{object|safe}", variables: ["object": .object(["private": .string("hidden")])]), "safe")
    }
    func testChapterCoverComesFromActualImgArrAndPreservesBlocks() throws {
        let chapter = try ChapterStoryDocument(raw: wire(#"{"chapterId":8,"name":"A chapter","imgArr":"https://story.test/first.jpg,https://story.test/second.jpg","blocks":[{"type":"text","content":"Hello"}]}"#))
        XCTAssertEqual(chapter.cover, "https://story.test/first.jpg"); XCTAssertEqual(chapter.title, "A chapter"); XCTAssertEqual(chapter.blocks.count, 1)
    }
    func testIncompleteNodeTruncatesFutureBodyAndInsertsActualGame() throws {
        let snapshot = try snapshot(nodes: #"[{"nodeId":1,"chapterId":8,"done":false,"locked":false}]"#)
        let chapter = try ChapterStoryDocument(raw: wire(#"{"chapterId":8,"description":"Projected duplicate","blocks":[{"type":"text","content":"Before {name}"},{"type":"node","nodeId":1},{"type":"text","content":"SPOILER"}]}"#))
        let rows = ChapterStoryProjection.segments(chapter: chapter, snapshot: snapshot, variables: ["name": .string("Ada")])
        XCTAssertEqual(rows.map(\.content), [.text("Before Ada"), .game(nodeID: 1)])
    }
    func testUnknownLockedAndCrossChapterNodeStopWithoutSpoilers() throws {
        for nodes in [#"[]"#, #"[{"nodeId":1,"chapterId":8,"done":false,"locked":true}]"#, #"[{"nodeId":1,"chapterId":9,"done":true}]"#] {
            let chapter = try ChapterStoryDocument(raw: wire(#"{"chapterId":8,"blocks":[{"type":"text","content":"Safe"},{"type":"node","nodeId":1},{"type":"text","content":"SPOILER"}]}"#))
            let rows = ChapterStoryProjection.segments(chapter: chapter, snapshot: try snapshot(nodes: nodes), variables: [:])
            XCTAssertEqual(rows.map(\.content), [.text("Safe")])
        }
    }
    func testCompletedNodeAddsEarnedNotesAndKnownThoughtsOnly() throws {
        let snapshot = try snapshot(nodes: #"[{"nodeId":1,"chapterId":8,"done":true,"storyText":"Earned note"}]"#)
        let chapter = try ChapterStoryDocument(raw: wire(#"{"chapterId":8,"blocks":[{"type":"node","nodeId":1},{"type":"thought","thoughtKey":"unknown"},{"type":"thought","thoughtKey":"known"},{"type":"text","content":"After"}]}"#))
        let rows = ChapterStoryProjection.segments(chapter: chapter, snapshot: snapshot, variables: [:], thoughts: [try wire(#"{"key":"known","name":"Earned thought","desc":"Description"}"#)])
        XCTAssertEqual(rows.map(\.content), [.text("Earned note"), .thought(name: "Earned thought", description: "Description"), .text("After")])
    }
    func testLegacyChapterDoesNotDuplicateDescriptionAndRendersCurrentGame() throws {
        let snapshot = try snapshot(nodes: #"[{"nodeId":1,"chapterId":8,"done":true,"storyText":"Earned note"},{"nodeId":2,"chapterId":8,"done":false}]"#)
        let chapter = try ChapterStoryDocument(raw: wire(#"{"chapterId":8,"description":"A\nB"}"#))
        XCTAssertEqual(ChapterStoryProjection.segments(chapter: chapter, snapshot: snapshot, variables: [:]).map(\.content), [.text("A"), .text("B"), .text("Earned note"), .game(nodeID: 2)])
    }
    func testMixedFlowPreservesImageAudioDreamRevealMoodAndOdd() throws {
        let chapter = try ChapterStoryDocument(raw: wire(#"{"chapterId":8,"blocks":[{"type":"mood","mood":"quiet"},{"type":"odd","level":9},{"type":"image","url":"https://story.test/a"},{"type":"audio","url":"https://story.test/b"},{"type":"reveal","who":"Guide","content":"A\nB"},{"type":"dream","title":"Album","images":[{"url":"https://story.test/c","line":"{name|Friend}"}]}]}"#))
        let rows = ChapterStoryProjection.segments(chapter: chapter, snapshot: try snapshot(nodes: "[]"), variables: [:])
        XCTAssertEqual(rows.count, 4); XCTAssertTrue(rows.allSatisfy { $0.mood == "quiet" && $0.odd == 3 })
        XCTAssertEqual(rows[2].content, .reveal(speaker: "Guide", lines: ["A", "B"]))
    }
    func testAuthorizedRuntimeDocumentCarriesVarsVoicesAndThoughts() throws {
        let document: PlayExperienceDocument = try wire(#"{"topicId":9,"playable":true,"nodes":[],"chapters":[{"chapterId":8,"name":"Chapter"}],"vars":{"name":"Ada"},"storyVoices":{"1":[{"who":"Guide","text":"Remember"}]},"routeState":{"thoughts":[{"key":"known","name":"Thought"}]}}"#).decoded()
        XCTAssertEqual(document.storyVariables["name"], .string("Ada")); XCTAssertNotNil(document.chapterStories[8]); XCTAssertEqual(document.storyThoughts.count, 1)
    }
    private func wire(_ source: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(source.utf8)) }
    private func snapshot(nodes: String) throws -> PlaySnapshot {
        let data = "{\"topicId\":9,\"mode\":1,\"playable\":true,\"registered\":true,\"nodes\":\(nodes),\"chapters\":[{\"chapterId\":8,\"name\":\"Chapter\"}]}"
        return try PlaySnapshot(scope: .topic(9), result: wire(data).decoded())
    }
}

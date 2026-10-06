import XCTest
@testable import QuestifyCore

final class ProjectEditPreparedNodesTests: XCTestCase {
    func testReadbackFollowsCapturedSerializedStoryOrderInsteadOfDraftNodeArray() throws {
        var draft = ProjectEditSyntheticFixtures.draft(), second = draft.chapters[0].nodes[0]
        second.id = "second"; second.name = "Second node"; second.description = "Second description"; second.imgUrl = "fixture:second"; second.nodeTime = 45
        let first = draft.chapters[0].nodes[0]
        draft.chapters[0].nodes.append(second)
        draft.chapters[0].blocks = [.init(kind: .text, content: "Real story"), .init(kind: .node, nodeID: second.id), .init(kind: .node, nodeID: first.id)]
        let payload = try ProjectEditContract.payload(draft, topicID: nil, scope: .full), readback = ProjectEditPreparedNodes(payload: payload)
        let nodes = try XCTUnwrap(readback.chapters?.first?.nodes)
        XCTAssertEqual(nodes.map { $0.value(.name).text }, ["Second node", first.name])
        XCTAssertEqual(nodes.map { $0.value(.sortID).text }, ["1", "2"])
        XCTAssertEqual(nodes[0].value(.description).text, "Second description"); XCTAssertEqual(nodes[0].value(.imgUrl).text, "fixture:second")
        XCTAssertEqual(nodes[0].value(.nodeTime).text, "45"); XCTAssertEqual(nodes[0].value(.templateId).text, "41")
        draft.chapters[0].nodes.reverse(); draft.chapters[0].nodes[0].description = "Later draft"
        XCTAssertEqual(readback.chapters?.first?.nodes?[0].value(.description).text, "Second description")
    }
    func testOmittedEmptyNullAndUnsupportedValuesRemainDistinct() throws {
        let payload: [String: ProjectEditJSON] = ["chapters": .array([.object(["name": .string("C"), "nodes": .array([.object(["name": .string("N"), "description": .string(""), "imgUrl": .null, "nodeTime": .number(0)])])])])]
        let node = try XCTUnwrap(ProjectEditPreparedNodes(payload: payload).chapters?.first?.nodes?.first)
        XCTAssertEqual(node.value(.description).raw, .string("")); XCTAssertEqual(node.value(.description).text, "")
        XCTAssertEqual(node.value(.imgUrl).raw, .null); XCTAssertEqual(node.value(.imgUrl).text, "null")
        XCTAssertNil(node.value(.templateId).raw); XCTAssertNil(node.value(.templateId).text)
        XCTAssertEqual(node.value(.nodeTime).text, "0")
        let bad = ProjectEditPreparedNodes.Value(.number(.nan)); XCTAssertNotNil(bad.raw); XCTAssertNil(bad.text)
    }
    func testWhitelistChapterOmissionDoesNotInventAnEmptyReplacement() throws {
        let payload = try ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(), topicID: 71, scope: .whitelist)
        let omitted = ProjectEditPreparedNodes(payload: payload), empty = ProjectEditPreparedNodes(payload: ["chapters": .array([])])
        XCTAssertTrue(omitted.omitted); XCTAssertNil(omitted.chapters)
        XCTAssertFalse(empty.omitted); XCTAssertEqual(empty.chapters?.count, 0)
    }
    func testMalformedStructureIsNotCoercedIntoSupportedEmptyFields() throws {
        XCTAssertNil(ProjectEditPreparedNodes(payload: ["chapters": .string("future")]).chapters)
        let chapter = try XCTUnwrap(ProjectEditPreparedNodes(payload: ["chapters": .array([.null])]).chapters?.first)
        XCTAssertFalse(chapter.isObject)
        let invalid = try XCTUnwrap(ProjectEditPreparedNodes(payload: ["chapters": .array([.object(["nodes": .string("future")])])]).chapters?.first)
        XCTAssertFalse(invalid.nodesOmitted); XCTAssertNil(invalid.nodes)
    }
    func testRawReferenceAndUnicodeBytesAreNeverNormalizedOrFetched() throws {
        let raw = "  fixture:node-e\u{301}\n", payload: [String: ProjectEditJSON] = ["chapters": .array([.object(["nodes": .array([.object(["imgUrl": .string(raw)])])])])]
        let node = try XCTUnwrap(ProjectEditPreparedNodes(payload: payload).chapters?.first?.nodes?.first)
        XCTAssertEqual(node.value(.imgUrl).text.map { Array($0.utf8) }, Array(raw.utf8))
        XCTAssertEqual(ProjectEditPreparedNodes(payload: payload).raw, payload["chapters"])
    }
    func testChapterDescriptionReadsPreparedProjectionRatherThanNarrativeDraftSummary() throws {
        let draft = ProjectEditRichStoryFixtures.draft(), payload = try ProjectEditContract.payload(draft, topicID: nil, scope: .full)
        let chapter = try XCTUnwrap(ProjectEditPreparedNodes(payload: payload).chapters?.first)
        XCTAssertTrue(draft.chapters[0].story.contains("Which clue will you follow?"))
        XCTAssertFalse(try XCTUnwrap(chapter.description.text).contains("Which clue will you follow?"))
        XCTAssertEqual(chapter.description.raw, payload["chapters"]?.array?.first?.object?["description"])
    }

}

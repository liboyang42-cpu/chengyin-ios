import XCTest
@testable import QuestifyCore

final class ProjectEditRichStoryTests: XCTestCase {
    private func payload(_ draft: ProjectEditDraft) throws -> [String: ProjectEditJSON] { try ProjectEditContract.payload(draft, topicID: nil, scope: .full) }
    private func rich(_ kind: ProjectEditBlock.Kind) -> ProjectEditBlock { ProjectEditRichStoryFixtures.draft().chapters[0].blocks!.first { $0.kind == kind }! }
    private func withBlock(_ block: ProjectEditBlock) -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.chapters[0].blocks = [.init(kind: .text, content: "Public story"), .init(kind: .node, nodeID: draft.chapters[0].nodes[0].id), block]; return draft
    }
    private func beat(_ value: ProjectEditNarrativeBeat, field: String, nodeID: String, content: String = "Narrative") -> ProjectEditBlock {
        var block = ProjectEditBlock(kind: .text, content: content, nodeID: nodeID); block.selectBeat(value); block.setField("field", .string(field)); block.nodeID = nodeID; return block
    }
    private func narrativeDraft(before: [ProjectEditBlock], after: [ProjectEditBlock], node: ProjectEditNode) -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.chapters[0].nodes = [node]
        draft.chapters[0].blocks = [.init(kind: .text, content: "Public story")] + before + [.init(kind: .node, nodeID: node.id)] + after
        return draft
    }
    func testAllRichKindsSerializeAndPersistWithoutDroppingMetadata() throws {
        let draft = ProjectEditRichStoryFixtures.draft(), body = try payload(draft)
        let blocks = try XCTUnwrap(body["chapters"]?.array?.first?.object?["blocks"]?.array)
        for kind in ProjectEditRichStoryContract.richKinds { XCTAssertTrue(blocks.contains { $0.object?["type"] == .string(kind.rawValue) }) }
        let restored = try JSONDecoder().decode(ProjectEditDraft.self, from: JSONEncoder().encode(draft)); XCTAssertEqual(restored, draft)
        XCTAssertEqual(try payload(restored), body)
    }
    func testDreamLimitsAndNoSingleMediaURLShape() throws {
        var block = rich(.dream); XCTAssertNoThrow(try payload(withBlock(block)))
        block.setField("images", .array([])); XCTAssertThrowsError(try payload(withBlock(block)))
        block.setField("title", nil); XCTAssertNoThrow(try payload(withBlock(block))) // source empty untitled placeholder omission
        block = rich(.dream); block.setField("images", .array(Array(repeating: .object(["url": .string("fixture://image")]), count: 7)))
        XCTAssertThrowsError(try payload(withBlock(block)))
        block = rich(.dream); block.setField("title", .string(String(repeating: "a", count: 21))); XCTAssertThrowsError(try payload(withBlock(block)))
        block = rich(.dream); block.setField("images", .array([.object(["url": .string("fixture://image"), "line": .string(String(repeating: "x", count: 81))])]))
        XCTAssertThrowsError(try payload(withBlock(block)))
        XCTAssertThrowsError(try ProjectEditRichStoryContract.validateShape(["type": .string("dream"), "url": .string("not-an-album")], kind: .dream))
    }
    func testMoodAliasesNormalizeAndUnknownFails() throws {
        for (old, expected) in ["NIGHT": "BLUE", "ARCHIVE": "YELLOW", "NEON": "RED", "MOSS": "DEFAULT"] { XCTAssertEqual(try ProjectEditRichStoryContract.normalizedMood(old), expected) }
        var block = rich(.mood); block.setField("mood", .string("NIGHT"))
        let blocks = try XCTUnwrap(payload(withBlock(block))["chapters"]?.array?.first?.object?["blocks"]?.array)
        XCTAssertEqual(blocks.last?.object?["mood"], .string("BLUE"))
        block.setField("mood", .string("#ff0000")); XCTAssertThrowsError(try payload(withBlock(block)))
    }
    func testThoughtKeysMustBeValidAndUniquePerChapter() throws {
        var draft = withBlock(rich(.thought)); var second = rich(.thought); second.id = "different-key"; draft.chapters[0].blocks?.append(second)
        XCTAssertThrowsError(try payload(draft))
        second.setField("thoughtKey", .string("UPPERCASE")); XCTAssertThrowsError(try payload(withBlock(second)))
        second.setField("thoughtKey", .string("second_thought")); XCTAssertNoThrow(try payload(withBlock(second)))
    }
    func testVoiceOddRevealValidateTypedLimits() throws {
        var voice = rich(.voice); voice.setField("who", .string("invented")); XCTAssertThrowsError(try payload(withBlock(voice)))
        voice = rich(.voice); voice.content = String(repeating: "x", count: 201); XCTAssertThrowsError(try payload(withBlock(voice)))
        voice.content = "Line"; voice.setField("when", .object(["op": .string("HAS_TAG"), "value": .string("thought.harbor.done")]))
        XCTAssertNoThrow(try payload(withBlock(voice)))
        var odd = rich(.odd); odd.setField("level", .number(4)); XCTAssertThrowsError(try payload(withBlock(odd)))
        odd.setField("level", .string("1")); XCTAssertThrowsError(try payload(withBlock(odd)))
        var reveal = rich(.reveal); reveal.content = " "; XCTAssertThrowsError(try payload(withBlock(reveal)))
        reveal.content = String(repeating: "x", count: 501); XCTAssertThrowsError(try payload(withBlock(reveal)))
    }
    func testAllSevenBeatSegmentsHaveSourceFieldsAndPlacement() throws {
        let node = ProjectEditSyntheticFixtures.draft().chapters[0].nodes[0]
        for segment in ProjectEditNarrativeBeat.allCases {
            let block = beat(segment, field: segment.fields[0], nodeID: node.id)
            let draft = narrativeDraft(before: segment.afterNode ? [] : [block], after: segment.afterNode ? [block] : [], node: node)
            XCTAssertNoThrow(try payload(draft), segment.rawValue)
            let bad = narrativeDraft(before: segment.afterNode ? [block] : [], after: segment.afterNode ? [] : [block], node: node)
            XCTAssertThrowsError(try payload(bad), segment.rawValue)
        }
    }
    func testNarrativeProjectionExcludesBeatsAndRemapsAfterNodeReorder() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); let first = draft.chapters[0].nodes[0]
        var second = first; second.id = "second-node"; draft.chapters[0].nodes.append(second)
        let intro = beat(.brief, field: "body", nodeID: first.id, content: "Private node prose")
        draft.chapters[0].blocks = [.init(kind: .text, content: "Public"), intro, .init(kind: .node, nodeID: second.id), .init(kind: .node, nodeID: first.id)]
        let chapter = try XCTUnwrap(payload(draft)["chapters"]?.array?.first?.object)
        XCTAssertEqual(chapter["description"], .string("Public")); XCTAssertEqual(chapter["blocks"]?.array?[1].object?["nodeIndex"], .number(1))
    }
    func testSingletonNarrativeSlotsCannotRepeat() throws {
        let node = ProjectEditSyntheticFixtures.draft().chapters[0].nodes[0]
        let block = beat(.brief, field: "question", nodeID: node.id); var duplicate = block; duplicate.id = "duplicate"
        XCTAssertThrowsError(try payload(narrativeDraft(before: [block, duplicate], after: [], node: node)))
    }
    func testNarrativeQARequiresPairsUniqueQIDsAndAtMostSixQuestions() throws {
        let node = ProjectEditSyntheticFixtures.draft().chapters[0].nodes[0]
        var q = beat(.enter, field: "q", nodeID: node.id), a = beat(.enter, field: "a", nodeID: node.id)
        q.setField("qid", .string("q1")); a.setField("qid", .string("q1"))
        XCTAssertNoThrow(try payload(narrativeDraft(before: [q, a], after: [], node: node)))
        XCTAssertThrowsError(try payload(narrativeDraft(before: [q], after: [], node: node)))
        var pairList: [ProjectEditBlock] = []
        for index in 0..<7 { var question = q, answer = a; question.id = "q-\(index)"; answer.id = "a-\(index)"; question.setField("qid", .string("pair\(index)")); answer.setField("qid", .string("pair\(index)")); pairList += [question, answer] }
        XCTAssertThrowsError(try payload(narrativeDraft(before: pairList, after: [], node: node)))
    }
    func testNarrativeNPCConsistencyAndSegmentScope() throws {
        let node = ProjectEditSyntheticFixtures.draft().chapters[0].nodes[0]
        var first = beat(.enter, field: "opener", nodeID: node.id), second = beat(.enter, field: "aside", nodeID: node.id)
        first.setField("npcId", .number(9)); second.setField("npcId", .number(10))
        XCTAssertThrowsError(try payload(narrativeDraft(before: [first, second], after: [], node: node)))
        second.setField("npcId", .number(9)); XCTAssertNoThrow(try payload(narrativeDraft(before: [first, second], after: [], node: node)))
        first.selectBeat(.brief); first.nodeID = node.id; first.setField("npcId", .number(9))
        XCTAssertThrowsError(try payload(narrativeDraft(before: [first], after: [], node: node)))
    }
    func testNarrativeListLimitsAndDeliverRewardRequirement() throws {
        let node = ProjectEditSyntheticFixtures.draft().chapters[0].nodes[0]
        for (segment, field, maximum) in [(ProjectEditNarrativeBeat.brief, "carry", 8), (.outcome, "fact", 8), (.revisit, "change", 6)] {
            let rows = (0...maximum).map { index -> ProjectEditBlock in var block = beat(segment, field: field, nodeID: node.id); block.id = "row-\(index)"; return block }
            XCTAssertThrowsError(try payload(narrativeDraft(before: segment.afterNode ? [] : rows, after: segment.afterNode ? rows : [], node: node)))
        }
        var line = beat(.deliver, field: "line", nodeID: node.id); line.setField("claimLater", .bool(true))
        XCTAssertThrowsError(try payload(narrativeDraft(before: [], after: [line], node: node)))
        let reward = beat(.deliver, field: "reward", nodeID: node.id)
        XCTAssertNoThrow(try payload(narrativeDraft(before: [], after: [reward, line], node: node)))
    }
    func testConditionsRespectSeparateNarrativeAndEndingDomains() throws {
        let thought: ProjectEditJSON = .object(["op": .string("HAS_TAG"), "value": .string("thought.harbor.done")])
        XCTAssertThrowsError(try ProjectEditRichStoryContract.validateCondition(thought))
        XCTAssertNoThrow(try ProjectEditRichStoryContract.validateCondition(thought, ending: true))
        for variable in ["clue.door", "counter.visits", "relation.guide", "sys.hp", "sys.luck", "sys.exhausted", "sys.asked.8.q1", "sys.mistakes.8", "sys.outcome.8", "sys.passed.8"] {
            XCTAssertNoThrow(try ProjectEditRichStoryContract.validateCondition(.object(["op": .string("GTE"), "var": .string(variable), "value": .number(1)])))
        }
        for number in [ProjectEditJSON.number(100), .string("1"), .number(Decimal(string: "1.5")!)] {
            XCTAssertThrowsError(try ProjectEditRichStoryContract.validateCondition(.object(["op": .string("EQ"), "var": .string("sys.hp"), "value": number])))
        }
        XCTAssertThrowsError(try ProjectEditRichStoryContract.validateCondition(.object(["op": .string("NODE_COMPLETED"), "nodeId": .number(0)])))
    }
    func testNarrativeWhenAndClaimLaterOnlyAllowedAtSourceSlots() throws {
        let node = ProjectEditSyntheticFixtures.draft().chapters[0].nodes[0]
        var block = beat(.brief, field: "question", nodeID: node.id); block.setField("when", .object(["op": .string("HAS_TAG"), "value": .string("tag.clue")]))
        XCTAssertThrowsError(try payload(narrativeDraft(before: [block], after: [], node: node)))
        block.setField("field", .string("carry")); XCTAssertNoThrow(try payload(narrativeDraft(before: [block], after: [], node: node)))
        block.setField("claimLater", .bool(true)); XCTAssertThrowsError(try payload(narrativeDraft(before: [block], after: [], node: node)))
    }
    func testNodeRemovalRemovesAssociatedNarrativeAndNoOtherProse() throws {
        var draft = ProjectEditRichStoryFixtures.draft(); let nodeID = draft.chapters[0].nodes[0].id
        draft.chapters[0].removeNode(id: nodeID)
        XCTAssertFalse(draft.chapters[0].blocks!.contains { $0.nodeID == nodeID })
        XCTAssertTrue(draft.chapters[0].blocks!.contains { $0.kind == .dream })
        XCTAssertTrue(draft.chapters[0].blocks!.contains { $0.kind == .text && !$0.isNarrative })
    }
    func testChangingNarrativeFieldClearsOnlyNowInapplicableMetadata() {
        var block = ProjectEditBlock(kind: .text); block.selectBeat(.enter); block.selectNarrativeField("q"); block.setField("qid", .string("one")); block.setField("npcId", .number(9))
        block.selectNarrativeField("opener"); XCTAssertNil(block.sourceFields?["qid"]); XCTAssertEqual(block.sourceFields?["npcId"], .number(9))
    }
    func testLegacyUnboundEndingsBecomeDeterministicChaptersAndKeepOtherStorySections() throws {
        var draft = ProjectEditSyntheticFixtures.draft(), copy = draft
        let rows: [ProjectEditJSON] = [.object(["code": .string("legacy"), "title": .string("Home"), "summary": .string("You return."), "fallback": .bool(true)])]
        try ProjectEditRichStoryContract.attachEndings(rows, draft: &draft); try ProjectEditRichStoryContract.attachEndings(rows, draft: &copy)
        XCTAssertEqual(draft, copy); XCTAssertEqual(draft.chapters.last?.id, "legacy-ending-0"); XCTAssertEqual(draft.chapters.last?.name, "Home")
        draft.preserved["journeyStory"] = .string(#"{"schemaVersion":1,"call":{"title":"Keep"},"ending":{"endings":[]}}"#)
        let body = try payload(draft), story = try XCTUnwrap(body["journeyStory"]?.text)
        let object = try JSONDecoder().decode([String: ProjectEditJSON].self, from: Data(story.utf8))
        XCTAssertNil(object["ending"]); XCTAssertNotNil(object["call"])
        let withExtras: ProjectEditJSON = .string(#"{"schemaVersion":1,"ending":{"endings":[],"epilogues":[]}}"#)
        XCTAssertEqual(try ProjectEditRichStoryContract.journeyStoryWithoutStandaloneEndingList(withExtras), withExtras)
    }
    func testEmptyLegacyEndingSummaryStillBuildsValidEndingChapter() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        try ProjectEditRichStoryContract.attachEndings([.object(["title": .string("Quiet ending"), "fallback": .bool(true)])], draft: &draft)
        XCTAssertNoThrow(try payload(draft)); XCTAssertEqual(draft.chapters.last?.blocks, [])
    }
    func testRichShapeRejectsUnknownFieldsAndWrongTypeMixes() throws {
        var fields: [String: ProjectEditJSON] = ["type": .string("voice"), "who": .string("心"), "content": .string("Line"), "futureSecret": .bool(true)]
        XCTAssertThrowsError(try ProjectEditRichStoryContract.validateShape(fields, kind: .voice))
        fields.removeValue(forKey: "futureSecret"); fields["nodeIndex"] = .number(0)
        XCTAssertThrowsError(try ProjectEditRichStoryContract.validateShape(fields, kind: .voice))
    }
    func testBeatReadbackResolvesServerNodeIDAndRetainsMetadata() throws {
        let raw = #"{"code":200,"data":{"editScope":"FULL","topic":{"id":71,"productType":1,"name":"Route","description":"Story","categoryIds":"7","updateTime":"r1"},"chapters":[{"id":11,"name":"One","description":"Public","cmsTopicNodeList":[{"id":22,"name":"Stop","longitude":"121","latitude":"31"}],"blocks":[{"key":"beat-stable","type":"text","content":"Who are you?","beat":"enter","field":"opener","npcId":9,"nodeId":22},{"key":"node-stable","type":"node","nodeId":22}]}],"tickets":[]}}"#
        let draft = try ProjectEditContract.decodeEditDetail(Data(raw.utf8), expectedTopicID: 71, owner: .personal).draft
        let block = try XCTUnwrap(draft.chapters[0].blocks?.first)
        XCTAssertTrue(block.isNarrative); XCTAssertEqual(block.nodeID, draft.chapters[0].nodes[0].id); XCTAssertEqual(block.sourceFields?["npcId"], .number(9)); XCTAssertEqual(block.id, "beat-stable")
    }
}

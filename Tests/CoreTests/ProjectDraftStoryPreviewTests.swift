import XCTest
@testable import QuestifyCore

final class ProjectDraftStoryPreviewTests: XCTestCase {
    private func draft(blocks: [ProjectEditBlock]? = nil) -> ProjectEditDraft {
        var draft = ProjectEditDraft(product: .city); draft.name = "Unsaved story"; draft.subtitle = "Current local version"
        var chapter = ProjectEditChapter(); chapter.id = "chapter"; chapter.name = "First"; chapter.description = "Legacy text"; chapter.blocks = blocks
        draft.chapters = [chapter]; return draft
    }
    func testCurrentUnsavedTextIsProjectedWithoutDraftMutation() throws {
        let draft = draft(blocks: [.init(kind: .text, content: "Not the server version")])
        let before = ProjectEditPendingMaterials.exactData(draft), preview = ProjectDraftStoryPreview(draft: draft)
        XCTAssertNil(preview.reason); XCTAssertEqual(preview.title, draft.name)
        XCTAssertEqual(preview.chapters[0].rows.map(\.text), ["Not the server version"])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(draft), before); XCTAssertTrue(preview.isCurrent(in: draft))
    }
    func testLegacyDescriptionThenNodesKeepSourceOrder() {
        var draft = draft(); var first = ProjectEditNode(); first.id = "a"; first.name = "A"; first.description = "Authored A"
        var second = ProjectEditNode(); second.id = "b"; second.name = "B"; draft.chapters[0].nodes = [first, second]
        let rows = ProjectDraftStoryPreview(draft: draft).chapters[0].rows
        XCTAssertEqual(rows.map(\.kind), [.text, .node, .node]); XCTAssertEqual(rows.map(\.title), ["", "A", "B"])
        XCTAssertEqual(rows.map(\.text), ["Legacy text", "Authored A", ""])
    }
    func testExplicitBlocksRemainInAuthoredOrderAndDoNotAppendUnplacedNodes() {
        var draft = draft(blocks: [.init(kind: .voice, content: "Voice"), .init(kind: .node, nodeID: "b"), .init(kind: .text, content: "After")])
        var first = ProjectEditNode(); first.id = "a"; first.name = "Unplaced"; var second = ProjectEditNode(); second.id = "b"; second.name = "Placed"
        draft.chapters[0].nodes = [first, second]
        let chapter = ProjectDraftStoryPreview(draft: draft).chapters[0]
        XCTAssertEqual(chapter.rows.map(\.kind), [.voice,.node,.text]); XCTAssertEqual(chapter.rows[1].title, "Placed"); XCTAssertEqual(chapter.unplacedNodeCount, 1)
    }
    func testEmptyExplicitBlocksDoNotFallBackToLegacyDescription() {
        let preview = ProjectDraftStoryPreview(draft: draft(blocks: [])); XCTAssertTrue(preview.chapters[0].rows.isEmpty)
    }
    func testConditionalContentAlwaysVisibleAndMarkedWithoutEvaluation() {
        var block = ProjectEditBlock(kind: .text, content: "Only after a choice")
        block.setField("when", .object(["op": .string("HAS_TAG"), "value": .string("tag.never_chosen")]))
        let row = ProjectDraftStoryPreview(draft: draft(blocks: [block])).chapters[0].rows[0]
        XCTAssertTrue(row.conditional); XCTAssertEqual(row.text, block.content)
    }
    func testVariablesRemainLiteralRatherThanInventingPlayerValues() {
        let source = "Hello {{counter.score}} / ${player.name}"
        XCTAssertEqual(ProjectDraftStoryPreview(draft: draft(blocks: [.init(kind: .text, content: source)])).chapters[0].rows[0].text, source)
    }
    func testMediaURLsAreExcludedButAlbumCaptionOrderRemains() {
        var album = ProjectEditBlock(kind: .dream); album.setField("title", .string("Album")); album.setField("images", .array([
            .object(["url":.string("https://example.invalid/private-a"),"line":.string("First caption")]),
            .object(["url":.string("https://example.invalid/private-b"),"line":.string("Second caption")])]))
        let rows = ProjectDraftStoryPreview(draft: draft(blocks: [.init(kind: .image, url:"https://example.invalid/photo"), .init(kind:.audio,url:"https://example.invalid/sound"),album])).chapters[0].rows
        XCTAssertEqual(rows.map(\.kind), [.image,.audio,.album]); XCTAssertEqual(rows[2].details, ["First caption","Second caption"])
        XCTAssertTrue(rows.allSatisfy { !$0.text.contains("https://") && !$0.title.contains("https://") && !$0.details.joined().contains("https://") })
    }
    func testEmptyAndUnsupportedMediaAreExplicit() {
        var album = ProjectEditBlock(kind:.dream); album.setField("images",.string("unsupported"))
        let rows = ProjectDraftStoryPreview(draft:draft(blocks:[.init(kind:.audio),album])).chapters[0].rows
        XCTAssertTrue(rows[0].emptyMediaReference); XCTAssertTrue(rows[1].unsupported)
        album.setField("images", .array([.null, .object(["line": .string("Second")])]))
        let projected = ProjectDraftStoryPreview(draft: draft(blocks: [album])).chapters[0].rows[0]
        XCTAssertTrue(projected.unsupported); XCTAssertEqual(projected.details, ["", "Second"])
    }
    func testUnknownMetadataAndUnresolvedNodeAreMarkedWithoutHidingKnownText() {
        var text = ProjectEditBlock(kind:.text,content:"Keep this text"); text.setField("future",.bool(true))
        let rows = ProjectDraftStoryPreview(draft:draft(blocks:[text,.init(kind:.node,nodeID:"missing")])).chapters[0].rows
        XCTAssertTrue(rows[0].unsupported); XCTAssertEqual(rows[0].text,"Keep this text"); XCTAssertEqual(rows[1].kind,.unsupported)
    }
    func testThoughtDeclarationNameAndSummaryAreAuthorContentOnly() {
        var thought = ProjectEditBlock(kind:.thought); thought.setField("thoughtKey",.string("mystery"))
        var draft = draft(blocks:[thought]); draft.preserved["journeyRules"] = .string(#"{"thoughts":[{"key":"mystery","name":"A mystery","desc":"Authored summary","need":500}]}"#)
        let row = ProjectDraftStoryPreview(draft:draft).chapters[0].rows[0]
        XCTAssertEqual(row.title,"A mystery"); XCTAssertEqual(row.text,"Authored summary"); XCTAssertFalse(row.unsupported)
    }
    func testMissingAmbiguousAndMalformedThoughtDefinitionsStayUnsupported() {
        var thought = ProjectEditBlock(kind:.thought); thought.setField("thoughtKey",.string("a"))
        for raw in ["bad",#"{"thoughts":[{"key":"a","name":"A"},{"key":"a","name":"B"}]}"#,#"{"thoughts":null}"#] {
            var draft = draft(blocks:[thought]); draft.preserved["journeyRules"] = .string(raw)
            XCTAssertTrue(ProjectDraftStoryPreview(draft:draft).chapters[0].rows[0].unsupported)
        }
    }
    func testOpeningAndEndingChaptersAreLabeledNotSelectedAsOutcomes() {
        var draft = draft(blocks:[]); draft.chapters[0].preserved["opening"] = .bool(true)
        var ending = ProjectEditChapter(); ending.id="ending"; ending.name="A possible ending"; ending.preserved["ending"] = .object(["fallback":.bool(true)])
        draft.chapters.append(ending); let preview = ProjectDraftStoryPreview(draft:draft)
        XCTAssertEqual(preview.chapters.map(\.role),[.opening,.ending]); XCTAssertEqual(preview.chapters.map(\.title),["First","A possible ending"])
    }
    func testUnsupportedChapterVersionAndConflictingRoleDoNotPretendReadable() {
        var draft = draft(); draft.chapters[0].schemaVersion=2
        XCTAssertTrue(ProjectDraftStoryPreview(draft:draft).chapters[0].unsupported)
        draft.chapters[0].schemaVersion=1; draft.chapters[0].preserved["opening"] = .bool(true); draft.chapters[0].preserved["ending"] = .object([:])
        XCTAssertTrue(ProjectDraftStoryPreview(draft:draft).chapters[0].unsupported)
    }
    func testBranchAndUnknownRoutesAreExplicitlyUnsupported() {
        var draft = draft(); draft.preserved["routeMode"] = .string("BRANCH_GRAPH")
        XCTAssertEqual(ProjectDraftStoryPreview(draft:draft).reason,.branchRoute)
        draft.preserved["routeMode"] = .string("FUTURE"); XCTAssertEqual(ProjectDraftStoryPreview(draft:draft).reason,.unsupportedRoute)
        draft.preserved["routeMode"] = .string("LINEAR"); XCTAssertNil(ProjectDraftStoryPreview(draft:draft).reason)
    }
    func testDuplicateAndCanonicalEquivalentChapterNodeAndBlockIDsFailClosed() {
        for kind in ["chapter","node","block"] {
            var draft = draft(blocks:[])
            switch kind {
            case "chapter": draft.chapters.append(draft.chapters[0])
            case "node": var node=ProjectEditNode(); node.id="é"; var other=node; other.id="e\u{301}"; draft.chapters[0].nodes=[node,other]
            default: var block=ProjectEditBlock(kind:.text); block.id="same"; draft.chapters[0].blocks=[block,block]
            }
            XCTAssertEqual(ProjectDraftStoryPreview(draft:draft).reason,.identity)
        }
    }
    func testBoundsFailClosedWithoutTruncatingStory() {
        var draft = draft(blocks:(0..<201).map { _ in .init(kind:.text,content:"x") }); XCTAssertEqual(ProjectDraftStoryPreview(draft:draft).reason,.limit)
        draft = self.draft(blocks:[.init(kind:.text,content:String(repeating:"x",count:1024*1024))]); XCTAssertEqual(ProjectDraftStoryPreview(draft:draft).reason,.limit)
    }
    func testExactUnsavedBytesFenceCanonicalEquivalentTextAndEdits() {
        var draft = draft(blocks:[.init(kind:.text,content:"e\u{301}")]); let preview=ProjectDraftStoryPreview(draft:draft)
        draft.chapters[0].blocks?[0].content="é"; XCTAssertFalse(preview.isCurrent(in:draft))
    }
    func testPendingMaterialsAreExcludedAndEmptyDraftRemainsAnHonestEmptyState() {
        var draft=ProjectEditDraft(product:.city); var node=ProjectEditNode(); node.id="pending"; node.name="Do not expose as placed story"
        draft.pendingMaterials=[.init(node: node)]; let preview=ProjectDraftStoryPreview(draft:draft)
        XCTAssertEqual(preview.excludedPendingCount,1); XCTAssertTrue(preview.chapters.isEmpty); XCTAssertNil(preview.reason)
    }
    func testUnresolvedConditionalNodeRetainsUnevaluatedLabel() {
        var block = ProjectEditBlock(kind: .node, nodeID: "missing")
        block.setField("when", .object(["op": .string("HAS_TAG")]))
        let row = ProjectDraftStoryPreview(draft: draft(blocks: [block])).chapters[0].rows[0]
        XCTAssertTrue(row.unsupported); XCTAssertTrue(row.conditional)
    }
    func testUnresolvedConditionalThoughtRetainsUnevaluatedLabel() {
        var block = ProjectEditBlock(kind: .thought); block.setField("thoughtKey", .string("missing"))
        block.setField("when", .object(["op": .string("HAS_TAG")]))
        let row = ProjectDraftStoryPreview(draft: draft(blocks: [block])).chapters[0].rows[0]
        XCTAssertTrue(row.unsupported); XCTAssertTrue(row.conditional)
    }
    func testMalformedAndOverLimitConditionalAlbumRetainsUnevaluatedLabel() {
        let cases: [ProjectEditJSON] = [.string("malformed"), .array(Array(repeating: .object([:]), count: 7))]
        for images in cases {
            var block = ProjectEditBlock(kind: .dream); block.setField("images", images)
            block.setField("when", .object(["op": .string("HAS_TAG")]))
            let row = ProjectDraftStoryPreview(draft: draft(blocks: [block])).chapters[0].rows[0]
            XCTAssertTrue(row.unsupported); XCTAssertTrue(row.conditional)
        }
    }
    func testThoughtReferencesRequireExactUTF8Identity() {
        var block = ProjectEditBlock(kind: .thought); block.setField("thoughtKey", .string("e\u{301}"))
        var draft = draft(blocks: [block]); draft.preserved["journeyRules"] = .string(#"{"thoughts":[{"key":"é","name":"Never resolve this alias"}]}"#)
        let mismatch = ProjectDraftStoryPreview(draft: draft).chapters[0].rows[0]
        XCTAssertTrue(mismatch.unsupported); XCTAssertEqual(mismatch.title, "")
        draft.chapters[0].blocks?[0].setField("thoughtKey", .string("é"))
        XCTAssertEqual(ProjectDraftStoryPreview(draft: draft).chapters[0].rows[0].title, "Never resolve this alias")
    }
    func testCanonicalEquivalentThoughtDeclarationsRemainAmbiguous() {
        var block = ProjectEditBlock(kind: .thought); block.setField("thoughtKey", .string("é"))
        var draft = draft(blocks: [block]); draft.preserved["journeyRules"] = .string("{\"thoughts\":[{\"key\":\"é\",\"name\":\"First\"},{\"key\":\"e\\u0301\",\"name\":\"Alias\"}]}")
        XCTAssertTrue(ProjectDraftStoryPreview(draft: draft).chapters[0].rows[0].unsupported)
    }
}

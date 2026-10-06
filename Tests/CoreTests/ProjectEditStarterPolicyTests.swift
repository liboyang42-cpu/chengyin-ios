import XCTest
@testable import QuestifyCore

final class ProjectEditStarterPolicyTests: XCTestCase {
    func testCityCreatesEmptyStoryFlowWithoutPlaceholderOrNode() {
        let chapter = ProjectEditStarterPolicy.chapter(name: "第1章", product: .city)
        XCTAssertEqual(chapter.name, "第1章"); XCTAssertEqual(chapter.blocks, [])
        XCTAssertEqual(chapter.required, 1); XCTAssertEqual(chapter.schemaVersion, 1)
        XCTAssertTrue(chapter.description.isEmpty); XCTAssertTrue(chapter.nodes.isEmpty); XCTAssertFalse(chapter.hasRealStory)
        XCTAssertEqual(ProjectEditStarterPolicy.destination(product: .city, chapter: chapter, hadChapters: false), .story)
        XCTAssertEqual(ProjectEditStarterPolicy.destination(product: .city, chapter: chapter, hadChapters: true), .story)
        var copy = chapter; XCTAssertThrowsError(try copy.addNode(product: .city))
    }
    func testFreeOnlyFirstCreationOpensTemporaryNodeWithoutMaterializingStory() {
        let chapter = ProjectEditStarterPolicy.chapter(name: "Chapter 1", product: .freeExplore)
        XCTAssertNil(chapter.blocks); XCTAssertTrue(chapter.nodes.isEmpty)
        XCTAssertEqual(ProjectEditStarterPolicy.destination(product: .freeExplore, chapter: chapter, hadChapters: false), .firstNode)
        XCTAssertNil(ProjectEditStarterPolicy.destination(product: .freeExplore, chapter: chapter, hadChapters: true))
        XCTAssertFalse(ProjectEditStarterPolicy.usesStoryEditor(product: .freeExplore, chapter: chapter))
    }
    func testOnlyExplicitOpeningIsSharedStoryExceptionInFreeMode() {
        var chapter = ProjectEditChapter()
        let flags: [ProjectEditJSON?] = [nil, .null, .bool(false), .string("true"), .number(1)]
        for flag in flags {
            chapter.preserved["opening"] = flag
            XCTAssertFalse(ProjectEditStarterPolicy.usesStoryEditor(product: .freeExplore, chapter: chapter))
        }
        chapter.preserved["opening"] = .bool(true)
        XCTAssertEqual(ProjectEditStarterPolicy.destination(product: .freeExplore, chapter: chapter, hadChapters: true), .story)
        XCTAssertEqual(ProjectEditStarterPolicy.destination(product: .freeExplore, chapter: chapter, hadChapters: false), .story)
    }
    func testFormalCandidateNeedsRealCoordinatesAndNameWithoutRewritingRawFields() {
        var node = ProjectEditNode(); node.name = "  Raw e\u{301}\n"; node.longitude = "121.5"; node.latitude = "31.2"
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try? encoder.encode(node)
        XCTAssertTrue(ProjectEditStarterPolicy.canAddFormalNode(node))
        XCTAssertEqual(try? encoder.encode(node), before)
        for coordinate in ["", "0", "NaN", "infinity", "181"] { node.longitude = coordinate; XCTAssertFalse(ProjectEditStarterPolicy.canAddFormalNode(node)) }
        node.longitude = "121.5"; node.latitude = "-91"; XCTAssertFalse(ProjectEditStarterPolicy.canAddFormalNode(node))
        node.latitude = "31.2"; node.name = " \n"; XCTAssertFalse(ProjectEditStarterPolicy.canAddFormalNode(node))
        node.name = "Valid"; node.nodeTime = -1; XCTAssertFalse(ProjectEditStarterPolicy.canAddFormalNode(node))
    }
    func testOpeningRejectsDirectNodeMutationInBothModes() throws {
        for product in [ProjectEditProduct.city, .freeExplore] {
            var chapter = ProjectEditChapter(); chapter.description = "Real story"
            chapter.blocks = [.init(kind: .text, content: "Real story")]
            XCTAssertTrue(chapter.hasRealStory)
            var allowed = chapter; try allowed.addNode(product: product)
            XCTAssertEqual(allowed.nodes.count, 1); XCTAssertEqual(allowed.blocks?.last?.kind, .node)
            chapter.preserved["opening"] = .bool(true)
            let original = chapter
            XCTAssertThrowsError(try chapter.addNode(product: product)) { error in
                XCTAssertEqual(error as? ProjectEditError, .invalidDraft, "Opening must fail independently of storyRequired")
            }
            XCTAssertEqual(chapter, original); XCTAssertTrue(chapter.nodes.isEmpty)
            chapter.preserved["opening"] = .bool(false); try chapter.addNode(product: product)
            XCTAssertEqual(chapter.nodes.count, 1)
        }
    }

}

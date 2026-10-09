import XCTest
@testable import QuestifyCore

final class ProjectEmptyStoryTextRemovalTests: XCTestCase {
    private func draft(_ text: String = "") -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].id = "chapter"
        var before = ProjectEditBlock(kind: .text, content: " e\u{301} "); before.id = "before"
        var target = ProjectEditBlock(kind: .text, content: text); target.id = "target"
        var after = ProjectEditBlock(kind: .text, content: "é\n"); after.id = "after"
        draft.chapters[0].blocks = [before, target, after]; return draft
    }
    private func snapshot(_ draft: ProjectEditDraft) -> ProjectEmptyStoryTextRemoval { .init(draft: draft, chapterID: "chapter", blockID: "target") }
    func testEveryECMAScriptWhitespaceScalarAndCombinedStringAreEmpty() {
        let scalars: [UInt32] = Array(0x09...0x0D) + [0x20, 0xA0, 0x1680] + Array(0x2000...0x200A) + [0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]
        for value in scalars { XCTAssertTrue(ProjectEmptyStoryTextRemoval.isEmptyAfterECMAScriptTrim(String(UnicodeScalar(value)!))) }
        XCTAssertTrue(ProjectEmptyStoryTextRemoval.isEmptyAfterECMAScriptTrim(scalars.map { String(UnicodeScalar($0)!) }.joined()))
        XCTAssertTrue(ProjectEmptyStoryTextRemoval.isEmptyAfterECMAScriptTrim(""))
    }
    func testExcludedWhitespaceCombiningMarksAndVisibleContentRemainNonempty() {
        for value in ["\u{85}", "\u{180E}", "\u{200B}", "\u{2060}", " \u{301}", " \u{FE0F}", "{name}", "\u{0}", "正文"] {
            XCTAssertFalse(ProjectEmptyStoryTextRemoval.isEmptyAfterECMAScriptTrim(value), value)
        }
    }
    func testRemovalOnlyDeletesExactOrdinalAndDoesNotMergeOrReproject() throws {
        let before = draft("\u{FEFF} \n"), next = try snapshot(before).removingIfEmpty(in: before)
        var expected = before; expected.chapters[0].blocks?.remove(at: 1)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(next.chapters[0].blocks?.map(\.id), ["before", "after"])
        XCTAssertEqual(Data(next.chapters[0].blocks![0].content.utf8), Data(" e\u{301} ".utf8))
    }
    func testEveryNonemptyValueIsByteExactNoop() throws {
        for content in [" \u{85} ", "é", "e\u{301}", " \u{301}", " \r\n正文 ", "{KEY}"] {
            let original = draft(content), next = try snapshot(original).removingIfEmpty(in: original)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(original))
        }
    }
    func testTypingEmptyRetainsBlockAndOnlyChangesContent() throws {
        let original = draft("Text"), next = try snapshot(original).replacingContent(with: "", in: original)
        var expected = original; expected.chapters[0].blocks?[1].content = ""
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected)); XCTAssertEqual(next.chapters[0].blocks?.count, 3)
    }
    func testCanonicalEquivalentContentEditRetainsItsExactRepresentation() throws {
        let original = draft("é"), next = try snapshot(original).replacingContent(with: "e\u{301}", in: original)
        XCTAssertEqual(Data(next.chapters[0].blocks![1].content.utf8), Data("e\u{301}".utf8))
        XCTAssertNotEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(original))
    }
    func testRichNarrativeReferenceUnknownAndConditionalShapesAreRetained() {
        for kind in ["kind", "node", "url", "narrative", "condition", "unknown"] {
            var value = draft()
            switch kind {
            case "kind": value.chapters[0].blocks?[1].kind = .voice
            case "node": value.chapters[0].blocks?[1].nodeID = "node"
            case "url": value.chapters[0].blocks?[1].url = "asset"
            case "narrative": value.chapters[0].blocks?[1].sourceFields = ["beat": .string("outcome")]
            case "condition": value.chapters[0].blocks?[1].sourceFields = ["when": .object([:])]
            default: value.chapters[0].blocks?[1].sourceFields = ["future": .null]
            }
            XCTAssertEqual(snapshot(value).reason, .unsupported); XCTAssertThrowsError(try snapshot(value).removingIfEmpty(in: value))
        }
    }
    func testMissingDuplicateAndCanonicalAliasIdentityFailsClosed() {
        for kind in ["missing", "duplicate", "chapter", "alias"] {
            var value = draft()
            switch kind {
            case "missing": value.chapters[0].blocks = []
            case "duplicate": let duplicate = value.chapters[0].blocks![1]; value.chapters[0].blocks?.append(duplicate)
            case "chapter": let duplicate = value.chapters[0]; value.chapters.append(duplicate)
            default:
                value.chapters[0].blocks?[1].id = "é"
                var alias = ProjectEditBlock(kind: .text); alias.id = "e\u{301}"; value.chapters[0].blocks?.append(alias)
                XCTAssertEqual(ProjectEmptyStoryTextRemoval(draft: value, chapterID: "chapter", blockID: "é").reason, .identity); continue
            }
            XCTAssertEqual(snapshot(value).reason, .identity)
        }
        var value = draft(); value.chapters[0].blocks?[1].id = "é"
        XCTAssertEqual(ProjectEmptyStoryTextRemoval(draft: value, chapterID: "chapter", blockID: "e\u{301}").reason, .identity)
    }
    func testStaleDraftReorderOtherMutationAndRemovalReject() {
        let original = draft(), captured = snapshot(original)
        for kind in ["reorder", "other", "delete", "text"] {
            var next = original
            switch kind {
            case "reorder": next.chapters[0].blocks?.swapAt(0, 1)
            case "other": next.name += "!"
            case "delete": next.chapters[0].blocks?.remove(at: 1)
            default: next.chapters[0].blocks?[1].content = "new"
            }
            XCTAssertFalse(captured.isCurrent(in: next)); XCTAssertThrowsError(try captured.removingIfEmpty(in: next))
        }
    }
}

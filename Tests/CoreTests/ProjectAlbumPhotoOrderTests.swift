import XCTest
@testable import QuestifyCore

final class ProjectAlbumPhotoOrderTests: XCTestCase {
    private func draft() -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft(); value.chapters[0].id = "chapter"
        var album = ProjectEditBlock(kind: .dream); album.id = "album"
        album.sourceFields = ["title": .string(" e\u{301} "), "future": .object(["keep": .bool(true)]),
            "images": .array((0..<3).map { .object(["url": .string("same-url"), "line": .string("caption-\($0)"), "future": .number(Decimal($0))]) })]
        value.chapters[0].blocks = [album]; return value
    }
    private func capture(_ value: ProjectEditDraft, index: Int = 1) -> ProjectAlbumPhotoOrder {
        .init(draft: value, chapterID: "chapter", blockID: "album", index: index)
    }
    func testAdjacentMovePreservesWholeRowsCaptionsUnknownFieldsAndOtherDraftBytes() throws {
        for direction in [ProjectAlbumPhotoOrder.Direction.up, .down] {
            let original = draft(), next = try capture(original).moving(direction, in: original)
            var expected = original, rows = original.chapters[0].blocks![0].sourceFields!["images"]!.array!
            rows.swapAt(1, 1 + direction.rawValue); expected.chapters[0].blocks![0].setField("images", .array(rows))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
            let inverseIndex = 1 + direction.rawValue
            let restored = try capture(next, index: inverseIndex).moving(direction == .up ? .down : .up, in: next)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(restored), ProjectEditPendingMaterials.exactData(original))
        }
    }
    func testBoundaryAndInvalidIndexDoNotMutate() {
        let original = draft()
        XCTAssertFalse(capture(original, index: 0).canMove(.up)); XCTAssertFalse(capture(original, index: 2).canMove(.down))
        for index in [-1, 3, Int.max, Int.min] { XCTAssertFalse(capture(original, index: index).available) }
        XCTAssertThrowsError(try capture(original, index: 0).moving(.up, in: original))
    }
    func testMalformedRowsAreNotCompactedAndUnsupportedAlbumSizesAreRejected() {
        for rows: [ProjectEditJSON] in [[], [.object([:])], Array(repeating: .object([:]), count: 7), [.object([:]), .null, .object([:])]] {
            var value = draft(); value.chapters[0].blocks![0].setField("images", .array(rows)); XCTAssertFalse(capture(value).available)
        }
    }
    func testUnknownPhotoFieldsAndDuplicateURLsRemainSupported() throws {
        let value = draft(); XCTAssertTrue(capture(value).available)
        let next = try capture(value).moving(.up, in: value)
        XCTAssertEqual(next.chapters[0].blocks![0].dreamImages.map { $0["url"] }, value.chapters[0].blocks![0].dreamImages.map { $0["url"] })
        XCTAssertEqual(next.chapters[0].blocks![0].dreamImages[0]["line"], .string("caption-1"))
    }
    func testChangedCaptionOtherDraftFieldRemovalAndReorderRejectStaleCapture() {
        let original = draft(), captured = capture(original)
        for kind in ["caption", "other", "remove", "reorder"] {
            var next = original
            switch kind {
            case "caption": next.chapters[0].blocks![0].setDreamImage(index: 0, field: "line", value: "new")
            case "other": next.name += "!"
            case "remove": next.chapters[0].blocks = []
            default: next.chapters[0].blocks![0].sourceFields!["images"] = .array(Array(next.chapters[0].blocks![0].sourceFields!["images"]!.array!.reversed()))
            }
            XCTAssertFalse(captured.isCurrent(in: next)); XCTAssertThrowsError(try captured.moving(.up, in: next))
        }
    }
    func testExactIdentityDuplicateChapterDuplicateBlockAndSchemaRejection() {
        for kind in ["chapter", "block", "alias", "schema", "kind"] {
            var value = draft()
            switch kind {
            case "chapter": value.chapters.append(value.chapters[0])
            case "block": value.chapters[0].blocks!.append(value.chapters[0].blocks![0])
            case "alias": value.chapters[0].blocks![0].id = "é"
            case "schema": value.chapters[0].schemaVersion = 2
            default: value.chapters[0].blocks![0].kind = .text
            }
            XCTAssertFalse(capture(value).available)
            if kind == "alias" { XCTAssertFalse(ProjectAlbumPhotoOrder(draft: value, chapterID: "chapter", blockID: "e\u{301}", index: 1).available) }
        }
    }
}

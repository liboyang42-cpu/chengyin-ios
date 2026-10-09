import XCTest
@testable import QuestifyCore

final class ProjectAlbumPhotoRemovalTests: XCTestCase {
    private func draft(count: Int = 3) -> ProjectEditDraft {
        var d = ProjectEditSyntheticFixtures.draft(); d.chapters[0].id = "chapter"
        var album = ProjectEditBlock(kind: .dream); album.id = "album"
        album.sourceFields = ["title": .string("album"), "future": .string(" e\u{301} "), "images": .array((0..<count).map { .object(["url": .string("duplicate"), "line": .string("caption-\($0)"), "future": .number(Decimal($0))]) })]
        d.chapters[0].blocks = [album]; return d
    }
    private func snapshot(_ d: ProjectEditDraft, index: Int = 1) -> ProjectAlbumPhotoRemoval { .init(draft: d, chapterID: "chapter", blockID: "album", index: index) }
    func testFirstMiddleLastRemovalPreservesAllOtherRawRowsAndDraftFields() throws {
        for index in 0..<3 {
            let original = draft(), captured = snapshot(original, index: index)
            XCTAssertEqual(captured.reference, "duplicate"); XCTAssertEqual(captured.caption, "caption-\(index)")
            var expected = original, rows = original.chapters[0].blocks![0].sourceFields!["images"]!.array!
            rows.remove(at: index); expected.chapters[0].blocks![0].setField("images", .array(rows))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(try captured.removing(in: original)), ProjectEditPendingMaterials.exactData(expected))
        }
    }
    func testRemovingLastPhotoRetainsAlbumAndItsTitleAsEmptyDraft() throws {
        let original = draft(count: 1), next = try snapshot(original, index: 0).removing(in: original)
        XCTAssertEqual(next.chapters[0].blocks?.count, 1); XCTAssertEqual(next.chapters[0].blocks![0].fieldText("title"), "album")
        XCTAssertEqual(next.chapters[0].blocks![0].sourceFields?["images"], .array([]))
    }
    func testMalformedRowsAreNotCompactedOrDropped() {
        for raw: ProjectEditJSON in [.null, .string("bad"), .object(["url": .number(1)]), .object(["url": .string("x"), "line": .null])] {
            var d = draft(); var rows = d.chapters[0].blocks![0].sourceFields!["images"]!.array!; rows[0] = raw; d.chapters[0].blocks![0].setField("images", .array(rows))
            XCTAssertFalse(snapshot(d).available); XCTAssertThrowsError(try snapshot(d).removing(in: d))
        }
    }
    func testUnsupportedSizesAndIndicesReject() {
        for count in [0, 7] { XCTAssertFalse(snapshot(draft(count: count), index: 0).available) }
        for index in [-1, 3, Int.min, Int.max] { XCTAssertFalse(snapshot(draft(), index: index).available) }
    }
    func testReorderCaptionReplacementAndUnrelatedChangesInvalidateCapture() {
        let original = draft(), captured = snapshot(original)
        for kind in ["reorder", "caption", "other", "delete"] {
            var changed = original
            switch kind {
            case "reorder": let images = changed.chapters[0].blocks![0].sourceFields!["images"]!.array!; changed.chapters[0].blocks![0].setField("images", .array(Array(images.reversed())))
            case "caption": changed.chapters[0].blocks![0].setDreamImage(index: 1, field: "line", value: "new")
            case "other": changed.name += "!"
            default: changed.chapters[0].blocks = []
            }
            XCTAssertThrowsError(try captured.removing(in: changed))
        }
    }
    func testDuplicateAndCanonicalAliasIdentityAndUnknownSchemaReject() {
        var d = draft(); d.chapters.append(d.chapters[0]); XCTAssertFalse(snapshot(d).available)
        d = draft(); d.chapters[0].blocks!.append(d.chapters[0].blocks![0]); XCTAssertFalse(snapshot(d).available)
        d = draft(); d.chapters[0].blocks![0].id = "é"; XCTAssertFalse(ProjectAlbumPhotoRemoval(draft: d, chapterID: "chapter", blockID: "e\u{301}", index: 0).available)
        d = draft(); d.chapters[0].schemaVersion = 2; XCTAssertFalse(snapshot(d).available)
    }
}

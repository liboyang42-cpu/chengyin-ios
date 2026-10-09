import XCTest
@testable import QuestifyCore

final class ProjectNodePhotoRemovalTests: XCTestCase {
    private func draft(_ raw: String) -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.chapters[0].id = "chapter"; draft.chapters[0].nodes[0].id = "node"
        draft.chapters[0].nodes[0].imgUrl = raw; draft.chapters[0].nodes[0].localMetadata["unknown"] = .string("e\u{301}")
        return draft
    }
    private func snapshot(_ draft: ProjectEditDraft) -> ProjectNodePhotoRemoval { .init(draft: draft, chapterID: "chapter", nodeID: "node") }
    func testExactSlotRemovalPreservesOtherBytesFieldsOrderAndDuplicateReferences() throws {
        let raw = "fixture://é,fixture://e\u{301},fixture://é,opaque%2Cref", original = draft(raw), captured = snapshot(original)
        XCTAssertNil(captured.reason); XCTAssertEqual(captured.photos.map(\.id), [0, 1, 2, 3])
        let next = try captured.applying(removing: 2, to: original)
        var expected = original; expected.chapters[0].nodes[0].imgUrl = "fixture://é,fixture://e\u{301},opaque%2Cref"
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(captured.photos[0].reference.utf8.map { $0 }, Array("fixture://é".utf8))
        XCTAssertEqual(captured.photos[1].reference.utf8.map { $0 }, Array("fixture://e\u{301}".utf8))
    }
    func testLiteralCommaBeforeCombiningMarksOrVariationSelectorsStillSeparatesExactSlots() throws {
        for suffix in ["\u{301}b", "\u{FE0F}b", "\u{20E3}"] {
            let original = draft("a," + suffix + ",c"), captured = snapshot(original)
            XCTAssertNil(captured.reason); XCTAssertEqual(captured.photos.count, 3)
            XCTAssertEqual(Array(captured.photos[1].reference.utf8), Array(suffix.utf8))
            for (slot, expected) in [(0, suffix + ",c"), (1, "a,c"), (2, "a," + suffix)] {
                XCTAssertEqual(Array(try captured.applying(removing: slot, to: original).chapters[0].nodes[0].imgUrl.utf8), Array(expected.utf8))
            }
        }
        for raw in [",\u{301}", "a,,\u{FE0F}"] { XCTAssertEqual(snapshot(draft(raw)).reason, .unsupported) }
    }
    func testFirstMiddleAndLastSlotOnlyRemoveTheirOwnDelimiter() throws {
        let original = draft("a,b,c"), captured = snapshot(original)
        for (slot, expected) in [(0, "b,c"), (1, "a,c"), (2, "a,b")] {
            XCTAssertEqual(try captured.applying(removing: slot, to: original).chapters[0].nodes[0].imgUrl, expected)
        }
    }
    func testNoSelectionAndEmptyListRemainExactNoOps() throws {
        for raw in ["", "fixture://a,fixture://a", "fixture://e\u{301}"] {
            let original = draft(raw), captured = snapshot(original)
            XCTAssertNil(captured.reason)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(try captured.applying(removing: nil, to: original)), ProjectEditPendingMaterials.exactData(original))
        }
        let empty = draft(""); XCTAssertThrowsError(try snapshot(empty).applying(removing: 0, to: empty))
    }
    func testRemovingLastPhotoUsesExistingFullReplacementPayloadClearContract() throws {
        for pro in [false, true] {
            var original = draft("fixture://only")
            if pro { original.preserved["publishMode"] = .string("pro") }
            let next = try snapshot(original).applying(removing: 0, to: original)
            XCTAssertEqual(next.chapters[0].nodes[0].imgUrl, "")
            let payload = try ProjectEditContract.payload(next, topicID: nil, scope: .full)
            let row = try XCTUnwrap(payload["chapters"]?.array?.first?.object?["nodes"]?.array?.first?.object)
            XCTAssertNil(row["imgUrl"])
            XCTAssertEqual(row["name"], .string(original.chapters[0].nodes[0].name))
            XCTAssertEqual(row["templateId"], .number(41))
        }
    }
    func testMalformedOrUnsupportedSavedCSVIsReadOnlyWithoutFilteringTrimmingOrTruncation() {
        for raw in [",a", "a,", "a,,b", " a,b", "a, b", "a\nb", "[\"a\",\"b\"]", "{\"image\":\"a\"}", (1...10).map(String.init).joined(separator: ","), String(repeating: "a", count: 96 * 1024 + 1)] {
            let original = draft(raw), captured = snapshot(original)
            XCTAssertEqual(captured.reason, .unsupported); XCTAssertTrue(captured.photos.isEmpty)
            XCTAssertThrowsError(try captured.applying(removing: 0, to: original))
            XCTAssertEqual(Array(original.chapters[0].nodes[0].imgUrl.utf8), Array(raw.utf8))
        }
    }
    func testNinePhotosAreSupportedAndInvalidIndicesNeverMutateAnything() throws {
        let original = draft((1...9).map { "photo\($0)" }.joined(separator: ",")), captured = snapshot(original)
        XCTAssertNil(captured.reason); XCTAssertEqual(captured.photos.count, 9)
        XCTAssertThrowsError(try captured.applying(removing: -1, to: original)); XCTAssertThrowsError(try captured.applying(removing: 9, to: original))
        XCTAssertEqual(try captured.applying(removing: 8, to: original).chapters[0].nodes[0].imgUrl, (1...8).map { "photo\($0)" }.joined(separator: ","))
    }
    func testDuplicateAndCanonicalEquivalentChapterNodeOrPendingIdentityIsUnavailable() {
        for kind in ["chapter", "node", "pending", "bytes"] {
            var original = draft("a,b")
            switch kind {
            case "chapter": original.chapters.append(original.chapters[0])
            case "node": original.chapters[0].nodes.append(original.chapters[0].nodes[0])
            case "pending": original.pendingMaterials = [.init(node: original.chapters[0].nodes[0])]
            default: original.chapters[0].nodes[0].id = "é"
            }
            let captured = kind == "bytes" ? ProjectNodePhotoRemoval(draft: original, chapterID: "chapter", nodeID: "e\u{301}") : snapshot(original)
            XCTAssertEqual(captured.reason, .identity)
        }
    }
    func testChangedPhotosDeletedTargetReorderedNodesAndOtherDraftChangesRejectOldSnapshot() throws {
        let original = draft("a,b"), captured = snapshot(original)
        for kind in ["photos", "delete", "reorder", "metadata", "chapter"] {
            var changed = original
            switch kind {
            case "photos": changed.chapters[0].nodes[0].imgUrl = "b,a"
            case "delete": changed.chapters[0].nodes = []
            case "reorder": var other = ProjectEditNode(); other.id = "second"; changed.chapters[0].nodes.insert(other, at: 0)
            case "metadata": changed.chapters[0].nodes[0].localMetadata["unknown"] = .string("changed")
            default: changed.chapters[0].id = "different"
            }
            XCTAssertFalse(captured.isCurrent(in: changed)); XCTAssertThrowsError(try captured.applying(removing: 0, to: changed))
        }
    }
}

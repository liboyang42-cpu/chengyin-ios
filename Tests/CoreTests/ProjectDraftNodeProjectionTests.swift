import XCTest
@testable import QuestifyCore

final class ProjectDraftNodeProjectionTests: XCTestCase {
    private func draft() -> ProjectEditDraft {
        var d = ProjectEditSyntheticFixtures.draft(); d.chapters[0].id = "first"; d.chapters[0].name = "Chapter e\u{301}"
        d.chapters[0].nodes[0].id = "a"; d.chapters[0].nodes[0].name = "Node é"; d.chapters[0].nodes[0].address = "  Raw address\n"
        var second = ProjectEditChapter(); second.id = "second"; second.name = "Chapter 2"
        var node = ProjectEditNode(); node.id = "b"; node.name = "Node B"; second.nodes = [node]; d.chapters.append(second)
        return d
    }
    func testAllPlacedNodesRetainExactChapterAndNodeSourceOrder() {
        let d = draft(), p = ProjectDraftNodeProjection(draft: d)
        XCTAssertNil(p.reason); XCTAssertEqual(p.rows.map(\.nodeID), ["a", "b"]); XCTAssertEqual(p.rows.map(\.order), [1, 2]); XCTAssertEqual(p.rows.map(\.chapterOrder), [1, 2])
        XCTAssertEqual(p.rows.map(\.chapterID), ["first", "second"])
    }
    func testRawDisplayTextCoordinatesAndUnknownFieldsRemainByteExact() {
        var d = draft(); d.chapters[0].nodes[0].longitude = " 121.5000 "; d.chapters[0].nodes[0].latitude = "31.230400"; d.chapters[0].nodes[0].localMetadata["extra"] = .string("e\u{301}")
        let before = ProjectEditPendingMaterials.exactData(d), p = ProjectDraftNodeProjection(draft: d), row = p.rows[0]
        XCTAssertEqual(Array(row.longitude.utf8), Array(" 121.5000 ".utf8)); XCTAssertEqual(Array(row.latitude.utf8), Array("31.230400".utf8))
        XCTAssertEqual(Array(row.chapterName.utf8), Array(d.chapters[0].name.utf8)); XCTAssertEqual(Array(row.address.utf8), Array("  Raw address\n".utf8))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(d), before)
    }
    func testValidNumericCoordinatesStillHaveUnverifiedDatum() {
        for pair in [("121.5", "31.2"), ("-74", "40"), ("180", "90"), ("-180", "-90")] {
            var d = draft(); d.chapters[0].nodes[0].longitude = pair.0; d.chapters[0].nodes[0].latitude = pair.1
            XCTAssertEqual(ProjectDraftNodeProjection(draft: d).rows[0].coordinates, .datumUnverified)
        }
    }
    func testMissingPartialNonfiniteOutOfRangeAndZeroAreNotFabricatedLocations() {
        let cases: [(String, String, ProjectDraftNodeProjection.CoordinateState)] = [("", "", .missing), (" \n", "", .missing), ("1", "", .invalid), ("", "1", .invalid), ("NaN", "2", .invalid), ("inf", "2", .invalid), ("2", "-inf", .invalid), ("181", "1", .invalid), ("1", "91", .invalid), ("0", "10", .zero), ("10", "-0", .zero)]
        for (longitude, latitude, state) in cases {
            var d = draft(); d.chapters[0].nodes[0].longitude = longitude; d.chapters[0].nodes[0].latitude = latitude
            let p = ProjectDraftNodeProjection(draft: d); XCTAssertEqual(p.rows[0].coordinates, state); XCTAssertEqual(p.rows.count, 2)
        }
    }
    func testInvalidCoordinatesRemainInOrderedListAndCanResolveExistingEditorTarget() {
        let d = draft(), p = ProjectDraftNodeProjection(draft: d)
        XCTAssertEqual(p.rows[1].coordinates, .missing)
        XCTAssertEqual(p.resolve(.init(chapterID: "second", nodeID: "b"), in: d)?.nodeID, "b")
    }
    func testPendingMaterialsAreExcludedWithoutMovingOrNumberingThem() {
        var d = draft(); var pending = ProjectEditNode(); pending.id = "pending"; pending.name = "Unplaced"; d.pendingMaterials = [.init(node: pending)]
        let p = ProjectDraftNodeProjection(draft: d)
        XCTAssertEqual(p.excludedPendingCount, 1); XCTAssertEqual(p.rows.map(\.nodeID), ["a", "b"]); XCTAssertNil(p.row(.init(chapterID: "first", nodeID: "pending")))
    }
    func testEmptyDraftAndEmptyChapterAreTrueEmptyStates() {
        var d = draft(); d.chapters = []; let empty = ProjectDraftNodeProjection(draft: d)
        XCTAssertNil(empty.reason); XCTAssertTrue(empty.rows.isEmpty); XCTAssertEqual(empty.chapterCount, 0)
        var chapter = ProjectEditChapter(); chapter.id = "empty"; d.chapters = [chapter]
        XCTAssertTrue(ProjectDraftNodeProjection(draft: d).rows.isEmpty); XCTAssertEqual(ProjectDraftNodeProjection(draft: d).chapterCount, 1)
    }
    func testDuplicateEmptyAndCanonicalAliasedIdentitiesFailClosed() {
        for kind in ["chapter", "node", "pending", "empty", "canonicalNode", "canonicalChapter"] {
            var d = draft()
            switch kind {
            case "chapter": d.chapters[1].id = d.chapters[0].id
            case "node": d.chapters[1].nodes[0].id = "a"
            case "pending": d.pendingMaterials = [.init(node: d.chapters[0].nodes[0])]
            case "empty": d.chapters[0].nodes[0].id = ""
            case "canonicalNode": d.chapters[0].nodes[0].id = "é"; d.chapters[1].nodes[0].id = "e\u{301}"
            default: d.chapters[0].id = "é"; d.chapters[1].id = "e\u{301}"
            }
            let p = ProjectDraftNodeProjection(draft: d); XCTAssertEqual(p.reason, .identity); XCTAssertTrue(p.rows.isEmpty)
        }
    }
    func testExactKeyLookupDoesNotAliasUnicodeOrWrongChapter() {
        var d = draft(); d.chapters[0].nodes[0].id = "é"; let p = ProjectDraftNodeProjection(draft: d)
        XCTAssertNotNil(p.resolve(.init(chapterID: "first", nodeID: "é"), in: d))
        XCTAssertNil(p.resolve(.init(chapterID: "first", nodeID: "e\u{301}"), in: d)); XCTAssertNil(p.resolve(.init(chapterID: "second", nodeID: "é"), in: d))
    }
    func testAnyDraftChangeRejectsOldRenderedProjection() {
        let d = draft(), p = ProjectDraftNodeProjection(draft: d), key = p.rows[0].id
        for kind in ["text", "order", "delete", "coordinate", "metadata"] {
            var changed = d
            switch kind {
            case "text": changed.chapters[0].nodes[0].name += "!"
            case "order": changed.chapters.reverse()
            case "delete": changed.chapters[0].nodes = []
            case "coordinate": changed.chapters[0].nodes[0].latitude = "1"
            default: changed.preserved["unknown"] = .string("changed")
            }
            XCTAssertFalse(p.isCurrent(in: changed)); XCTAssertNil(p.resolve(key, in: changed))
        }
    }
    func testBranchGraphRemainsOpaqueAndDoesNotChangeSourceOrder() {
        var d = draft(); d.preserved["routeMode"] = .string("BRANCH_GRAPH"); d.preserved["routeGraphJson"] = .string(" unknown raw e\u{301} ")
        let before = ProjectEditPendingMaterials.exactData(d), p = ProjectDraftNodeProjection(draft: d)
        XCTAssertEqual(p.rows.map(\.nodeID), ["a", "b"]); XCTAssertEqual(ProjectEditPendingMaterials.exactData(d), before)
    }
    func testBoundedProjectionDoesNotTruncateLargeDrafts() {
        var d = draft(); d.chapters = Array(repeating: d.chapters[0], count: 129)
        XCTAssertEqual(ProjectDraftNodeProjection(draft: d).reason, .limit)
        d = draft(); d.chapters[0].nodes = Array(repeating: d.chapters[0].nodes[0], count: 513)
        let p = ProjectDraftNodeProjection(draft: d); XCTAssertEqual(p.reason, .limit); XCTAssertTrue(p.rows.isEmpty)
    }
}

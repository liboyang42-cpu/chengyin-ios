import XCTest
@testable import QuestifyCore

final class ProjectNodePlaceSelectionTests: XCTestCase {
    private func draft() -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].id = "chapter"; draft.chapters[0].nodes[0].id = "node"
        return draft
    }
    private func poi(_ json: String = #"{"poiId":7,"name":"Place label","lat":31.25,"lng":121.5,"merchantId":99,"templateId":88}"#) throws -> SearchMapCityNode {
        try JSONDecoder().decode(SearchMapCityNode.self, from: Data(json.utf8))
    }
    func testChosenPOIChangesOnlyCoordinatesAndAddressPreservingNameAndMetadata() throws {
        let old = draft(), row = try poi(), capture = ProjectNodePlaceSelection(draft: old, chapterID: "chapter", nodeID: "node")
        var expected = old; expected.chapters[0].nodes[0].latitude = "31.25"; expected.chapters[0].nodes[0].longitude = "121.5"; expected.chapters[0].nodes[0].address = "Place label"
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try capture.applying(row, to: old)), ProjectEditPendingMaterials.exactData(expected))
    }
    func testOnlyEmptyNameUsesChosenLabel() throws {
        for name in ["", " ", "Keep me"] {
            var old = draft(); old.chapters[0].nodes[0].name = name
            let capture = ProjectNodePlaceSelection(draft: old, chapterID: "chapter", nodeID: "node")
            XCTAssertEqual(try capture.applying(poi(), to: old).chapters[0].nodes[0].name, name.isEmpty ? "Place label" : name)
        }
    }
    func testSameCoordinateRetainsOriginalRawRepresentation() throws {
        var old = draft(); old.chapters[0].nodes[0].latitude = "031.2500"; old.chapters[0].nodes[0].longitude = "121.500"; old.chapters[0].nodes[0].address = "Place label"
        let c = ProjectNodePlaceSelection(draft: old, chapterID: "chapter", nodeID: "node")
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try c.applying(poi(), to: old)), ProjectEditPendingMaterials.exactData(old))
    }
    func testMissingNameOrInvalidCoordinatesCannotApply() throws {
        let old = draft(), c = ProjectNodePlaceSelection(draft: old, chapterID: "chapter", nodeID: "node")
        for json in [#"{"poiId":7,"lat":31,"lng":121}"#, #"{"poiId":7,"name":" ","lat":31,"lng":121}"#, #"{"poiId":7,"name":"x","lat":0,"lng":121}"#, #"{"poiId":7,"name":"x","lat":91,"lng":121}"#, #"{"poiId":7,"name":"x"}"#] {
            let row = try poi(json); XCTAssertFalse(ProjectNodePlaceSelection.permits(row)); XCTAssertThrowsError(try c.applying(row, to: old))
        }
    }
    func testDuplicatePendingAndLocationFreeTargetsUnavailable() {
        var old = draft(); old.pendingMaterials = [.init(node: old.chapters[0].nodes[0])]
        XCTAssertFalse(ProjectNodePlaceSelection(draft: old, chapterID: "chapter", nodeID: "node").available)
        old = draft(); old.chapters[0].nodes.append(old.chapters[0].nodes[0])
        XCTAssertFalse(ProjectNodePlaceSelection(draft: old, chapterID: "chapter", nodeID: "node").available)
        old = draft(); var block = ProjectEditBlock(kind: .node, nodeID: "node"); block.sourceFields = ["locationRequired": .bool(false)]; old.chapters[0].blocks = [block]
        XCTAssertFalse(ProjectNodePlaceSelection(draft: old, chapterID: "chapter", nodeID: "node").available)
    }
    func testStaleWholeDraftAndWrongExactIDReject() throws {
        let old = draft(), c = ProjectNodePlaceSelection(draft: old, chapterID: "chapter", nodeID: "node")
        var next = old; next.name += "!"; XCTAssertThrowsError(try c.applying(poi(), to: next))
        XCTAssertFalse(ProjectNodePlaceSelection(draft: old, chapterID: "CHAPTER", nodeID: "node").available)
    }
    func testSharedLocationHelperPreservesStagedCandidateIdentityAndUnknownMetadata() throws {
        var node = draft().chapters[0].nodes[0]; node.id = "pending-only"; node.localMetadata["future"] = .object(["value": .string("retain")])
        var expected = node; expected.latitude = "31.25"; expected.longitude = "121.5"; expected.address = "Place label"
        let next = try ProjectNodePlaceSelection.replacingLocation(of: node, with: poi())
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected)); XCTAssertEqual(node.id, "pending-only")
    }

}

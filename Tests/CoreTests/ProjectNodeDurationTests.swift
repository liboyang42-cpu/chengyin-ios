import XCTest
@testable import QuestifyCore

final class ProjectNodeDurationTests: XCTestCase {
    private func draft() -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft(); value.chapters[0].id = "chapter"; value.chapters[0].nodes[0].id = "node"
        value.chapters[0].nodes[0].nodeTime = 30; value.chapters[0].nodes[0].localMetadata["future"] = .string(" e\u{301} "); return value
    }
    private func capture(_ value: ProjectEditDraft) -> ProjectNodeDuration { .init(draft: value, chapterID: "chapter", nodeID: "node") }
    func testASCIIIntegerMinutesIncludeZeroAndJavaIntegerMaximum() {
        for (text, expected) in [("0", 0), ("30", 30), ("00030", 30), ("2147483647", 2147483647)] { XCTAssertEqual(ProjectNodeDuration.parse(text), expected) }
        for text in ["", " ", " 30", "30 ", "-1", "+1", "1.0", "1e2", "１２", "١٢", "2147483648", "9223372036854775807", "00000000000", "1\n"] { XCTAssertNil(ProjectNodeDuration.parse(text), text) }
    }
    func testOnlyNodeTimeChangesWithMinutesUnscaled() throws {
        let value = draft(); var expected = value; expected.chapters[0].nodes[0].nodeTime = 90
        let next = try capture(value).replacing(with: "90", in: value)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
    }
    func testSameValueIncludingLeadingZerosIsExactNoOp() throws {
        let value = draft()
        for text in ["30", "00030"] { XCTAssertEqual(ProjectEditPendingMaterials.exactData(try capture(value).replacing(with: text, in: value)), ProjectEditPendingMaterials.exactData(value)) }
    }
    func testLegacyInvalidImportedValuePreservedUntilExplicitValidReplacement() throws {
        for minutes in [-1, Int.max] {
            var value = draft(); value.chapters[0].nodes[0].nodeTime = minutes; let snapshot = capture(value)
            XCTAssertTrue(snapshot.available); XCTAssertEqual(snapshot.minutes, minutes)
            XCTAssertThrowsError(try snapshot.replacing(with: String(minutes), in: value))
            let next = try snapshot.replacing(with: "45", in: value); XCTAssertEqual(next.chapters[0].nodes[0].nodeTime, 45)
            XCTAssertEqual(value.chapters[0].nodes[0].nodeTime, minutes)
        }
    }
    func testStepperCannotOverflowOrInventReplacementForInvalidLegacyValue() {
        XCTAssertEqual(ProjectNodeDuration.adjusted(30, by: 1), 31); XCTAssertEqual(ProjectNodeDuration.adjusted(30, by: -1), 29)
        XCTAssertNil(ProjectNodeDuration.adjusted(0, by: -1)); XCTAssertNil(ProjectNodeDuration.adjusted(2147483647, by: 1))
        XCTAssertEqual(ProjectNodeDuration.adjusted(2147483647, by: -1), 2147483646)
        for value in [-1, Int.min, Int.max] { for delta in [-1, 1] { XCTAssertNil(ProjectNodeDuration.adjusted(value, by: delta)) } }
        XCTAssertNil(ProjectNodeDuration.adjusted(30, by: 2))
    }
    func testStaleUnrelatedEditNodeChangeDeletionAndReorderReject() {
        let value = draft(), snapshot = capture(value)
        for kind in ["other", "time", "delete", "id"] {
            var changed = value
            switch kind { case "other": changed.name += "!"; case "time": changed.chapters[0].nodes[0].nodeTime = 31; case "delete": changed.chapters[0].nodes = []; default: changed.chapters[0].nodes[0].id = "other" }
            XCTAssertFalse(snapshot.isCurrent(in: changed)); XCTAssertThrowsError(try snapshot.replacing(with: "90", in: changed))
        }
    }
    func testDuplicateAndCanonicalAliasIdentityReject() {
        var value = draft(); value.chapters.append(value.chapters[0]); XCTAssertFalse(capture(value).available)
        value = draft(); value.chapters[0].nodes.append(value.chapters[0].nodes[0]); XCTAssertFalse(capture(value).available)
        value = draft(); value.chapters[0].nodes[0].id = "é"
        XCTAssertFalse(ProjectNodeDuration(draft: value, chapterID: "chapter", nodeID: "e\u{301}").available)
    }
}

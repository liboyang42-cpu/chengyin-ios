import XCTest
@testable import QuestifyCore

/// BK-NARRATIVE (A03 SOURCE_READY) frozen fixture. Native renders the authoritative ending read;
/// it never rebuilds an ending from current chapters or reorders the existing selection rules.
final class ProjectNarrativeEndingCompatibilityTests: XCTestCase {
    private func payload(_ draft: ProjectEditDraft) throws -> [String: ProjectEditJSON] {
        try ProjectEditContract.payload(draft, topicID: nil, scope: .full)
    }
    private func endingDraft(_ ending: [String: ProjectEditJSON]) -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft()
        var fallback = ProjectEditChapter(); fallback.description = "Fallback"; fallback.preserved["ending"] = .object(["fallback": .bool(true)])
        var chapter = ProjectEditChapter(); chapter.description = "Finish"; chapter.preserved["ending"] = .object(ending)
        draft.chapters += [chapter, fallback]
        return draft
    }
    private let when: ProjectEditJSON = .array([.object(["op": .string("HAS_TAG"), "value": .string("tag.brave")])])

    func testPresentFallbackMustBeJSONBooleanBeforeAnyDispatch() throws {
        XCTAssertNoThrow(try payload(endingDraft(["fallback": .bool(false), "when": when])))
        XCTAssertNoThrow(try payload(endingDraft(["when": when])))
        for invalid: ProjectEditJSON in [.string("true"), .number(1), .null, .object([:])] {
            XCTAssertThrowsError(try payload(endingDraft(["fallback": invalid, "when": when])), "\(invalid)")
        }
    }

    func testLegacyEndingRowsKeepMiniProgramStrictTrueSemantics() throws {
        let rows: [ProjectEditJSON] = [
            .object(["code": .string("a"), "title": .string("Old title"), "fallback": .string("true"), "when": when]),
            .object(["code": .string("b"), "title": .string("Null"), "fallback": .null, "when": when]),
            .object(["code": .string("c"), "title": .string("Numeric"), "fallback": .number(1), "when": when]),
            .object(["code": .string("d"), "title": .string("Explicit"), "fallback": .bool(false), "when": when]),
            .object(["code": .string("e"), "title": .string("Home"), "fallback": .bool(true)])]
        var draft = ProjectEditSyntheticFixtures.draft()
        try ProjectEditRichStoryContract.attachEndings(rows, draft: &draft)
        let endings = draft.chapters.suffix(5).map { $0.preserved["ending"]?.object ?? [:] }
        XCTAssertEqual(endings.map { $0["fallback"] }, [nil, nil, nil, .bool(false), .bool(true)])
        XCTAssertTrue(endings.prefix(4).allSatisfy { $0["when"] == when })
        // Order is the stored array order; first-hit and priority rules stay server-owned.
        XCTAssertEqual(draft.chapters.suffix(5).map(\.name), ["Old title", "Null", "Numeric", "Explicit", "Home"])
        let sent = try XCTUnwrap(payload(draft)["chapters"]?.array).compactMap { $0.object?["ending"]?.object }
        XCTAssertTrue(sent.allSatisfy { $0["fallback"] == nil || $0["fallback"] == .bool(true) || $0["fallback"] == .bool(false) })
        XCTAssertEqual(sent.filter { $0["fallback"] == .bool(true) }.count, 1)
    }

    private func ending(_ chapter: String?) throws -> JourneyEndingDocument {
        let chapterField = chapter.map { #","chapter":"# + $0 } ?? ""
        let body = #"{"code":200,"data":{"title":"Old title","summary":"Frozen summary","epilogues":[],"exhibits":[],"costs":[],"badge":null,"found":1,"total":2"# + chapterField + "}}"
        return try JourneyEndingDocument(JSONDecoder().decode(PlayWireValue.self, from: Data(body.utf8))["data"])
    }

    func testFrozenEndingChapterIsRenderedVerbatimForOldSessions() throws {
        let value = try ending(#"{"id":11,"name":"old title","atmospherePreset":null,"audioUrl":"","blocks":[{"type":"text","content":"Frozen"}]}"#)
        XCTAssertEqual(value.chapter["name"], .string("old title")); XCTAssertEqual(value.chapter["id"], .integer(11))
        XCTAssertEqual(value.title, "Old title"); XCTAssertEqual(value.summary, "Frozen summary")
    }

    func testMissingFrozenChapterAndLegacySessionDegradeToTitleSummaryOnly() throws {
        for raw in ["null", nil] {
            let value = try ending(raw)
            XCTAssertEqual(value.chapter, .null); XCTAssertNil(value.chapter.object)
            XCTAssertEqual(value.title, "Old title"); XCTAssertEqual(value.summary, "Frozen summary")
        }
        for malformed in [#""chapter text""#, "[]", "1"] { XCTAssertThrowsError(try ending(malformed)) }
    }
}

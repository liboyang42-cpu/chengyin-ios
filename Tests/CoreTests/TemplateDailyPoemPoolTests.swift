import XCTest
@testable import QuestifyCore

final class TemplateDailyPoemPoolTests: XCTestCase {
    private func fixture(_ poems: [[String]] = []) -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(.dailySign, true)
        draft.set("dailySign", "signer", .string("Author")); draft.set("dailySign", "poems", .array(poems.map { .array($0.map { .string($0) }) })); return draft
    }
    private func apply(_ edit: TemplateDailyPoemPool.Edit, pool: inout TemplateDailyPoemPool, draft: inout TemplateAdvancedDraft) throws {
        let update = try XCTUnwrap(pool.applying(edit, to: draft)); pool = update.pool; draft = update.draft
    }
    func testOpeningPreservesStoredDataAndJoinsRawLinesWithoutTrimming() {
        let draft = fixture([[" first ", "", " second"]]), before = draft, pool = TemplateDailyPoemPool(draft)
        XCTAssertTrue(pool.isSupported); XCTAssertEqual(pool.rows[0].text, " first \n\n second"); XCTAssertEqual(draft, before)
    }
    func testAddBlankPoemUsesEmptyCanonicalArrayAndStableLocalIdentity() throws {
        var draft = fixture(), pool = TemplateDailyPoemPool(draft); try apply(.add, pool: &pool, draft: &draft)
        XCTAssertEqual(pool.rows[0].text, ""); XCTAssertEqual(draft.value["dailySign"]?.object?["poems"], .array([.array([])]))
        let id = pool.rows[0].id; try apply(.text(id, "First\nSecond\n"), pool: &pool, draft: &draft)
        XCTAssertEqual(pool.rows[0].id, id); XCTAssertEqual(pool.rows[0].text, "First\nSecond\n")
    }
    func testWholePasteNormalizesLinesButKeepsExactRawInput() throws {
        var draft = fixture([[]]), pool = TemplateDailyPoemPool(draft)
        let input = "  First \r\n\nSecond  \n\t\nThird\n"
        try apply(.text(pool.rows[0].id, input), pool: &pool, draft: &draft)
        XCTAssertEqual(pool.rows[0].text, input)
        XCTAssertEqual(draft.value["dailySign"]?.object?["poems"], .array([.array([.string("First"), .string("Second"), .string("Third")])]))
    }
    func testRawOnlyNewlinesChangeEditorEvenWhenCanonicalDraftIsIdentical() throws {
        var draft = fixture([["First"]]), pool = TemplateDailyPoemPool(draft); let before = draft
        try apply(.text(pool.rows[0].id, "First\n\n"), pool: &pool, draft: &draft)
        XCTAssertEqual(draft, before); XCTAssertEqual(pool.rows[0].text, "First\n\n"); XCTAssertTrue(pool.isCurrent(draft))
    }
    func testEachExplicitActionRebuildsTheWholePoolLikeMini() throws {
        var draft = fixture([[" first "], [" second "]]), pool = TemplateDailyPoemPool(draft)
        try apply(.add, pool: &pool, draft: &draft)
        XCTAssertEqual(pool.rows[0].text, " first ")
        XCTAssertEqual(draft.value["dailySign"]?.object?["poems"], .array([.array([.string("first")]), .array([.string("second")]), .array([])]))
    }
    func testDeleteTargetsOccurrenceByIDAndAllowsAnEmptyPool() throws {
        var draft = fixture([["Same"], ["Same"]]), pool = TemplateDailyPoemPool(draft)
        let firstID = pool.rows[0].id, secondID = pool.rows[1].id
        try apply(.remove(firstID), pool: &pool, draft: &draft); XCTAssertEqual(pool.rows.map(\.id), [secondID])
        try apply(.remove(secondID), pool: &pool, draft: &draft); XCTAssertTrue(pool.rows.isEmpty)
        XCTAssertEqual(draft.value["dailySign"]?.object?["poems"], .array([])); XCTAssertFalse(draft.creatorIssues(.dailySign).isEmpty)
        XCTAssertNil(pool.applying(.text(firstID, "stale"), to: draft))
    }
    func testExistingPoolCapAndMalformedLegacyFallback() {
        let draft = fixture(Array(repeating: ["Line"], count: 60)), pool = TemplateDailyPoemPool(draft)
        XCTAssertFalse(pool.canAdd); XCTAssertNil(pool.applying(.add, to: draft))
        for raw in [TemplateAuthoringJSON.string("legacy"), .array([.string("scalar poem")]), .array([.array([.number(3)])]), .array(Array(repeating: .array([.string("Line")]), count: 61))] {
            var malformed = fixture(); malformed.set("dailySign", "poems", raw)
            XCTAssertFalse(TemplateDailyPoemPool(malformed).isSupported)
        }
    }
    func testExistingLineAndLengthValidationStillRejectsInvalidTextWithoutTruncating() throws {
        var draft = fixture([[]]), pool = TemplateDailyPoemPool(draft)
        for text in ["1\n2\n3\n4\n5", String(repeating: "a", count: 25), "\n \n"] {
            try apply(.text(pool.rows[0].id, text), pool: &pool, draft: &draft)
            XCTAssertEqual(pool.rows[0].text, text); XCTAssertFalse(draft.creatorIssues(.dailySign).isEmpty); XCTAssertThrowsError(try draft.serialize())
        }
    }
    func testUnknownFieldsSignerSealAndOtherFamiliesArePreserved() throws {
        var draft = fixture([["Line"]]); draft.set("dailySign", "future", .string("keep")); draft.set("dailySign", "sealText", .string("Seal")); draft.set("timer", "enabled", .bool(true))
        var pool = TemplateDailyPoemPool(draft); let before = draft
        try apply(.text(pool.rows[0].id, "Edited"), pool: &pool, draft: &draft)
        for key in ["signer", "sealText", "future"] { XCTAssertEqual(draft.value["dailySign"]?.object?[key], before.value["dailySign"]?.object?[key]) }
        XCTAssertEqual(draft.value["timer"], before.value["timer"]); XCTAssertThrowsError(try draft.serialize())
    }
    func testExternalSectionChangeAndDisabledFamilyRejectStaleEdit() {
        let original = fixture([["Line"]]), pool = TemplateDailyPoemPool(original)
        var changed = original; changed.set("dailySign", "signer", .string("Other")); XCTAssertNil(pool.applying(.remove(pool.rows[0].id), to: changed))
        changed = original; changed.setCreatorEnabled(.dailySign, false); XCTAssertFalse(TemplateDailyPoemPool(changed).canEdit)
    }
    func testExactSnapshotDistinguishesCanonicallyEquivalentUnicodeBytes() {
        let draft = fixture([["\u{00E9}"]]), pool = TemplateDailyPoemPool(draft)
        let changed = fixture([["e\u{0301}"]])
        XCTAssertFalse(pool.isCurrent(changed)); XCTAssertNil(pool.applying(.text(pool.rows[0].id, "New"), to: changed))
    }
    func testValidFourLinePoemSerializesAndLocalRestoreReopensCanonicalText() throws {
        var draft = fixture([[]]), pool = TemplateDailyPoemPool(draft)
        try apply(.text(pool.rows[0].id, " First \n\nSecond\nThird\nFourth\n"), pool: &pool, draft: &draft)
        XCTAssertTrue(draft.creatorIssues(.dailySign).isEmpty)
        let serialized = try TemplateAdvancedDraft(raw: draft.serialize()); XCTAssertEqual(TemplateDailyPoemPool(serialized).rows[0].text, "First\nSecond\nThird\nFourth")
        var local = TemplateAuthoringDraft(title: "Poems"); local.advanced = draft
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(local))
        XCTAssertEqual(restored, local); XCTAssertEqual(TemplateDailyPoemPool(restored.advanced).rows[0].text, "First\nSecond\nThird\nFourth")
    }
}

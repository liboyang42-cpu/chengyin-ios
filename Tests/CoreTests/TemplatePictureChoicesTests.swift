import XCTest
@testable import QuestifyCore

final class TemplatePictureChoicesTests: XCTestCase {
    private func fixture() -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(.pricePair, true); draft.set("pricePair", "title", .string("Find our drink"))
        for index in 0..<3 {
            draft.setCreatorValue(.pricePair, path: [.field("items"), .index(index), .field("id")], entry: .string("items_\(index + 1)"))
            draft.setCreatorValue(.pricePair, path: [.field("items"), .index(index), .field("name")], entry: .string("Picture \(index + 1)"))
            draft.setCreatorValue(.pricePair, path: [.field("items"), .index(index), .field("correct")], entry: .bool(false))
        }
        return draft
    }
    private func apply(_ edit: TemplatePictureChoices.Edit, choices: inout TemplatePictureChoices, draft: inout TemplateAdvancedDraft) throws {
        let update = try XCTUnwrap(choices.applying(edit, to: draft)); choices = update.choices; draft = update.draft
    }
    func testOpeningPreservesMissingOrMultipleAnswersUntilExplicitSelection() {
        var draft = fixture(); draft.setCreatorValue(.pricePair, path: [.field("items"), .index(0), .field("correct")], entry: .bool(true)); draft.setCreatorValue(.pricePair, path: [.field("items"), .index(1), .field("correct")], entry: .bool(true))
        let before = draft, choices = TemplatePictureChoices(draft)
        XCTAssertTrue(choices.isSupported); XCTAssertEqual(choices.correctCount, 2); XCTAssertEqual(draft, before)
    }
    func testSelectionAtomicallySetsExactlyOneAnswerAndRepeatedTapNeverUnsetsIt() throws {
        var draft = fixture(), choices = TemplatePictureChoices(draft); let id = choices.rows[1].id
        try apply(.choose(id), choices: &choices, draft: &draft); XCTAssertEqual(choices.rows.map(\.isCorrect), [false, true, false])
        let before = draft; try apply(.choose(id), choices: &choices, draft: &draft); XCTAssertEqual(draft, before)
        try apply(.choose(choices.rows[2].id), choices: &choices, draft: &draft); XCTAssertEqual(choices.rows.map(\.isCorrect), [false, false, true])
    }
    func testCompleteAddNameAddressSelectRemoveFlowUsesExistingWireShape() throws {
        var draft = fixture(), choices = TemplatePictureChoices(draft); try apply(.add, choices: &choices, draft: &draft)
        let row = try XCTUnwrap(choices.rows.last); XCTAssertEqual(row.wireID, "items_4"); XCTAssertFalse(row.isCorrect)
        try apply(.text(row.id, .name, "Tea"), choices: &choices, draft: &draft); try apply(.text(row.id, .imageURL, "/media/tea.jpg"), choices: &choices, draft: &draft)
        try apply(.choose(row.id), choices: &choices, draft: &draft); XCTAssertTrue(draft.creatorIssues(.pricePair).isEmpty); XCTAssertNoThrow(try draft.serialize())
        try apply(.remove(choices.rows[0].id), choices: &choices, draft: &draft); XCTAssertEqual(choices.rows.count, 3); XCTAssertEqual(choices.rows.last?.imageURL, "/media/tea.jpg"); XCTAssertEqual(choices.correctCount, 1)
    }
    func testRemovingChosenPictureDoesNotInventAnotherAnswerAndAllowsEmptyList() throws {
        var draft = fixture(), choices = TemplatePictureChoices(draft); let id = choices.rows[1].id
        try apply(.choose(id), choices: &choices, draft: &draft); try apply(.remove(id), choices: &choices, draft: &draft)
        XCTAssertEqual(choices.correctCount, 0); XCTAssertFalse(draft.creatorIssues(.pricePair).isEmpty)
        while let row = choices.rows.first { try apply(.remove(row.id), choices: &choices, draft: &draft) }
        XCTAssertTrue(choices.rows.isEmpty); XCTAssertTrue(choices.canAdd); XCTAssertThrowsError(try draft.serialize())
    }
    func testMovingRowsKeepsSelectedAnswerAndDuplicateNamesOccurrenceSpecific() throws {
        var draft = fixture(), choices = TemplatePictureChoices(draft); let id = choices.rows[1].id
        for row in choices.rows { try apply(.text(row.id, .name, "Same"), choices: &choices, draft: &draft) }
        try apply(.choose(id), choices: &choices, draft: &draft); let wireID = choices.rows[1].wireID
        try apply(.move(id, -1), choices: &choices, draft: &draft); XCTAssertEqual(choices.rows[0].id, id); XCTAssertEqual(choices.rows[0].wireID, wireID); XCTAssertTrue(choices.rows[0].isCorrect)
        XCTAssertNil(choices.applying(.move(id, -1), to: draft)); XCTAssertNil(choices.applying(.move(id, 2), to: draft))
    }
    func testNativeIDAllocatorAvoidsCollisionsAndCapsAtEight() throws {
        var draft = fixture(), choices = TemplatePictureChoices(draft)
        try apply(.remove(choices.rows[1].id), choices: &choices, draft: &draft); try apply(.add, choices: &choices, draft: &draft)
        XCTAssertEqual(choices.rows.last?.wireID, "items_2")
        while choices.canAdd { try apply(.add, choices: &choices, draft: &draft) }
        XCTAssertEqual(choices.rows.count, 8); XCTAssertEqual(Set(choices.rows.map(\.wireID)).count, 8); XCTAssertNil(choices.applying(.add, to: draft))
    }
    func testMalformedShapesUseFallbackWithoutChangingBytes() {
        for raw in [TemplateAuthoringJSON.string("legacy"), .array([.string("legacy")]), .array([.object(["correct": .string("yes")])]), .array([.object(["imageUrl": .number(9)])])] {
            var draft = fixture(); draft.set("pricePair", "items", raw); let before = draft, choices = TemplatePictureChoices(draft)
            XCTAssertFalse(choices.isSupported); XCTAssertNil(choices.applying(.add, to: draft)); XCTAssertEqual(draft, before)
        }
    }
    func testNameAndAddressValidationDoesNotTruncateOrDownload() throws {
        var draft = fixture(), choices = TemplatePictureChoices(draft); let id = choices.rows[0].id
        try apply(.choose(id), choices: &choices, draft: &draft); try apply(.text(id, .name, String(repeating: "a", count: 33)), choices: &choices, draft: &draft)
        XCTAssertEqual(choices.rows[0].name.count, 33); XCTAssertFalse(draft.creatorIssues(.pricePair).isEmpty)
        try apply(.text(id, .name, "Tea"), choices: &choices, draft: &draft); try apply(.text(id, .imageURL, "http://example.invalid/tea.jpg"), choices: &choices, draft: &draft)
        XCTAssertFalse(draft.creatorIssues(.pricePair).isEmpty); XCTAssertThrowsError(try draft.serialize())
        try apply(.text(id, .imageURL, "https://example.invalid/tea.jpg"), choices: &choices, draft: &draft); XCTAssertTrue(draft.creatorIssues(.pricePair).isEmpty)
    }
    func testUnknownRowFieldsOtherFamiliesAndGameMetadataSurviveSelection() throws {
        var draft = fixture(); draft.setCreatorValue(.pricePair, path: [.field("items"), .index(0), .field("future")], entry: .string("keep")); draft.set("pricePair", "future", .number(7)); draft.set("timer", "enabled", .bool(true))
        let before = draft; var choices = TemplatePictureChoices(draft)
        try apply(.choose(choices.rows[0].id), choices: &choices, draft: &draft)
        for key in ["title", "xp", "maxTries", "future"] { XCTAssertEqual(draft.value["pricePair"]?.object?[key], before.value["pricePair"]?.object?[key]) }
        XCTAssertEqual(draft.value["timer"], before.value["timer"]); XCTAssertEqual(draft.value["pricePair"]?.object?["items"]?.array?.first?.object?["future"], .string("keep"))
    }
    func testStaleSnapshotDisabledFamilyAndRemovedIdentityRejectActions() throws {
        let original = fixture(), old = TemplatePictureChoices(original); var changed = original
        changed.set("pricePair", "title", .string("Other")); XCTAssertNil(old.applying(.choose(old.rows[0].id), to: changed))
        changed = original; changed.setCreatorEnabled(.pricePair, false); XCTAssertFalse(TemplatePictureChoices(changed).canEdit)
        var draft = original, choices = TemplatePictureChoices(draft); let removed = choices.rows[0].id
        try apply(.remove(removed), choices: &choices, draft: &draft); XCTAssertNil(choices.applying(.choose(removed), to: draft)); XCTAssertNil(choices.applying(.text(removed, .name, "Stale"), to: draft))
    }
    func testSnapshotDistinguishesCanonicalUnicodeBytes() throws {
        var draft = fixture(), choices = TemplatePictureChoices(draft); let id = choices.rows[0].id
        try apply(.text(id, .name, "\u{00E9}"), choices: &choices, draft: &draft); let before = choices
        try apply(.text(id, .name, "e\u{0301}"), choices: &choices, draft: &draft); XCTAssertFalse(before.isCurrent(draft)); XCTAssertEqual(Data(choices.rows[0].name.utf8), Data("e\u{0301}".utf8))
    }
    func testExistingRehearsalSerializationAndLocalDraftRoundTripReadTheSameAnswer() throws {
        var draft = fixture(), choices = TemplatePictureChoices(draft); let selected = choices.rows[2]
        try apply(.choose(selected.id), choices: &choices, draft: &draft)
        let decoded = try TemplateAdvancedDraft(raw: draft.serialize()); var rehearsal = TemplateCreatorRehearsal()
        rehearsal.evaluate(.pricePair, draft: decoded, selected: [selected.wireID]); XCTAssertEqual(rehearsal.result, .matched)
        rehearsal.evaluate(.pricePair, draft: decoded, selected: [choices.rows[0].wireID]); XCTAssertEqual(rehearsal.result, .missed)
        var local = TemplateAuthoringDraft(title: "Pictures"); local.advanced = draft
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(local)); XCTAssertEqual(restored.advanced, draft)
        XCTAssertEqual(TemplatePictureChoices(restored.advanced).rows.filter(\.isCorrect).map(\.wireID), [selected.wireID])
    }
}

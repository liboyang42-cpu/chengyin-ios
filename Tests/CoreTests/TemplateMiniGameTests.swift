import XCTest
@testable import QuestifyCore

final class TemplateMiniGameTests: XCTestCase {
    private func valid(_ game: TemplateAdvancedGame) -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.select(game)
        if game.isReasoning {
            draft.set(game.section, "prompt", .string("Arrange these synthetic examples"))
            for field in game == .sort ? ["items"] : game == .match ? ["left","right"] : ["items","bins"] {
                for index in draft.rows(game.section,field).indices { draft.setRow(game.section,field,index:index,key:"label",text:"Label \(field) \(index)") }
            }
        }
        if game == .compass { draft.set(game.section,"bearing",.number(0)) }
        return draft
    }
    private func serialized(_ draft: TemplateAdvancedDraft) throws -> [String:TemplateAuthoringJSON] {
        try JSONDecoder().decode([String:TemplateAuthoringJSON].self,from:Data(draft.serialize().utf8))
    }
    func testNewDefaultsStayDisabledAndCompassHasNoGuessedBearing() {
        let draft = TemplateAdvancedDraft()
        for game in TemplateAdvancedGame.allCases.filter(\.isMiniProgramAddition) { XCTAssertFalse(draft.enabled(game.section)) }
        XCTAssertEqual(draft.value["compass"]?.object?["bearing"],.string(""))
    }
    func testEveryNewGameHasValidEditableBaselineAfterRequiredFieldsAreFilled() {
        for game in TemplateAdvancedGame.allCases.filter(\.isMiniProgramAddition) { XCTAssertTrue(valid(game).issues.isEmpty,game.rawValue) }
    }
    func testEmptyCompassBearingNeverSerializesAsNorth() {
        var draft = TemplateAdvancedDraft(); draft.select(.compass)
        XCTAssertTrue(draft.issues.contains("playkitAuthor.validation.compass.bearing")); XCTAssertThrowsError(try draft.serialize())
        draft.set("compass","bearing",.string("  ")); XCTAssertThrowsError(try draft.serialize())
        draft.set("compass","bearing",.number(0)); XCTAssertTrue(draft.issues.isEmpty)
    }
    func testCompassNumericLimitsAndIntegralBearing() {
        for value in [-1.0,360,0.5,.nan,.infinity] { var draft=valid(.compass);draft.set("compass","bearing",.number(value));XCTAssertFalse(draft.issues.isEmpty) }
        for value in [0.0,359] { var draft=valid(.compass);draft.set("compass","bearing",.number(value));XCTAssertTrue(draft.issues.isEmpty) }
        var draft=valid(.compass);draft.set("compass","tolerance",.number(4));XCTAssertFalse(draft.issues.isEmpty)
        draft=valid(.compass);draft.set("compass","holdSeconds",.number(11));XCTAssertFalse(draft.issues.isEmpty)
    }
    func testCompassAndShoutRewardLimitsAreIndependentOfDisplay() {
        for game in [TemplateAdvancedGame.compass,.shout] {
            for value in [-1.0,1001,1.5] { var draft=valid(game);draft.set(game.section,"xp",.number(value));XCTAssertFalse(draft.issues.isEmpty) }
        }
    }
    func testShoutDurationBounds() {
        for value in [4.0,301] { var draft=valid(.shout);draft.set("shout","seconds",.number(value));XCTAssertFalse(draft.issues.isEmpty) }
        for value in [5.0,300] { var draft=valid(.shout);draft.set("shout","seconds",.number(value));XCTAssertTrue(draft.issues.isEmpty) }
    }
    func testSortDerivesAnswerOrderFromEnteredOrderNotStaleKey() throws {
        var draft=valid(.sort);draft.set("sort","answerOrder",.array([.string("forged")]))
        draft.moveRow("sort","items",from:0,to:2)
        let raw=try serialized(draft), items=draft.rows("sort","items")
        XCTAssertEqual(raw["sort"]?.object?["answerOrder"],.array(items.compactMap{$0.object?["id"]}))
    }
    func testMatchDerivesExactPairsAndRejectsUnequalColumns() throws {
        var draft=valid(.match);draft.set("match","pairs",.array([]))
        let raw=try serialized(draft)
        XCTAssertEqual(raw["match"]?.object?["pairs"],.array([.array([.string("left_1"),.string("right_1")]),.array([.string("left_2"),.string("right_2")])]))
        draft.appendRow("match","left",prefix:"left",maximum:6);XCTAssertTrue(draft.issues.contains("playkitAuthor.validation.match.sameCount"))
    }
    func testReasoningItemCountsHaveSourceBounds() {
        var sort=valid(.sort)
        while sort.rows("sort","items").count < 8 { sort.appendRow("sort","items",prefix:"item",maximum:8) }
        sort.appendRow("sort","items",prefix:"item",maximum:8);XCTAssertEqual(sort.rows("sort","items").count,8)
        sort.set("sort","items",.array(Array(sort.rows("sort","items").prefix(1))));XCTAssertFalse(sort.issues.isEmpty)
    }
    func testIDsCannotDuplicateOrContainInvalidCharacters() {
        var draft=valid(.sort);draft.setRow("sort","items",index:1,key:"id",text:"item_1");XCTAssertFalse(draft.issues.isEmpty)
        draft=valid(.sort);draft.setRow("sort","items",index:0,key:"id",text:"../bad");XCTAssertFalse(draft.issues.isEmpty)
    }
    func testUTF16LengthMatchesServerRatherThanVisibleGraphemeCount() {
        var draft=valid(.sort);draft.setRow("sort","items",index:0,key:"label",text:String(repeating:"😀",count:21));XCTAssertFalse(draft.issues.isEmpty)
        draft.setRow("sort","items",index:0,key:"label",text:String(repeating:"😀",count:20));XCTAssertTrue(draft.issues.isEmpty)
    }
    func testAuthorOwnedImageAndUnknownRowFieldsArePreserved() throws {
        var draft=valid(.sort);draft.setRow("sort","items",index:0,key:"img",text:"https://example.com/owned.png")
        draft.setRow("sort","items",index:0,key:"sourceNote",text:"owned metadata")
        let rows=try serialized(draft)["sort"]?.object?["items"]?.array
        XCTAssertEqual(rows?.first?.object?["img"],.string("https://example.com/owned.png"))
        XCTAssertEqual(rows?.first?.object?["sourceNote"],.string("owned metadata"))
    }
    func testRemovingCategoryClearsItsAssignmentsInsteadOfGuessingNewAnswers() {
        var draft=valid(.classify);draft.removeRow("classify","bins",index:0)
        XCTAssertNil(draft.value["classify"]?.object?["answer"]?.object?["item_1"]);XCTAssertFalse(draft.issues.isEmpty)
    }
    func testClassificationRequiresExactItemCoverageAndKnownCategory() {
        var draft=valid(.classify);draft.setClassification(itemID:"item_1",binID:"missing");XCTAssertFalse(draft.issues.isEmpty)
        draft=valid(.classify);draft.setClassification(itemID:"foreign",binID:"bin_1");XCTAssertFalse(draft.issues.isEmpty)
    }
    func testNewIDsDoNotCollideWithExistingImportedIDs() {
        var draft=valid(.sort);draft.removeRow("sort","items",index:1);draft.appendRow("sort","items",prefix:"item",maximum:8)
        let ids=draft.rows("sort","items").compactMap{$0.object?["id"]?.string};XCTAssertEqual(ids.count,Set(ids).count)
    }
    func testPresentRootFieldRoundTripsAndRejectsUnsupportedInline() throws {
        var draft=valid(.compass);draft.setPresentation("inline");XCTAssertFalse(draft.issues.isEmpty)
        draft.setPresentation("fullscreen");let serialized=try draft.serialize()
        XCTAssertEqual(try TemplateAdvancedDraft(raw:serialized).explicitPresentation,"fullscreen")
        draft.setPresentation("");XCTAssertNil(draft.value["present"])
    }
    func testUnknownPresentValueNeverBecomesASilentDefault() {
        var draft=valid(.sort);draft.setPresentation("future");XCTAssertFalse(draft.issues.isEmpty)
    }
    func testPreviewProjectionOmitsAllAnswerAndRewardSecrets() throws {
        for game in [TemplateAdvancedGame.sort,.match,.classify,.compass,.shout] {
            let segment=try valid(game).miniPreviewSegment(game)
            for key in ["answerOrder","pairs","answer","xp","enabled"] { XCTAssertEqual(segment[key],.null) }
        }
    }
    func testSelectingNewGameDisablesOldMainGameButKeepsTimer() {
        var draft=valid(.sort);draft.set("timer","enabled",.bool(true));draft.select(.compass)
        XCTAssertFalse(draft.enabled("sort"));XCTAssertTrue(draft.enabled("compass"));XCTAssertTrue(draft.enabled("timer"))
    }
}

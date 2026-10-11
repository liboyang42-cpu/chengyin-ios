import XCTest
@testable import QuestifyCore

final class TemplateMultiplayerPlanTests: XCTestCase {
    private func fixture() -> TemplateAdvancedDraft { var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(.multiplayer, true); return draft }
    private func apply(_ edit: TemplateMultiplayerPlan.Edit, plan: inout TemplateMultiplayerPlan, draft: inout TemplateAdvancedDraft) throws {
        let update = try XCTUnwrap(plan.applying(edit, to: draft)); plan = update.plan; draft = update.draft
    }
    func testOpeningPreservesInitialPlayerDefaultsAndOrder() {
        let draft = fixture(), before = draft, plan = TemplateMultiplayerPlan(draft)
        XCTAssertTrue(plan.isSupported); XCTAssertEqual(plan.roles[0].wireID, "player"); XCTAssertEqual(plan.roles[0].minimumText, "1"); XCTAssertEqual(plan.roles[0].maximumText, "4"); XCTAssertEqual(plan.orderText, "player"); XCTAssertEqual(draft, before)
    }
    func testNewRoleHasSourceZeroOneBoundsAndUniqueAutomaticIdentifier() throws {
        var draft = fixture(), plan = TemplateMultiplayerPlan(draft)
        try apply(.add, plan: &plan, draft: &draft); try apply(.add, plan: &plan, draft: &draft)
        XCTAssertEqual(Set(plan.roles.map(\.wireID)).count, 3)
        for role in plan.roles.dropFirst() { XCTAssertTrue(role.wireID.hasPrefix("role_")); XCTAssertEqual(role.label, ""); XCTAssertEqual(role.minimumText, "0"); XCTAssertEqual(role.maximumText, "1") }
    }
    func testBulkCommaChineseCommaWhitespaceInputPreservesSequenceAndDuplicates() {
        XCTAssertEqual(TemplateMultiplayerPlan.parseOrder(" scout, player，scout\n\tplayer ,, "), ["scout", "player", "scout", "player"])
        XCTAssertEqual(TemplateMultiplayerPlan.parseOrder(" ,，\n\t "), [])
    }
    func testMiniWhitespaceIncludesBOMAndDoesNotTreatNELAsSeparator() {
        XCTAssertEqual(TemplateMultiplayerPlan.parseOrder("a\u{FEFF}b\u{00A0}c\u{2003}d\u{2028}e\u{3000}f"), ["a","b","c","d","e","f"])
        XCTAssertEqual(TemplateMultiplayerPlan.parseOrder("a\u{0085}b"), ["a\u{0085}b"])
    }
    func testRawTrailingDelimiterRemainsVisibleWithoutChangingWireOrder() throws {
        var draft = fixture(), plan = TemplateMultiplayerPlan(draft); let before = draft
        try apply(.order("player,\n "), plan: &plan, draft: &draft)
        XCTAssertEqual(plan.orderText, "player,\n "); XCTAssertEqual(draft, before); XCTAssertEqual(plan.turns.map(\.roleID), ["player"])
    }
    func testRenameAndRemoveKeepDanglingReferencesUntilAuthorEditsOrder() throws {
        var draft = fixture(), plan = TemplateMultiplayerPlan(draft); let role = plan.roles[0].id, order = draft.value["multiplayer"]?.object?["turnOrder"]
        try apply(.text(role, .identifier, "scout"), plan: &plan, draft: &draft)
        XCTAssertEqual(draft.value["multiplayer"]?.object?["turnOrder"], order); XCTAssertFalse(plan.turns[0].resolvesUniquely); XCTAssertFalse(draft.creatorIssues(.multiplayer).isEmpty)
        try apply(.order("scout"), plan: &plan, draft: &draft); XCTAssertTrue(plan.turns[0].resolvesUniquely)
        try apply(.remove(role), plan: &plan, draft: &draft); XCTAssertTrue(plan.roles.isEmpty); XCTAssertEqual(plan.turns.map(\.roleID), ["scout"]); XCTAssertFalse(plan.turns[0].resolvesUniquely)
    }
    func testNumericIncompleteAndLeadingZeroInputIsPreservedWithoutCoercingEmptyToZero() throws {
        var draft = fixture(), plan = TemplateMultiplayerPlan(draft); let id = plan.roles[0].id
        try apply(.text(id, .minimum, "-"), plan: &plan, draft: &draft); XCTAssertEqual(plan.roles[0].minimumText, "-"); XCTAssertThrowsError(try draft.serialize())
        try apply(.text(id, .minimum, ""), plan: &plan, draft: &draft); XCTAssertEqual(plan.roles[0].minimumText, ""); XCTAssertFalse(draft.creatorIssues(.multiplayer).isEmpty)
        try apply(.text(id, .minimum, "01"), plan: &plan, draft: &draft); XCTAssertEqual(plan.roles[0].minimumText, "01"); XCTAssertEqual(draft.value["multiplayer"]?.object?["roles"]?.array?.first?.object?["min"], .number(1)); XCTAssertTrue(draft.creatorIssues(.multiplayer).isEmpty)
    }
    func testDuplicateIdentifiersAreShownAsAmbiguousAndRejectedByExistingValidation() throws {
        var draft = fixture(), plan = TemplateMultiplayerPlan(draft); try apply(.add, plan: &plan, draft: &draft)
        try apply(.text(plan.roles[1].id, .identifier, "player"), plan: &plan, draft: &draft)
        XCTAssertEqual(plan.turns[0].labels.count, 2); XCTAssertFalse(plan.turns[0].resolvesUniquely); XCTAssertFalse(draft.creatorIssues(.multiplayer).isEmpty)
    }
    func testRoleReorderRetainsTurnSequenceAndStableOccurrenceIDs() throws {
        var draft = fixture(), plan = TemplateMultiplayerPlan(draft); try apply(.add, plan: &plan, draft: &draft); let second = plan.roles[1].id
        let order = draft.value["multiplayer"]?.object?["turnOrder"]
        try apply(.move(second, -1), plan: &plan, draft: &draft); XCTAssertEqual(plan.roles[0].id, second); XCTAssertEqual(draft.value["multiplayer"]?.object?["turnOrder"], order)
        XCTAssertNil(plan.applying(.move(second, -1), to: draft)); XCTAssertNil(plan.applying(.move(second, 2), to: draft))
    }
    func testRoleCapAndOrderLimitAreNotSilentTruncation() throws {
        var draft = fixture(), plan = TemplateMultiplayerPlan(draft)
        while plan.canAdd { try apply(.add, plan: &plan, draft: &draft) }; XCTAssertEqual(plan.roles.count, 20); XCTAssertNil(plan.applying(.add, to: draft))
        let input = Array(repeating: "player", count: 101).joined(separator: ",")
        try apply(.order(input), plan: &plan, draft: &draft); XCTAssertEqual(plan.turns.count, 101); XCTAssertFalse(draft.creatorIssues(.multiplayer).isEmpty)
    }
    func testMalformedFallbackStaleSnapshotAndDisabledFamily() {
        let original = fixture(), plan = TemplateMultiplayerPlan(original); var changed = original
        changed.set("multiplayer", "maxPlayers", .number(3)); XCTAssertNil(plan.applying(.order("player"), to: changed))
        changed = original; changed.setCreatorEnabled(.multiplayer, false); XCTAssertFalse(TemplateMultiplayerPlan(changed).canEdit)
        for raw in [TemplateAuthoringJSON.string("legacy"), .array([.number(7)])] { changed = original; changed.set("multiplayer", "roles", raw); XCTAssertFalse(TemplateMultiplayerPlan(changed).isSupported) }
        changed = original; changed.set("multiplayer", "turnOrder", .array([.number(7)])); XCTAssertFalse(TemplateMultiplayerPlan(changed).isSupported)
    }
    func testUnknownRowMetadataOtherFamiliesAndRawOrderArePreservedByRoleEdit() throws {
        var draft = fixture(); draft.set("multiplayer", "future", .string("keep")); draft.setCreatorValue(.multiplayer, path: [.field("roles"), .index(0), .field("future")], entry: .number(9)); draft.set("timer", "enabled", .bool(true))
        let before = draft; var plan = TemplateMultiplayerPlan(draft); try apply(.text(plan.roles[0].id, .label, "Team"), plan: &plan, draft: &draft)
        for key in ["mode", "assignment", "minPlayers", "maxPlayers", "requiredTurns", "unitScore", "turnOrder", "future"] { XCTAssertEqual(draft.value["multiplayer"]?.object?[key], before.value["multiplayer"]?.object?[key]) }
        XCTAssertEqual(draft.value["timer"], before.value["timer"]); XCTAssertEqual(draft.value["multiplayer"]?.object?["roles"]?.array?.first?.object?["future"], .number(9))
    }
    func testCompleteValidConfigurationSerializesAndLocalDraftRoundTrips() throws {
        var draft = fixture(), plan = TemplateMultiplayerPlan(draft); try apply(.add, plan: &plan, draft: &draft); let id = plan.roles[1].id
        try apply(.text(id, .identifier, "scout"), plan: &plan, draft: &draft); try apply(.text(id, .label, "Scout"), plan: &plan, draft: &draft)
        try apply(.order(" player，scout\nplayer, "), plan: &plan, draft: &draft)
        XCTAssertTrue(draft.creatorIssues(.multiplayer).isEmpty); let decoded = try TemplateAdvancedDraft(raw: draft.serialize()); XCTAssertEqual(TemplateMultiplayerPlan(decoded).turns.map(\.roleID), ["player", "scout", "player"])
        var local = TemplateAuthoringDraft(title: "Team"); local.advanced = draft
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(local)); XCTAssertEqual(restored, local); XCTAssertEqual(TemplateMultiplayerPlan(restored.advanced).orderText, "player, scout, player")
    }
}

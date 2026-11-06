import Foundation
import XCTest
@testable import QuestifyCore

final class SharedRecoveryAuthorContractTests: XCTestCase {
    private func draft(rows: [ProjectEditJSON] = [], runtime: String = "TEAM", world: String = "WORLD_SHARED", acts: [String] = ["act_a", "act_b"]) throws -> ProjectEditDraft {
        let game: [String: ProjectEditJSON] = ["runtimeScope": .string(runtime), "worldMode": .string(world),
            "quests": .array([.object(["questKey": .string("quest_a")])]),
            "acts": .array(acts.map { .object(["actKey": .string($0)]) }),
            "survival": .object(["recoveries": .array(rows), "zeroMessage": .string("retain exact e\u{301}"), "rations": .array([])])]
        let theme: ProjectEditJSON = .object(["schemaVersion": .number(1), "gameplayRuntime": .object(game), "futureSibling": .string("keep")])
        var draft = ProjectEditDraft(); draft.preserved["themeRuntimeConfig"] = .string(String(decoding: try JSONEncoder().encode(theme), as: UTF8.self))
        draft.preserved["unrelated"] = .string("original"); return draft
    }
    private func row(_ kind: String = "REST", key: String = "rest_a") -> ProjectEditJSON {
        .object(["recoveryKey": .string(key), "kind": .string(kind), "limit": .number(2),
            kind == "RESCUE" ? "hpFloor" : "hpDelta": .number(3), "actKeys": .array([.string("act_a")])])
    }
    private func makeRest(_ editor: inout NativeSharedRecoveryAuthorDraft) {
        editor.appendBlank(); editor.edit(0, "recoveryKey", "rest_a"); editor.edit(0, "kind", "REST")
        editor.edit(0, "limit", "2"); editor.edit(0, "hpDelta", "3"); editor.selectAct(0, key: "act_a", selected: true)
    }
    func testUnchangedDefinitionPreservesWholeOriginalBytes() throws {
        let source = try draft(rows: [row()]), editor = try NativeSharedRecoveryAuthorDraft(draft: source)
        XCTAssertTrue(editor.issues.isEmpty)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try editor.applying(to: source)), ProjectEditPendingMaterials.exactData(source))
    }
    func testRestRoundTripUsesOriginalCarrierAndPreservesOtherFields() throws {
        let source = try draft(); var editor = try NativeSharedRecoveryAuthorDraft(draft: source); makeRest(&editor)
        let applied = try editor.applying(to: source), reread = try NativeSharedRecoveryAuthorDraft(draft: applied)
        XCTAssertEqual(reread.text(0, "kind"), "REST"); XCTAssertEqual(reread.text(0, "hpDelta"), "3")
        XCTAssertEqual(reread.actKeys(0), ["act_a"]); XCTAssertEqual(reread.noEffectPolicy, "")
        XCTAssertEqual(applied.preserved["unrelated"], source.preserved["unrelated"])
        XCTAssertEqual(reread.theme["futureSibling"], .string("keep"))
        XCTAssertEqual(reread.theme["gameplayRuntime"]?.object?["survival"]?.object?["zeroMessage"], .string("retain exact e\u{301}"))
    }
    func testRescueSwitchClearsDeltaAndRequiresExplicitFloor() throws {
        let source = try draft(rows: [row()]); var editor = try NativeSharedRecoveryAuthorDraft(draft: source)
        editor.edit(0, "kind", "RESCUE"); XCTAssertEqual(editor.text(0, "hpDelta"), ""); XCTAssertFalse(editor.issues.isEmpty)
        XCTAssertThrowsError(try editor.applying(to: source)); editor.edit(0, "hpFloor", "5")
        let reread = try NativeSharedRecoveryAuthorDraft(draft: editor.applying(to: source))
        XCTAssertEqual(reread.text(0, "hpFloor"), "5"); XCTAssertEqual(reread.text(0, "hpDelta"), "")
    }
    func testC6UnsupportedSupplyAndFutureKindsPreserveOriginalByRefusal() throws {
        for kind in ["SUPPLY", "FUTURE", ""] {
            let source = try draft(rows: [row(kind)]), bytes = ProjectEditPendingMaterials.exactData(source)
            XCTAssertThrowsError(try NativeSharedRecoveryAuthorDraft(draft: source))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(source), bytes)
        }
        let source = try draft(rows: [row()]); var editor = try NativeSharedRecoveryAuthorDraft(draft: source)
        editor.edit(0, "kind", "SUPPLY"); XCTAssertEqual(editor.text(0, "kind"), "REST")
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try editor.applying(to: source)), ProjectEditPendingMaterials.exactData(source))
    }
    func testPersonalUnknownWorldAndMalformedSourceCannotCreateTeamDefaults() throws {
        for source in [try draft(runtime: "PLAYER"), try draft(world: "FUTURE"), ProjectEditDraft()] {
            XCTAssertThrowsError(try NativeSharedRecoveryAuthorDraft(draft: source))
        }
        var malformed = ProjectEditDraft(); malformed.preserved["themeRuntimeConfig"] = .string("{")
        XCTAssertThrowsError(try NativeSharedRecoveryAuthorDraft(draft: malformed))
    }
    func testNumericBadInputStaysVisibleAndBlocksApplyWithoutCoercion() throws {
        for (field, values) in [("limit", ["0", "100", "1.5", "true", ""]), ("hpDelta", ["0", "1000", "-1", "x"])] {
            for value in values {
                let source = try draft(rows: [row()]); var editor = try NativeSharedRecoveryAuthorDraft(draft: source)
                editor.edit(0, field, value); XCTAssertEqual(editor.text(0, field), value)
                XCTAssertFalse(editor.issues.isEmpty); XCTAssertThrowsError(try editor.applying(to: source))
            }
        }
    }
    func testActualActReferencesAndDuplicateIdentitiesRemainBlocked() throws {
        let source = try draft(rows: [row(), row()]); let editor = try NativeSharedRecoveryAuthorDraft(draft: source)
        XCTAssertFalse(editor.issues.isEmpty); XCTAssertThrowsError(try editor.applying(to: source))
        let missing = try draft(rows: [row()], acts: ["act_b"]); var next = try NativeSharedRecoveryAuthorDraft(draft: missing)
        XCTAssertFalse(next.issues.isEmpty); next.selectAct(0, key: "act_a", selected: false)
        XCTAssertTrue(next.issues.isEmpty); next.selectAct(0, key: "invented_act", selected: true); XCTAssertTrue(next.actKeys(0).isEmpty)
    }
    func testNewBlankNeverInventsKindQuantityOrLimitAndCapsAtTwenty() throws {
        var editor = try NativeSharedRecoveryAuthorDraft(draft: draft()); editor.appendBlank()
        for field in ["kind", "limit", "hpDelta", "hpFloor"] { XCTAssertEqual(editor.text(0, field), "") }
        XCTAssertFalse(editor.issues.isEmpty)
        for _ in 0..<30 { editor.appendBlank() }; XCTAssertEqual(editor.recoveries.count, 20)
    }
    func testNoEffectFlagIsExplicitAndRemovalRestoresAbsence() throws {
        let source = try draft(rows: [row()]); var editor = try NativeSharedRecoveryAuthorDraft(draft: source)
        XCTAssertEqual(editor.noEffectPolicy, ""); editor.noEffectPolicy("true"); XCTAssertEqual(editor.noEffectPolicy, "true")
        editor.noEffectPolicy("false"); XCTAssertEqual(editor.noEffectPolicy, "false")
        editor.noEffectPolicy(""); XCTAssertEqual(ProjectEditPendingMaterials.exactData(try editor.applying(to: source)), ProjectEditPendingMaterials.exactData(source))
    }
    func testForeignRecoveryFieldsCannotBeSilentlyDropped() throws {
        var fields = try XCTUnwrap(row().object); fields["grantXP"] = .number(100)
        let source = try draft(rows: [.object(fields)]), editor = try NativeSharedRecoveryAuthorDraft(draft: source)
        XCTAssertFalse(editor.issues.isEmpty); XCTAssertThrowsError(try editor.applying(to: source))
        XCTAssertEqual(editor.recoveries.first?.object?["grantXP"], .number(100))
    }
    func testDuplicateOriginalKeysCannotBeNormalizedIntoWritableConfiguration() throws {
        var source = try draft(rows: [row()])
        let raw = try XCTUnwrap(source.preserved["themeRuntimeConfig"]?.text)
        source.preserved["themeRuntimeConfig"] = .string(raw.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"schemaVersion\":1"))
        XCTAssertThrowsError(try NativeSharedRecoveryAuthorDraft(draft: source))
    }
    func testWholeDraftPreimageIncludingUnicodeOwnerRevisionCannotBeRetargeted() throws {
        var source = try draft(rows: [row()]); source.name = "e\u{301}"
        let editor = try NativeSharedRecoveryAuthorDraft(draft: source)
        for key in ["name", "owner", "revision", "unrelated"] {
            var changed = source
            switch key { case "name": changed.name = "\u{e9}"
            case "owner": changed.owner = .merchant
            case "revision": changed.baseRevision = "later"
            default: changed.preserved["unrelated"] = .string("changed") }
            XCTAssertThrowsError(try editor.applying(to: changed), key)
        }
    }
}

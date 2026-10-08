import Foundation
import XCTest
@testable import QuestifyCore

final class MerchantNPCPresetAvatarTests: XCTestCase {
    private func character(_ fields: [String: Any] = [:]) throws -> MerchantStoreCharacter {
        var data: [String: Any] = ["name": "Shop guide", "avatar": "px1:p01", "greeting": "Hello", "persona": "Friendly", "knowledge": "Menu"]
        fields.forEach { data[$0] = $1 }
        return try JSONDecoder().decode(MerchantStoreCharacter.self, from: JSONSerialization.data(withJSONObject: data))
    }
    func testExactPresetIDsAndCodes() {
        let ids = ["p01", "p04", "p07", "p10", "p13", "p17", "p18", "p23", "p25", "p27", "p31", "p36"]
        XCTAssertEqual(MerchantNPCPresetAvatar.all.map(\.id), ids)
        XCTAssertEqual(Set(MerchantNPCPresetAvatar.all.map(\.code)).count, 12)
        for value in MerchantNPCPresetAvatar.all {
            XCTAssertEqual(MerchantNPCPresetAvatar.matching(code: "px1:" + value.id), value)
            XCTAssertEqual(MerchantNPCPresetAvatar.matching(id: value.id), value)
        }
    }
    func testUnknownOrNonPresetNeverSubstitutesAnotherIdentity() {
        for value in ["", "px1:", "px1:p02", "px2:p01", " px1:p01", "px1:p01\n", "PX1:p01", "https://example.test/face.png", "/profile/face.png"] {
            XCTAssertNil(MerchantNPCPresetAvatar.matching(code: value), value)
        }
        XCTAssertNil(MerchantNPCPresetAvatar.matching(id: "px1:p01"))
    }
    func testAllPixelRunsAreValidAndNonempty() {
        for value in MerchantNPCPresetAvatar.all {
            XCTAssertTrue([32, 48].contains(value.gridSize))
            XCTAssertEqual(value.encodedRuns.utf8.count % 4, 0)
            XCTAssertEqual(value.runs.count * 4, value.encodedRuns.utf8.count)
            XCTAssertFalse(value.runs.isEmpty)
            XCTAssertLessThanOrEqual(value.backgroundRGB, 0xFFFFFF)
            for run in value.runs {
                XCTAssertGreaterThan(run.width, 0)
                XCTAssertLessThanOrEqual(run.x + run.width, value.gridSize)
                XCTAssertLessThan(run.y, value.gridSize)
                XCTAssertTrue(value.paletteRGB.indices.contains(run.paletteIndex))
            }
        }
    }
    func testNameAllows32UTF16UnitsButNot33() throws {
        var value = try character(["name": String(repeating: "a", count: 32)])
        XCTAssertNil(value.blocker)
        value.name += "a"; XCTAssertEqual(value.blocker, "merchantPreset.nameLimit")
        value.name = String(repeating: "🦊", count: 16); XCTAssertNil(value.blocker)
        value.name += "a"; XCTAssertEqual(value.blocker, "merchantPreset.nameLimit")
        value.name = " \n "; XCTAssertEqual(value.blocker, "merchant.operations.characterNameRequired")
    }
    func testPersonaAllows500UTF16UnitsAndExplicitEmptyClear() throws {
        var value = try character(["persona": String(repeating: "a", count: 500)])
        XCTAssertNil(value.blocker)
        value.persona += "a"; XCTAssertEqual(value.blocker, "merchantPreset.personaLimit")
        value.persona = String(repeating: "🦊", count: 250); XCTAssertNil(value.blocker)
        value.persona += "a"; XCTAssertEqual(value.blocker, "merchantPreset.personaLimit")
        value.persona = " \n "; XCTAssertNil(value.blocker)
        let preview = try XCTUnwrap(MerchantOperationsDraft.character(value).previews().first)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: preview.json) as? [String: Any])
        XCTAssertEqual(payload["persona"] as? String, "")
        XCTAssertFalse(payload["persona"] is NSNull)
    }
    func testMissingAndNullLegacyPersonaReadAsEmptyAndDoNotInventText() throws {
        let missing = try JSONDecoder().decode(MerchantStoreCharacter.self, from: Data(#"{"name":"Guide","avatar":"px1:p01"}"#.utf8))
        let null = try character(["persona": NSNull()])
        XCTAssertEqual(missing.persona, ""); XCTAssertEqual(null.persona, "")
        XCTAssertNil(missing.blocker); XCTAssertNil(null.blocker)
    }
    func testKnowledgeAndGreetingKeepMiniProgramLimits() throws {
        var value = try character(["knowledge": String(repeating: "a", count: 2000), "greeting": String(repeating: "a", count: 60)])
        XCTAssertNil(value.blocker)
        value.knowledge += "a"; XCTAssertEqual(value.blocker, "merchant.operations.knowledgeLimit")
        value.knowledge = String(repeating: "🦊", count: 1000); XCTAssertNil(value.blocker)
        value.knowledge += "a"; XCTAssertEqual(value.blocker, "merchant.operations.knowledgeLimit")
        value.knowledge = ""; value.greeting += "a"; XCTAssertEqual(value.blocker, "merchant.operations.greetingLimit")
        value.greeting = String(repeating: "🦊", count: 30); XCTAssertNil(value.blocker)
        value.greeting += "a"; XCTAssertEqual(value.blocker, "merchant.operations.greetingLimit")
    }
    func testAvatarRemainsRequiredAndUnknownReadValueIsPreserved() throws {
        var value = try character(["avatar": "px1:future"])
        XCTAssertEqual(value.avatar, "px1:future")
        XCTAssertNil(MerchantNPCPresetAvatar.matching(code: value.avatar))
        value.avatar = ""; XCTAssertEqual(value.blocker, "merchant.operations.characterAvatarRequired")
    }
    func testReadOnlyAuditReasonDoesNotEnterFiveFieldSavePayload() throws {
        let value = try character(["auditStatus": 2, "auditReason": "  Please clarify facts  ", "enabled": 0])
        XCTAssertEqual(value.rejectionReason, "Please clarify facts")
        XCTAssertEqual(value.reviewKey, "merchant.operations.review.rejected")
        let preview = try XCTUnwrap(MerchantOperationsDraft.character(value).previews().first)
        XCTAssertEqual(preview.path, "api/merchant/npc/save")
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: preview.json) as? [String: Any])
        XCTAssertEqual(Set(payload.keys), ["name", "avatar", "greeting", "persona", "knowledge"])
        XCTAssertEqual(payload["avatar"] as? String, "px1:p01")
    }
    func testAuditReasonIsOnlyDisplayedForAuthoritativeRejectedStatus() throws {
        for status in [0, 1, 99] { XCTAssertNil(try character(["auditStatus": status, "auditReason": "Not current rejection"]).rejectionReason) }
        XCTAssertNil(try character(["auditReason": "Unknown status"]).rejectionReason)
        XCTAssertNil(try character(["auditStatus": 2, "auditReason": " \n "]).rejectionReason)
    }
    func testSaveTrimsValuesAndPreservesEmptyKnowledge() throws {
        let value = try character(["name": " Guide ", "avatar": " px1:p04 ", "greeting": " Hi ", "persona": " Friendly ", "knowledge": " \n "])
        XCTAssertEqual(value.fields as? [String: String], ["name": "Guide", "avatar": "px1:p04", "greeting": "Hi", "persona": "Friendly", "knowledge": ""])
    }
}

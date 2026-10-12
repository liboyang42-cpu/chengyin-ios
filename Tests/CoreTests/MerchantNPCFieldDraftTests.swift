import XCTest
@testable import QuestifyCore

final class MerchantNPCFieldDraftTests: XCTestCase {
    private func character() throws -> MerchantStoreCharacter {
        try JSONDecoder().decode(MerchantStoreCharacter.self, from: Data(#"{"name":"Guide","avatar":"px1:p01","greeting":"Welcome","persona":"Kind","knowledge":"Local facts","auditStatus":2,"enabled":0,"auditReason":"Review me"}"#.utf8))
    }
    private func buffer(_ field: MerchantNPCTextField = .name, _ character: MerchantStoreCharacter? = nil) throws -> MerchantNPCFieldDraft {
        let source = try character ?? self.character()
        return try XCTUnwrap(.init(field: field, source: .character(source)))
    }
    func testExactSourceFieldsAndLimits() {
        XCTAssertEqual(MerchantNPCTextField.allCases.map(\.rawValue), ["name", "greeting", "persona", "knowledge"])
        XCTAssertEqual(MerchantNPCTextField.allCases.map(\.limit), [32, 60, 500, 2000])
        XCTAssertEqual(MerchantNPCTextField.allCases.map(\.multiline), [false, false, true, true])
    }
    func testEachFieldChangesOnlyItsOwnProperty() throws {
        let source = try character()
        for field in MerchantNPCTextField.allCases {
            var d = try buffer(field, source); d.value = " New e\u{0301} "
            var expected = source
            switch field { case .name: expected.name = "New e\u{0301}"; case .greeting: expected.greeting = "New e\u{0301}"; case .persona: expected.persona = "New e\u{0301}"; case .knowledge: expected.knowledge = "New e\u{0301}" }
            XCTAssertTrue(MerchantNPCFieldDraft.sameDraft(try d.applying(to: .character(source)), .character(expected)))
        }
    }
    func testEveryFieldBoundaryUsesUTF16() throws {
        for field in MerchantNPCTextField.allCases {
            var d = try buffer(field); d.value = String(repeating: "😀", count: field.limit / 2)
            XCTAssertNil(d.issueKey); d.value += "x"; XCTAssertEqual(d.issueKey, "merchant.npcField.limit." + field.rawValue)
        }
    }
    func testRawOverLimitIsRejectedWithoutTruncation() throws {
        var d = try buffer(); d.value = " " + String(repeating: "x", count: 32)
        XCTAssertNotNil(d.issueKey); XCTAssertEqual(d.value.utf16.count, 33)
    }
    func testChangedNameRejectsSourceWhitespace() throws {
        var d = try buffer(); d.value = " \n\t\u{FEFF}"
        XCTAssertEqual(d.issueKey, "merchant.npcField.nameRequired")
        XCTAssertThrowsError(try d.applying(to: .character(character())))
    }
    func testSourceTrimDoesNotTreatNELAsWhitespace() throws {
        var d = try buffer(); d.value = "\u{0085}"; XCTAssertNil(d.issueKey); XCTAssertEqual(d.appliedValue, "\u{0085}")
    }
    func testBufferRetainsWhitespaceUntilApply() throws {
        var d = try buffer(.persona); d.value = " \n e\u{0301} \t"
        XCTAssertEqual(Data(d.value.utf8), Data(" \n e\u{0301} \t".utf8)); XCTAssertEqual(Data(d.appliedValue.utf8), Data("e\u{0301}".utf8))
    }
    func testOptionalFieldsCanBeExplicitlyCleared() throws {
        let c = try character()
        for field in [MerchantNPCTextField.greeting, .persona, .knowledge] {
            var d = try buffer(field, c); d.value = " "; XCTAssertNil(d.issueKey)
            XCTAssertEqual(field.value(in: try d.applying(to: .character(c))), "")
        }
    }
    func testHistoricalUnchangedOverLimitIsNoOp() throws {
        var c = try character(); c.name = String(repeating: "x", count: 40)
        let d = try buffer(.name, c); XCTAssertNil(d.issueKey)
        XCTAssertTrue(MerchantNPCFieldDraft.sameDraft(try d.applying(to: .character(c)), .character(c)))
    }
    func testHistoricalUnchangedSpacingIsNotTrimmed() throws {
        var c = try character(); c.name = "  Guide  "
        let d = try buffer(.name, c); XCTAssertFalse(d.isDirty)
        XCTAssertEqual(MerchantNPCTextField.name.value(in: try d.applying(to: .character(c))), "  Guide  ")
    }
    func testWrongDestinationCannotOpen() throws { XCTAssertNil(MerchantNPCFieldDraft(field: .name, source: .businessStatus(try .init(merchantID: 31, status: .closed)))) }
    func testChangedSourceFieldCannotBeOverwritten() throws {
        var c = try character(); var d = try buffer(.name, c); d.value = "New"; c.name = "Other"
        XCTAssertThrowsError(try d.applying(to: .character(c)))
    }
    func testCanonicalEquivalentSiblingBytesAreDifferent() throws {
        var a = try character(); a.knowledge = "é"; var b = a; b.knowledge = "e\u{0301}"
        XCTAssertEqual(a,b); XCTAssertFalse(MerchantNPCFieldDraft.sameDraft(.character(a), .character(b)))
    }
    func testAuditMetadataAndAvatarParticipateInIdentity() throws {
        let a = try character(); var b = a; b.avatar += "changed"
        XCTAssertFalse(MerchantNPCFieldDraft.sameDraft(.character(a), .character(b)))
        let c = MerchantStoreCharacter(); XCTAssertFalse(MerchantNPCFieldDraft.sameDraft(.character(a), .character(c)))
    }
}

import XCTest
@testable import QuestifyCore

final class MerchantStoreFieldDraftTests: XCTestCase {
    private func storefront() throws -> MerchantStorefront {
        try JSONDecoder().decode(MerchantStorefront.self, from: Data(#"{"id":7,"logo":"logo","name":"Old shop","description":"Story","derivatives":"Legacy goods","website":"https://example.invalid","preference":"Cafe","businessTime":"opaque hours","slogan":"Welcome","cityRole":"Local stop","storyTitle":"Hidden title","gallery":["g"],"tags":["tag"],"categoryId":4,"featuredType":1,"featuredId":9,"serviceTag":"hidden","serviceText":"service","locationLat":30,"locationLng":120,"locationVerified":1,"capacity":"12","availableTime":"Weekend","demand":"Quiet","suitActivityTypes":"hidden coop","coopOpen":0}"#.utf8))
    }
    private func buffer(_ field: MerchantStoreTextField, _ source: MerchantOperationsDraft) throws -> MerchantStoreFieldDraft { try XCTUnwrap(.init(field: field, source: source)) }
    func testWhitelistIsExactlySixSourceFields() {
        XCTAssertEqual(Set(MerchantStoreTextField.allCases.map(\.rawValue)), Set(["name", "preference", "description", "derivativeBenefits", "slogan", "cityRole"]))
        XCTAssertNil(MerchantStoreTextField(rawValue: "website")); XCTAssertNil(MerchantStoreTextField(rawValue: "derivatives"))
    }
    func testEachProfileFieldAppliesOnlyToThatField() throws {
        let source = MerchantOperationsDraft.profile(try storefront().profile)
        for field in [MerchantStoreTextField.name, .preference, .description, .derivativeBenefits] {
            var d = try buffer(field, source); d.value = "  New e\u{0301}  "
            guard case .profile(let next) = try d.applying(to: source), case .profile(var expected) = source else { return XCTFail() }
            switch field { case .name: expected.name = d.value; case .preference: expected.preference = d.value; case .description: expected.description = d.value; case .derivativeBenefits: expected.derivativeBenefits = d.value; default: return XCTFail() }
            XCTAssertTrue(MerchantStoreFieldDraft.sameDraft(.profile(next), .profile(expected)))
        }
    }
    func testEachDecorFieldPreservesAllHiddenSiblings() throws {
        let source = MerchantOperationsDraft.decor(try storefront().decor)
        for field in [MerchantStoreTextField.slogan, .cityRole] {
            var d = try buffer(field, source); d.value = " New "
            guard case .decor(let next) = try d.applying(to: source), case .decor(var expected) = source else { return XCTFail() }
            if field == .slogan { expected.slogan = d.value } else { expected.cityRole = d.value }
            XCTAssertTrue(MerchantStoreFieldDraft.sameDraft(.decor(next), .decor(expected)))
        }
    }
    func testStoryChangesOnlyDescriptionAndPreservesCooperation() throws {
        let source = MerchantOperationsDraft.story(try storefront()); var d = try buffer(.description, source); d.value = "New story"
        guard case .story(var expected) = source else { return XCTFail() }; expected.profile.description = d.value
        XCTAssertTrue(MerchantStoreFieldDraft.sameDraft(try d.applying(to: source), .story(expected)))
    }
    func testUnchangedOptionalBenefitsDoesNotTurnNilIntoEmpty() throws {
        let source = MerchantOperationsDraft.profile(try storefront().profile); let d = try buffer(.derivativeBenefits, source)
        XCTAssertEqual(d.value, ""); guard case .profile(let result) = try d.applying(to: source) else { return XCTFail() }
        XCTAssertNil(result.derivativeBenefits)
    }
    func testExplicitClearKeepsAnEmptyBenefitsPatch() throws {
        var p = try storefront().profile; p.derivativeBenefits = "Old benefit"; let source = MerchantOperationsDraft.profile(p)
        var d = try buffer(.derivativeBenefits, source); d.value = ""; guard case .profile(let result) = try d.applying(to: source) else { return XCTFail() }
        XCTAssertEqual(result.derivativeBenefits, ""); XCTAssertEqual(result.fields["derivativeBenefits"] as? String, "")
    }
    func testChangedNameCannotBeWhitespaceOnly() throws {
        let source = MerchantOperationsDraft.profile(try storefront().profile); var d = try buffer(.name, source); d.value = " \n\t"
        XCTAssertEqual(d.issueKey, "merchant.storeField.nameRequired"); XCTAssertThrowsError(try d.applying(to: source))
    }
    func testSource100UTF16LimitIncludesEmojiPairs() throws {
        var d = try buffer(.name, .profile(try storefront().profile)); d.value = String(repeating: "😀", count: 50)
        XCTAssertNil(d.issueKey); d.value += "a"; XCTAssertEqual(d.issueKey, "merchant.storeField.limit100")
    }
    func testNameBlankValidationMatchesJavaScriptBOMAndNEL() throws {
        var d = try buffer(.name, .profile(try storefront().profile)); d.value = "\u{FEFF}"
        XCTAssertEqual(d.issueKey, "merchant.storeField.nameRequired")
        d.value = "\u{0085}"; XCTAssertNil(d.issueKey)
    }
    func testBrandStory300LimitInBothDestinations() throws {
        let store = try storefront()
        for source in [MerchantOperationsDraft.profile(store.profile), .story(store)] {
            var d = try buffer(.description, source); d.value = String(repeating: "a", count: 300); XCTAssertNil(d.issueKey)
            d.value += "b"; XCTAssertEqual(d.issueKey, "merchant.storeField.limit300")
        }
    }
    func testHistoricalOverLimitNoOpDoesNotTruncate() throws {
        var p = try storefront().profile; p.name = String(repeating: "x", count: 140); let source = MerchantOperationsDraft.profile(p)
        let d = try buffer(.name, source); XCTAssertNil(d.issueKey); XCTAssertTrue(MerchantStoreFieldDraft.sameDraft(try d.applying(to: source), source))
    }
    func testWrongDestinationCannotCreateBuffer() throws {
        let store = try storefront(); XCTAssertNil(MerchantStoreFieldDraft(field: .slogan, source: .profile(store.profile)))
        XCTAssertNil(MerchantStoreFieldDraft(field: .name, source: .story(store))); XCTAssertNil(MerchantStoreFieldDraft(field: .slogan, source: .gallery(store.decor)))
    }
    func testChangedSourceFieldCannotBeOverwritten() throws {
        let store = try storefront(); let source = MerchantOperationsDraft.profile(store.profile); var d = try buffer(.name, source); d.value = "New"
        var other = store.profile; other.name = "Other"; XCTAssertThrowsError(try d.applying(to: .profile(other)))
    }
    func testRawUnicodeAndWhitespaceAreNotNormalized() throws {
        let source = MerchantOperationsDraft.profile(try storefront().profile); var d = try buffer(.preference, source); d.value = " e\u{0301} \n"
        let result = try d.applying(to: source); XCTAssertEqual(Data(try XCTUnwrap(d.field.value(in: result)).utf8), Data(d.value.utf8))
    }
    func testCanonicalProfileSiblingByteChangeIsDifferent() throws {
        var a = try storefront().profile; a.website = "é"; var b = a; b.website = "e\u{0301}"
        XCTAssertEqual(a, b); XCTAssertFalse(MerchantStoreFieldDraft.sameDraft(.profile(a), .profile(b)))
    }
    func testCanonicalHiddenDecorAndStoryCooperationAreDifferent() throws {
        var a = try storefront(); a.decor.serviceText = "é"; var b = a; b.decor.serviceText = "e\u{0301}"
        XCTAssertFalse(MerchantStoreFieldDraft.sameDraft(.story(a), .story(b)))
        b = a; a.cooperation.demand = "é"; b.cooperation.demand = "e\u{0301}"
        XCTAssertFalse(MerchantStoreFieldDraft.sameDraft(.story(a), .story(b)))
    }
    func testBusinessTimeReplacementSurvivesLocalFieldApply() throws {
        var p = try storefront().profile; p.businessTimeReplacement = "New hours"; let source = MerchantOperationsDraft.profile(p)
        var d = try buffer(.name, source); d.value = "New name"; guard case .profile(let next) = try d.applying(to: source) else { return XCTFail() }
        XCTAssertEqual(next.businessTime, "opaque hours"); XCTAssertEqual(next.businessTimeReplacement, "New hours")
    }
}

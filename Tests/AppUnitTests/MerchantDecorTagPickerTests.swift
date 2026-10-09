import XCTest
@testable import Questify

@MainActor final class MerchantDecorTagPickerTests: XCTestCase {
    private func harness(tags: [String] = ["unknown legacy", "老街"]) async throws -> (MerchantOperationsViewModel, MerchantOperationsFixtureReader) {
        let reader = MerchantOperationsFixtureReader()
        let data: [String: Any] = ["slogan": "Original slogan", "cityRole": "Original role", "tags": tags,
                                   "gallery": ["original-image"], "featuredType": 1, "featuredId": 7, "categoryId": 2]
        let decor = try JSONDecoder().decode(MerchantStoreDecor.self, from: JSONSerialization.data(withJSONObject: data))
        reader.replace(.decor, with: .draft(.decor(decor)))
        let document = MerchantOperationsViewModel(reader: reader, destination: .decor); await document.load()
        return (document, reader)
    }
    func testOpenEditAndCancelNeverChangeOriginalDocumentOrSend() async throws {
        let (document, reader) = try await harness(); let before = document.coordinator.draft
        let picker = try XCTUnwrap(MerchantDecorTagPickerModel(document: document))
        try picker.draft.toggle("天台"); XCTAssertEqual(document.coordinator.draft, before)
        picker.cancel(); XCTAssertFalse(picker.apply()); XCTAssertEqual(document.coordinator.draft, before)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testExplicitApplyChangesOnlyTagsAndIsConsumedWithoutSaving() async throws {
        let (document, reader) = try await harness()
        guard case .decor(var expected) = document.coordinator.draft else { return XCTFail() }
        let picker = try XCTUnwrap(MerchantDecorTagPickerModel(document: document))
        try picker.draft.addCustom("New tag"); expected.tags.append("New tag")
        XCTAssertTrue(picker.apply()); XCTAssertFalse(picker.apply())
        XCTAssertEqual(document.coordinator.draft, .decor(expected)); XCTAssertEqual(reader.saveCount, 0)
        XCTAssertTrue(document.coordinator.isDirty)
    }
    func testUnchangedApplyPreservesUnknownLegacyValuesWithoutDirtying() async throws {
        let (document, reader) = try await harness(tags: ["long historical custom value", "same", "same"])
        let before = document.coordinator.draft
        let picker = try XCTUnwrap(MerchantDecorTagPickerModel(document: document))
        XCTAssertTrue(picker.apply()); XCTAssertEqual(document.coordinator.draft, before)
        XCTAssertFalse(document.coordinator.isDirty); XCTAssertEqual(reader.saveCount, 0)
    }
    func testHistoricalOverLimitIsNotSilentlyTruncatedOrApplied() async throws {
        let (document, _) = try await harness(tags: (0..<13).map { "tag-\($0)" })
        let before = document.coordinator.draft
        let picker = try XCTUnwrap(MerchantDecorTagPickerModel(document: document))
        XCTAssertEqual(picker.draft.selected.count, 13); XCTAssertFalse(picker.apply())
        XCTAssertEqual(document.coordinator.draft, before)
        picker.draft.remove(at: 12); XCTAssertTrue(picker.apply())
    }
    func testConcurrentOtherFieldEditCannotBeOverwrittenByOldPicker() async throws {
        let (document, _) = try await harness()
        let picker = try XCTUnwrap(MerchantDecorTagPickerModel(document: document)); try picker.draft.toggle("天台")
        guard case .decor(var newer) = document.coordinator.draft else { return XCTFail() }
        newer.slogan = "Newer slogan"; document.edit(.decor(newer))
        XCTAssertFalse(picker.apply()); XCTAssertEqual(document.coordinator.draft, .decor(newer))
    }
    func testReloadAccountSwitchAndDiscardInvalidateOldPicker() async throws {
        let (document, reader) = try await harness()
        let reload = try XCTUnwrap(MerchantDecorTagPickerModel(document: document)); await document.load(); XCTAssertFalse(reload.apply())
        let discard = try XCTUnwrap(MerchantDecorTagPickerModel(document: document)); document.discard(); XCTAssertFalse(discard.apply())
        let switched = try XCTUnwrap(MerchantDecorTagPickerModel(document: document)); reader.switchAccount(); XCTAssertFalse(switched.apply())
    }
    func testFailedExistingSaveRetainsAppliedTagsForReopen() async throws {
        let (document, reader) = try await harness()
        let picker = try XCTUnwrap(MerchantDecorTagPickerModel(document: document)); try picker.draft.toggle("天台")
        XCTAssertTrue(picker.apply()); document.prepare(); reader.saveFailure = .notSent
        await document.confirm(try XCTUnwrap(document.coordinator.confirmation))
        let reopened = try XCTUnwrap(MerchantDecorTagPickerModel(document: document))
        XCTAssertTrue(reopened.draft.contains("天台")); XCTAssertTrue(reopened.draft.contains("unknown legacy"))
        XCTAssertEqual(reader.saveCount, 1)
    }
}

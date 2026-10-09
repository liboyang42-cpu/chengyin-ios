import XCTest
@testable import Questify

@MainActor final class MerchantFeaturedClearControlTests: XCTestCase {
    private func harness() async throws -> (MerchantOperationsViewModel, MerchantOperationsFixtureReader) {
        let reader = MerchantOperationsFixtureReader()
        let value = try JSONDecoder().decode(MerchantStoreDecor.self, from: Data(MerchantOperationsFixtureData.storeJSON.utf8))
        reader.replace(.decor, with: .draft(.decor(value)))
        let model = MerchantOperationsViewModel(reader: reader, destination: .decor); await model.load(); return (model, reader)
    }
    private func decor(_ model: MerchantOperationsViewModel) throws -> MerchantStoreDecor {
        guard case .decor(let value) = model.coordinator.draft else { throw MerchantOperationsFailure.notSent }; return value
    }
    func testClearChangesOnlyFeaturedPairInLocalDraft() async throws {
        let (model, reader) = try await harness(); let original = try decor(model)
        let control = MerchantFeaturedClearControl(model: model, source: original)
        XCTAssertTrue(control.clear()); XCTAssertFalse(control.clear())
        var expected = original; expected.featuredType = 0; expected.featuredID = nil
        XCTAssertEqual(try decor(model), expected); XCTAssertEqual(reader.saveCount, 0)
    }
    func testRestoreReturnsOnlyReadFeaturedPairAndPreservesOtherNewEdits() async throws {
        let (model, reader) = try await harness(); let original = try decor(model)
        XCTAssertTrue(MerchantFeaturedClearControl(model: model, source: original).clear())
        var newer = try decor(model); newer.slogan = "New slogan"; model.edit(.decor(newer))
        XCTAssertTrue(MerchantFeaturedClearControl(model: model, source: newer).restore())
        newer.featuredType = original.featuredType; newer.featuredID = original.featuredID
        XCTAssertEqual(try decor(model), newer); XCTAssertEqual(reader.saveCount, 0)
    }
    func testOldClearCannotOverwriteAnotherDraftEdit() async throws {
        let (model, _) = try await harness(); let original = try decor(model)
        let control = MerchantFeaturedClearControl(model: model, source: original)
        var newer = original; newer.tags.append("new tag"); model.edit(.decor(newer))
        XCTAssertFalse(control.clear()); XCTAssertEqual(try decor(model), newer)
    }
    func testRestoreCannotCrossReloadEvenWhenReadValuesMatch() async throws {
        let (model, _) = try await harness(); let original = try decor(model)
        XCTAssertTrue(MerchantFeaturedClearControl(model: model, source: original).clear())
        let oldRestore = MerchantFeaturedClearControl(model: model, source: try decor(model))
        await model.load(); XCTAssertFalse(oldRestore.restore()); XCTAssertEqual(try decor(model), original)
    }
    func testAccountSwitchAndDiscardInvalidateCapturedControls() async throws {
        let (model, reader) = try await harness()
        let oldClear = MerchantFeaturedClearControl(model: model, source: try decor(model))
        model.discard(); XCTAssertFalse(oldClear.clear())
        let switched = MerchantFeaturedClearControl(model: model, source: try decor(model))
        reader.switchAccount(); XCTAssertFalse(switched.clear())
    }
    func testFrozenReviewKeepsZeroNullAndCancelDoesNotSave() async throws {
        let (model, reader) = try await harness()
        XCTAssertTrue(MerchantFeaturedClearControl(model: model, source: try decor(model)).clear())
        model.prepare(); let review = try XCTUnwrap(model.coordinator.confirmation)
        guard case .decor(let frozen) = review.draft else { return XCTFail() }
        XCTAssertEqual(frozen.featuredType, 0); XCTAssertNil(frozen.featuredID)
        XCTAssertFalse(MerchantFeaturedClearControl(model: model, source: try decor(model)).restore())
        model.cancel(); await model.confirm(review); XCTAssertEqual(reader.saveCount, 0)
    }
    func testUnknownSaveLockPreventsClearAndRestore() async throws {
        let (model, reader) = try await harness()
        XCTAssertTrue(MerchantFeaturedClearControl(model: model, source: try decor(model)).clear())
        model.prepare(); reader.saveFailure = .outcomeUnknown
        await model.confirm(try XCTUnwrap(model.coordinator.confirmation))
        XCTAssertTrue(model.coordinator.isLocked)
        let control = MerchantFeaturedClearControl(model: model, source: try decor(model))
        XCTAssertFalse(control.clear()); XCTAssertFalse(control.restore())
    }
}

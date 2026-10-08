import XCTest
@testable import Questify

@MainActor final class MerchantNPCPresetPickerTests: XCTestCase {
    private func harness(avatar: String = "https://example.test/existing.png") async throws -> (MerchantOperationsViewModel, MerchantOperationsFixtureReader) {
        let reader = MerchantOperationsFixtureReader()
        let data: [String: Any] = ["name": "Guide", "avatar": avatar, "greeting": "Welcome", "persona": "Friendly", "knowledge": "Menu", "auditStatus": 2, "auditReason": "Review source", "enabled": 0]
        let value = try JSONDecoder().decode(MerchantStoreCharacter.self, from: JSONSerialization.data(withJSONObject: data))
        reader.replace(.character, with: .draft(.character(value)))
        let document = MerchantOperationsViewModel(reader: reader, destination: .character)
        await document.load()
        return (document, reader)
    }
    func testOpenAndCancelKeepExistingPhotoAndAllFields() async throws {
        let (document, reader) = try await harness()
        let before = document.coordinator.draft
        let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document))
        XCTAssertNil(picker.selectedID); XCTAssertFalse(picker.canApply)
        picker.select("p18"); XCTAssertTrue(picker.canApply)
        XCTAssertEqual(document.coordinator.draft, before)
        picker.cancel(); XCTAssertFalse(picker.apply())
        XCTAssertEqual(document.coordinator.draft, before); XCTAssertFalse(document.coordinator.isDirty)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testExplicitConfirmChangesOnlyAvatarAndNeverSends() async throws {
        let (document, reader) = try await harness()
        guard case .character(var expected) = document.coordinator.draft else { return XCTFail() }
        let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document))
        picker.select("p25"); XCTAssertTrue(picker.apply())
        expected.avatar = "px1:p25"
        XCTAssertEqual(document.coordinator.draft, .character(expected))
        XCTAssertTrue(document.coordinator.isDirty); XCTAssertTrue(document.coordinator.canReview)
        XCTAssertEqual(reader.saveCount, 0); XCTAssertFalse(picker.apply())
    }
    func testExistingKnownPresetHasSelectionWithoutDirtyChange() async throws {
        let (document, _) = try await harness(avatar: "px1:p23")
        let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document))
        XCTAssertEqual(picker.selectedID, "p23"); XCTAssertFalse(picker.canApply)
        XCTAssertFalse(document.coordinator.isDirty)
    }
    func testUnknownAvatarIsRetainedUntilExplicitKnownChoice() async throws {
        for avatar in ["", "px1:future", "px2:p01"] {
            let (document, _) = try await harness(avatar: avatar)
            let before = document.coordinator.draft
            let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document))
            XCTAssertNil(picker.selectedID)
            picker.select("unknown"); XCTAssertNil(picker.selectedID); XCTAssertFalse(picker.apply())
            XCTAssertEqual(document.coordinator.draft, before)
            picker.select("p01"); XCTAssertTrue(picker.apply())
        }
    }
    func testNullProfileCanChooseFirstAvatarWithoutInventingNameOrPersona() async throws {
        let reader = MerchantOperationsFixtureReader()
        reader.replace(.character, with: .draft(.character(.init())))
        let document = MerchantOperationsViewModel(reader: reader, destination: .character)
        await document.load()
        let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document))
        XCTAssertNil(picker.selectedID); picker.select("p04"); XCTAssertTrue(picker.apply())
        guard case .character(let value) = document.coordinator.draft else { return XCTFail() }
        XCTAssertEqual(value.avatar, "px1:p04"); XCTAssertEqual(value.name, ""); XCTAssertEqual(value.persona, "")
        XCTAssertEqual(value.blocker, "merchant.operations.characterNameRequired")
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testConcurrentFieldEditRejectsOldPickerInsteadOfOverwriting() async throws {
        let (document, _) = try await harness()
        let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document)); picker.select("p18")
        guard case .character(var newer) = document.coordinator.draft else { return XCTFail() }
        newer.knowledge = "Updated menu"; document.edit(.character(newer))
        XCTAssertFalse(picker.canApply); XCTAssertFalse(picker.apply())
        XCTAssertEqual(document.coordinator.draft, .character(newer))
    }
    func testSourceReloadWithSameValuesStillInvalidatesOldPicker() async throws {
        let (document, _) = try await harness()
        let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document)); picker.select("p18")
        await document.load()
        XCTAssertFalse(picker.apply()); XCTAssertFalse(document.coordinator.isDirty)
    }
    func testAccountSwitchAndDiscardInvalidatePicker() async throws {
        let (document, reader) = try await harness()
        let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document)); picker.select("p18")
        reader.switchAccount(); XCTAssertFalse(picker.apply())
        let (other, _) = try await harness()
        let pending = try XCTUnwrap(MerchantNPCPresetPickerModel(document: other)); pending.select("p18")
        other.discard(); XCTAssertFalse(pending.apply())
    }
    func testReviewMustBeSeparateAndUsesExistingSyntheticSavePipeline() async throws {
        let (document, reader) = try await harness()
        let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document)); picker.select("p18")
        XCTAssertTrue(picker.apply()); XCTAssertEqual(reader.saveCount, 0)
        document.prepare(); let confirmation = try XCTUnwrap(document.coordinator.confirmation)
        XCTAssertNil(MerchantNPCPresetPickerModel(document: document))
        await document.confirm(confirmation)
        XCTAssertEqual(reader.saveCount, 1); XCTAssertTrue(document.coordinator.exampleSaved)
        await document.load()
        guard case .character(let value) = document.coordinator.draft else { return XCTFail() }
        XCTAssertEqual(value.avatar, "px1:p18")
    }
    func testUnknownWriteLockCannotBeBypassedByPickingAnotherAvatar() async throws {
        let (document, reader) = try await harness(); reader.saveFailure = .outcomeUnknown
        let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document)); picker.select("p18")
        XCTAssertTrue(picker.apply()); document.prepare()
        await document.confirm(try XCTUnwrap(document.coordinator.confirmation))
        XCTAssertTrue(document.coordinator.isLocked)
        XCTAssertNil(MerchantNPCPresetPickerModel(document: document))
        await document.load()
        XCTAssertNil(MerchantNPCPresetPickerModel(document: document)); XCTAssertEqual(reader.saveCount, 1)
    }
    func testBackgroundOrDismissCancellationIsPermanent() async throws {
        let (document, reader) = try await harness()
        let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document)); picker.select("p18")
        picker.cancel(); picker.select("p04")
        XCTAssertNil(picker.selectedID); XCTAssertFalse(picker.apply()); XCTAssertEqual(reader.saveCount, 0)
    }
    func testFrozenReviewKeepsChosenAvatarWhileLaterEditRevokesSubmission() async throws {
        let (document, reader) = try await harness()
        let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document)); picker.select("p18")
        XCTAssertTrue(picker.apply()); document.prepare()
        let confirmation = try XCTUnwrap(document.coordinator.confirmation)
        let preview = try XCTUnwrap(MerchantNPCCharacterAvatarSnapshot(draft: confirmation.draft))
        guard case .character(var later) = document.coordinator.draft else { return XCTFail() }
        later.avatar = "px1:p25"; document.edit(.character(later))
        XCTAssertEqual(preview.rawValue, "px1:p18"); XCTAssertEqual(preview.preset?.id, "p18")
        XCTAssertNil(document.coordinator.confirmation)
        await document.confirm(confirmation)
        XCTAssertEqual(reader.saveCount, 0); XCTAssertEqual(document.coordinator.draft, .character(later))
    }
    func testFrozenReviewCannotAuthorizeSubmissionAfterAccountSwitch() async throws {
        let (document, reader) = try await harness()
        let picker = try XCTUnwrap(MerchantNPCPresetPickerModel(document: document)); picker.select("p18")
        XCTAssertTrue(picker.apply()); document.prepare()
        let confirmation = try XCTUnwrap(document.coordinator.confirmation)
        let preview = try XCTUnwrap(MerchantNPCCharacterAvatarSnapshot(draft: confirmation.draft))
        reader.switchAccount()
        await document.confirm(confirmation)
        XCTAssertEqual(reader.saveCount, 0); XCTAssertFalse(document.coordinator.isCurrent)
        XCTAssertEqual(preview.rawValue, "px1:p18"); XCTAssertEqual(preview.preset?.id, "p18")
    }
    func testFrozenReviewPreservesPhotoAndUnknownCodeWithoutSubstitution() async throws {
        for avatar in ["https://example.test/existing.png", "px1:future", "px2:p01"] {
            let (document, _) = try await harness(avatar: avatar)
            let snapshot = try XCTUnwrap(MerchantNPCCharacterAvatarSnapshot(draft: try XCTUnwrap(document.coordinator.draft)))
            XCTAssertEqual(snapshot.rawValue, avatar); XCTAssertNil(snapshot.preset)
        }
        XCTAssertNil(MerchantNPCCharacterAvatarSnapshot(draft: .template(.init())))
    }
    func testNonCharacterDocumentNeverCreatesPicker() async throws {
        let reader = MerchantOperationsFixtureReader()
        let document = MerchantOperationsViewModel(reader: reader, destination: .profile); await document.load()
        XCTAssertNil(MerchantNPCPresetPickerModel(document: document))
    }
}

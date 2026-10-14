import XCTest
import UIKit
@testable import Questify

@MainActor private final class ProfilePreferenceSessionBox {
    var value: ProfileEditSession?
    init() throws { value = try .init(accountID: 901, epoch: 1, token: "synthetic-profile-preferences", viewerRevision: 1) }
}
@MainActor private final class ProfilePreferenceRemovalService: ProfileEditServing {
    var reads = 0, saves = 0
    var unknown = false, rejected = false, failRead = false
    var readback: String?
    var captured: ProfileEditPayload?
    var fields: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Walks",
        "avatar": " original-avatar ", "wechat": " original-qr ", "casePics": " one ;two ", "caseIntroducton": "Case", "tagIds": "4,7007",
        "sysCategoryList": [["id": 4, "categoryName": "Walks"], ["id": 7007, "categoryName": "Unavailable category"]]]
    func read(token: String) async throws -> ProfileEditSnapshot {
        reads += 1; if failRead { throw APIError.malformedResponse }
        var data = fields; if saves > 0, let readback { data["tagIds"] = readback }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: data))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        saves += 1; captured = payload
        if rejected { throw ProfileEditWriteError.rejected(.init(code: 422, message: "Synthetic rejection")) }
        if unknown { throw ProfileEditWriteError.outcomeUnknown }
        fields["nickname"] = payload.name; fields["introduction"] = payload.introduction
        fields["wechat"] = payload.wechat; fields["tagIds"] = payload.tagIds
        if let text = payload.caseIntroduction { fields["caseIntroducton"] = text }
    }
}
@MainActor final class ProfilePreferenceRemovalModelTests: XCTestCase {
    private func harness() async throws -> (ProfileEditModel, ProfilePreferenceRemovalService, ProfilePreferenceSessionBox) {
        let source = ProfilePreferenceRemovalService(), session = try ProfilePreferenceSessionBox()
        let model = ProfileEditModel(coordinator: .init(service: source, currentSession: { session.value }))
        await model.resetAndLoad(); return (model, source, session)
    }
    private func open(_ model: ProfileEditModel) throws -> ProfileTextFieldEdit {
        model.beginTextEdit(.preferences); return try XCTUnwrap(model.textEdit)
    }
    func testOpeningUsesCurrentSelfSelectionWithoutCatalogueOrAnotherRequest() async throws {
        let (model, source, _) = try await harness(); let edit = try open(model)
        XCTAssertEqual(ProfilePreferenceRemoval.selection(draft: edit.draft, snapshot: edit.snapshot), [4, 7007])
        XCTAssertEqual(edit.snapshot.preferenceNames[7007], "Unavailable category")
        XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0); model.cancelTextEdit(edit)
    }
    func testCancellationAndNoOpKeepExactRawTagIDsAndOtherDraftFields() async throws {
        let (model, source, _) = try await harness(); source.fields["tagIds"] = " 4, 7007 "; await model.load()
        model.draft.caseIntroduction = "Local case"; model.draft.removesContactQR = true
        let before = model.draft, cancelled = try open(model); model.cancelTextEdit(cancelled)
        XCTAssertEqual(model.draft, before)
        XCTAssertTrue(model.confirmPreferenceRemoval(try open(model), selectedIDs: [4, 7007]))
        XCTAssertNil(model.draft.routePreferenceIDs); XCTAssertEqual(model.draft, before)
        let payload = try ProfileEditPayload(draft: model.draft, preserving: XCTUnwrap(model.coordinator.snapshot))
        XCTAssertEqual(payload.tagIds, " 4, 7007 "); XCTAssertEqual(source.saves, 0)
    }
    func testRemovingUnavailableSelectedIDStagesOnlyPreferenceSubset() async throws {
        let (model, source, _) = try await harness(); model.draft.caseIntroduction = "Case draft"; model.draft.removesContactQR = true
        XCTAssertTrue(model.confirmPreferenceRemoval(try open(model), selectedIDs: [4]))
        XCTAssertEqual(model.draft.routePreferenceIDs, [4]); XCTAssertEqual(model.draft.caseIntroduction, "Case draft")
        XCTAssertTrue(model.draft.removesContactQR); XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0)
    }
    func testAdditionReorderDuplicateAndNonpositiveActionsAreRejected() async throws {
        for proposed in [[4, 9], [7007, 4], [4, 4], [-4], [0]] {
            let (model, source, _) = try await harness(); XCTAssertFalse(model.confirmPreferenceRemoval(try open(model), selectedIDs: proposed))
            XCTAssertNil(model.draft.routePreferenceIDs); XCTAssertEqual(source.saves, 0)
        }
    }
    func testWrongFieldAndFreeFormInvalidSelectionCannotStage() async throws {
        let (model, _, _) = try await harness(); model.beginTextEdit(.name); let name = try XCTUnwrap(model.textEdit)
        XCTAssertFalse(model.confirmPreferenceRemoval(name, selectedIDs: [])); XCTAssertEqual(model.textEdit?.id, name.id)
        model.cancelTextEdit(name); let edit = try open(model)
        XCTAssertFalse(model.confirmTextEdit(edit, text: "4,,7007")); XCTAssertNil(model.draft.routePreferenceIDs)
    }
    func testExistingStagedNewSelectionCanOnlyBeReducedNotReplaced() async throws {
        let (model, _, _) = try await harness(); model.draft.routePreferenceIDs = [9, 4]
        XCTAssertTrue(model.confirmPreferenceRemoval(try open(model), selectedIDs: [9])); XCTAssertEqual(model.draft.routePreferenceIDs, [9])
        XCTAssertFalse(model.confirmPreferenceRemoval(try open(model), selectedIDs: [7007])); XCTAssertEqual(model.draft.routePreferenceIDs, [9])
    }
    func testClearAllIsAnExplicitDirtySelectionAndRequiresWholePageReview() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmPreferenceRemoval(try open(model), selectedIDs: []))
        XCTAssertEqual(model.draft.routePreferenceIDs, []); XCTAssertFalse(model.requestExit()); XCTAssertNotNil(model.exitConfirmation)
        model.cancelExit(); await model.requestReload(); XCTAssertNotNil(model.reloadConfirmation); model.cancelReload()
        await model.prepare(); let review = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(review.payload.preferenceIDs, []); XCTAssertEqual(review.payload.tagIds, ""); XCTAssertEqual(source.saves, 0)
    }
    func testMalformedStoredSelectionFailsClosedWithoutLosingOtherDrafts() async throws {
        let (model, source, _) = try await harness(); source.fields["tagIds"] = "4,invalid,7007"; await model.load()
        model.draft.caseIntroduction = "Local"; let edit = try open(model)
        XCTAssertNil(ProfilePreferenceRemoval.selection(draft: edit.draft, snapshot: edit.snapshot))
        XCTAssertFalse(model.confirmPreferenceRemoval(edit, selectedIDs: [])); XCTAssertNil(model.draft.routePreferenceIDs)
        XCTAssertEqual(model.draft.caseIntroduction, "Local"); XCTAssertEqual(source.saves, 0)
    }
    func testOldApplyCancelAndDraftABACannotAffectNewerSelectionEditor() async throws {
        let (model, _, _) = try await harness(); let first = try open(model), before = model.draft
        model.draft.name = "Temporary"; model.draft = before
        XCTAssertFalse(model.confirmPreferenceRemoval(first, selectedIDs: [])); let second = try open(model)
        model.cancelTextEdit(first); XCTAssertEqual(model.textEdit?.id, second.id)
        XCTAssertFalse(model.confirmPreferenceRemoval(first, selectedIDs: [])); XCTAssertEqual(model.textEdit?.id, second.id)
    }
    func testOwnerEpochAndViewerChangesInvalidateOldRemoval() async throws {
        for next in [(902, UInt64(1), UInt64(1)), (901, UInt64(2), UInt64(1)), (901, UInt64(1), UInt64(2))] {
            let (model, source, session) = try await harness(); let edit = try open(model)
            session.value = try .init(accountID: next.0, epoch: next.1, token: "synthetic-profile-preferences", viewerRevision: next.2)
            XCTAssertFalse(model.confirmPreferenceRemoval(edit, selectedIDs: [])); XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0)
        }
    }
    func testChangedSelectedIDsRejectOldLocalEditorAndPreReviewSave() async throws {
        let (model, source, _) = try await harness(); let edit = try open(model)
        source.fields["tagIds"] = "4,8"; _ = await model.coordinator.load()
        XCTAssertFalse(model.confirmPreferenceRemoval(edit, selectedIDs: [4]))
        XCTAssertTrue(model.confirmPreferenceRemoval(try open(model), selectedIDs: [4]))
        source.fields["tagIds"] = "4,9"; await model.prepare(); XCTAssertNil(model.confirmation); XCTAssertEqual(source.saves, 0)
    }
    func testSelectionChangeAfterReviewPreventsWrite() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmPreferenceRemoval(try open(model), selectedIDs: [4])); await model.prepare()
        let review = try XCTUnwrap(model.confirmation); source.fields["tagIds"] = "4,9"; await model.save(review)
        XCTAssertEqual(source.saves, 0); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.changed")
    }
    func testSaveReopensVerifiedReducedSelectionAndCannotRestoreWithOldAction() async throws {
        let (model, source, _) = try await harness(); let old = try open(model)
        XCTAssertTrue(model.confirmPreferenceRemoval(old, selectedIDs: [4])); await model.prepare(); await model.save(try XCTUnwrap(model.confirmation))
        XCTAssertEqual(source.saves, 1); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved")
        XCTAssertEqual(model.coordinator.snapshot?.tagIds, "4"); XCTAssertNil(model.draft.routePreferenceIDs)
        XCTAssertFalse(model.confirmPreferenceRemoval(old, selectedIDs: [4, 7007]))
        let new = try open(model); XCTAssertEqual(ProfilePreferenceRemoval.selection(draft: new.draft, snapshot: new.snapshot), [4])
    }
    func testKnownAcknowledgmentWaitsForSelectedIDsReadbackWithoutReposting() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmPreferenceRemoval(try open(model), selectedIDs: [4])); await model.prepare()
        source.readback = "4,7007"; await model.save(try XCTUnwrap(model.confirmation)); XCTAssertTrue(model.coordinator.isLocked)
        source.readback = nil; await model.requestReload(); XCTAssertFalse(model.coordinator.isLocked); XCTAssertEqual(source.saves, 1)
    }
    func testUnknownWriteRemainsLockedEvenAfterMatchingSelectionReadback() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmPreferenceRemoval(try open(model), selectedIDs: [])); await model.prepare()
        source.unknown = true; await model.save(try XCTUnwrap(model.confirmation)); source.fields["tagIds"] = ""; await model.requestReload()
        XCTAssertTrue(model.coordinator.isLocked); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.readbackUnconfirmed")
        model.beginTextEdit(.preferences); XCTAssertNil(model.textEdit); XCTAssertEqual(source.saves, 1)
    }
    func testRejectedWriteAndFailedRefreshPreserveRemovalProposal() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmPreferenceRemoval(try open(model), selectedIDs: [4])); await model.prepare()
        source.rejected = true; await model.save(try XCTUnwrap(model.confirmation)); XCTAssertEqual(model.draft.routePreferenceIDs, [4])
        source.failRead = true; await model.requestReload(); let task = try XCTUnwrap(model.confirmReload(try XCTUnwrap(model.reloadConfirmation)))
        await task.value; XCTAssertEqual(model.draft.routePreferenceIDs, [4]); XCTAssertEqual(source.saves, 1)
    }
}

@MainActor private final class ProfilePreferencePickerTestReader: DiscoveryReading {
    var isConfigured = true
    var discoveryPresentationIdentity = "synthetic-preference-catalogue-1"
    var reads = 0
    func discoveryCategories(type: Int?) async throws -> [DiscoveryCategory] { reads += 1; return [] }
    func discoveryBanners() async throws -> [DiscoveryBanner] { throw APIError.notConfigured }
    func discoveryTemplateHome() async throws -> DiscoveryTemplateHome { throw APIError.notConfigured }
    func discoveryPlayTemplates(keyword: String, packType: DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate] { throw APIError.notConfigured }
    func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate] { throw APIError.notConfigured }
    func discoveryTopicTemplateDetail(id: Int) async throws -> PublicTopicTemplateDetail { throw APIError.notConfigured }
    func discoveryPlayTemplate(id: Int) async throws -> DiscoveryPlayTemplate { throw APIError.notConfigured }
}

extension ProfilePreferenceRemovalModelTests {
    private func openPicker(_ model: ProfileEditModel, reader: (any DiscoveryReading)?) throws -> ProfilePreferencePickerEdit {
        model.beginPreferencePicker(reader: reader)
        return try XCTUnwrap(model.preferencePicker)
    }
    func testCurrentCatalogueDoneStagesOnceAndPreservesOtherDraftFields() async throws {
        let (model, source, _) = try await harness(), reader = ProfilePreferencePickerTestReader()
        model.draft.name = "Local name"; model.draft.introduction = "Local introduction"
        model.draft.caseIntroduction = "Local case"; model.draft.removesContactQR = true
        let before = model.draft, edit = try openPicker(model, reader: reader)
        XCTAssertEqual(edit.selected, [4, 7007]); XCTAssertEqual(model.preferencePickerIdentity(edit), model.coordinator.identity)
        XCTAssertTrue(model.confirmPreferencePicker(edit, selectedIDs: [9, 4]))
        var expected = before; expected.routePreferenceIDs = [9, 4]
        XCTAssertEqual(model.draft, expected); XCTAssertNil(model.preferencePicker)
        XCTAssertFalse(model.confirmPreferencePicker(edit, selectedIDs: [])); XCTAssertEqual(model.draft, expected)
        XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0); XCTAssertEqual(reader.reads, 0)
    }
    func testCancelledCatalogueBindingsDoneAndDismissCannotAffectReopenedPicker() async throws {
        let (model, source, _) = try await harness(), reader = ProfilePreferencePickerTestReader()
        let before = model.draft, initial = model.preferencePickerPresentation(for: nil)
        let old = try openPicker(model, reader: reader), binding = model.preferencePickerPresentation(for: model.preferencePicker)
        let pendingReadIdentity = { model.preferencePickerIdentity(old) }
        XCTAssertEqual(binding.wrappedValue?.id, old.id); XCTAssertNil(initial.wrappedValue)
        binding.wrappedValue = nil; XCTAssertNil(model.preferencePicker); XCTAssertEqual(model.draft, before)
        let fresh = try openPicker(model, reader: reader), current = model.preferencePickerPresentation(for: model.preferencePicker)
        XCTAssertNotEqual(fresh.id, old.id); XCTAssertNil(binding.wrappedValue); XCTAssertNil(initial.wrappedValue)
        XCTAssertNil(pendingReadIdentity())
        initial.wrappedValue = fresh; binding.wrappedValue = fresh
        initial.wrappedValue = nil; binding.wrappedValue = nil; model.cancelPreferencePicker(old)
        XCTAssertFalse(model.confirmPreferencePicker(old, selectedIDs: []))
        XCTAssertEqual(current.wrappedValue?.id, fresh.id); XCTAssertEqual(model.draft, before)
        XCTAssertTrue(model.confirmPreferencePicker(fresh, selectedIDs: [4])); XCTAssertEqual(model.draft.routePreferenceIDs, [4])
        XCTAssertNil(current.wrappedValue); XCTAssertEqual(source.saves, 0); XCTAssertEqual(reader.reads, 0)
    }
    func testCatalogueOwnerEpochAndViewerChangesRejectOldDoneBeforeParentReload() async throws {
        for next in [(902, UInt64(1), UInt64(1)), (901, UInt64(2), UInt64(1)), (901, UInt64(1), UInt64(2))] {
            let (model, source, session) = try await harness(), reader = ProfilePreferencePickerTestReader()
            let edit = try openPicker(model, reader: reader), before = model.draft
            session.value = try .init(accountID: next.0, epoch: next.1, token: "synthetic-profile-preferences", viewerRevision: next.2)
            XCTAssertNil(model.preferencePickerIdentity(edit)); XCTAssertNil(model.preferencePicker)
            XCTAssertFalse(model.confirmPreferencePicker(edit, selectedIDs: [])); XCTAssertEqual(model.draft, before)
            XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0); XCTAssertEqual(reader.reads, 0)
        }
    }
    func testCatalogueDraftABAAndReloadCannotReviveOldSelection() async throws {
        let (model, source, _) = try await harness(), reader = ProfilePreferencePickerTestReader()
        let edit = try openPicker(model, reader: reader), before = model.draft
        model.draft.name = "Temporary"; model.draft = before
        XCTAssertNil(model.preferencePickerIdentity(edit)); XCTAssertFalse(model.confirmPreferencePicker(edit, selectedIDs: []))
        for failure in [false, true] {
            let captured = try openPicker(model, reader: reader)
            source.failRead = failure; await model.load()
            XCTAssertNil(model.preferencePickerIdentity(captured))
            XCTAssertFalse(model.confirmPreferencePicker(captured, selectedIDs: []))
            XCTAssertNil(model.draft.routePreferenceIDs); XCTAssertEqual(source.saves, 0)
        }
    }
    func testCatalogueReadInvalidationRetiresOldIdentityAndCannotRevive() async throws {
        let (model, source, _) = try await harness(), reader = ProfilePreferencePickerTestReader()
        let edit = try openPicker(model, reader: reader), before = model.draft
        reader.isConfigured = false
        XCTAssertNil(model.preferencePickerIdentity(edit)); XCTAssertNil(model.preferencePicker)
        reader.isConfigured = true
        XCTAssertFalse(model.confirmPreferencePicker(edit, selectedIDs: [])); XCTAssertEqual(model.draft, before)
        reader.discoveryPresentationIdentity = "\u{00E9}"
        let fresh = try openPicker(model, reader: reader)
        reader.discoveryPresentationIdentity = "e\u{0301}"
        XCTAssertNil(model.preferencePickerIdentity(fresh))
        XCTAssertFalse(model.confirmPreferencePicker(fresh, selectedIDs: [])); XCTAssertEqual(model.draft, before)
        XCTAssertEqual(source.saves, 0); XCTAssertEqual(reader.reads, 0)
    }
    func testCatalogueBackgroundAndActualAnchorDismantleRejectLateDone() async throws {
        for mode in 0...2 {
            let (model, source, _) = try await harness(), reader = ProfilePreferencePickerTestReader()
            let edit = try openPicker(model, reader: reader), before = model.draft
            if mode == 2 {
                let anchor = ProfileAvatarOwnerAnchor(model: model)
                ProfileAvatarOwnerAnchor.dismantleUIViewController(UIViewController(), coordinator: anchor.makeCoordinator())
            } else if mode == 1 { model.suspendForBackground() }
            else { model.retireAvatar() }
            XCTAssertNil(model.preferencePicker); XCTAssertNil(model.preferencePickerIdentity(edit))
            XCTAssertFalse(model.confirmPreferencePicker(edit, selectedIDs: []))
            model.beginPreferencePicker(reader: reader); XCTAssertNil(model.preferencePicker)
            XCTAssertEqual(model.draft, before); XCTAssertEqual(source.saves, 0)
            model.activateAvatar(); let fresh = try openPicker(model, reader: reader)
            model.cancelPreferencePicker(edit); XCTAssertEqual(model.preferencePicker?.id, fresh.id)
        }
    }
    func testUnconfiguredCatalogueCannotStageEvenWithDirectDoneCallback() async throws {
        let (model, source, _) = try await harness(), reader = ProfilePreferencePickerTestReader()
        for available in [false, true] {
            reader.isConfigured = false
            let edit = try openPicker(model, reader: available ? reader : nil), before = model.draft
            XCTAssertNotNil(model.preferencePickerIdentity(edit))
            XCTAssertFalse(model.confirmPreferencePicker(edit, selectedIDs: [9]))
            XCTAssertEqual(model.draft, before); XCTAssertNil(model.preferencePicker)
        }
        XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0); XCTAssertEqual(reader.reads, 0)
    }
    func testCatalogueAndFieldEditorsRemainMutuallyExclusive() async throws {
        let (model, source, _) = try await harness(), reader = ProfilePreferencePickerTestReader()
        let picker = try openPicker(model, reader: reader)
        model.beginTextEdit(.name); XCTAssertNil(model.textEdit); XCTAssertEqual(model.preferencePicker?.id, picker.id)
        model.cancelPreferencePicker(picker); model.beginTextEdit(.name)
        let field = try XCTUnwrap(model.textEdit)
        model.beginPreferencePicker(reader: reader); XCTAssertNil(model.preferencePicker); XCTAssertEqual(model.textEdit?.id, field.id)
        XCTAssertEqual(source.saves, 0); XCTAssertEqual(reader.reads, 0)
    }
}


extension ProfilePreferenceRemovalModelTests {
    func testMalformedStoredPreferencesCannotBeSilentlyCompactedByCatalogueEntry() async throws {
        let (model, source, _) = try await harness(), reader = ProfilePreferencePickerTestReader()
        source.fields["tagIds"] = "4,invalid,7007"; await model.load()
        let before = model.draft
        model.beginPreferencePicker(reader: reader)
        XCTAssertNil(model.preferencePicker); XCTAssertEqual(model.draft, before)
        XCTAssertEqual(source.saves, 0); XCTAssertEqual(reader.reads, 0)
    }
}

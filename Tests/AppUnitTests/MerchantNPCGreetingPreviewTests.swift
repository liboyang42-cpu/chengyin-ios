import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class MerchantNPCGreetingPreviewTests: XCTestCase {
    private func harness(name: String = "  Draft name  ", greeting: String = "Opening\n**as written**") async -> (MerchantOperationsViewModel, MerchantOperationsFixtureReader) {
        let reader = MerchantOperationsFixtureReader(); var value = MerchantStoreCharacter()
        value.name = name; value.greeting = greeting; value.avatar = "px1:p01"
        value.persona = "Private persona must not enter the preview"; value.knowledge = "Private knowledge must not enter the preview"
        reader.replace(.character, with: .draft(.character(value)))
        let document = MerchantOperationsViewModel(reader: reader, destination: .character); await document.load()
        return (document, reader)
    }
    func testPreviewCopiesOnlyTwoOriginalFieldsWithoutReadOrSave() async throws {
        let (document, reader) = await harness(); let before = document.coordinator.draft; let reads = reader.accessCount
        let model = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document)); let snapshot = try XCTUnwrap(model.snapshot)
        XCTAssertEqual(snapshot.name, "  Draft name  "); XCTAssertEqual(snapshot.greeting, "Opening\n**as written**")
        XCTAssertEqual(Set(Mirror(reflecting: snapshot).children.compactMap(\.label)), Set(["name", "greeting"]))
        XCTAssertEqual(document.coordinator.draft, before); XCTAssertFalse(document.coordinator.isDirty)
        XCTAssertEqual(reader.saveCount, 0); XCTAssertEqual(reader.accessCount, reads)
    }
    func testEmptyFieldsStayEmptyInsteadOfInventingAnOpening() async throws {
        let (document, _) = await harness(name: "", greeting: "")
        let model = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
        XCTAssertEqual(model.snapshot?.name, ""); XCTAssertEqual(model.snapshot?.greeting, "")
    }
    func testUTF8BudgetRejectsOversizedProjectionWithoutChangingDraft() async {
        let (document, reader) = await harness(name: "Name", greeting: String(repeating: "界", count: 1_365))
        let before = document.coordinator.draft
        XCTAssertNil(MerchantNPCGreetingPreviewModel(document: document)); XCTAssertEqual(document.coordinator.draft, before)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testVisibleFieldChangeAndReturnToSameTextCannotReviveOldPreview() async throws {
        let (document, _) = await harness(); let model = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
        guard case .character(let original) = document.coordinator.draft else { return XCTFail() }
        var changed = original; changed.greeting = "Changed"
        document.edit(.character(changed)); document.edit(.character(original))
        XCTAssertNil(model.snapshot); XCTAssertNil(model.snapshot)
        XCTAssertNotNil(MerchantNPCGreetingPreviewModel(document: document))
    }
    func testAnyDocumentEditRetiresSnapshotWithoutCopyingPrivateFields() async throws {
        let (document, _) = await harness(); let model = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
        guard case .character(var changed) = document.coordinator.draft else { return XCTFail() }
        changed.persona = "New private input"; document.edit(.character(changed))
        XCTAssertNil(model.snapshot)
    }
    func testScopeAndDraftIdentityChangesRetirePreview() async throws {
        let (document, reader) = await harness(); let model = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
        reader.switchAccount(); XCTAssertNil(model.snapshot)
        let (other, _) = await harness(); let original = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: other))
        other.discard(); XCTAssertNil(original.snapshot)
    }
    func testSignedOutAndDeniedDocumentsCannotOpenPreview() async throws {
        let (document, reader) = await harness(); let model = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
        reader.isAuthenticated = false; XCTAssertNil(model.snapshot); XCTAssertNil(MerchantNPCGreetingPreviewModel(document: document))
        let denied = MerchantOperationsFixtureReader(); denied.denied = true
        let other = MerchantOperationsViewModel(reader: denied, destination: .character); await other.load()
        XCTAssertNil(MerchantNPCGreetingPreviewModel(document: other))
    }
    func testUnloadedOrDifferentDestinationCannotBeUsedAsCharacterPreview() async {
        let reader = MerchantOperationsFixtureReader()
        let unloaded = MerchantOperationsViewModel(reader: reader, destination: .character)
        XCTAssertNil(MerchantNPCGreetingPreviewModel(document: unloaded))
        let profile = MerchantOperationsViewModel(reader: reader, destination: .profile); await profile.load()
        XCTAssertNil(MerchantNPCGreetingPreviewModel(document: profile))
    }
    func testReviewAndUnknownWriteLockCannotBeBypassed() async throws {
        let (document, reader) = await harness(name: "Name", greeting: "Opening")
        guard case .character(var changed) = document.coordinator.draft else { return XCTFail() }
        changed.name = "New name"; document.edit(.character(changed)); document.prepare()
        XCTAssertNil(MerchantNPCGreetingPreviewModel(document: document))
        reader.saveFailure = .outcomeUnknown
        await document.confirm(try XCTUnwrap(document.coordinator.confirmation))
        XCTAssertTrue(document.coordinator.isLocked); XCTAssertNil(MerchantNPCGreetingPreviewModel(document: document))
    }
    func testRetirementIsPermanentAndNeverEditsOrSaves() async throws {
        let (document, reader) = await harness(); let before = document.coordinator.draft
        let model = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
        model.retire(); XCTAssertNil(model.snapshot); XCTAssertNil(model.snapshot)
        XCTAssertEqual(document.coordinator.draft, before); XCTAssertEqual(reader.saveCount, 0)
    }
    func testExactUTF8BudgetIsAcceptedAndOneByteOverIsRejected() async throws {
        let (document, _) = await harness(name: "N", greeting: String(repeating: "a", count: 4_095))
        let preview = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
        XCTAssertEqual(preview.snapshot?.greeting.utf8.count, 4_095)
        guard case .character(var changed) = document.coordinator.draft else { return XCTFail() }
        changed.greeting.append("a"); document.edit(.character(changed))
        XCTAssertNil(preview.snapshot); XCTAssertNil(MerchantNPCGreetingPreviewModel(document: document))
    }
    func testCanonicallyEquivalentRawNameChangeRetiresEvenWithoutViewModelRevision() async throws {
        let (document, _) = await harness(name: "Caf\u{00E9}")
        let preview = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document)); let revision = document.revision
        guard case .character(var changed) = document.coordinator.draft else { return XCTFail() }
        changed.name = "Cafe\u{0301}"; document.coordinator.edit(.character(changed))
        XCTAssertEqual(document.revision, revision)
        XCTAssertNil(preview.snapshot)
    }
    func testCanonicallyEquivalentRawGreetingChangeRetiresEvenWithoutViewModelRevision() async throws {
        let (document, _) = await harness(greeting: "Caf\u{00E9}")
        let preview = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document)); let revision = document.revision
        guard case .character(var changed) = document.coordinator.draft else { return XCTFail() }
        changed.greeting = "Cafe\u{0301}"; document.coordinator.edit(.character(changed))
        XCTAssertEqual(document.revision, revision)
        XCTAssertNil(preview.snapshot)
    }
    func testObservedSignOutCannotReviveRetiredPreviewAfterSignIn() async throws {
        let (document, reader) = await harness(); let preview = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
        reader.isAuthenticated = false; XCTAssertNil(preview.snapshot)
        reader.isAuthenticated = true; XCTAssertNil(preview.snapshot)
        XCTAssertNotNil(MerchantNPCGreetingPreviewModel(document: document))
    }
    func testReopenUsesCurrentDraftAndKeepsPreviousPreviewRetired() async throws {
        let (document, reader) = await harness(); let first = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
        first.retire()
        guard case .character(var changed) = document.coordinator.draft else { return XCTFail() }
        changed.name = "Current name"; changed.greeting = "Current opening"; document.edit(.character(changed))
        let next = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
        XCTAssertNotEqual(first.id, next.id); XCTAssertNil(first.snapshot)
        XCTAssertEqual(next.snapshot?.name, "Current name"); XCTAssertEqual(next.snapshot?.greeting, "Current opening")
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testReviewAndInvalidationRetireExistingPreview() async throws {
        let (document, _) = await harness(name: "Name", greeting: "Opening")
        guard case .character(var changed) = document.coordinator.draft else { return XCTFail() }
        changed.name = "New name"; document.edit(.character(changed))
        let preview = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
        document.prepare(); XCTAssertNotNil(document.coordinator.confirmation); XCTAssertNil(preview.snapshot)
        document.cancel(); XCTAssertNil(preview.snapshot)
        let reopened = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
        document.invalidate(); XCTAssertNil(reopened.snapshot)
    }
    func testBilingualLargeTextSheetConstructionIsReadOnly() async throws {
        let (document, reader) = await harness(); let reads = reader.accessCount
        for locale in ["en", "zh-Hans"] {
            let model = try XCTUnwrap(MerchantNPCGreetingPreviewModel(document: document))
            let host = UIHostingController(rootView: MerchantNPCGreetingPreviewSheet(model: model, document: document)
                .environment(\.locale, Locale(identifier: locale)).dynamicTypeSize(.accessibility5))
            host.loadViewIfNeeded()
        }
        XCTAssertEqual(reader.accessCount, reads); XCTAssertEqual(reader.saveCount, 0); XCTAssertFalse(document.coordinator.isDirty)
    }
}

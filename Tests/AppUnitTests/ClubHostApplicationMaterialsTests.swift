import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ClubHostApplicationMaterialsTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 81, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var storageNamespace = "synthetic-host-materials"
        let isConfigured = false
        let allowsOfflineWrites = false
        var reads = 0
        var sends = 0
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            reads += 1; throw ClubGovernanceFailure.notConfigured
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1; throw ClubGovernanceFailure.notConfigured
        }
    }
    private func context(_ access: Access, form: UUID = UUID()) -> ClubHostApplicationMaterials.Context {
        ClubHostApplicationMaterials.context(formID: form, scope: .init(), identity: access.identity, access: access)
    }
    private func image(bytes: Int = 4, id: UUID = UUID()) throws -> RetainedSelectedImage {
        try .init(jpeg: Data([255, 216, 255]) + Data(repeating: 0, count: max(0, bytes - 3)), width: 1, height: 1, id: id)
    }
    private func picker(_ model: ClubHostApplicationMaterials, _ c: ClubHostApplicationMaterials.Context) throws -> ClubHostApplicationMaterials.Presentation {
        XCTAssertTrue(model.open(.picker, context: c, allowed: { true }))
        return try XCTUnwrap(model.presentation)
    }
    private func add(_ model: ClubHostApplicationMaterials, _ c: ClubHostApplicationMaterials.Context, _ images: [RetainedSelectedImage]) throws {
        let p = try picker(model, c); XCTAssertTrue(model.accept(images, for: p, allowed: { true }))
    }
    func testOptionalEmptySelectionDoesNotBlockOriginalSubmission() {
        let access = Access(), model = ClubHostApplicationMaterials(); model.appear(context(access))
        XCTAssertFalse(model.blocksSubmission); XCTAssertEqual(access.reads, 0); XCTAssertEqual(access.sends, 0)
    }
    func testSelectionRetainsOnlySanitizedLocalImages() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()), picture = try image()
        model.appear(c); try add(model, c, [picture])
        XCTAssertEqual(model.items.map(\.image), [picture]); XCTAssertTrue(model.blocksSubmission)
    }
    func testNineImagesAcceptedAndTenthCannotOpenPicker() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()); model.appear(c)
        try add(model, c, (0..<9).map { _ in try image() })
        XCTAssertEqual(model.items.count, 9); XCTAssertFalse(model.open(.picker, context: c, allowed: { true }))
    }
    func testOversizedBatchCannotPartiallyReplaceExistingItems() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()), first = try image(); model.appear(c)
        try add(model, c, [first]); let p = try picker(model, c)
        XCTAssertFalse(model.accept(try (0..<9).map { _ in try image() }, for: p, allowed: { true }))
        XCTAssertEqual(model.items.map(\.image), [first]); XCTAssertTrue(model.selectionFailed)
    }
    func testExistingBoundedByteBudgetRejectsBatchAtomically() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()); model.appear(c)
        let p = try picker(model, c)
        let images = try (0..<4).map { _ in try image(bytes: RetainedSelectedImage.maximumBytes) }
        XCTAssertFalse(model.accept(images, for: p, allowed: { true })); XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(ClubHostApplicationMaterials.maximumBytes, MerchantGalleryBatchLimits.maximumRetainedBytes)
    }
    func testDuplicateImageIdentityCannotBeAddedTwice() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()), first = try image(); model.appear(c)
        try add(model, c, [first]); let p = try picker(model, c)
        XCTAssertFalse(model.accept([first], for: p, allowed: { true })); XCTAssertEqual(model.items.count, 1)
    }
    func testPickerCancelLeavesExistingSelectionUnchanged() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()), first = try image(); model.appear(c)
        try add(model, c, [first]); let p = try picker(model, c)
        XCTAssertFalse(model.accept(nil, for: p, allowed: { true })); XCTAssertEqual(model.items.map(\.image), [first])
    }
    func testEachRemoveRestoresOptionalEmptyReadiness() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()), first = try image(); model.appear(c)
        try add(model, c, [first]); XCTAssertTrue(model.remove(first.id, context: c, allowed: { true }))
        XCTAssertFalse(model.blocksSubmission)
    }
    func testPreviewUsesOnlyTheExactCurrentItem() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()), first = try image(); model.appear(c)
        try add(model, c, [first]); XCTAssertFalse(model.open(.preview(UUID()), context: c, allowed: { true }))
        XCTAssertTrue(model.open(.preview(first.id), context: c, allowed: { true }))
        XCTAssertEqual(model.presentation?.kind, .preview(first.id))
    }
    func testOldNilBindingCannotCloseReopenedPicker() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()); model.appear(c)
        let a = try picker(model, c), old = model.binding(a, allowed: { true }); model.close(a)
        let b = try picker(model, c); old.wrappedValue = nil
        XCTAssertNil(old.wrappedValue); XCTAssertEqual(model.presentation, b)
    }
    func testOldCancelCannotCloseNewPreview() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()), first = try image(); model.appear(c)
        try add(model, c, [first]); let a = try picker(model, c); model.close(a)
        XCTAssertTrue(model.open(.preview(first.id), context: c, allowed: { true })); let b = model.presentation
        model.close(a); XCTAssertEqual(model.presentation, b)
    }
    func testOldPickerCompletionCannotAppendIntoReopenedPicker() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()); model.appear(c)
        let a = try picker(model, c); model.close(a); let b = try picker(model, c)
        XCTAssertFalse(model.accept([try image()], for: a, allowed: { true }))
        XCTAssertTrue(model.items.isEmpty); XCTAssertEqual(model.presentation, b)
    }
    func testIdentityChangeRejectsLateSelectionBeforeLifecycleCallback() throws {
        let access = Access(), model = ClubHostApplicationMaterials(), form = UUID(); let c = context(access, form: form)
        model.appear(c); let p = try picker(model, c); access.identity = .init(accountID: 82, epoch: 2)
        XCTAssertFalse(model.accept([try image()], for: p, allowed: { c == self.context(access, form: form) }))
        XCTAssertTrue(model.items.isEmpty)
    }
    func testAuthorizationChangeClearsMaterialAndRejectsOldRemoval() throws {
        let access = Access(), model = ClubHostApplicationMaterials(), form = UUID(); let a = context(access, form: form)
        model.appear(a); let first = try image(); try add(model, a, [first]); access.authorizationGeneration = UUID()
        let b = context(access, form: form); model.appear(b)
        XCTAssertTrue(model.items.isEmpty); XCTAssertFalse(model.remove(first.id, context: a, allowed: { true }))
    }
    func testSameAccountReopenedFormRejectsPreviousPicker() throws {
        let access = Access(), model = ClubHostApplicationMaterials(); let a = context(access); model.appear(a)
        let p = try picker(model, a); let b = context(access); model.appear(b)
        XCTAssertFalse(model.accept([try image()], for: p, allowed: { true })); XCTAssertTrue(model.items.isEmpty)
    }
    func testBackgroundRetirementDropsBytesAndBlocksLateCallback() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()); model.appear(c)
        try add(model, c, [try image()]); let p = try picker(model, c); model.retire()
        XCTAssertTrue(model.items.isEmpty); XCTAssertNil(model.presentation)
        XCTAssertFalse(model.accept([try image()], for: p, allowed: { true }))
    }
    func testOldDepartureCannotRetireNewAttachment() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()); model.appear(c)
        let a = try XCTUnwrap(model.attachment); model.retire(); model.appear(c)
        let b = try XCTUnwrap(model.attachment); XCTAssertNotEqual(a, b)
        try add(model, c, [try image()]); model.retire(c, attachment: a)
        XCTAssertEqual(model.items.count, 1); XCTAssertEqual(model.attachment, b)
    }
    func testRepeatedAppearWhileCoveredPreservesMaterials() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()); model.appear(c)
        try add(model, c, [try image()]); let attachment = model.attachment; model.appear(c)
        XCTAssertEqual(model.items.count, 1); XCTAssertEqual(model.attachment, attachment)
    }
    func testUnavailableEditRejectsPickerPreviewRemoveAndLateResult() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()), first = try image(); model.appear(c)
        try add(model, c, [first]); let p = try picker(model, c)
        XCTAssertFalse(model.accept([try image()], for: p, allowed: { false })); model.close(p)
        XCTAssertFalse(model.open(.picker, context: c, allowed: { false }))
        XCTAssertFalse(model.open(.preview(first.id), context: c, allowed: { false }))
        XCTAssertFalse(model.remove(first.id, context: c, allowed: { false }))
        XCTAssertEqual(model.items.map(\.image), [first])
    }
    func testLocalMaterialNeverCreatesServerReferenceOrServiceCall() throws {
        let access = Access(), model = ClubHostApplicationMaterials(); let c = context(access); model.appear(c)
        var draft = ClubGovernanceFormDraft(operation: .hostApply, scope: .init())
        draft.text["leaderName"] = "Example"; draft.text["phone"] = "13800000000"
        try add(model, c, [try image()])
        XCTAssertEqual(draft.text["certImages"], ""); XCTAssertTrue(model.blocksSubmission)
        XCTAssertEqual(access.reads, 0); XCTAssertEqual(access.sends, 0)
    }
    func testHiddenHostCannotReactivateOnForegroundOrContextChange() throws {
        let access = Access(), model = ClubHostApplicationMaterials(), form = UUID()
        let c = context(access, form: form); model.appear(c)
        let lease = try XCTUnwrap(model.attachment); model.hide(); model.depart(c, attachment: lease)
        model.activate(c)
        XCTAssertNil(model.attachment); XCTAssertFalse(model.open(.picker, context: c, allowed: { true }))
        access.authorizationGeneration = UUID(); let changed = context(access, form: form); model.activate(changed)
        XCTAssertNil(model.attachment); XCTAssertFalse(model.open(.picker, context: changed, allowed: { true }))
    }
    func testCoveredHostKeepsExistingPickerButCannotOpenAnother() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()); model.appear(c)
        let p = try picker(model, c), lease = model.attachment; model.hide(); model.activate(c)
        XCTAssertEqual(model.attachment, lease); XCTAssertTrue(model.current(p, allowed: { true }))
        XCTAssertTrue(model.accept([try image()], for: p, allowed: { true }))
        XCTAssertFalse(model.open(.picker, context: c, allowed: { true }))
        model.appear(c); XCTAssertEqual(model.items.count, 1)
    }
    func testOldRowAttachmentCannotOpenAfterTrueDepartureAndReturn() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()); model.appear(c)
        let old = try XCTUnwrap(model.attachment)
        let oldRow: () -> Bool = { model.attachment == old }
        model.depart(c, attachment: old); model.appear(c)
        XCTAssertNotEqual(model.attachment, old)
        XCTAssertFalse(model.open(.picker, context: c, allowed: oldRow))
        XCTAssertTrue(model.open(.picker, context: c, allowed: { true }))
    }
    func testActualDepartureImmediatelyInvalidatesCoveredPicker() throws {
        let model = ClubHostApplicationMaterials(), c = context(Access()); model.appear(c)
        let p = try picker(model, c), lease = try XCTUnwrap(model.attachment)
        model.hide(); model.depart(c, attachment: lease)
        XCTAssertFalse(model.current(p, allowed: { true }))
        XCTAssertFalse(model.accept([try image()], for: p, allowed: { true }))
        XCTAssertTrue(model.items.isEmpty); model.activate(c); XCTAssertNil(model.attachment)
    }

}

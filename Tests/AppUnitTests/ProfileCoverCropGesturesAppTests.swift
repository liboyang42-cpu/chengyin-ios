import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ProfileCoverCropGesturesAppTests: XCTestCase {
    private final class Box { var value = ProfileCoverCropPosition(zoom: 2); var current = true; var changes = 0 }
    private func bind(_ coordinator: ProfileCoverGesturePreview.Coordinator, _ view: ProfileCoverCropCanvas,
                      _ box: Box, id: UUID, source: RetainedSelectedImage) {
        coordinator.bind(view, draftID: id, source: source,
                         position: Binding(get: { box.value }, set: { box.value = $0; box.changes += 1 }), isCurrent: { box.current })
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 240); view.layoutIfNeeded()
    }
    func testSyntheticCanvasPreservesFixedFrameAndGestureUpdatesBinding() throws {
        let c = ProfileCoverGesturePreview.Coordinator(), v = ProfileCoverCropCanvas(), b = Box()
        bind(c, v, b, id: UUID(), source: try ProfileLocalCoverSyntheticImage.make())
        XCTAssertEqual(v.cropBounds.width, 320); XCTAssertEqual(v.cropBounds.height, 180)
        c.applyPan(deltaX: 32, deltaY: 0, to: v)
        XCTAssertEqual(b.changes, 1); XCTAssertLessThan(b.value.horizontal, 0.5)
        c.applyPinch(factor: 1.5, to: v); XCTAssertEqual(b.value.zoom, 3)
        XCTAssertEqual(v.position, b.value)
    }
    func testSliderChangeIsReflectedWithoutReplacingGestureLifetime() throws {
        let c = ProfileCoverGesturePreview.Coordinator(), v = ProfileCoverCropCanvas(), b = Box(), id = UUID()
        let source = try ProfileLocalCoverSyntheticImage.make()
        bind(c, v, b, id: id, source: source)
        b.value.horizontal = 0.1; b.value.vertical = 0.9; b.value.zoom = 3
        bind(c, v, b, id: id, source: source)
        XCTAssertEqual(v.position, b.value); c.applyPan(deltaX: -16, deltaY: 0, to: v)
        XCTAssertGreaterThan(b.value.horizontal, 0.1); XCTAssertEqual(b.value.zoom, 3)
    }
    func testRetiredCoordinatorCannotWriteOrRebind() throws {
        let c = ProfileCoverGesturePreview.Coordinator(), v = ProfileCoverCropCanvas(), b = Box(), source = try ProfileLocalCoverSyntheticImage.make()
        bind(c, v, b, id: UUID(), source: source); c.retire(v)
        c.applyPinch(factor: 2, to: v); bind(c, v, b, id: UUID(), source: source); c.applyPan(deltaX: 20, deltaY: 0, to: v)
        XCTAssertEqual(b.changes, 0); XCTAssertFalse(v.hasValidImage); XCTAssertNil(v.source)
    }
    func testExpiredOwnerLeaseCannotRevive() throws {
        let c = ProfileCoverGesturePreview.Coordinator(), v = ProfileCoverCropCanvas(), b = Box()
        bind(c, v, b, id: UUID(), source: try ProfileLocalCoverSyntheticImage.make())
        b.current = false; c.applyPinch(factor: 2, to: v); b.current = true; c.applyPinch(factor: 2, to: v)
        XCTAssertEqual(b.changes, 0); XCTAssertFalse(v.hasValidImage)
    }
    func testUnexpectedDraftReplacementRetiresOldCoordinator() throws {
        let c = ProfileCoverGesturePreview.Coordinator(), v = ProfileCoverCropCanvas(), a = Box(), b = Box()
        let source = try ProfileLocalCoverSyntheticImage.make()
        bind(c, v, a, id: UUID(), source: source); bind(c, v, b, id: UUID(), source: source)
        c.applyPinch(factor: 2, to: v)
        XCTAssertEqual(a.changes, 0); XCTAssertEqual(b.changes, 0); XCTAssertNil(v.draftID)
    }
    func testUnexpectedSourceReplacementRetiresEvenForSameDraftID() throws {
        let c = ProfileCoverGesturePreview.Coordinator(), v = ProfileCoverCropCanvas(), b = Box(), id = UUID()
        bind(c, v, b, id: id, source: try ProfileLocalCoverSyntheticImage.make())
        bind(c, v, b, id: id, source: try ProfileLocalCoverSyntheticImage.make())
        c.applyPinch(factor: 2, to: v); XCTAssertEqual(b.changes, 0); XCTAssertNil(v.source)
    }
    func testInvalidViewportAndGestureDoNotChangeBinding() throws {
        let c = ProfileCoverGesturePreview.Coordinator(), v = ProfileCoverCropCanvas(), b = Box()
        bind(c, v, b, id: UUID(), source: try ProfileLocalCoverSyntheticImage.make())
        v.frame = .zero; v.layoutIfNeeded(); c.applyPan(deltaX: 20, deltaY: 10, to: v)
        c.applyPinch(factor: .nan, to: v); XCTAssertEqual(b.changes, 0)
    }
    func testGestureResultUsesExistingReviewAndOnlyExplicitSavePersists() throws {
        let reader = ProfileAuthorPostsRefreshFixtureReader(), store = ProfileLocalCoverFixtureStore()
        let owner = try ProfileLocalCoverOwner(accountID: 81, namespace: "synthetic-cover-gesture")
        let model = ProfileLocalCoverModel(context: .init(owner: owner, reader: reader), store: store, current: { .init(owner: owner, reader: reader) })
        model.controller.load(); model.open()
        let source = try ProfileLocalCoverSyntheticImage.make(), draft = MerchantImageCropDraft(source: source, aspect: .gallery)
        model.crop = draft
        let p = try ProfileCoverCropPosition().pinched(by: 2, sourceWidth: source.width, sourceHeight: source.height)
        let moved = try p.panned(deltaX: 20, deltaY: 0, viewportWidth: 320, viewportHeight: 180, sourceWidth: source.width, sourceHeight: source.height)
        model.acceptCrop(id: draft.id, rect: try moved.rect(sourceWidth: source.width, sourceHeight: source.height))
        XCTAssertEqual(store.writes, 0)
        let review = try XCTUnwrap(model.controller.review); XCTAssertEqual(review.image?.width, 160)
        model.confirm(review); XCTAssertEqual(store.writes, 1); XCTAssertFalse(model.isPresented)
    }
    func testCancelAfterGestureNeverWritesExistingCover() throws {
        let reader = ProfileAuthorPostsRefreshFixtureReader(), store = ProfileLocalCoverFixtureStore()
        let owner = try ProfileLocalCoverOwner(accountID: 81, namespace: "synthetic-cover-gesture")
        let model = ProfileLocalCoverModel(context: .init(owner: owner, reader: reader), store: store, current: { .init(owner: owner, reader: reader) })
        model.controller.load(); model.open(); model.crop = .init(source: try ProfileLocalCoverSyntheticImage.make(), aspect: .gallery)
        model.cancelCrop(id: try XCTUnwrap(model.crop?.id)); XCTAssertNil(model.crop)
        model.close(); XCTAssertEqual(store.writes, 0); XCTAssertNil(model.controller.review)
    }
    func testAccountSwitchRejectsGestureAndItsOldCropConfirmation() throws {
        let reader = ProfileAuthorPostsRefreshFixtureReader(), store = ProfileLocalCoverFixtureStore()
        let owner = try ProfileLocalCoverOwner(accountID: 81, namespace: "synthetic-cover-gesture")
        let model = ProfileLocalCoverModel(context: .init(owner: owner, reader: reader), store: store, current: { .init(owner: owner, reader: reader) })
        model.controller.load(); model.open(); let source = try ProfileLocalCoverSyntheticImage.make(), draft = MerchantImageCropDraft(source: source, aspect: .gallery)
        model.crop = draft
        let c = ProfileCoverGesturePreview.Coordinator(), v = ProfileCoverCropCanvas(), b = Box()
        c.bind(v, draftID: draft.id, source: source, position: Binding(get: { b.value }, set: { b.value = $0; b.changes += 1 }),
               isCurrent: { model.isPresented && model.controller.canEdit && model.crop?.id == draft.id })
        reader.switchAccount(); c.applyPinch(factor: 2, to: v)
        model.acceptCrop(id: draft.id, rect: try b.value.rect(sourceWidth: source.width, sourceHeight: source.height))
        XCTAssertEqual(b.changes, 0); XCTAssertEqual(store.writes, 0); XCTAssertNil(model.controller.review)
    }
    func testRenderedImageCoversFrameAfterExtremePanAndPinch() throws {
        let c = ProfileCoverGesturePreview.Coordinator(), v = ProfileCoverCropCanvas(), b = Box()
        bind(c, v, b, id: UUID(), source: try ProfileLocalCoverSyntheticImage.make())
        for delta in [-10000.0, 10000.0] {
            c.applyPinch(factor: 2, to: v); c.applyPan(deltaX: delta, deltaY: -delta, to: v); v.layoutIfNeeded()
            XCTAssertLessThanOrEqual(v.renderedImageBounds.minX, 0)
            XCTAssertLessThanOrEqual(v.renderedImageBounds.minY, 0)
            XCTAssertGreaterThanOrEqual(v.renderedImageBounds.maxX, v.cropBounds.width - 0.001)
            XCTAssertGreaterThanOrEqual(v.renderedImageBounds.maxY, v.cropBounds.height - 0.001)
        }
    }
    func testMalformedLocalImageCannotBecomeGestureSource() throws {
        let c = ProfileCoverGesturePreview.Coordinator(), v = ProfileCoverCropCanvas(), b = Box()
        let bad = try RetainedSelectedImage(jpeg: Data([255, 216, 255, 0]), width: 320, height: 180)
        bind(c, v, b, id: UUID(), source: bad); c.applyPinch(factor: 2, to: v)
        XCTAssertEqual(b.changes, 0); XCTAssertFalse(v.hasValidImage)
    }

}
extension ProfileCoverCropGesturesAppTests {
    private func cropRetryFixture(saved: Bool = false) throws -> (
        model: ProfileLocalCoverModel, reader: ProfileAuthorPostsRefreshFixtureReader,
        store: ProfileLocalCoverFixtureStore, owner: ProfileLocalCoverOwner,
        source: RetainedSelectedImage, draft: MerchantImageCropDraft
    ) {
        let reader = ProfileAuthorPostsRefreshFixtureReader(), store = ProfileLocalCoverFixtureStore()
        let owner = try ProfileLocalCoverOwner(accountID: 81, namespace: "synthetic-crop-retry")
        let source = try ProfileLocalCoverSyntheticImage.make()
        if saved { store.images[owner] = source }
        let model = ProfileLocalCoverModel(context: .init(owner: owner, reader: reader), store: store,
            current: { .init(owner: owner, reader: reader) })
        model.controller.load(); model.open()
        let draft = MerchantImageCropDraft(source: source, aspect: .gallery)
        model.crop = draft
        return (model, reader, store, owner, source, draft)
    }
    private func outOfSourceCrop() throws -> MerchantImageCropRect {
        // Real renderer failure, using only synthetic pixels. Never an actual photo.
        try .init(sourceWidth: 640, sourceHeight: 360, aspect: .gallery)
    }
    func testCropRenderFailureKeepsCurrentDraftAndSavedCoverWithoutWriting() throws {
        let f = try cropRetryFixture(saved: true)
        f.model.acceptCrop(id: f.draft.id, rect: try outOfSourceCrop())
        XCTAssertTrue(f.model.selectionError); XCTAssertTrue(f.model.isPresented)
        XCTAssertEqual(f.model.crop?.id, f.draft.id)
        XCTAssertEqual(f.model.crop?.source, f.source)
        XCTAssertNil(f.model.controller.review); XCTAssertEqual(f.store.writes, 0)
        XCTAssertTrue(ProfileLocalCoverController.sameImage(f.model.controller.saved, f.source))
        XCTAssertTrue(ProfileLocalCoverController.sameImage(try f.store.read(owner: f.owner), f.source))
    }
    func testUserCropRetryClearsFailureButStillRequiresExplicitReviewedSave() throws {
        let f = try cropRetryFixture()
        f.model.acceptCrop(id: f.draft.id, rect: try outOfSourceCrop())
        XCTAssertTrue(f.model.selectionError); XCTAssertEqual(f.store.writes, 0)
        let rect = try ProfileCoverCropPosition().rect(sourceWidth: f.source.width, sourceHeight: f.source.height)
        f.model.acceptCrop(id: f.draft.id, rect: rect)
        XCTAssertFalse(f.model.selectionError); XCTAssertNil(f.model.crop)
        let review = try XCTUnwrap(f.model.controller.review)
        XCTAssertEqual(f.store.writes, 0); XCTAssertNil(f.model.controller.saved)
        f.model.confirm(review)
        XCTAssertEqual(f.store.writes, 1); XCTAssertFalse(f.model.isPresented)
        XCTAssertTrue(ProfileLocalCoverController.sameImage(f.model.controller.saved, review.image))
    }
    func testCurrentFailedCropCanBeCancelledWithoutChangingSavedCover() throws {
        let f = try cropRetryFixture(saved: true)
        f.model.acceptCrop(id: f.draft.id, rect: try outOfSourceCrop())
        f.model.cancelCrop(id: f.draft.id)
        XCTAssertFalse(f.model.selectionError); XCTAssertNil(f.model.crop)
        XCTAssertTrue(f.model.isPresented); XCTAssertNil(f.model.controller.review)
        XCTAssertEqual(f.store.writes, 0)
        XCTAssertTrue(ProfileLocalCoverController.sameImage(try f.store.read(owner: f.owner), f.source))
    }
    func testOldCropCallbacksCannotClearNewCropFailureOrPrepareAnImage() throws {
        let f = try cropRetryFixture()
        f.model.acceptCrop(id: f.draft.id, rect: try outOfSourceCrop())
        f.model.cancelCrop(id: f.draft.id)
        let replacement = MerchantImageCropDraft(source: f.source, aspect: .gallery)
        f.model.crop = replacement
        f.model.acceptCrop(id: replacement.id, rect: try outOfSourceCrop())
        XCTAssertTrue(f.model.selectionError)
        f.model.cancelCrop(id: f.draft.id)
        f.model.acceptCrop(id: f.draft.id,
            rect: try ProfileCoverCropPosition().rect(sourceWidth: f.source.width, sourceHeight: f.source.height))
        XCTAssertTrue(f.model.selectionError); XCTAssertEqual(f.model.crop?.id, replacement.id)
        XCTAssertNil(f.model.controller.review); XCTAssertEqual(f.store.writes, 0)
    }
    func testOwnerChangeBlocksCropRetryAndRetirementClearsFailure() throws {
        let f = try cropRetryFixture(saved: true)
        f.model.acceptCrop(id: f.draft.id, rect: try outOfSourceCrop())
        f.reader.switchAccount()
        f.model.acceptCrop(id: f.draft.id,
            rect: try ProfileCoverCropPosition().rect(sourceWidth: f.source.width, sourceHeight: f.source.height))
        XCTAssertNil(f.model.controller.review); XCTAssertEqual(f.store.writes, 0)
        f.model.retire()
        XCTAssertFalse(f.model.selectionError); XCTAssertNil(f.model.crop)
        XCTAssertFalse(f.model.isPresented); XCTAssertNil(f.model.controller.saved)
        XCTAssertTrue(ProfileLocalCoverController.sameImage(try f.store.read(owner: f.owner), f.source))
    }
    func testClosingFailedCropAndReopeningStartsWithoutAnOldError() throws {
        let f = try cropRetryFixture()
        f.model.acceptCrop(id: f.draft.id, rect: try outOfSourceCrop())
        f.model.close()
        XCTAssertFalse(f.model.selectionError); XCTAssertNil(f.model.crop)
        f.model.open()
        let replacement = MerchantImageCropDraft(source: f.source, aspect: .gallery)
        f.model.crop = replacement
        f.model.acceptCrop(id: f.draft.id, rect: try outOfSourceCrop())
        XCTAssertFalse(f.model.selectionError); XCTAssertEqual(f.model.crop?.id, replacement.id)
        XCTAssertNil(f.model.controller.review); XCTAssertEqual(f.store.writes, 0)
    }
}

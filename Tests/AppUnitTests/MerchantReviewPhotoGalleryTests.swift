import SwiftUI
import XCTest
@testable import Questify

@MainActor final class MerchantReviewPhotoGalleryTests: XCTestCase {
    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "fixture://merchant", accountID: 9001, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = false
        var reads = 0, accessReads = 0, writes = 0
        var merchantID = 610, name = "Synthetic store", role = "MERCHANT_OWNER"
        var permissions: [String] = []
        var images = ["https://example.invalid/one.jpg", "https://example.invalid/two.jpg"]
        var content = "é", version = 0, reviewID = 63001
        var fail = false, multiplePages = false
        func access() async throws -> MerchantBusinessAccess {
            accessReads += 1; return try accessValue()
        }
        func accessValue() throws -> MerchantBusinessAccess {
            try .init(["active": .bool(true), "merchant": .object(["id": .int(merchantID), "name": .string(name)]),
                       "roleCode": .string(role), "permissions": .array(permissions.map(MerchantBusinessValue.string))])
        }
        func row(id: Int? = nil) throws -> MerchantBusinessRecord {
            try .init(kind: .review, fields: ["id": .int(id ?? reviewID), "version": .int(version), "rating": .int(4),
                "status": .string("VISIBLE"), "verifiedRedemption": .bool(true), "canReply": .bool(true), "canReport": .bool(true),
                "content": .string(content), "imageUrls": .array(images.map(MerchantBusinessValue.string))])
        }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            reads += 1
            if fail { throw URLError(.notConnectedToInternet) }
            let page = query.page
            let records = try multiplePages ? (page == 1 ? (1...20).map { try row(id: 63000 + $0) } : [row(id: 63021)]) : [row()]
            let payload: MerchantBusinessValue = .object(["mode": .string("manage"), "pageNum": .int(page), "pageSize": .int(20),
                "total": .int(multiplePages ? 21 : 1), "hasMore": .bool(multiplePages && page == 1),
                "items": .array(records.map { .object($0.fields) })])
            return .init(access: try accessValue(), document: try .init(query: query, payload: payload))
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            writes += 1; throw MerchantBusinessFailure.disabled
        }
    }
    @MainActor private final class Harness {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore(), model = MerchantReviewPhotoGalleryModel()
        let owner: MerchantBusinessViewModel
        init() { owner = .init(reader: reader, journal: journal) }
        func start() async { await owner.load(.reviews(page: 1)); model.activate() }
        func row() throws -> MerchantBusinessRecord { try XCTUnwrap(owner.coordinator.snapshot?.document.rows.first) }
        @discardableResult func open(index: Int = 0) throws -> MerchantReviewPhotoSession {
            let row = try row()
            model.open(permit: model.generation, context: .init(owner: owner, row: row), row: row, index: index)
            return try XCTUnwrap(model.session)
        }
    }
    func testExplicitSelectedOrdinalUsesExistingURLsWithoutAnotherReadOrWrite() async throws {
        let h = Harness(); await h.start(); XCTAssertNil(h.model.session)
        let session = try h.open(index: 1)
        XCTAssertEqual(session.index, 1); XCTAssertEqual(session.count, 2)
        XCTAssertEqual(session.currentURL?.absoluteString, h.reader.images[1])
        XCTAssertEqual(h.reader.reads, 1); XCTAssertEqual(h.reader.accessReads, 0); XCTAssertEqual(h.reader.writes, 0)
        XCTAssertTrue(try h.journal.intents().isEmpty)
    }
    func testDuplicateURLsKeepDistinctOrdinalPages() async throws {
        let h = Harness(); h.reader.images = Array(repeating: "https://example.invalid/same.jpg", count: 3); await h.start()
        let session = try h.open(index: 1), old = session.imageGeneration
        XCTAssertEqual(session.count, 3); XCTAssertTrue(session.select(2)); XCTAssertEqual(session.index, 2)
        XCTAssertNotEqual(session.imageGeneration, old); XCTAssertEqual(session.currentURL?.absoluteString, h.reader.images[2])
    }
    func testSourceNinePhotoLimitAndEmptyProjection() async throws {
        let h = Harness(); h.reader.images = (0..<9).map { "https://example.invalid/\($0).jpg" }; await h.start()
        XCTAssertEqual(try h.open(index: 8).count, 9)
        let reader = Reader(); reader.images = []; XCTAssertNil(MerchantReviewPhotoContext.photos(try reader.row()))
        reader.images = Array(repeating: "https://example.invalid/a.jpg", count: 10); XCTAssertThrowsError(try reader.row())
    }
    func testUnsafeSourceURLsAreRejectedByExistingRecordValidation() throws {
        let reader = Reader()
        for raw in ["http://example.invalid/a.jpg", "file:///a.jpg", "https://user:pass@example.invalid/a.jpg"] {
            reader.images = [raw]; XCTAssertThrowsError(try reader.row())
        }
    }
    func testFirstAndLastBoundariesDoNotWrapOrChangeImageGeneration() async throws {
        let h = Harness(); await h.start(); let session = try h.open(); let first = session.imageGeneration
        XCTAssertFalse(session.select(-1)); XCTAssertEqual(session.index, 0); XCTAssertEqual(session.imageGeneration, first)
        XCTAssertTrue(session.select(1)); let last = session.imageGeneration
        XCTAssertFalse(session.select(2)); XCTAssertFalse(session.select(Int.max)); XCTAssertEqual(session.imageGeneration, last)
    }
    func testZoomIsBoundedFiniteAndResetOnPageChange() async throws {
        let h = Harness(); await h.start(); let session = try h.open()
        XCTAssertTrue(session.setZoom(9)); XCTAssertEqual(session.zoom, 5)
        XCTAssertFalse(session.setZoom(.nan)); XCTAssertFalse(session.setZoom(.infinity)); XCTAssertEqual(session.zoom, 5)
        XCTAssertTrue(session.setZoom(-1)); XCTAssertEqual(session.zoom, 1)
        XCTAssertTrue(session.setZoom(2.5)); XCTAssertTrue(session.select(1)); XCTAssertEqual(session.zoom, 1)
    }
    func testSinglePhotoStaysAtOrdinalZero() async throws {
        let h = Harness(); h.reader.images = [h.reader.images[0]]; await h.start(); let session = try h.open()
        XCTAssertEqual(session.count, 1); XCTAssertFalse(session.select(1)); XCTAssertFalse(session.select(-1))
        XCTAssertTrue(session.select(0)); XCTAssertEqual(session.index, 0)
    }
    func testInvalidInitialOrdinalDoesNotPresent() async throws {
        let h = Harness(); await h.start(); let row = try h.row(), context = MerchantReviewPhotoContext(owner: h.owner, row: row)
        for index in [-1, 2, Int.max] { h.model.open(permit: h.model.generation, context: context, row: row, index: index); XCTAssertNil(h.model.session) }
    }
    func testAccountEpochRealmAndAuthorizationChangesHideAndRetire() async throws {
        for change in 0..<4 {
            let h = Harness(); await h.start(); let session = try h.open()
            if change == 0 { h.reader.scope = .init(realm: "fixture://merchant", accountID: 9002, epoch: 1) }
            if change == 1 { h.reader.scope = .init(realm: "fixture://merchant", accountID: 9001, epoch: 2) }
            if change == 2 { h.reader.scope = .init(realm: "fixture://other", accountID: 9001, epoch: 1) }
            if change == 3 { h.reader.authorizationGeneration = UUID() }
            XCTAssertNil(session.currentURL); h.model.revalidate(); XCTAssertFalse(session.active); XCTAssertNil(h.model.session)
        }
    }
    func testCanonicallyEquivalentRealmBytesDoNotShareLease() async throws {
        let h = Harness(); h.reader.scope = .init(realm: "fixture://é", accountID: 9001, epoch: 1); await h.start(); let session = try h.open()
        h.reader.scope = .init(realm: "fixture://e\u{0301}", accountID: 9001, epoch: 1)
        XCTAssertNil(session.currentURL); XCTAssertFalse(session.isCurrent)
    }
    func testLoadSameBytesInvalidatesRenderedContextAndOldPresentation() async throws {
        let h = Harness(); await h.start(); let row = try h.row(), context = MerchantReviewPhotoContext(owner: h.owner, row: row), permit = h.model.generation
        let old = try h.open(); await h.owner.load(.reviews(page: 1)); XCTAssertNil(old.currentURL)
        h.model.revalidate(); XCTAssertNil(h.model.session)
        h.model.open(permit: permit, context: context, row: row, index: 0); XCTAssertNil(h.model.session)
        XCTAssertNotNil(try h.open())
    }
    func testStoreRolePermissionsAndNameReplacementInvalidatesContext() async throws {
        for change in 0..<4 {
            let h = Harness(); await h.start(); let session = try h.open()
            if change == 0 { h.reader.merchantID = 611 }
            if change == 1 { h.reader.role = "MERCHANT_MANAGER" }
            if change == 2 { h.reader.permissions = ["merchant:crm:read"] }
            if change == 3 { h.reader.name = "Different" }
            // Direct coordinator replacement also tests exact access, independent of view-model revision.
            await h.owner.coordinator.load(.reviews(page: 1))
            XCTAssertNil(session.currentURL); h.model.revalidate(); XCTAssertNil(h.model.session)
        }
    }
    func testExactUTF8ReviewFingerprintRejectsCanonicallyEquivalentReplacement() async throws {
        let h = Harness(); await h.start(); let row = try h.row(), context = MerchantReviewPhotoContext(owner: h.owner, row: row)
        h.reader.content = "e\u{0301}"; let changed = try h.reader.row()
        XCTAssertEqual(row, changed); XCTAssertNotEqual(MerchantReviewPhotoContext.fingerprint(row), MerchantReviewPhotoContext.fingerprint(changed))
        h.model.open(permit: h.model.generation, context: context, row: changed, index: 0); XCTAssertNil(h.model.session)
    }
    func testOldReviewVersionAndImageOrderCannotOpenAfterReload() async throws {
        let h = Harness(); await h.start(); let old = try h.row(), context = MerchantReviewPhotoContext(owner: h.owner, row: old)
        h.reader.version = 1; h.reader.images.reverse(); await h.owner.load(.reviews(page: 1))
        h.model.open(permit: h.model.generation, context: context, row: old, index: 0); XCTAssertNil(h.model.session)
        XCTAssertEqual(try h.open().currentURL?.absoluteString, h.reader.images[0])
    }
    func testFilteredOutRowCannotOpenAndRetiresExistingViewer() async throws {
        let h = Harness(); await h.start(); let old = try h.open(), row = try h.row()
        h.owner.listFilters.review = .low
        XCTAssertNil(MerchantReviewPhotoContext(owner: h.owner, row: row)); XCTAssertNil(old.currentURL)
        h.model.revalidate(); XCTAssertFalse(old.active); XCTAssertNil(h.model.session)
    }
    func testLoadedEarlierPagePhotoRemainsEligibleInCurrentAccumulation() async throws {
        let h = Harness(); h.reader.multiplePages = true; await h.start(); let first = try h.row()
        await h.owner.loadMoreReviews(); XCTAssertEqual(h.owner.reviewLoadedPages?.rows.count, 21)
        h.model.open(permit: h.model.generation, context: .init(owner: h.owner, row: first), row: first, index: 1)
        XCTAssertEqual(h.model.session?.currentURL?.absoluteString, h.reader.images[1]); XCTAssertEqual(h.reader.reads, 2)
    }
    func testFailedReloadRemovesRowsAndCannotReviveOldPresentation() async throws {
        let h = Harness(); await h.start(); let old = try h.open(); h.reader.fail = true
        await h.owner.load(.reviews(page: 1)); h.model.revalidate(); XCTAssertNil(h.model.session); XCTAssertFalse(old.active)
        h.reader.fail = false; await h.owner.load(.reviews(page: 1)); XCTAssertNil(old.currentURL)
    }
    func testDisabledReaderCannotPresentOrExposeExistingImage() async throws {
        let h = Harness(); await h.start(); let old = try h.open(); h.reader.isConfigured = false
        XCTAssertNil(old.currentURL); h.model.revalidate(); XCTAssertNil(h.model.session)
        XCTAssertNil(MerchantReviewPhotoContext(owner: h.owner, row: try h.row()))
    }
    func testCloseRetiresOldSessionWithoutChangingOwnerRowsOrJournal() async throws {
        let h = Harness(); await h.start(); let snapshot = h.owner.coordinator.snapshot, old = try h.open()
        h.model.cancel(id: old.id); XCTAssertFalse(old.active); XCTAssertEqual(old.count, 0); XCTAssertNil(old.currentURL)
        XCTAssertEqual(h.owner.coordinator.snapshot, snapshot); XCTAssertTrue(try h.journal.intents().isEmpty)
        XCTAssertEqual(h.reader.reads, 1); XCTAssertEqual(h.reader.writes, 0)
    }
    func testOldAndEmptyActualBindingsCannotDismissNewPresentation() async throws {
        let h = Harness(); await h.start(); let empty = h.model.presentationBinding(), old = try h.open(), binding = h.model.presentationBinding()
        h.model.cancel(id: old.id); let fresh = try h.open(index: 1)
        XCTAssertNil(binding.wrappedValue); XCTAssertNil(empty.wrappedValue)
        binding.wrappedValue = nil; empty.wrappedValue = nil
        XCTAssertEqual(h.model.session?.id, fresh.id); XCTAssertTrue(fresh.isCurrent)
    }
    func testCurrentBindingDismissesOnlyItsOwnSession() async throws {
        let h = Harness(); await h.start(); let old = try h.open(), binding = h.model.presentationBinding()
        XCTAssertEqual(binding.wrappedValue?.id, old.id); binding.wrappedValue = nil
        XCTAssertNil(h.model.session); XCTAssertFalse(old.active)
    }
    func testBackgroundAndReappearanceCannotReplayOldTapOrImageCallback() async throws {
        let h = Harness(); await h.start(); let row = try h.row(), context = MerchantReviewPhotoContext(owner: h.owner, row: row), permit = h.model.generation
        let old = try h.open(), image = old.imageGeneration
        h.model.retire(); h.model.activate()
        h.model.open(permit: permit, context: context, row: row, index: 0); XCTAssertNil(h.model.session)
        let fresh = try h.open(); old.retryImage(image, at: 0); XCTAssertFalse(old.select(1)); XCTAssertFalse(old.setZoom(3))
        XCTAssertEqual(h.model.session?.id, fresh.id); XCTAssertFalse(old.isImageCurrent(image, at: 0)); XCTAssertNil(old.currentURL)
    }
    func testOldImageCompletionAndRetryCannotAffectNewOrdinalOrReturnToSameURL() async throws {
        let h = Harness(); await h.start(); let session = try h.open(), old = session.imageGeneration
        XCTAssertTrue(session.select(1)); XCTAssertTrue(session.select(0)); let fresh = session.imageGeneration
        XCTAssertFalse(session.isImageCurrent(old, at: 0)); session.retryImage(old, at: 0)
        XCTAssertEqual(session.imageGeneration, fresh); XCTAssertEqual(session.index, 0)
    }
    func testExplicitImageRetryChangesOnlyLocalImageGeneration() async throws {
        let h = Harness(); await h.start(); let session = try h.open(), image = session.imageGeneration
        session.retryImage(image, at: 0); XCTAssertNotEqual(session.imageGeneration, image)
        XCTAssertEqual(session.currentURL?.absoluteString, h.reader.images[0]); XCTAssertEqual(h.reader.reads, 1); XCTAssertEqual(h.reader.writes, 0)
    }
    func testExistingUnknownJournalReservationSurvivesGalleryLifetime() async throws {
        let h = Harness(); await h.start(); let scope = try XCTUnwrap(h.reader.scope)
        let intent = MerchantBusinessIntent(scope: scope, merchantID: 610, target: "review:63001", requestID: "synthetic-unknown")
        try h.journal.reserve(intent); let session = try h.open(); h.model.cancel(id: session.id)
        XCTAssertEqual(try h.journal.intents(), [intent]); XCTAssertEqual(h.reader.writes, 0)
    }
    func testOldImageGestureCannotZoomNewOrdinalOrSameOrdinalAfterReturn() async throws {
        let h = Harness(); await h.start(); let session = try h.open(), old = session.imageGeneration
        XCTAssertTrue(session.select(1))
        XCTAssertFalse(session.setImageZoom(4, generation: old, at: 0)); XCTAssertEqual(session.zoom, 1)
        XCTAssertTrue(session.select(0))
        XCTAssertFalse(session.setImageZoom(4, generation: old, at: 0)); XCTAssertEqual(session.zoom, 1)
        XCTAssertTrue(session.setImageZoom(2, generation: session.imageGeneration, at: 0)); XCTAssertEqual(session.zoom, 2)
    }
    func testOldImageGestureCannotZoomRetriedImage() async throws {
        let h = Harness(); await h.start(); let session = try h.open(), old = session.imageGeneration
        session.retryImage(old, at: 0)
        XCTAssertFalse(session.setImageZoom(4, generation: old, at: 0)); XCTAssertEqual(session.zoom, 1)
        XCTAssertTrue(session.setImageZoom(3, generation: session.imageGeneration, at: 0)); XCTAssertEqual(session.zoom, 3)
    }

    func testReplacementOwnerRemountLifetimeDoesNotAffectNewOwnerPresentation() async throws {
        let old = Harness(), fresh = Harness(); fresh.reader.authorizationGeneration = old.reader.authorizationGeneration
        await old.start(); await fresh.start()
        XCTAssertEqual(old.owner.revision, fresh.owner.revision); XCTAssertEqual(old.reader.scope, fresh.reader.scope)
        XCTAssertEqual(try old.row(), try fresh.row()); XCTAssertNotEqual(ObjectIdentifier(old.owner), ObjectIdentifier(fresh.owner))
        let prior = try old.open(), oldBinding = old.model.presentationBinding()
        // Mirrors the old host's onDisappear after its ObjectIdentifier(owner) mount changes.
        // Actual SwiftUI remount/dismissal must still be exercised on Apple runtime.
        old.model.retire(); let replacement = try fresh.open(index: 1)
        oldBinding.wrappedValue = nil; prior.retryImage(prior.imageGeneration, at: 0)
        XCTAssertNil(prior.currentURL); XCTAssertFalse(prior.active)
        XCTAssertEqual(fresh.model.session?.id, replacement.id); XCTAssertEqual(replacement.index, 1)
    }

}

import SwiftUI
import XCTest
@testable import Questify

/// Exercises the actual binding retained before a first tap. These tests do not
/// fetch image URLs, execute business actions, or claim SwiftUI device validation.
@MainActor final class MerchantReviewPhotoPresentationBindingTests: XCTestCase {
    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "fixture://photo-binding", accountID: 9001, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = false
        var reads = 0, writes = 0
        func access() async throws -> MerchantBusinessAccess { try accessValue() }
        func accessValue() throws -> MerchantBusinessAccess {
            try .init(["active": .bool(true), "merchant": .object(["id": .int(610), "name": .string("Synthetic store")]),
                       "roleCode": .string("MERCHANT_OWNER"), "permissions": .array([])])
        }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            reads += 1
            let row: MerchantBusinessValue = .object(["id": .int(63001), "version": .int(0), "rating": .int(4),
                "status": .string("VISIBLE"), "verifiedRedemption": .bool(true), "canReply": .bool(true), "canReport": .bool(true),
                "content": .string("Synthetic review"), "imageUrls": .array([
                    .string("https://example.invalid/one.jpg"), .string("https://example.invalid/two.jpg")])])
            let payload: MerchantBusinessValue = .object(["mode": .string("manage"), "pageNum": .int(1), "pageSize": .int(20),
                "total": .int(1), "hasMore": .bool(false), "items": .array([row])])
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
        func start(activate: Bool = true) async {
            await owner.load(.reviews(page: 1))
            if activate { model.activate() }
        }
        func open(index: Int = 0) throws -> MerchantReviewPhotoSession {
            let row = try XCTUnwrap(owner.coordinator.snapshot?.document.rows.first)
            model.open(permit: model.generation, context: .init(owner: owner, row: row), row: row, index: index)
            return try XCTUnwrap(model.session)
        }
    }
    func testBindingInstalledBeforeFirstTapAdoptsThatFirstSession() async throws {
        let h = Harness(); await h.start()
        let binding = h.model.presentationBinding(), epoch = h.model.generation
        XCTAssertNil(binding.wrappedValue)
        let shown = try h.open(index: 1)
        XCTAssertEqual(h.model.generation, epoch)
        XCTAssertEqual(binding.wrappedValue?.id, shown.id)
        XCTAssertEqual(binding.wrappedValue?.currentURL?.absoluteString, "https://example.invalid/two.jpg")
        binding.wrappedValue = nil
        XCTAssertNil(h.model.session)
        XCTAssertFalse(shown.active)
        XCTAssertNil(shown.currentURL)
    }
    func testCloseAndReopenNeedNewEpochButOldBindingsCannotDismissSuccessor() async throws {
        let h = Harness(); await h.start()
        let firstBinding = h.model.presentationBinding(), first = try h.open()
        XCTAssertEqual(firstBinding.wrappedValue?.id, first.id)
        firstBinding.wrappedValue = nil
        let nextBinding = h.model.presentationBinding()
        XCTAssertNil(nextBinding.wrappedValue)
        let next = try h.open(index: 1)
        XCTAssertEqual(nextBinding.wrappedValue?.id, next.id)
        XCTAssertNil(firstBinding.wrappedValue)
        firstBinding.wrappedValue = nil
        XCTAssertEqual(h.model.session?.id, next.id)
        XCTAssertTrue(next.isCurrent)
        nextBinding.wrappedValue = nil
        XCTAssertNil(h.model.session)
        XCTAssertFalse(next.active)
    }
    func testEmptyBindingNeverObservedBeforeCloseCannotAdoptLaterVisit() async throws {
        let h = Harness(); await h.start()
        let empty = h.model.presentationBinding(), first = try h.open()
        h.model.cancel(id: first.id)
        let next = try h.open(index: 1)
        XCTAssertNil(empty.wrappedValue)
        empty.wrappedValue = nil
        XCTAssertEqual(h.model.session?.id, next.id)
    }
    func testPreActivationBindingCannotBorrowNewVisibleVisit() async throws {
        let h = Harness(); await h.start(activate: false)
        let hiddenBinding = h.model.presentationBinding()
        XCTAssertNil(hiddenBinding.wrappedValue)
        h.model.activate()
        let visibleBinding = h.model.presentationBinding(), shown = try h.open()
        XCTAssertNil(hiddenBinding.wrappedValue)
        hiddenBinding.wrappedValue = nil
        XCTAssertEqual(visibleBinding.wrappedValue?.id, shown.id)
    }
    func testBackgroundRetirementPreventsOldBindingFromAdoptingReopenedSession() async throws {
        let h = Harness(); await h.start()
        let oldBinding = h.model.presentationBinding(), old = try h.open()
        XCTAssertEqual(oldBinding.wrappedValue?.id, old.id)
        h.model.retire(); h.model.activate()
        let nextBinding = h.model.presentationBinding(), next = try h.open(index: 1)
        XCTAssertNil(oldBinding.wrappedValue)
        oldBinding.wrappedValue = nil
        XCTAssertNil(old.currentURL)
        XCTAssertEqual(nextBinding.wrappedValue?.id, next.id)
    }
    func testInitialAdoptionRechecksSourceAndNeverMutatesUnknownJournal() async throws {
        let h = Harness(); await h.start()
        let intent = MerchantBusinessIntent(scope: try XCTUnwrap(h.reader.scope), merchantID: 610,
            target: "review:63001", requestID: "synthetic-unknown")
        try h.journal.reserve(intent)
        let binding = h.model.presentationBinding(), shown = try h.open(), snapshot = h.owner.coordinator.snapshot
        h.reader.authorizationGeneration = UUID()
        XCTAssertNil(binding.wrappedValue)
        h.model.revalidate()
        binding.wrappedValue = nil
        XCTAssertFalse(shown.active)
        XCTAssertEqual(try h.journal.intents(), [intent])
        XCTAssertEqual(h.owner.coordinator.snapshot, snapshot)
        XCTAssertEqual(h.reader.reads, 1)
        XCTAssertEqual(h.reader.writes, 0)
    }
}

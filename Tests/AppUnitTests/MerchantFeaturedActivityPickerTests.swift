import Foundation
import XCTest
@testable import Questify

@MainActor private final class FeaturedPickerFixtureReader: MerchantOperationsReading {
    let base = MerchantOperationsFixtureReader()
    var scope: UUID { base.scope }
    var isConfigured: Bool { base.isConfigured }
    var isAuthenticated: Bool { base.isAuthenticated }
    var isOfflineExample: Bool { true }
    var pages = [#"{"rows":[{"id":17,"name":"First"}],"total":2}"#, #"{"rows":[{"id":18,"name":"Second"}],"total":2}"#]
    var requests: [Int] = []
    var failure: Error?
    var delay = false
    var pending: CheckedContinuation<MerchantFeaturedActivityPage, Error>?
    var onPending: (() -> Void)?
    func access() async throws -> MerchantOperationsAccess { try await base.access() }
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { try await base.document(destination) }
    func saveExample(_ draft: MerchantOperationsDraft) async throws { try await base.saveExample(draft) }
    func featuredActivities(page: Int) async throws -> MerchantFeaturedActivityPage {
        requests.append(page)
        if let failure { throw failure }
        if delay { return try await withCheckedThrowingContinuation { pending = $0; onPending?() } }
        guard pages.indices.contains(page - 1) else { throw APIError.malformedResponse }
        return try JSONDecoder().decode(MerchantFeaturedActivityPage.self, from: Data(pages[page - 1].utf8))
    }
}

@MainActor final class MerchantFeaturedActivityPickerTests: XCTestCase {
    private func harness(type: Int? = 1, id: Int? = 17) async throws -> (MerchantOperationsViewModel, FeaturedPickerFixtureReader) {
        let reader = FeaturedPickerFixtureReader()
        var source = try JSONDecoder().decode(MerchantStoreDecor.self, from: Data(MerchantOperationsFixtureData.storeJSON.utf8))
        source.featuredType = type; source.featuredID = id; reader.base.replace(.decor, with: .draft(.decor(source)))
        let document = MerchantOperationsViewModel(reader: reader, destination: .decor); await document.load(); return (document, reader)
    }
    func testOpeningAndCancellingNeverClearCurrentFeaturedPair() async throws {
        let (document, reader) = try await harness(type: 2, id: 42); let original = document.coordinator.draft
        let picker = try XCTUnwrap(MerchantFeaturedActivityPickerModel(document: document)); await picker.loadFirst()
        XCTAssertTrue(picker.originalNotLoaded); picker.select(17); picker.cancel(); XCTAssertFalse(picker.apply())
        XCTAssertEqual(document.coordinator.draft, original); XCTAssertEqual(reader.base.saveCount, 0)
    }
    func testPaginationLoadsRemainingCandidatesAndApplyChangesOnlyPair() async throws {
        let (document, reader) = try await harness()
        guard case .decor(var expected) = document.coordinator.draft else { return XCTFail() }
        let picker = try XCTUnwrap(MerchantFeaturedActivityPickerModel(document: document))
        await picker.loadFirst(); XCTAssertTrue(picker.hasMore); XCTAssertEqual(picker.rows.map(\.id), [17])
        await picker.loadMore(); XCTAssertFalse(picker.hasMore); XCTAssertEqual(picker.rows.map(\.id), [17, 18])
        picker.select(18); XCTAssertTrue(picker.apply()); XCTAssertFalse(picker.apply())
        expected.featuredType = 1; expected.featuredID = 18
        XCTAssertEqual(document.coordinator.draft, .decor(expected)); XCTAssertEqual(reader.base.saveCount, 0)
        XCTAssertEqual(reader.requests, [1, 2])
    }
    func testArrayResponseDoesNotInventAdditionalPagesOrFullCoverage() async throws {
        let (document, reader) = try await harness(); reader.pages = [#"[{"id":17,"name":"First"}]"#]
        let picker = try XCTUnwrap(MerchantFeaturedActivityPickerModel(document: document)); await picker.loadFirst()
        XCTAssertNil(picker.total); XCTAssertFalse(picker.hasMore); await picker.loadMore(); XCTAssertEqual(reader.requests, [1])
    }
    func testMissingCurrentIDStaysInDraftAndCannotApplyAnUnloadedGuess() async throws {
        let (document, _) = try await harness(id: 99); let original = document.coordinator.draft
        let picker = try XCTUnwrap(MerchantFeaturedActivityPickerModel(document: document)); await picker.loadFirst()
        XCTAssertEqual(picker.selectedID, 99); XCTAssertTrue(picker.originalNotLoaded); XCTAssertFalse(picker.canApply)
        picker.select(777); XCTAssertEqual(picker.selectedID, 99); XCTAssertFalse(picker.apply())
        XCTAssertEqual(document.coordinator.draft, original)
    }
    func testFailureAndRetryKeepOriginalDraftAndNoOpApplyStaysClean() async throws {
        let (document, reader) = try await harness(); let original = document.coordinator.draft
        reader.failure = URLError(.timedOut)
        let picker = try XCTUnwrap(MerchantFeaturedActivityPickerModel(document: document)); await picker.loadFirst()
        XCTAssertNotNil(picker.issue); XCTAssertEqual(document.coordinator.draft, original)
        reader.failure = nil; await picker.reload(); XCTAssertNil(picker.issue); XCTAssertTrue(picker.apply())
        XCTAssertEqual(document.coordinator.draft, original); XCTAssertFalse(document.coordinator.isDirty)
    }
    func testDuplicatePageLeavesAlreadyLoadedRowsAndSelectionUnchanged() async throws {
        let (document, reader) = try await harness(); reader.pages[1] = reader.pages[0]
        let picker = try XCTUnwrap(MerchantFeaturedActivityPickerModel(document: document)); await picker.loadFirst(); await picker.loadMore()
        XCTAssertNotNil(picker.issue); XCTAssertEqual(picker.rows.map(\.id), [17]); XCTAssertEqual(picker.selectedID, 17)
        XCTAssertFalse(picker.canApply)
    }
    func testConcurrentEditReloadAndAccountReplacementRejectOldPicker() async throws {
        let (document, reader) = try await harness()
        let edited = try XCTUnwrap(MerchantFeaturedActivityPickerModel(document: document)); await edited.loadFirst(); edited.select(17)
        guard case .decor(var newer) = document.coordinator.draft else { return XCTFail() }
        newer.slogan = "Newer"; document.edit(.decor(newer)); XCTAssertFalse(edited.apply())
        let reloaded = try XCTUnwrap(MerchantFeaturedActivityPickerModel(document: document)); await reloaded.loadFirst(); await document.load(); XCTAssertFalse(reloaded.apply())
        let switched = try XCTUnwrap(MerchantFeaturedActivityPickerModel(document: document)); await switched.loadFirst(); reader.base.switchAccount(); XCTAssertFalse(switched.apply())
    }
    func testDismissedPendingReadCannotRestoreRowsOrChangeDraft() async throws {
        let (document, reader) = try await harness(); let original = document.coordinator.draft; reader.delay = true
        let started = expectation(description: "candidate read started"); reader.onPending = { started.fulfill() }
        let picker = try XCTUnwrap(MerchantFeaturedActivityPickerModel(document: document))
        let load = Task { await picker.loadFirst() }; await fulfillment(of: [started], timeout: 2)
        picker.cancel()
        let late = try JSONDecoder().decode(MerchantFeaturedActivityPage.self, from: Data(reader.pages[0].utf8))
        reader.pending?.resume(returning: late); reader.pending = nil; await load.value
        XCTAssertTrue(picker.rows.isEmpty); XCTAssertFalse(picker.busy); XCTAssertFalse(picker.apply())
        XCTAssertEqual(document.coordinator.draft, original)
    }
}

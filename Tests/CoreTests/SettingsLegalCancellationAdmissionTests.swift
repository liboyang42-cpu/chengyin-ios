import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class SettingsLegalCancellationAdmissionTests: XCTestCase {
    private func cancelledLoad(_ coordinator: SettingsLegalCoordinator) async {
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await coordinator.load(type: .privacyPolicy, market: .unitedStates)
        }
        await task.value
    }

    func testAlreadyCancelledEntryDoesNotStartReaderOrPublishLoading() async {
        let reader = LegalAdmissionReader()
        let coordinator = SettingsLegalCoordinator(reader: reader)
        var states: [SettingsLegalState] = []
        coordinator.onChange = { states.append($0) }
        await cancelledLoad(coordinator)
        XCTAssertEqual(reader.calls, 0)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(states.isEmpty)
    }

    func testCancelledEntryPreservesCompletedReadAndFreshReadStillWorks() async {
        let reader = SettingsBundledLegalReader()
        let coordinator = SettingsLegalCoordinator(reader: reader)
        await coordinator.load(type: .userAgreement, market: .china)
        let original = coordinator.state
        XCTAssertEqual(original, .loaded(.sourceDocument(SettingsSourceLegalCatalog.userAgreement)))
        await cancelledLoad(coordinator)
        XCTAssertEqual(coordinator.state, original)
        await coordinator.load(type: .privacyPolicy, market: .china)
        XCTAssertEqual(coordinator.state, .loaded(.missing(.pendingSourceText)))
    }

    func testCancelledEntryCannotSupersedeValidInFlightRead() async {
        let reader = LegalAdmissionReader()
        reader.suspend = true
        let coordinator = SettingsLegalCoordinator(reader: reader)
        let started = expectation(description: "Original read started")
        reader.onStart = { started.fulfill() }
        let task = Task { await coordinator.load(type: .userAgreement, market: .china) }
        await fulfillment(of: [started], timeout: 1)
        await cancelledLoad(coordinator)
        XCTAssertEqual(reader.calls, 1)
        reader.pending?.resume(returning: .sourceDocument(SettingsSourceLegalCatalog.userAgreement))
        reader.pending = nil
        await task.value
        XCTAssertEqual(coordinator.state, .loaded(.sourceDocument(SettingsSourceLegalCatalog.userAgreement)))
    }

    func testInvalidationRemainsAuthoritativeAndFreshReadCanRecover() async {
        let coordinator = SettingsLegalCoordinator(reader: SettingsBundledLegalReader())
        await coordinator.load(type: .userAgreement, market: .china)
        coordinator.invalidate()
        await cancelledLoad(coordinator)
        XCTAssertEqual(coordinator.state, .idle)
        await coordinator.load(type: .privacyPolicy, market: nil)
        XCTAssertEqual(coordinator.state, .loaded(.missing(.missingMarket)))
    }
}

@MainActor private final class LegalAdmissionReader: SettingsLegalReading {
    var calls = 0
    var suspend = false
    var onStart: (() -> Void)?
    var pending: CheckedContinuation<SettingsLegalAvailability, Never>?
    func document(type: SettingsLegalType, market: RegionalMarket?) async throws -> SettingsLegalAvailability {
        calls += 1
        if suspend {
            return await withCheckedContinuation { continuation in
                pending = continuation
                onStart?()
            }
        }
        return SettingsSourceLegalCatalog.document(type: type, market: market)
    }
}

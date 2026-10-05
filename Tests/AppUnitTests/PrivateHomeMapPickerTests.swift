import XCTest
@testable import Questify

@MainActor final class PrivateHomeMapPickerTests: XCTestCase {
    private let owner = try! PlayExperienceSession(accountID: 12, epoch: 1, namespace: "fixture-private", token: "fixture-token")
    private final class Recorder: PrivateHomeMapPointPicking {
        var approvedSource: PrivateHomeMapSource? = PrivateHomeFixtureMapAdapter.source
        var callbacks: [(PrivateHomeMapCandidate) -> Void] = []
        var cancels = 0
        func start(receive: @escaping (PrivateHomeMapCandidate) -> Void) { callbacks.append(receive) }
        func cancel() { cancels += 1 } // Retain callbacks deliberately to simulate late provider delivery.
    }
    private func setup(adapter: (any PrivateHomeMapPointPicking)? = nil, current: (() -> PlayExperienceSession?)? = nil) async -> (PrivateHomeMapPickerModel, PrivateHomeFixtureService, PrivateHomeFixtureJournal) {
        let service = PrivateHomeFixtureService(), journal = PrivateHomeFixtureJournal(owner: owner)
        let captured = owner
        let model = PrivateHomeCoordinator(service: service, journal: journal, owner: owner, enabled: true, current: current ?? { captured })
        await model.load()
        return (PrivateHomeMapPickerModel(owner: model, adapter: adapter ?? PrivateHomeInactiveMapKitAdapter()), service, journal)
    }
    func testNormalAdapterUnavailableAndNoProviderStartBeforeIntent() async throws {
        let (inactive, service, journal) = await setup()
        XCTAssertFalse(inactive.isPresented); XCTAssertNil(inactive.adapter.approvedSource)
        inactive.open(); XCTAssertTrue(inactive.isPresented); XCTAssertEqual(inactive.selection.issue, .providerUnverified)
        XCTAssertFalse(inactive.review(label: "Synthetic")); XCTAssertTrue(service.mutations.isEmpty); XCTAssertNil(journal.value)
        inactive.close()
        inactive.owner.prepareSet(label: "Manual", point: try PrivateHomePoint.parse(latitude: "12", longitude: "45"))
        XCTAssertTrue(inactive.owner.canConfirm)
        let recorder = Recorder(); let (picker, _, _) = await setup(adapter: recorder)
        XCTAssertTrue(recorder.callbacks.isEmpty); picker.open(); XCTAssertEqual(recorder.callbacks.count, 1)
    }
    func testPreviewAndReviewNeverDispatchUntilExistingOwnerConfirmation() async throws {
        let recorder = Recorder(); let (picker, service, journal) = await setup(adapter: recorder)
        picker.open(); recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid))
        XCTAssertTrue(picker.canUsePoint); XCTAssertTrue(service.mutations.isEmpty); XCTAssertNil(journal.value)
        XCTAssertTrue(picker.review(label: "Synthetic")); XCTAssertFalse(picker.isPresented); XCTAssertNil(picker.selection.point)
        let review = try XCTUnwrap(picker.owner.review)
        XCTAssertEqual(review.latitude, Decimal(string: "12.345678")); XCTAssertEqual(review.expectedVersion, 0)
        XCTAssertTrue(service.mutations.isEmpty); XCTAssertNil(journal.value)
        XCTAssertTrue(picker.authorizeOwnerConfirmation())
        await picker.owner.confirm(); XCTAssertEqual(service.mutations, [review]); XCTAssertNil(journal.value)
    }
    func testRepeatedSelectionUsesLastPointAndCancelReopenRejectsOldCallback() async throws {
        let recorder = Recorder(); let (picker, service, _) = await setup(adapter: recorder)
        picker.open(); recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid))
        recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.alternate))
        XCTAssertEqual(picker.selection.point?.latitude, Decimal(string: "-12.345678"))
        picker.close(); picker.open(); recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid))
        XCTAssertNil(picker.selection.point); XCTAssertFalse(picker.canUsePoint)
        recorder.callbacks[1](PrivateHomeFixtureMapAdapter.candidate(.valid)); XCTAssertTrue(picker.review(label: "Synthetic"))
        picker.owner.cancelReview(); await picker.owner.confirm(); XCTAssertTrue(service.mutations.isEmpty)
    }
    func testInvalidSourceOrPrecisionDisablesReviewAndClearsGoodPoint() async {
        let recorder = Recorder(); let (picker, service, _) = await setup(adapter: recorder)
        picker.open()
        for choice in [PrivateHomeFixtureMapAdapter.Choice.unknown, .gcj02, .precision, .outOfRange] {
            recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid)); XCTAssertTrue(picker.canUsePoint)
            recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(choice)); XCTAssertFalse(picker.canUsePoint)
            XCTAssertFalse(picker.review(label: "Synthetic")); XCTAssertNil(picker.owner.review)
        }
        XCTAssertTrue(service.mutations.isEmpty)
    }
    func testInvalidLabelLeavesPointForCorrectionWithoutMutation() async {
        let recorder = Recorder(); let (picker, service, _) = await setup(adapter: recorder)
        picker.open(); recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid))
        XCTAssertFalse(picker.review(label: "")); XCTAssertTrue(picker.isPresented); XCTAssertTrue(picker.canUsePoint)
        XCTAssertTrue(picker.review(label: "Corrected")); XCTAssertTrue(service.mutations.isEmpty)
    }
    func testSessionReplacementInvalidationAndLateCallbackCannotReview() async throws {
        for next in [nil, try PlayExperienceSession(accountID: 13, epoch: 1, namespace: "fixture-private", token: "fixture-token"),
                     try PlayExperienceSession(accountID: 12, epoch: 2, namespace: "fixture-private", token: "replacement"),
                     try PlayExperienceSession(accountID: 12, epoch: 1, namespace: "other-realm", token: "fixture-token")] {
            var current: PlayExperienceSession? = owner
            let recorder = Recorder(); let (picker, service, _) = await setup(adapter: recorder, current: { current })
            picker.open(); recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid)); current = next
            XCTAssertFalse(picker.canUsePoint); XCTAssertFalse(picker.review(label: "Synthetic")); XCTAssertFalse(picker.isPresented)
            recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid)); XCTAssertNil(picker.selection.point)
            XCTAssertTrue(service.mutations.isEmpty)
        }
    }
    func testVersionChangeAndExplicitInvalidationDiscardSelection() async {
        let recorder = Recorder(); let (picker, service, _) = await setup(adapter: recorder)
        picker.open(); recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid))
        service.version = 1; await picker.owner.load()
        XCTAssertFalse(picker.review(label: "Stale")); XCTAssertFalse(picker.isPresented)
        picker.open(); recorder.callbacks[1](PrivateHomeFixtureMapAdapter.candidate(.valid)); picker.owner.invalidate()
        XCTAssertFalse(picker.review(label: "Invalidated")); XCTAssertNil(picker.selection.point)
        XCTAssertTrue(service.mutations.isEmpty)
    }
    func testMapReviewedUnknownOutcomeRetriesIdenticalVersionedPayload() async throws {
        let recorder = Recorder(); let (picker, service, journal) = await setup(adapter: recorder)
        service.lost = true; picker.open(); recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid))
        XCTAssertTrue(picker.review(label: "Synthetic")); await picker.owner.confirm()
        let pending = try XCTUnwrap(journal.value); XCTAssertTrue(picker.owner.canRetry)
        picker.open(); XCTAssertFalse(picker.isPresented)
        await picker.owner.retryExact()
        XCTAssertEqual(service.mutations, [pending, pending]); XCTAssertEqual(service.receipts.count, 1)
        XCTAssertNil(journal.value); XCTAssertEqual(service.version, 1)
    }
    func testProviderContractRevocationCannotUsePreviouslySelectedPoint() async {
        let recorder = Recorder(); let (picker, service, _) = await setup(adapter: recorder)
        picker.open(); recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid))
        recorder.approvedSource = nil
        XCTAssertFalse(picker.canUsePoint); XCTAssertFalse(picker.review(label: "Revoked"))
        XCTAssertFalse(picker.isPresented); XCTAssertNil(picker.selection.point); XCTAssertTrue(service.mutations.isEmpty)
    }

    func testSourceRevocationOrRevisionChangeAfterReviewRejectsFinalConfirmation() async {
        for source in [nil, PrivateHomeMapSource(providerID: "synthetic.private-home", region: "ZZ", datum: .wgs84, contractRevision: "revoked-replacement")] {
            let recorder = Recorder(); let (picker, service, journal) = await setup(adapter: recorder)
            picker.open(); recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid))
            XCTAssertTrue(picker.review(label: "Synthetic")); XCTAssertTrue(picker.owner.canConfirm)
            recorder.approvedSource = source
            if picker.authorizeOwnerConfirmation() { await picker.owner.confirm(); XCTFail("Revoked map source authorized confirmation") }
            XCTAssertFalse(picker.owner.canConfirm); XCTAssertNil(picker.owner.review)
            XCTAssertEqual(picker.confirmationIssue, .providerUnverified)
            XCTAssertTrue(service.mutations.isEmpty); XCTAssertNil(journal.value)
            XCTAssertFalse(picker.authorizeOwnerConfirmation())
        }
    }
    func testNewManualReviewAfterMapCancellationRemainsIndependentOfProvider() async throws {
        let recorder = Recorder(); let (picker, service, journal) = await setup(adapter: recorder)
        picker.open(); recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid))
        XCTAssertTrue(picker.review(label: "Synthetic")); let mapRequest = picker.owner.review?.requestId
        picker.owner.cancelReview(); recorder.approvedSource = nil
        picker.owner.prepareSet(label: "Manual", point: try PrivateHomePoint.parse(latitude: "-12", longitude: "-45"))
        XCTAssertNotEqual(picker.owner.review?.requestId, mapRequest)
        XCTAssertTrue(picker.authorizeOwnerConfirmation()); await picker.owner.confirm()
        XCTAssertEqual(service.mutations.count, 1); XCTAssertEqual(service.mutations.first?.latitude, Decimal(-12))
        XCTAssertNil(journal.value)
    }
    func testFinalConfirmationRechecksSessionAfterPickerReview() async {
        var current: PlayExperienceSession? = owner
        let recorder = Recorder(); let (picker, service, journal) = await setup(adapter: recorder, current: { current })
        picker.open(); recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid))
        XCTAssertTrue(picker.review(label: "Synthetic")); current = nil
        XCTAssertFalse(picker.authorizeOwnerConfirmation())
        await picker.owner.confirm(); XCTAssertTrue(service.mutations.isEmpty); XCTAssertNil(journal.value)
    }
    func testViewCleanupPreservesUnknownOutcomeDurableJournal() async throws {
        let recorder = Recorder(); let (picker, service, journal) = await setup(adapter: recorder)
        service.lost = true; picker.open(); recorder.callbacks[0](PrivateHomeFixtureMapAdapter.candidate(.valid))
        XCTAssertTrue(picker.review(label: "Synthetic")); XCTAssertTrue(picker.authorizeOwnerConfirmation())
        await picker.owner.confirm(); let pending = try XCTUnwrap(journal.value)
        picker.close(); picker.owner.cancelReview(); picker.owner.invalidate()
        XCTAssertNil(picker.selection.point); XCTAssertNil(picker.owner.review)
        XCTAssertEqual(journal.value, pending); XCTAssertEqual(service.mutations, [pending])
    }
}

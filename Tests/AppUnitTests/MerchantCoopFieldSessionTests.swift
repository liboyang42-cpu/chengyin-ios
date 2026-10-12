import XCTest
@testable import Questify

@MainActor final class MerchantCoopFieldSessionTests: XCTestCase {
    @MainActor private final class ReadOnlyReader: MerchantOperationsReading {
        let base = MerchantOperationsFixtureReader()
        var scope: UUID { base.scope }
        var isConfigured = true
        var isAuthenticated: Bool { base.isAuthenticated }
        var isOfflineExample = false
        var canSave = false
        var pending = false
        var saveAttempts = 0
        func hasPending(_ destination: MerchantOperationsDestination) -> Bool { pending }
        func access() async throws -> MerchantOperationsAccess { try await base.access() }
        func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { try await base.document(destination) }
        func saveExample(_ draft: MerchantOperationsDraft) async throws { saveAttempts += 1; throw MerchantOperationsFailure.liveWritesDisabled }
    }
    private func harness() async -> (MerchantOperationsViewModel, MerchantOperationsFixtureReader) {
        let reader = MerchantOperationsFixtureReader()
        let document = MerchantOperationsViewModel(reader: reader, destination: .cooperation); await document.load()
        return (document, reader)
    }
    private func open(_ document: MerchantOperationsViewModel, _ field: MerchantCoopField = .demand) throws -> MerchantCoopFieldSession {
        try XCTUnwrap(MerchantCoopFieldSession(document: document, field: field))
    }
    func testTypingIsOnlyEphemeralAndDoesNotReadOrWrite() async throws {
        let (document, reader) = await harness(); let before = document.coordinator.draft, reads = reader.accessCount
        let session = try open(document); XCTAssertTrue(session.update("  Local e\u{301}  "))
        XCTAssertEqual(document.coordinator.draft, before); XCTAssertEqual(reader.accessCount, reads); XCTAssertEqual(reader.saveCount, 0)
    }
    func testApplyChangesExactlyOneFieldAndConsumesSession() async throws {
        let (document, reader) = await harness(); guard case .cooperation(var expected) = document.coordinator.draft else { return XCTFail() }
        let session = try open(document); expected.demand = "  New  "; session.update(expected.demand)
        XCTAssertTrue(session.apply()); XCTAssertFalse(session.apply()); XCTAssertTrue(session.consumed)
        guard case .cooperation(let actual) = document.coordinator.draft else { return XCTFail() }
        XCTAssertTrue(MerchantCoopFieldDraft.sameValues(actual, expected)); XCTAssertEqual(reader.saveCount, 0)
    }
    func testUnchangedApplyDoesNotIncrementOwnerRevisionOrDirtyDraft() async throws {
        let (document, _) = await harness(); let revision = document.revision, before = document.coordinator.draft
        XCTAssertTrue(try open(document).apply()); XCTAssertEqual(document.revision, revision)
        XCTAssertEqual(document.coordinator.draft, before); XCTAssertFalse(document.coordinator.isDirty)
    }
    func testCleanCancelClosesWithoutConfirmation() async throws {
        let (document, reader) = await harness(); let session = try open(document)
        XCTAssertTrue(session.requestClose()); XCTAssertTrue(session.consumed); XCTAssertFalse(session.asksDiscard)
        XCTAssertFalse(document.coordinator.isDirty); XCTAssertEqual(reader.saveCount, 0)
    }
    func testDirtyCancelThenKeepEditingRetainsExactInput() async throws {
        let (document, _) = await harness(); let session = try open(document), input = " \ne\u{301}  "
        session.update(input); XCTAssertFalse(session.requestClose()); XCTAssertTrue(session.asksDiscard); XCTAssertFalse(session.canApply)
        session.keepEditing(); XCTAssertFalse(session.asksDiscard); XCTAssertEqual(Array(session.buffer.value.utf8), Array(input.utf8)); XCTAssertTrue(session.canApply)
    }
    func testConfirmedDiscardClearsOnlyBufferAndPreservesPriorSiblingEdit() async throws {
        let (document, reader) = await harness(); guard case .cooperation(var prior) = document.coordinator.draft else { return XCTFail() }
        prior.availableTime = "Earlier draft edit"; document.edit(.cooperation(prior))
        let session = try open(document); session.update("Discard me"); session.requestClose(); XCTAssertTrue(session.discard())
        XCTAssertEqual(session.buffer.value, ""); XCTAssertEqual(document.coordinator.draft, .cooperation(prior)); XCTAssertEqual(reader.saveCount, 0)
    }
    func testInvalidCapacityKeepsRawInputAndCannotApply() async throws {
        let (document, _) = await harness(); let before = document.coordinator.draft, session = try open(document, .capacity)
        session.update("-2"); XCTAssertFalse(session.apply()); XCTAssertEqual(session.buffer.value, "-2"); XCTAssertEqual(document.coordinator.draft, before)
        session.update("2"); XCTAssertTrue(session.apply())
    }
    func testUnrelatedChargeEditInvalidatesOlderFieldSession() async throws {
        let (document, _) = await harness(); let session = try open(document); session.update("Old buffer")
        guard case .cooperation(var newer) = document.coordinator.draft else { return XCTFail() }
        newer.chargeType = newer.chargeType == 0 ? 1 : 0; document.edit(.cooperation(newer))
        XCTAssertFalse(session.apply()); XCTAssertEqual(document.coordinator.draft, .cooperation(newer))
    }
    func testSameBytesOwnerRevisionChangeStillInvalidates() async throws {
        let (document, _) = await harness(); let session = try open(document)
        document.edit(try XCTUnwrap(document.coordinator.draft)); XCTAssertFalse(session.isCurrent); XCTAssertFalse(session.apply())
    }
    func testSameBytesReloadInvalidatesByIdentityAndRevision() async throws {
        let (document, _) = await harness(); let session = try open(document); session.update("Old")
        await document.load(); XCTAssertFalse(session.isCurrent); XCTAssertFalse(session.apply())
    }
    func testWholeDraftDiscardInvalidatesOldFieldBuffer() async throws {
        let (document, _) = await harness(); let session = try open(document); session.update("Old")
        document.discard(); XCTAssertFalse(session.apply()); XCTAssertFalse(document.coordinator.isDirty)
    }
    func testAccountSwitchAndLogoutRejectOldActions() async throws {
        let (document, reader) = await harness(); let session = try open(document); session.update("Old")
        reader.switchAccount(); XCTAssertFalse(session.apply()); XCTAssertFalse(session.update("Leak"))
        XCTAssertFalse(reader.isAuthenticated)
        XCTAssertNil(MerchantCoopFieldSession(document: document, field: .demand))
        reader.isAuthenticated = true
        await document.load(); let signedOut = try open(document); reader.signOut(); XCTAssertFalse(signedOut.apply())
    }
    func testReviewInProgressRejectsFieldSessionAndKeepsFrozenReview() async throws {
        let (document, _) = await harness(); guard case .cooperation(var draft) = document.coordinator.draft else { return XCTFail() }
        draft.demand += " changed"; document.edit(.cooperation(draft)); let session = try open(document)
        document.prepare(); let review = try XCTUnwrap(document.coordinator.confirmation)
        XCTAssertFalse(session.apply()); XCTAssertEqual(document.coordinator.confirmation, review); XCTAssertNil(MerchantCoopFieldSession(document: document, field: .capacity))
    }
    func testFieldAppliedDraftReachesOriginalFullReviewWithoutSending() async throws {
        let (document, reader) = await harness(); let session = try open(document); session.update("Ready for review")
        XCTAssertTrue(session.apply()); document.prepare(); let review = try XCTUnwrap(document.coordinator.confirmation)
        XCTAssertEqual(review.draft, document.coordinator.draft); XCTAssertEqual(reader.saveCount, 0)
    }
    func testDeniedReaderCannotOpenFieldEditor() async {
        let reader = MerchantOperationsFixtureReader(); reader.denied = true
        let document = MerchantOperationsViewModel(reader: reader, destination: .cooperation); await document.load()
        XCTAssertNil(MerchantCoopFieldSession(document: document, field: .demand))
    }
    func testAnotherDestinationCannotOpenCooperationFields() async {
        let document = MerchantOperationsViewModel(reader: MerchantOperationsFixtureReader(), destination: .profile); await document.load()
        XCTAssertNil(MerchantCoopFieldSession(document: document, field: .demand))
    }
    func testCanceledOldSessionCannotAffectReopenedField() async throws {
        let (document, _) = await harness(); let old = try open(document); old.update("Old"); old.cancel()
        let current = try open(document, .availableTime); current.update("New")
        old.cancel(); XCTAssertFalse(old.apply()); XCTAssertFalse(old.discard()); XCTAssertTrue(current.isCurrent); XCTAssertEqual(current.buffer.value, "New")
    }
    func testBackgroundStyleRetirementClearsInputAndRejectsApply() async throws {
        let (document, _) = await harness(); let session = try open(document); session.update("Private draft"); session.cancel()
        XCTAssertEqual(session.buffer.value, ""); XCTAssertFalse(session.isCurrent); XCTAssertFalse(session.apply())
    }
    func testCanonicalSiblingChangeCannotPassExactValueFence() async throws {
        let (document, _) = await harness(); guard case .cooperation(var value) = document.coordinator.draft else { return XCTFail() }
        value.availableTime = "é"; document.edit(.cooperation(value)); let session = try open(document)
        value.availableTime = "e\u{301}"; document.coordinator.edit(.cooperation(value))
        XCTAssertFalse(session.isCurrent); XCTAssertFalse(session.apply())
    }
    func testPendingDiscardPreventsEditsUntilKeepEditing() async throws {
        let (document, _) = await harness(); let session = try open(document); session.update("Keep"); session.requestClose()
        XCTAssertFalse(session.update("Unexpected")); XCTAssertFalse(session.apply()); XCTAssertEqual(session.buffer.value, "Keep")
        session.keepEditing(); XCTAssertTrue(session.update("Expected"))
    }
    func testExistingReadOnlyCompositionAllowsLocalApplyAndReviewWithoutSend() async throws {
        let reader = ReadOnlyReader()
        let owner = MerchantOperationsViewModel(reader: reader, destination: .cooperation); await owner.load()
        let session = try open(owner); session.update("Local only"); XCTAssertTrue(session.apply()); owner.prepare()
        XCTAssertNotNil(owner.coordinator.confirmation); XCTAssertFalse(reader.canSave); XCTAssertEqual(reader.saveAttempts, 0)
    }
    func testExistingPendingWriteLockPreventsOpeningField() async {
        let reader = ReadOnlyReader(); reader.pending = true
        let owner = MerchantOperationsViewModel(reader: reader, destination: .cooperation); await owner.load()
        XCTAssertTrue(owner.coordinator.isLocked); XCTAssertNil(MerchantCoopFieldSession(document: owner, field: .demand))
    }

}

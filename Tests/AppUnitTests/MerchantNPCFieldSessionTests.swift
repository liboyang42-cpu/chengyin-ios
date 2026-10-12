import XCTest
@testable import Questify

@MainActor final class MerchantNPCFieldSessionTests: XCTestCase {
    @MainActor private final class ReadOnlyReader: MerchantOperationsReading {
        let base = MerchantOperationsFixtureReader()
        var scope: UUID { base.scope }
        var isConfigured = true
        var isAuthenticated: Bool { base.isAuthenticated }
        var isOfflineExample = false, canSave = false, pending = false
        var saves = 0
        func hasPending(_ destination: MerchantOperationsDestination) -> Bool { pending }
        func access() async throws -> MerchantOperationsAccess { try await base.access() }
        func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { try await base.document(destination) }
        func saveExample(_ draft: MerchantOperationsDraft) async throws { saves += 1; throw MerchantOperationsFailure.liveWritesDisabled }
    }
    private func harness() async -> (MerchantOperationsViewModel, MerchantOperationsFixtureReader) {
        let reader = MerchantOperationsFixtureReader()
        let d = MerchantOperationsViewModel(reader: reader, destination: .character)
        await d.load(); return (d, reader)
    }
    private func open(_ d: MerchantOperationsViewModel, _ field: MerchantNPCTextField = .name) throws -> MerchantNPCFieldSession { try XCTUnwrap(.init(document: d, field: field)) }
    func testTypingNeverEditsOwnerOrReadsOrSaves() async throws {
        let (d,r) = await harness(); let original = try XCTUnwrap(d.coordinator.draft), reads = r.accessCount
        let s = try open(d); s.update("New"); XCTAssertTrue(MerchantNPCFieldDraft.sameDraft(try XCTUnwrap(d.coordinator.draft),original))
        XCTAssertEqual(r.accessCount,reads); XCTAssertEqual(r.saveCount,0)
    }
    func testAllFourFieldsApplyLocallyWithSourceTrim() async throws {
        for field in MerchantNPCTextField.allCases {
            let (d,r) = await harness(); let s = try open(d,field); s.update(" New e\u{0301} ")
            XCTAssertTrue(s.apply()); let next = try XCTUnwrap(d.coordinator.draft)
            XCTAssertEqual(Data(try XCTUnwrap(field.value(in: next)).utf8),Data("New e\u{0301}".utf8)); XCTAssertEqual(r.saveCount,0)
        }
    }
    func testApplyPreservesOtherFieldsAndAudit() async throws {
        let (d,_) = await harness(); guard case .character(var expected) = d.coordinator.draft else { return XCTFail() }
        let s = try open(d,.knowledge); s.update(" New knowledge "); expected.knowledge = "New knowledge"
        XCTAssertTrue(s.apply()); XCTAssertTrue(MerchantNPCFieldDraft.sameDraft(try XCTUnwrap(d.coordinator.draft),.character(expected)))
    }
    func testUnchangedApplyDoesNotChangeRevision() async throws {
        let (d,_) = await harness(); let revision = d.revision; XCTAssertTrue(try open(d).apply()); XCTAssertEqual(d.revision,revision)
    }
    func testDirtyCancelKeepPreservesRawBuffer() async throws {
        let (d,_) = await harness(); let s = try open(d); s.update(" e\u{0301} "); XCTAssertFalse(s.requestClose())
        XCTAssertFalse(s.update("Blocked")); XCTAssertFalse(s.apply()); s.keepEditing(); XCTAssertEqual(Data(s.buffer.value.utf8),Data(" e\u{0301} ".utf8))
    }
    func testCleanCancelConsumesSession() async throws {
        let (d,_) = await harness(); let s = try open(d); XCTAssertTrue(s.requestClose()); XCTAssertTrue(s.consumed); XCTAssertFalse(s.asksDiscard)
    }
    func testDiscardKeepsEarlierSiblingDraft() async throws {
        let (d,_) = await harness(); guard case .character(var c) = d.coordinator.draft else { return XCTFail() }; c.persona = "Earlier edit"; d.edit(.character(c))
        let s = try open(d); s.update("Discard"); s.requestClose(); XCTAssertTrue(s.discard()); XCTAssertEqual(s.buffer.value,"")
        XCTAssertTrue(MerchantNPCFieldDraft.sameDraft(try XCTUnwrap(d.coordinator.draft),.character(c)))
    }
    func testInvalidInputStaysInBufferThenCanBeCorrected() async throws {
        let (d,_) = await harness(); let s = try open(d); s.update(" "); XCTAssertFalse(s.apply()); XCTAssertEqual(s.buffer.value," ")
        s.update("Valid"); XCTAssertTrue(s.apply())
    }
    func testConsumedApplyCannotRunTwice() async throws {
        let (d,_) = await harness(); let s = try open(d); s.update("One"); XCTAssertTrue(s.apply()); let revision = d.revision
        XCTAssertFalse(s.apply()); XCTAssertFalse(s.update("Two")); XCTAssertEqual(d.revision,revision)
    }
    func testSiblingEditAndRestorationInvalidateOldSession() async throws {
        let (d,_) = await harness(); let original = try XCTUnwrap(d.coordinator.draft); let s = try open(d)
        guard case .character(var c) = original else { return XCTFail() }; c.greeting += "X"; d.edit(.character(c)); d.edit(original)
        XCTAssertFalse(s.apply())
    }
    func testCanonicalSiblingByteChangeBlocksBeforeViewCallback() async throws {
        let (d,_) = await harness(); guard case .character(var c) = d.coordinator.draft else { return XCTFail() }; c.persona = "é"; d.edit(.character(c))
        let s = try open(d); c.persona = "e\u{0301}"; d.coordinator.edit(.character(c)); XCTAssertFalse(s.apply())
    }
    func testReloadAndWholeDraftDiscardRetireSessions() async throws {
        let (d,_) = await harness(); let s = try open(d); await d.load(); XCTAssertFalse(s.apply()); let next = try open(d); d.discard(); XCTAssertFalse(next.apply())
    }
    func testAccountSwitchAndReauthenticationThenLogout() async throws {
        let (d,r) = await harness(); let s = try open(d); r.switchAccount(); XCTAssertFalse(s.apply()); XCTAssertNil(MerchantNPCFieldSession(document:d,field:.name))
        r.isAuthenticated = true; await d.load(); let next = try open(d); r.signOut(); XCTAssertFalse(next.apply())
    }
    func testReviewRejectsOldAndNewSessionsWithoutSaving() async throws {
        let (d,r) = await harness(); let s = try open(d); s.update("New"); XCTAssertTrue(s.apply()); let stale = try open(d); d.prepare()
        XCTAssertNotNil(d.coordinator.confirmation); XCTAssertFalse(stale.apply()); XCTAssertNil(MerchantNPCFieldSession(document:d,field:.name)); XCTAssertEqual(r.saveCount,0)
    }
    func testBackgroundReturnRejectsOldOpenPermitAndBuffer() async throws {
        let (d,_) = await harness(); let p = MerchantNPCFieldPresentation(); p.activate(); let permit = p.generation; p.open(permit:permit,document:d,field:.name)
        let old = try XCTUnwrap(p.session); p.deactivate(); p.activate(); XCTAssertFalse(old.apply()); XCTAssertEqual(old.buffer.value,"")
        p.open(permit:permit,document:d,field:.name); XCTAssertNil(p.session); p.open(permit:p.generation,document:d,field:.name); XCTAssertNotNil(p.session)
    }
    func testOldCloseCannotDismissNewField() async throws {
        let (d,_) = await harness(); let p = MerchantNPCFieldPresentation(); p.activate(); p.open(permit:p.generation,document:d,field:.name); let old = try XCTUnwrap(p.session)
        p.close(old.id); p.open(permit:p.generation,document:d,field:.knowledge); let next = try XCTUnwrap(p.session); p.close(old.id); XCTAssertTrue(p.session === next)
    }
    func testOldBindingCannotExposeOrDismissNewField() async throws {
        let (d,_) = await harness(); let p = MerchantNPCFieldPresentation(); p.activate(); p.open(permit:p.generation,document:d,field:.name); let old = try XCTUnwrap(p.session), binding = p.presentationBinding()
        p.close(old.id); p.open(permit:p.generation,document:d,field:.persona); let next = try XCTUnwrap(p.session); XCTAssertNil(binding.wrappedValue); binding.wrappedValue = nil; XCTAssertTrue(p.session === next)
    }
    func testEmptyBindingCannotCloseLaterField() async throws {
        let (d,_) = await harness(); let p = MerchantNPCFieldPresentation(); p.activate(); let binding = p.presentationBinding(); p.open(permit:p.generation,document:d,field:.name)
        let next = try XCTUnwrap(p.session); binding.wrappedValue = nil; XCTAssertNil(binding.wrappedValue); XCTAssertTrue(p.session === next)
    }
    func testReadOnlyConfiguredReaderAllowsOnlyLocalApply() async throws {
        let r = ReadOnlyReader(); let d = MerchantOperationsViewModel(reader:r,destination:.character); await d.load()
        let s = try open(d); s.update("Local guide"); XCTAssertTrue(s.apply()); XCTAssertFalse(r.canSave); XCTAssertEqual(r.saves,0)
    }
    func testPendingWriteAndUnconfiguredReaderCannotOpen() async throws {
        let r = ReadOnlyReader(); let d = MerchantOperationsViewModel(reader:r,destination:.character); await d.load(); r.isConfigured = false
        XCTAssertNil(MerchantNPCFieldSession(document:d,field:.name)); r.isConfigured = true; r.pending = true; await d.load()
        XCTAssertNil(MerchantNPCFieldSession(document:d,field:.name)); XCTAssertEqual(r.saves,0)
    }
    func testMissingAvatarRetainsOriginalWholeDraftBlocker() async throws {
        let (d,r) = await harness(); guard case .character(var c) = d.coordinator.draft else { return XCTFail() }
        c.avatar = ""; d.edit(.character(c)); let s = try open(d,.knowledge); s.update("Prepared facts"); XCTAssertTrue(s.apply())
        XCTAssertEqual(d.coordinator.draft?.blocker,"merchant.operations.characterAvatarRequired"); XCTAssertFalse(d.coordinator.canReview); XCTAssertEqual(r.saveCount,0)
    }

}

import XCTest
@testable import Questify

@MainActor final class MerchantStoreFieldSessionTests: XCTestCase {
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
    private func harness(_ destination: MerchantOperationsDestination = .profile) async -> (MerchantOperationsViewModel, MerchantOperationsFixtureReader) {
        let reader = MerchantOperationsFixtureReader(); let document = MerchantOperationsViewModel(reader: reader, destination: destination); await document.load(); return (document, reader)
    }
    private func open(_ document: MerchantOperationsViewModel, _ field: MerchantStoreTextField = .name) throws -> MerchantStoreFieldSession { try XCTUnwrap(.init(document: document, field: field)) }
    func testTypingIsEphemeralAndDoesNotReadOrWrite() async throws {
        let (d,r) = await harness(); let before = try XCTUnwrap(d.coordinator.draft), reads = r.accessCount; let s = try open(d); s.update("New name")
        XCTAssertTrue(MerchantStoreFieldDraft.sameDraft(try XCTUnwrap(d.coordinator.draft), before)); XCTAssertEqual(r.accessCount, reads); XCTAssertEqual(r.saveCount, 0)
    }
    func testApplyUsesExistingEditAndPreservesSiblingBytes() async throws {
        let (d,r) = await harness(); guard case .profile(var expected) = d.coordinator.draft else { return XCTFail() }
        let s = try open(d); s.update("  New e\u{0301}  "); expected.name = s.buffer.value
        XCTAssertTrue(s.apply()); XCTAssertTrue(MerchantStoreFieldDraft.sameDraft(try XCTUnwrap(d.coordinator.draft), .profile(expected))); XCTAssertEqual(r.saveCount, 0)
    }
    func testAllSixFieldsAndStoryHaveExistingDestinations() async throws {
        for (dest,fields) in [(MerchantOperationsDestination.profile,[MerchantStoreTextField.name,.preference,.description,.derivativeBenefits]),(.decor,[.slogan,.cityRole]),(.story,[.description])] {
            for field in fields { let (d,r) = await harness(dest); let s = try open(d,field); s.update("Prepared locally"); XCTAssertTrue(s.apply()); XCTAssertEqual(r.saveCount,0) }
        }
    }
    func testUnchangedApplyDoesNotChangeRevision() async throws {
        let (d,_) = await harness(); let revision = d.revision; XCTAssertTrue(try open(d).apply()); XCTAssertEqual(d.revision,revision)
    }
    func testCleanCancelClosesWithoutPrompt() async throws {
        let (d,_) = await harness(); let s = try open(d); XCTAssertTrue(s.requestClose()); XCTAssertFalse(s.asksDiscard); XCTAssertTrue(s.consumed)
    }
    func testDirtyCancelKeepEditingPreservesExactInput() async throws {
        let (d,_) = await harness(); let s = try open(d); s.update(" \ne\u{0301}  "); XCTAssertFalse(s.requestClose()); XCTAssertTrue(s.asksDiscard)
        XCTAssertFalse(s.update("Replacement")); XCTAssertFalse(s.apply()); s.keepEditing(); XCTAssertEqual(Data(s.buffer.value.utf8),Data(" \ne\u{0301}  ".utf8))
    }
    func testDiscardRetainsExistingSiblingDraftChanges() async throws {
        let (d,_) = await harness(); guard case .profile(var value) = d.coordinator.draft else { return XCTFail() }; value.website = "Earlier draft"; d.edit(.profile(value))
        let s = try open(d); s.update("Discard"); s.requestClose(); XCTAssertTrue(s.discard()); XCTAssertEqual(s.buffer.value, "")
        XCTAssertTrue(MerchantStoreFieldDraft.sameDraft(try XCTUnwrap(d.coordinator.draft),.profile(value)))
    }
    func testInvalidNameAndLengthRetainBufferUntilCorrected() async throws {
        let (d,_) = await harness(); let s = try open(d); s.update(" "); XCTAssertFalse(s.apply()); XCTAssertEqual(s.buffer.value," ")
        s.update(String(repeating:"x",count:101)); XCTAssertFalse(s.apply()); s.update("Valid"); XCTAssertTrue(s.apply())
    }
    func testSingleUseApplyCannotRunAgain() async throws {
        let (d,_) = await harness(); let s = try open(d); s.update("One"); XCTAssertTrue(s.apply()); let revision=d.revision
        XCTAssertFalse(s.apply()); XCTAssertFalse(s.update("Two")); XCTAssertEqual(d.revision,revision)
    }
    func testOwnerRevisionAndSiblingEditInvalidate() async throws {
        let (d,_) = await harness(); let s = try open(d); guard case .profile(var value) = d.coordinator.draft else { return XCTFail() }; value.derivatives += " change"; d.edit(.profile(value))
        XCTAssertFalse(s.apply()); XCTAssertFalse(s.isCurrent)
    }
    func testSameValueOwnerEditAlsoInvalidates() async throws {
        let (d,_) = await harness(); let s=try open(d); d.edit(try XCTUnwrap(d.coordinator.draft)); XCTAssertFalse(s.apply())
    }
    func testCanonicalSiblingChangeBlocksBeforeViewCallback() async throws {
        let (d,_) = await harness(); guard case .profile(var value) = d.coordinator.draft else { return XCTFail() }; value.website="é"; d.edit(.profile(value))
        let s=try open(d); value.website="e\u{0301}"; d.coordinator.edit(.profile(value)); XCTAssertFalse(s.apply())
    }
    func testReloadAndWholeDraftDiscardRetireOldSessions() async throws {
        let (d,_) = await harness(); let s=try open(d); await d.load(); XCTAssertFalse(s.apply())
        let next=try open(d); d.discard(); XCTAssertFalse(next.apply())
    }
    func testAccountSwitchAndSignoutBlockActions() async throws {
        let (d,r) = await harness(); let s=try open(d); r.switchAccount(); XCTAssertFalse(s.apply()); r.isAuthenticated = true; await d.load()
        let next=try open(d); r.signOut(); XCTAssertFalse(next.apply()); XCTAssertFalse(next.update("Leak"))
    }
    func testReadOnlyConfiguredReaderSupportsOnlyLocalApply() async throws {
        let r=ReadOnlyReader(); let d=MerchantOperationsViewModel(reader:r,destination:.profile); await d.load(); let s=try open(d); s.update("Local only")
        XCTAssertTrue(s.apply()); XCTAssertFalse(r.canSave); XCTAssertEqual(r.saves,0)
    }
    func testUnconfiguredOrPendingReaderCannotOpen() async throws {
        let r=ReadOnlyReader(); let d=MerchantOperationsViewModel(reader:r,destination:.profile); await d.load(); r.isConfigured=false
        XCTAssertNil(MerchantStoreFieldSession(document:d,field:.name)); r.isConfigured=true; r.pending=true; await d.load()
        XCTAssertNil(MerchantStoreFieldSession(document:d,field:.name))
    }
    func testReviewRetiresBufferAndNewFieldOpening() async throws {
        let (d,r)=await harness(); let first=try open(d); first.update("New"); XCTAssertTrue(first.apply()); let stale=try open(d); d.prepare()
        XCTAssertNotNil(d.coordinator.confirmation); XCTAssertFalse(stale.apply()); XCTAssertNil(MerchantStoreFieldSession(document:d,field:.name)); XCTAssertEqual(r.saveCount,0)
    }
    func testAppliedFieldReachesOriginalWholeDraftReview() async throws {
        let (d,r)=await harness(.story); let s=try open(d,.description); s.update("A local story"); XCTAssertTrue(s.apply()); d.prepare()
        XCTAssertNotNil(d.coordinator.confirmation); XCTAssertEqual(r.saveCount,0)
    }
    func testBackgroundReturnRejectsOldOpenPermitAndBuffer() async throws {
        let (d,_)=await harness(); let p=MerchantStoreFieldPresentation(); p.activate(); let permit=p.generation; p.open(permit:permit,document:d,field:.name)
        let old=try XCTUnwrap(p.session); p.deactivate(); p.activate(); XCTAssertFalse(old.apply()); XCTAssertEqual(old.buffer.value,"")
        p.open(permit:permit,document:d,field:.name); XCTAssertNil(p.session); p.open(permit:p.generation,document:d,field:.name); XCTAssertNotNil(p.session)
    }
    func testOldCloseCannotDismissNewField() async throws {
        let (d,_)=await harness(); let p=MerchantStoreFieldPresentation(); p.activate(); p.open(permit:p.generation,document:d,field:.name); let old=try XCTUnwrap(p.session)
        p.close(old.id); p.open(permit:p.generation,document:d,field:.preference); let new=try XCTUnwrap(p.session); p.close(old.id); XCTAssertTrue(p.session === new)
    }
    func testOldPresentationBindingCannotExposeOrDismissNewField() async throws {
        let (d,_)=await harness(); let p=MerchantStoreFieldPresentation(); p.activate(); p.open(permit:p.generation,document:d,field:.name); let old=try XCTUnwrap(p.session); let binding=p.presentationBinding()
        p.close(old.id); p.open(permit:p.generation,document:d,field:.description); let new=try XCTUnwrap(p.session)
        XCTAssertNil(binding.wrappedValue); binding.wrappedValue=nil; XCTAssertTrue(p.session === new)
    }
    func testEmptyPresentationBindingCannotCloseLaterField() async throws {
        let (d,_)=await harness(); let p=MerchantStoreFieldPresentation(); p.activate(); let empty=p.presentationBinding(); p.open(permit:p.generation,document:d,field:.name)
        let new=try XCTUnwrap(p.session); empty.wrappedValue=nil; XCTAssertNil(empty.wrappedValue); XCTAssertTrue(p.session === new)
    }
}

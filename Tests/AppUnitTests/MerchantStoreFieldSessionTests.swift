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
    func testHiddenForegroundReturnCannotReopenStoreField() async throws {
        let (d, r) = await harness()
        let p = MerchantStoreFieldPresentation()
        p.viewAppeared(sceneIsActive: true)
        p.open(permit: p.generation, document: d, field: .name)
        let old = try XCTUnwrap(p.session)
        XCTAssertTrue(old.update("Private scratch"))
        let original = try XCTUnwrap(d.coordinator.draft), reads = r.accessCount
        p.viewDisappeared()
        p.sceneChanged(isActive: false)
        p.sceneChanged(isActive: true)
        XCTAssertFalse(p.isVisible); XCTAssertFalse(p.active)
        XCTAssertNil(p.session); XCTAssertEqual(old.buffer.value, "")
        XCTAssertFalse(old.apply())
        p.open(permit: p.generation, document: d, field: .name)
        XCTAssertNil(p.session)
        XCTAssertTrue(MerchantStoreFieldDraft.sameDraft(try XCTUnwrap(d.coordinator.draft), original))
        XCTAssertEqual(r.accessCount, reads); XCTAssertEqual(r.saveCount, 0)
    }
    func testExplicitReappearanceRequiresFreshPermitAndKeepsOldBindingRetired() async throws {
        let (d, r) = await harness()
        let p = MerchantStoreFieldPresentation()
        p.viewAppeared(sceneIsActive: true)
        let oldPermit = p.generation
        p.open(permit: oldPermit, document: d, field: .name)
        let old = try XCTUnwrap(p.session), binding = p.presentationBinding()
        p.viewDisappeared(); p.sceneChanged(isActive: true)
        p.viewAppeared(sceneIsActive: true)
        XCTAssertTrue(p.isVisible); XCTAssertTrue(p.active)
        p.open(permit: oldPermit, document: d, field: .name)
        XCTAssertNil(p.session)
        p.open(permit: p.generation, document: d, field: .preference)
        let current = try XCTUnwrap(p.session)
        XCTAssertFalse(old.update("Stale")); XCTAssertNil(binding.wrappedValue)
        binding.wrappedValue = nil; p.close(old.id)
        XCTAssertTrue(p.session === current); XCTAssertEqual(r.saveCount, 0)
    }
    func testVisibleBackgroundReturnAndInactiveAppearanceUseSceneGate() async throws {
        let (d, r) = await harness()
        let p = MerchantStoreFieldPresentation()
        p.viewAppeared(sceneIsActive: false)
        XCTAssertTrue(p.isVisible); XCTAssertFalse(p.active)
        p.open(permit: p.generation, document: d, field: .name)
        XCTAssertNil(p.session)
        p.sceneChanged(isActive: true)
        p.open(permit: p.generation, document: d, field: .name)
        let old = try XCTUnwrap(p.session), permit = p.generation
        p.sceneChanged(isActive: false)
        XCTAssertTrue(p.isVisible); XCTAssertFalse(p.active); XCTAssertNil(p.session)
        p.sceneChanged(isActive: true)
        XCTAssertTrue(p.active); XCTAssertFalse(old.isCurrent)
        p.open(permit: permit, document: d, field: .name)
        XCTAssertNil(p.session)
        p.open(permit: p.generation, document: d, field: .name)
        XCTAssertNotNil(p.session); XCTAssertEqual(r.saveCount, 0)
    }
}

extension MerchantStoreFieldSessionTests {
    func testDecorRoutesOnlyExistingGalleryAndCooperationWithoutRequests() async throws {
        let (document, reader) = await harness(.decor), reads = reader.accessCount
        let gallery = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .gallery))
        let cooperation = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .cooperation))
        XCTAssertEqual(gallery.destination, .gallery); XCTAssertEqual(cooperation.destination, .cooperation)
        XCTAssertNotEqual(gallery, cooperation); XCTAssertTrue(gallery.isCurrent(document: document))
        XCTAssertEqual(ObjectIdentifier(gallery.reader), ObjectIdentifier(reader))
        XCTAssertEqual(reader.accessCount, reads); XCTAssertEqual(reader.saveCount, 0)
    }
    func testDecorNavigationRetainsParentUnsavedDraftOnChildReadAndReturn() async throws {
        let (document, reader) = await harness(.decor)
        guard case .decor(var edited) = document.coordinator.draft else { return XCTFail() }
        edited.slogan = "  Local draft e\u{0301}  "; document.edit(.decor(edited))
        let before = try XCTUnwrap(document.coordinator.draft), identity = document.coordinator.draftIdentity
        let route = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .gallery))
        let child = MerchantOperationsViewModel(reader: route.reader, destination: route.destination)
        await child.load()
        XCTAssertEqual(child.coordinator.destination, .gallery); XCTAssertTrue(child.coordinator.isCurrent)
        XCTAssertEqual(document.coordinator.draftIdentity, identity)
        XCTAssertTrue(MerchantStoreFieldDraft.sameDraft(try XCTUnwrap(document.coordinator.draft), before))
        XCTAssertTrue(document.coordinator.isDirty); XCTAssertEqual(reader.saveCount, 0)
        child.invalidate(); XCTAssertTrue(route.isCurrent(document: document))
    }
    func testDecorDestinationFreshPermissionDenialUsesExistingErrorAndRetry() async throws {
        let (document, reader) = await harness(.decor)
        let route = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .cooperation))
        let child = MerchantOperationsViewModel(reader: route.reader, destination: route.destination)
        reader.denied = true; await child.load()
        XCTAssertNil(child.coordinator.draft); XCTAssertNotNil(child.coordinator.issue)
        reader.denied = false; await child.load()
        XCTAssertNotNil(child.coordinator.draft); XCTAssertNil(child.coordinator.issue)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testDecorRouteCannotRebindToNewAccountOrReplacementDocument() async throws {
        let (document, reader) = await harness(.decor)
        let route = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .gallery))
        let replacement = MerchantOperationsViewModel(reader: reader, destination: .decor); await replacement.load()
        XCTAssertFalse(route.isCurrent(document: replacement))
        reader.switchAccount(); XCTAssertFalse(route.isCurrent(document: document))
        reader.isAuthenticated = true; await document.load()
        XCTAssertFalse(route.isCurrent(document: document))
    }
    func testDecorRouteRejectsReloadAndUnknownLockedSource() async throws {
        let (document, _) = await harness(.decor)
        let route = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .gallery))
        await document.load(); XCTAssertFalse(route.isCurrent(document: document))
        let lockedReader = ReadOnlyReader(); lockedReader.pending = true
        let locked = MerchantOperationsViewModel(reader: lockedReader, destination: .decor); await locked.load()
        XCTAssertTrue(locked.coordinator.isLocked)
        XCTAssertNil(MerchantDecorEditorRoute(document: locked, target: .cooperation))
    }
    func testNonDecorUnconfiguredSignedOutAndReviewSourceCannotOpenLinkedEditor() async throws {
        let (profile, _) = await harness(.profile)
        XCTAssertNil(MerchantDecorEditorRoute(document: profile, target: .gallery))
        let (document, reader) = await harness(.decor)
        reader.isConfigured = false; XCTAssertNil(MerchantDecorEditorRoute(document: document, target: .gallery))
        reader.isConfigured = true; reader.isAuthenticated = false
        XCTAssertNil(MerchantDecorEditorRoute(document: document, target: .gallery))
        reader.isAuthenticated = true
        guard case .decor(var value) = document.coordinator.draft else { return XCTFail() }
        value.slogan = "Changed"; document.edit(.decor(value)); document.prepare()
        XCTAssertNotNil(document.coordinator.confirmation)
        XCTAssertNil(MerchantDecorEditorRoute(document: document, target: .gallery))
    }
    func testLinkedCooperationUsesOriginalExplicitReviewSaveAndKeepsParentDraft() async throws {
        let (document, reader) = await harness(.decor), before = document.coordinator.draft
        let route = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .cooperation))
        let child = MerchantOperationsViewModel(reader: route.reader, destination: route.destination); await child.load()
        guard case .cooperation(var value) = child.coordinator.draft else { return XCTFail() }
        value.demand = "Synthetic cooperation request"; child.edit(.cooperation(value))
        XCTAssertEqual(reader.saveCount, 0); child.prepare()
        let review = try XCTUnwrap(child.coordinator.confirmation); await child.confirm(review)
        XCTAssertEqual(reader.saveCount, 1); XCTAssertEqual(document.coordinator.draft, before)
        XCTAssertEqual(child.coordinator.draft, .cooperation(value))
    }
}

extension MerchantStoreFieldSessionTests {
    func testActualAppearanceEntryPreservesDirtyDecorAfterLinkedChildReturn() async throws {
        let (document, reader) = await harness(.decor)
        guard case .decor(var draft) = document.coordinator.draft else { return XCTFail() }
        draft.slogan = "  Unsaved e\u{0301}  "; document.edit(.decor(draft))
        let identity = document.coordinator.draftIdentity
        let route = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .gallery))
        document.openDecorEditor(route)
        let binding = document.decorNavigationBinding()
        document.documentDisappeared()
        let child = MerchantOperationsViewModel(reader: route.reader, destination: route.destination)
        await child.loadForAppearance()
        binding.wrappedValue = nil
        let reads = reader.accessCount
        await document.loadForAppearance()
        XCTAssertEqual(document.coordinator.draftIdentity, identity)
        XCTAssertTrue(MerchantStoreFieldDraft.sameDraft(try XCTUnwrap(document.coordinator.draft), .decor(draft)))
        XCTAssertTrue(document.coordinator.isDirty); XCTAssertEqual(reader.accessCount, reads)
        XCTAssertEqual(reader.saveCount, 0); XCTAssertNil(document.decorNavigation)
        XCTAssertFalse(route.isCurrent(document: document))
    }
    func testOldNavigationBindingAndButtonCannotCloseOrReopenNextChild() async throws {
        let (document, _) = await harness(.decor)
        let old = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .gallery))
        document.openDecorEditor(old); let binding = document.decorNavigationBinding()
        document.documentDisappeared(); binding.wrappedValue = nil
        await document.loadForAppearance()
        let next = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .cooperation))
        document.openDecorEditor(next)
        binding.wrappedValue = nil; document.openDecorEditor(old)
        XCTAssertNil(binding.wrappedValue); XCTAssertEqual(document.decorNavigation?.id, next.id)
    }
    func testActualDepartureRetiresDraftAndOldNavigationBeforeReappearance() async throws {
        let (document, reader) = await harness(.decor)
        let stale = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .gallery))
        let identity = document.coordinator.draftIdentity
        document.documentDisappeared()
        document.openDecorEditor(stale)
        XCTAssertNil(document.decorNavigation); XCTAssertNil(document.coordinator.draft)
        let reads = reader.accessCount
        await document.loadForAppearance()
        XCTAssertGreaterThan(reader.accessCount, reads)
        XCTAssertNotEqual(document.coordinator.draftIdentity, identity)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testReturnWithChangedAccountUsesFreshAppearanceRead() async throws {
        let (document, reader) = await harness(.decor)
        let route = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .gallery))
        document.openDecorEditor(route); document.documentDisappeared()
        reader.switchAccount(); reader.isAuthenticated = true
        let reads = reader.accessCount
        await document.loadForAppearance()
        XCTAssertGreaterThan(reader.accessCount, reads)
        XCTAssertTrue(document.coordinator.isCurrent); XCTAssertNil(document.decorNavigation)
        XCTAssertFalse(route.isCurrent(document: document)); XCTAssertEqual(reader.saveCount, 0)
    }
    func testInvalidatedDraftAndBackgroundReturnCannotUseOldReturnTicket() async throws {
        let (document, reader) = await harness(.decor)
        let route = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .gallery))
        document.openDecorEditor(route); document.documentDisappeared()
        document.retireDecorNavigation(); document.leaveImages()
        let reads = reader.accessCount
        await document.loadForAppearance()
        XCTAssertGreaterThan(reader.accessCount, reads); XCTAssertFalse(route.isCurrent(document: document))
        let next = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .cooperation))
        document.openDecorEditor(next); document.discard()
        let nextReads = reader.accessCount
        await document.loadForAppearance()
        XCTAssertGreaterThan(reader.accessCount, nextReads); XCTAssertEqual(reader.saveCount, 0)
    }
    func testReturnWithDisabledReaderUsesExistingFailureRatherThanOldDraft() async throws {
        let (document, reader) = await harness(.decor)
        let route = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .gallery))
        document.openDecorEditor(route); document.documentDisappeared()
        reader.isConfigured = false
        await document.loadForAppearance()
        XCTAssertNil(document.coordinator.draft); XCTAssertNotNil(document.coordinator.issue)
        XCTAssertNil(document.decorNavigation); XCTAssertFalse(route.isCurrent(document: document))
        reader.isConfigured = true; await document.loadForAppearance()
        XCTAssertNotNil(document.coordinator.draft); XCTAssertEqual(reader.saveCount, 0)
    }
    func testExplicitReloadStillRetiresReturnTicketAndReplacesDraftIdentity() async throws {
        let (document, reader) = await harness(.decor)
        let route = try XCTUnwrap(MerchantDecorEditorRoute(document: document, target: .gallery))
        document.openDecorEditor(route)
        let before = document.coordinator.draftIdentity, reads = reader.accessCount
        await document.load()
        XCTAssertGreaterThan(reader.accessCount, reads); XCTAssertNotEqual(document.coordinator.draftIdentity, before)
        XCTAssertNil(document.decorNavigation); XCTAssertFalse(route.isCurrent(document: document))
        XCTAssertEqual(reader.saveCount, 0)
    }
}

import XCTest
@testable import Questify

@MainActor final class MerchantCityTemplateHandoffPresentationTests: XCTestCase {
    private func opened(_ state: MerchantCityTemplateHandoffFixtureState) async throws -> (MerchantCityTemplateHandoffModel, MerchantCityTemplateHandoffModel.Opening, MerchantOperationsCoordinator) {
        let model = MerchantCityTemplateHandoffModel()
        model.activate()
        await model.open(.init(reader: state.reader), binding: state.binding)
        let opening = try XCTUnwrap(model.opening)
        let editor = MerchantOperationsCoordinator(reader: state.reader, destination: .template(nil))
        model.registerEditor(editor, original: opening, binding: state.binding)
        await editor.load()
        return (model, opening, editor)
    }
    private func save(_ editor: MerchantOperationsCoordinator) async throws {
        var value = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(MerchantOperationsFixtureData.templateJSON.utf8))
        value.id = nil; value.couponID = nil
        editor.edit(.template(value)); editor.prepare()
        await editor.confirm(try XCTUnwrap(editor.confirmation))
    }
    func testOpeningAndCancelOnlyReadAndKeepPlacementBytes() async throws {
        let state = MerchantCityTemplateHandoffFixtureState(), before = state.local
        let (model, _, _) = try await opened(state)
        model.close()
        XCTAssertEqual(state.local, before); XCTAssertEqual(state.reader.saveCount, 0)
        XCTAssertEqual(state.readCount, 0); XCTAssertEqual(state.applyCount, 0)
    }
    func testUnsavedTemplateCannotReturnAnyID() async throws {
        let state = MerchantCityTemplateHandoffFixtureState()
        let (model, opening, editor) = try await opened(state)
        XCTAssertFalse(model.canReturn(editor, original: opening, binding: state.binding))
        await model.accept(editor, original: opening, binding: state.binding)
        XCTAssertEqual(state.applyCount, 0); XCTAssertEqual(state.readCount, 0)
    }
    func testOnlyTheRegisteredNewTemplateEditorCanReturn() async throws {
        let state = MerchantCityTemplateHandoffFixtureState()
        let (model, opening, _) = try await opened(state)
        let unrelated = MerchantOperationsCoordinator(reader: state.reader, destination: .template(71))
        await unrelated.load(); model.registerEditor(unrelated, original: opening, binding: state.binding)
        XCTAssertFalse(model.canReturn(unrelated, original: opening, binding: state.binding))
    }
    func testAcknowledgedReadbackChangesOnlySelectedIDAndDirtyFlag() async throws {
        let state = MerchantCityTemplateHandoffFixtureState(), before = state.local
        let (model, opening, editor) = try await opened(state); try await save(editor)
        XCTAssertTrue(model.canReturn(editor, original: opening, binding: state.binding))
        await model.accept(editor, original: opening, binding: state.binding)
        XCTAssertEqual(state.local.fields, before.fields); XCTAssertEqual(state.local.confirmedAddress, before.confirmedAddress)
        XCTAssertEqual(state.local.templateID, 73); XCTAssertTrue(state.local.dirty)
        XCTAssertEqual(state.reader.saveCount, 1); XCTAssertEqual(state.readCount, 1); XCTAssertEqual(state.applyCount, 1)
        XCTAssertTrue(model.applied); XCTAssertNil(model.opening)
    }
    func testMissingOwnedRowRetryReadsWithoutResubmittingTemplate() async throws {
        let state = MerchantCityTemplateHandoffFixtureState(), before = state.local
        state.includeReturnedTemplate = false
        let (model, opening, editor) = try await opened(state); try await save(editor)
        await model.accept(editor, original: opening, binding: state.binding)
        XCTAssertEqual(model.issue, .missingTemplate); XCTAssertEqual(state.local, before)
        state.includeReturnedTemplate = true
        await model.retryRead(opening, binding: state.binding)
        XCTAssertEqual(state.readCount, 2); XCTAssertEqual(state.reader.saveCount, 1); XCTAssertEqual(state.local.templateID, 73)
    }
    func testFailedReadCanRetryWithoutLosingPlacementDraft() async throws {
        let state = MerchantCityTemplateHandoffFixtureState(), before = state.local
        state.failRead = true
        let (model, opening, editor) = try await opened(state); try await save(editor)
        await model.accept(editor, original: opening, binding: state.binding)
        XCTAssertEqual(state.local, before); XCTAssertEqual(model.issue, .readFailed)
        state.failRead = false
        await model.retryRead(opening, binding: state.binding)
        XCTAssertEqual(state.local.templateID, 73); XCTAssertEqual(state.reader.saveCount, 1)
    }
    func testCancelAfterFailedReadCanRecoverParentWithoutApplyingSavedID() async throws {
        let state = MerchantCityTemplateHandoffFixtureState(), before = state.local
        state.failRead = true
        let (model, opening, editor) = try await opened(state); try await save(editor)
        await model.accept(editor, original: opening, binding: state.binding)
        model.close(); state.failRead = false
        await model.recoverParent(binding: state.binding)
        XCTAssertNotNil(state.snapshot); XCTAssertEqual(state.local, before)
        XCTAssertEqual(state.applyCount, 0); XCTAssertEqual(state.reader.saveCount, 1); XCTAssertEqual(state.readCount, 2)
    }
    func testAlbumReturnedByFreshListNeverReplacesOriginalSelection() async throws {
        let state = MerchantCityTemplateHandoffFixtureState(), before = state.local
        state.album = true
        let (model, opening, editor) = try await opened(state); try await save(editor)
        await model.accept(editor, original: opening, binding: state.binding)
        XCTAssertEqual(model.issue, .albumOnly); XCTAssertEqual(state.local, before); XCTAssertEqual(state.applyCount, 0)
    }
    func testIdenticalParentReloadRevokesTheOpening() async throws {
        let state = MerchantCityTemplateHandoffFixtureState()
        let (model, opening, editor) = try await opened(state); try await save(editor)
        state.snapshot = state.makeSnapshot(includeReturned: false, observedAt: Date(timeIntervalSince1970: 3))
        XCTAssertFalse(model.canReturn(editor, original: opening, binding: state.binding))
    }
    func testHeldReadCannotCrossCancellationScopeOrLocalDraftChange() async throws {
        for change in ["cancel", "scope", "draft", "locked"] {
            let state = MerchantCityTemplateHandoffFixtureState()
            let (model, opening, editor) = try await opened(state); try await save(editor)
            state.holdRead = true
            let task = Task { await model.accept(editor, original: opening, binding: state.binding) }
            for _ in 0..<100 where state.pendingRead == nil { await Task.yield() }
            XCTAssertNotNil(state.pendingRead)
            switch change {
            case "cancel": model.close()
            case "scope": state.scope = UUID()
            case "draft": state.local = .init(fields: ["name": "new edit"], templateID: 71, confirmedAddress: false, dirty: true)
            default: state.locked = true
            }
            let beforeRelease = state.local
            state.releaseRead(); await task.value
            XCTAssertEqual(state.local, beforeRelease); XCTAssertEqual(state.applyCount, 0); XCTAssertEqual(state.reader.saveCount, 1)
        }
    }
    func testUnknownTemplateSaveDoesNotOfferReturnOrReplay() async throws {
        let state = MerchantCityTemplateHandoffFixtureState()
        state.reader.saveFailure = .outcomeUnknown
        let (model, opening, editor) = try await opened(state); try await save(editor)
        XCTAssertTrue(editor.isLocked)
        XCTAssertFalse(model.canReturn(editor, original: opening, binding: state.binding))
        await model.accept(editor, original: opening, binding: state.binding)
        XCTAssertEqual(state.applyCount, 0); XCTAssertEqual(state.readCount, 0)
    }
    func testFreshPermissionRevocationBlocksReadback() async throws {
        let state = MerchantCityTemplateHandoffFixtureState(), before = state.local
        let (model, opening, editor) = try await opened(state); try await save(editor)
        state.reader.denied = true
        await model.accept(editor, original: opening, binding: state.binding)
        XCTAssertEqual(state.local, before); XCTAssertEqual(state.readCount, 0)
    }
    func testOfflineExampleCannotBeMixedIntoLiveParent() async {
        let state = MerchantCityTemplateHandoffFixtureState(), model = MerchantCityTemplateHandoffModel()
        model.activate()
        var live = state.binding; live.isOfflineFixture = false
        await model.open(.init(reader: state.reader), binding: live)
        XCTAssertNil(model.opening); XCTAssertEqual(model.issue, .unavailable)
    }
    func testOldSheetDismissAndHostCloseCannotCloseReopenedFlow() async throws {
        let state = MerchantCityTemplateHandoffFixtureState()
        let (model, old, _) = try await opened(state); let oldBinding = model.presentationBinding()
        model.close(id: old.id); await model.open(.init(reader: state.reader), binding: state.binding)
        let current = try XCTUnwrap(model.opening)
        XCTAssertNotEqual(old.id, current.id); XCTAssertNil(oldBinding.wrappedValue)
        oldBinding.wrappedValue = nil; model.close(id: old.id)
        XCTAssertEqual(model.opening?.id, current.id); XCTAssertTrue(model.isCurrent(current, binding: state.binding))
        XCTAssertNil(model.issue); XCTAssertEqual(state.applyCount, 0); XCTAssertEqual(state.reader.saveCount, 0)
    }
    func testFreshOpeningIdentityBindingAndUnpresentedSetterAreIsolated() async throws {
        let state = MerchantCityTemplateHandoffFixtureState(), model = MerchantCityTemplateHandoffModel()
        model.activate()
        let empty = model.presentationBinding(); await model.open(.init(reader: state.reader), binding: state.binding)
        let current = try XCTUnwrap(model.opening); let currentBinding = model.presentationBinding()
        XCTAssertEqual(currentBinding.wrappedValue?.id, current.id); XCTAssertNil(empty.wrappedValue)
        empty.wrappedValue = nil; XCTAssertEqual(model.opening?.id, current.id)
        currentBinding.wrappedValue = nil; XCTAssertNil(model.opening)
        XCTAssertEqual(state.readCount, 0); XCTAssertEqual(state.applyCount, 0)
    }
    func testOldRetryCallbackCannotSetIssueOnNewOpening() async throws {
        let state = MerchantCityTemplateHandoffFixtureState()
        let (model, old, _) = try await opened(state)
        model.close(id: old.id); await model.open(.init(reader: state.reader), binding: state.binding)
        let current = try XCTUnwrap(model.opening)
        await model.retryRead(old, binding: state.binding)
        XCTAssertEqual(model.opening?.id, current.id); XCTAssertNil(model.issue)
        XCTAssertFalse(model.returning); XCTAssertFalse(model.busy)
        XCTAssertEqual(state.readCount, 0); XCTAssertEqual(state.applyCount, 0)
    }

    func testQueuedOpenBeforeExitDoesNotEnterReadProtocol() async {
        let state = MerchantCityTemplateHandoffFixtureState(), model = MerchantCityTemplateHandoffModel()
        model.activate(); let permit = model.generation
        model.deactivate()
        // A nil launch would report unavailable if stale work entered the open protocol.
        await model.open(nil, binding: state.binding, permit: permit)
        XCTAssertFalse(model.accepts(permit)); XCTAssertNil(model.issue); XCTAssertNil(model.opening)
        XCTAssertEqual(state.readCount, 0); XCTAssertEqual(state.reader.saveCount, 0)
    }
    func testQueuedOpenCannotCrossReactivationButFreshTapCanOpen() async throws {
        let state = MerchantCityTemplateHandoffFixtureState(), model = MerchantCityTemplateHandoffModel()
        model.activate(); let stale = model.generation
        model.deactivate(); model.activate()
        await model.open(.init(reader: state.reader), binding: state.binding, permit: stale)
        XCTAssertNil(model.opening); XCTAssertNil(model.issue); XCTAssertFalse(model.accepts(stale))
        let current = model.generation
        await model.open(.init(reader: state.reader), binding: state.binding, permit: current)
        let opening = try XCTUnwrap(model.opening)
        model.activate() // Duplicate appearance must retain the live presentation.
        XCTAssertEqual(model.opening?.id, opening.id)
        XCTAssertEqual(state.applyCount, 0); XCTAssertEqual(state.reader.saveCount, 0)
    }
    func testQueuedParentRecoveryCannotCrossExitAndReactivation() async throws {
        let state = MerchantCityTemplateHandoffFixtureState()
        let (model, opening, editor) = try await opened(state); try await save(editor)
        state.failRead = true
        await model.accept(editor, original: opening, binding: state.binding)
        XCTAssertTrue(model.recoveryNeeded)
        model.close(); let stale = model.generation; let reads = state.readCount
        model.deactivate(); model.activate(); state.failRead = false
        await model.recoverParent(binding: state.binding, permit: stale)
        XCTAssertEqual(state.readCount, reads); XCTAssertNil(state.snapshot)
        await model.recoverParent(binding: state.binding, permit: model.generation)
        XCTAssertEqual(state.readCount, reads + 1); XCTAssertNotNil(state.snapshot)
        XCTAssertEqual(state.applyCount, 0); XCTAssertEqual(state.reader.saveCount, 1)
    }

}

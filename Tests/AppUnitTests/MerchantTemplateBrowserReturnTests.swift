import XCTest
import SwiftUI
@testable import Questify

@MainActor final class MerchantTemplateBrowserReturnTests: XCTestCase {
    @MainActor private final class Reader: MerchantOperationsReading {
        let fixture = MerchantOperationsFixtureReader()
        var scope = UUID()
        var isConfigured = true
        var isAuthenticated = true
        var isOfflineExample: Bool { true }
        var calls: [Int] = []
        var fail = false
        var denied = false
        var suspend = false
        var pending: CheckedContinuation<MerchantTemplatePageRead, Error>?
        var ids = [71]
        func access() async throws -> MerchantOperationsAccess { try await fixture.access() }
        func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { try await fixture.document(destination) }
        func saveExample(_ draft: MerchantOperationsDraft) async throws { try await fixture.saveExample(draft) }
        func response() throws -> MerchantTemplatePageRead {
            let data = try JSONSerialization.data(withJSONObject: ["rows": ids.map { ["id": $0, "title": "Synthetic template"] }, "total": ids.count])
            return .init(page: try JSONDecoder().decode(MerchantTemplatePage.self, from: data),
                         access: try JSONDecoder().decode(MerchantOperationsAccess.self, from: Data(#"{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:project:manage"]}"#.utf8)))
        }
        func templatePage(page: Int) async throws -> MerchantTemplatePageRead {
            calls.append(page)
            if suspend { suspend = false; return try await withCheckedThrowingContinuation { pending = $0 } }
            if denied { throw MerchantOperationsFailure.accessDenied }
            if fail { throw APIError.httpStatus(503) }
            return try response()
        }
    }
    private func loaded(_ reader: Reader) async -> MerchantTemplateBrowserModel {
        let model = MerchantTemplateBrowserModel(reader: reader)
        model.appear(active: true); await model.loadAppearance(model.readID)
        return model
    }
    func testTaskBeforeAppearDoesNotReadAndAppearanceReadsOnlyOnce() async {
        let r = Reader(), m = MerchantTemplateBrowserModel(reader: r)
        await m.loadAppearance(nil); XCTAssertTrue(r.calls.isEmpty)
        m.appear(active: true); let id = m.readID
        await m.loadAppearance(id); await m.loadAppearance(id)
        m.appear(active: true); await m.loadAppearance(m.readID)
        XCTAssertEqual(r.calls, [1]); XCTAssertTrue(m.browser.canOpen)
    }
    func testNormalEditorPushSurvivesParentDisappearAndReturnFreshReadsOnce() async throws {
        let r = Reader(), m = await loaded(r)
        m.open(71, permit: m.permit); let editor = try XCTUnwrap(m.editor), binding = m.editorBinding(m.editor)
        m.disappear(); XCTAssertEqual(binding.wrappedValue, editor); XCTAssertEqual(r.calls, [1])
        r.ids = [72]; binding.wrappedValue = nil; m.appear(active: true)
        let id = m.readID; await m.loadAppearance(id); await m.loadAppearance(id)
        XCTAssertNil(m.editor); XCTAssertEqual(m.browser.rows.map(\.id), [72]); XCTAssertEqual(r.calls, [1, 1])
        XCTAssertEqual(r.fixture.saveCount, 0)
    }
    func testHiddenForegroundDoesNotReadOrDiscardTheExistingEditor() async throws {
        let r = Reader(), m = await loaded(r)
        m.open(nil, permit: m.permit); let editor = try XCTUnwrap(m.editor)
        m.disappear(); m.sceneChanged(active: false); m.sceneChanged(active: true)
        await m.loadAppearance(m.readID); XCTAssertNil(m.readID)
        XCTAssertEqual(m.editor, editor); XCTAssertEqual(r.calls, [1])
    }
    func testVisibleBackgroundResumeRequiresFreshReadAndOldQueuedButtonsCannotRun() async {
        let r = Reader(), m = await loaded(r), old = m.permit
        m.sceneChanged(active: false); await m.refresh(old); await m.more(old); m.open(71, permit: old)
        XCTAssertNil(m.editor); XCTAssertEqual(r.calls, [1])
        m.sceneChanged(active: true); await m.loadAppearance(m.readID)
        await m.refresh(old); m.open(71, permit: old)
        XCTAssertEqual(r.calls, [1, 1]); XCTAssertNil(m.editor)
    }
    func testOldNavigationBindingCannotClearNewOccurrenceForTheSameTemplate() async throws {
        let r = Reader(), m = await loaded(r)
        m.open(71, permit: m.permit); let a = try XCTUnwrap(m.editor), old = m.editorBinding(m.editor)
        old.wrappedValue = nil; m.open(71, permit: m.permit); let b = try XCTUnwrap(m.editor)
        XCTAssertNotEqual(a, b); XCTAssertEqual(Set([a, b]).count, 2)
        old.wrappedValue = nil; XCTAssertNil(old.wrappedValue); XCTAssertEqual(m.editor, b)
    }
    func testScopeReplacementRetiresNavigationAndQueuedOldReads() async {
        let r = Reader(), m = await loaded(r), old = m.permit
        m.open(71, permit: old); r.scope = UUID(); m.scopeChanged()
        XCTAssertNil(m.editor); await m.refresh(old); await m.more(old); m.open(71, permit: old)
        XCTAssertEqual(r.calls, [1]); await m.loadAppearance(m.readID); XCTAssertEqual(r.calls, [1, 1])
    }
    func testHiddenScopeReplacementDoesNotReopenUntilExplicitAppearance() async {
        let r = Reader(), m = await loaded(r)
        m.disappear(); r.scope = UUID(); m.scopeChanged(); m.sceneChanged(active: true)
        await m.loadAppearance(m.readID); XCTAssertEqual(r.calls, [1])
        m.appear(active: true); await m.loadAppearance(m.readID); XCTAssertEqual(r.calls, [1, 1])
    }
    func testFailureAndRetryUseExistingReadWithoutSaveOrOptimisticRows() async {
        let r = Reader(); r.fail = true; let m = await loaded(r)
        XCTAssertNotNil(m.browser.issue); XCTAssertFalse(m.browser.loaded)
        r.fail = false; await m.refresh(m.permit)
        XCTAssertNil(m.browser.issue); XCTAssertEqual(m.browser.rows.map(\.id), [71])
        XCTAssertEqual(r.calls, [1, 1]); XCTAssertEqual(r.fixture.saveCount, 0)
    }
    func testDeniedReadMissingRowSignedOutAndUnconfiguredCannotOpen() async {
        let r = Reader(); r.denied = true; let m = await loaded(r)
        m.open(nil, permit: m.permit); XCTAssertNil(m.editor)
        r.denied = false; await m.refresh(m.permit); m.open(999, permit: m.permit); XCTAssertNil(m.editor)
        r.isAuthenticated = false; await m.refresh(m.permit); m.open(71, permit: m.permit)
        r.isAuthenticated = true; r.isConfigured = false; await m.refresh(m.permit)
        XCTAssertNil(m.editor); XCTAssertEqual(r.calls, [1, 1])
    }
    func testLateOldReadCannotOverwriteNewScopeList() async throws {
        let r = Reader(), m = MerchantTemplateBrowserModel(reader: r)
        r.suspend = true; m.appear(active: true); let id = m.readID
        let old = Task { await m.loadAppearance(id) }
        while r.pending == nil { await Task.yield() }
        let continuation = try XCTUnwrap(r.pending), oldResponse = try r.response(); r.pending = nil
        m.disappear(); r.scope = UUID(); r.ids = [82]; m.scopeChanged(); m.appear(active: true)
        await m.loadAppearance(m.readID); continuation.resume(returning: oldResponse); await old.value
        XCTAssertEqual(m.browser.rows.map(\.id), [82]); XCTAssertFalse(m.browser.isBusy); XCTAssertEqual(r.calls, [1, 1])
    }
}

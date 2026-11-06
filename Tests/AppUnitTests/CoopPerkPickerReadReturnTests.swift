import XCTest
import SwiftUI
@testable import Questify

@MainActor final class CoopPerkPickerReadReturnTests: XCTestCase {
    @MainActor private final class Reader: CoopFlowReading {
        var session: CoopFlowSession? = try! .init(accountID: 42, epoch: 1, token: "synthetic-token")
        var calls: [CoopFlowRead] = []
        var fail = false, suspend = false
        var continuation: CheckedContinuation<CoopFlowJSON, Error>?
        var rows: CoopFlowJSON = .array([
            .object(["id": .id(7), "name": .string("Synthetic benefit"), "retailValue": .id(12), "quota": .id(4)]),
            .object(["id": .id(8), "name": .string("Another benefit"), "retailValue": .id(6), "quota": .id(2)])
        ])
        func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
            calls.append(resource)
            if suspend { suspend = false; return try await withCheckedThrowingContinuation { continuation = $0 } }
            if fail { throw APIError.httpStatus(503) }
            return rows
        }
        func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw APIError.invalidRequest }
    }
    private func loaded(_ reader: Reader) async -> CoopPerkPickerReadModel {
        let model = CoopPerkPickerReadModel(reader: reader, inviteID: 71)
        model.appear(active: true); await model.loadForAppearance(permit: model.permit)
        return model
    }
    func testReadFailureRetryUsesOnlyOriginalTemplateReadAndClearsFailure() async {
        let reader = Reader(); reader.fail = true
        let model = await loaded(reader)
        XCTAssertTrue(model.failed); XCTAssertTrue(model.rows.isEmpty); XCTAssertTrue(model.selected.isEmpty)
        reader.fail = false; await model.load(permit: model.permit)
        XCTAssertTrue(model.isCurrent); XCTAssertFalse(model.failed); XCTAssertEqual(model.rows.count, 2)
        XCTAssertEqual(reader.calls, [.templates, .templates])
    }
    func testPreviewReturnUsesActualAppearanceEntryAndKeepsSelectionWithoutRead() async throws {
        let reader = Reader(), model = await loaded(reader)
        model.selectionBinding(id: 7, permit: model.permit).wrappedValue = true
        model.openPreview(permit: model.permit)
        let preview = try XCTUnwrap(model.preview), binding = model.previewBinding()
        XCTAssertEqual(preview.inviteID, 71); XCTAssertEqual(preview.templateIDs, [7])
        model.disappear(); XCTAssertTrue(model.current(preview))
        binding.wrappedValue = nil
        model.appear(active: true); await model.loadForAppearance(permit: model.permit)
        XCTAssertNil(model.preview); XCTAssertEqual(model.selected, [7]); XCTAssertEqual(reader.calls, [.templates])
        XCTAssertFalse(model.current(preview)); XCTAssertNil(binding.wrappedValue)
    }
    func testOldSelectionAndPreviewBindingsCannotChangeNewRound() async throws {
        let reader = Reader(), model = await loaded(reader), permit = model.permit
        let selection = model.selectionBinding(id: 7, permit: permit)
        selection.wrappedValue = true; model.openPreview(permit: permit)
        let old = model.previewBinding()
        model.disappear(); old.wrappedValue = nil; model.appear(active: true)
        await model.loadForAppearance(permit: model.permit)
        model.selectionBinding(id: 8, permit: model.permit).wrappedValue = true
        model.openPreview(permit: model.permit); let current = try XCTUnwrap(model.preview)
        old.wrappedValue = nil; selection.wrappedValue = false
        XCTAssertTrue(model.showingPreview); XCTAssertEqual(model.preview?.id, current.id)
        XCTAssertEqual(model.selected, [7, 8]); XCTAssertNil(old.wrappedValue)
    }
    func testOrdinaryDepartureClearsChoicesAndReappearanceFreshReads() async {
        let reader = Reader(), model = await loaded(reader)
        model.selectionBinding(id: 7, permit: model.permit).wrappedValue = true
        model.disappear(); XCTAssertTrue(model.rows.isEmpty); XCTAssertTrue(model.selected.isEmpty)
        model.appear(active: true); await model.loadForAppearance(permit: model.permit)
        XCTAssertEqual(reader.calls, [.templates, .templates]); XCTAssertTrue(model.selected.isEmpty)
    }
    func testBackgroundRetiresPreviewAndHiddenForegroundDoesNotRead() async {
        let reader = Reader(), model = await loaded(reader)
        model.selectionBinding(id: 7, permit: model.permit).wrappedValue = true
        model.openPreview(permit: model.permit); model.disappear()
        model.sceneChanged(active: false); model.sceneChanged(active: true)
        await model.loadForAppearance(permit: model.permit)
        XCTAssertNil(model.preview); XCTAssertTrue(model.rows.isEmpty); XCTAssertEqual(reader.calls, [.templates])
        model.appear(active: true); await model.loadForAppearance(permit: model.permit)
        XCTAssertEqual(reader.calls, [.templates, .templates])
    }
    func testVisibleForegroundReloadsOnceAfterBackground() async {
        let reader = Reader(), model = await loaded(reader)
        let old = model.permit
        model.sceneChanged(active: false); model.sceneChanged(active: true)
        await model.loadForAppearance(permit: old); XCTAssertEqual(reader.calls.count, 1)
        await model.loadForAppearance(permit: model.permit)
        await model.loadForAppearance(permit: model.permit)
        XCTAssertEqual(reader.calls.count, 2); XCTAssertTrue(model.isCurrent)
    }
    func testSessionChangeRejectsOldSelectionAndLoadsNewReaderSession() async throws {
        let reader = Reader(), model = await loaded(reader)
        let old = model.selectionBinding(id: 7, permit: model.permit)
        reader.session = try .init(accountID: 43, epoch: 2, token: "synthetic-next-token")
        old.wrappedValue = true; XCTAssertTrue(model.selected.isEmpty)
        model.identityChanged(); await model.loadForAppearance(permit: model.permit)
        XCTAssertTrue(model.isCurrent); XCTAssertTrue(model.selected.isEmpty)
        XCTAssertEqual(reader.calls, [.templates, .templates])
    }
    func testSignedOutAndInvalidInviteCannotReadOrPreview() async {
        let reader = Reader(); reader.session = nil
        let model = await loaded(reader)
        XCTAssertTrue(reader.calls.isEmpty); XCTAssertFalse(model.isCurrent)
        model.openPreview(permit: model.permit); XCTAssertNil(model.preview)
        reader.session = try? .init(accountID: 42, epoch: 1, token: "synthetic-token")
        let invalid = CoopPerkPickerReadModel(reader: reader, inviteID: 0)
        invalid.appear(active: true); await invalid.loadForAppearance(permit: invalid.permit)
        XCTAssertTrue(reader.calls.isEmpty)
    }
    func testOriginalEligibilityAndAmbiguousIDsCannotCreatePreview() async {
        let reader = Reader()
        let eligible = reader.rows.rows![0]
        reader.rows = .array([eligible, eligible, .object(["id": .id(9), "retailValue": .id(0), "quota": .id(2)])])
        let model = await loaded(reader)
        XCTAssertEqual(model.rows.count, 2)
        model.selectionBinding(id: 7, permit: model.permit).wrappedValue = true
        model.selectionBinding(id: 9, permit: model.permit).wrappedValue = true
        model.openPreview(permit: model.permit)
        XCTAssertTrue(model.selected.isEmpty); XCTAssertNil(model.preview)
    }
    func testMalformedReadIsFailureButActualEmptyArrayIsEmptySuccess() async {
        let reader = Reader(); reader.rows = .object([:])
        let model = await loaded(reader)
        XCTAssertTrue(model.failed); XCTAssertFalse(model.isCurrent)
        reader.rows = .array([]); await model.load(permit: model.permit)
        XCTAssertTrue(model.isCurrent); XCTAssertFalse(model.failed); XCTAssertTrue(model.rows.isEmpty)
    }
    func testQueuedOldRetryCannotStartAfterDepartureAndReappearance() async {
        let reader = Reader(); reader.fail = true
        let model = await loaded(reader), old = model.permit
        model.disappear(); model.appear(active: true)
        await model.load(permit: old); XCTAssertEqual(reader.calls.count, 1)
        reader.fail = false; await model.loadForAppearance(permit: model.permit)
        XCTAssertEqual(reader.calls.count, 2); XCTAssertTrue(model.isCurrent)
    }
    func testLateReadCannotClearNewSessionLoadingOrReplaceRows() async throws {
        let reader = Reader(), model = CoopPerkPickerReadModel(reader: reader, inviteID: 71)
        model.appear(active: true); reader.suspend = true
        let old = Task { await model.loadForAppearance(permit: model.permit) }
        while reader.continuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(reader.continuation); reader.continuation = nil
        model.disappear(); reader.session = try .init(accountID: 44, epoch: 3, token: "synthetic-third-token")
        model.appear(active: true); reader.rows = .array([])
        await model.loadForAppearance(permit: model.permit)
        continuation.resume(returning: .array([.object(["id": .id(99), "retailValue": .id(12), "quota": .id(4)])]))
        await old.value
        XCTAssertTrue(model.isCurrent); XCTAssertFalse(model.loading); XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(reader.calls, [.templates, .templates])
    }
}


extension CoopPerkPickerReadReturnTests {
    func testPreviewNavigationHashUsesConcreteOccurrenceRatherThanSameSelectedIDs() async throws {
        let reader = Reader(), model = await loaded(reader)
        model.selectionBinding(id: 7, permit: model.permit).wrappedValue = true
        model.openPreview(permit: model.permit)
        let first = try XCTUnwrap(model.preview), binding = model.previewBinding()
        XCTAssertEqual(Set([first, first]).count, 1)
        model.disappear(); binding.wrappedValue = nil; model.appear(active: true)
        await model.loadForAppearance(permit: model.permit)
        model.openPreview(permit: model.permit)
        let second = try XCTUnwrap(model.preview)
        XCTAssertEqual(first.templateIDs, second.templateIDs)
        XCTAssertEqual(first.inviteID, second.inviteID)
        XCTAssertNotEqual(first, second); XCTAssertEqual(Set([first, second]).count, 2)
        XCTAssertNil(binding.wrappedValue); XCTAssertEqual(reader.calls, [.templates])
    }
}

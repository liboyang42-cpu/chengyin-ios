import XCTest
import UIKit
@testable import Questify

@MainActor final class TemplateAudioDocumentPickerAdapterTests: XCTestCase {
    private let selectedURL = URL(fileURLWithPath: "/synthetic-only/selected.mp3")
    private func metadata() throws -> TemplateAudioDocumentMetadata {
        var read = false
        return try TemplateAudioDocumentInspection.inspect(fileExtension: "mp3", reportedByteCount: 1) { _ in
            defer { read = true }
            return read ? Data() : Data([0])
        }
    }

    func testDefaultOffDoesNotCreatePickerOrInvokeInspector() async {
        let inspector = ControlledAudioDocumentInspector()
        let adapter = TemplateAudioDocumentPickerAdapter(inspector: inspector)
        XCTAssertFalse(adapter.selectionEnabled)
        XCTAssertThrowsError(try adapter.makePicker(request: .init(purpose: .narration)) { _ in XCTFail() }) {
            XCTAssertEqual($0 as? TemplateAudioDocumentFailure, .notConfigured)
        }
        let calls = await inspector.callCount
        XCTAssertEqual(calls, 0)
    }

    func testPickerAllowsOnlyOneDocumentAndHasNoAutomaticPresentation() throws {
        let adapter = TemplateAudioDocumentPickerAdapter(selectionEnabled: true)
        let picker = try adapter.makePicker(request: .init(purpose: .questionAudio)) { _ in }
        XCTAssertFalse(picker.allowsMultipleSelection)
        XCTAssertNil(picker.presentingViewController)
        XCTAssertTrue(picker.delegate === adapter)
        adapter.cancel()
        XCTAssertNil(picker.delegate)
    }

    func testMultipleOrEmptySelectionFailsWithoutInspectorAndKeepsExistingReferences() async throws {
        for urls in [[], [selectedURL, selectedURL]] as [[URL]] {
            let inspector = ControlledAudioDocumentInspector()
            let adapter = TemplateAudioDocumentPickerAdapter(selectionEnabled: true, inspector: inspector)
            let request = TemplateAudioDocumentRequest(purpose: .optionAudio(.a))
            let original = TemplateAuthoringDraft(title: "Keep exact references")
            var draft = original
            draft.questionAudio = "  existing-question  "
            draft.audioUrl = "  existing-narration  "
            draft.audioDuration = 23
            draft.questionOptionMediaJson = #"{"A":{"audio":" existing-option "}}"#
            let before = draft
            var results: [TemplateAudioDocumentSelectionResult] = []
            let picker = try adapter.makePicker(request: request) { results.append($0) }
            adapter.documentPicker(picker, didPickDocumentsAt: urls)
            XCTAssertEqual(results, [.failed(request, .invalidSelectionCount)])
            XCTAssertEqual(draft, before)
            let calls = await inspector.callCount
            XCTAssertEqual(calls, 0)
        }
    }

    func testRepeatedMakePickerRequiresExplicitCancellationWithoutDroppingFirstRequest() throws {
        let adapter = TemplateAudioDocumentPickerAdapter(selectionEnabled: true)
        let first = TemplateAudioDocumentRequest(purpose: .narration)
        var results: [TemplateAudioDocumentSelectionResult] = []
        let picker = try adapter.makePicker(request: first) { results.append($0) }
        XCTAssertThrowsError(try adapter.makePicker(request: .init(purpose: .questionAudio)) { _ in XCTFail() }) {
            XCTAssertEqual($0 as? TemplateAudioDocumentFailure, .selectionInProgress)
        }
        XCTAssertTrue(results.isEmpty)
        adapter.documentPickerWasCancelled(picker)
        XCTAssertEqual(results, [.cancelled(first)])
    }

    func testRepeatedCancelAndDelegateCancellationProduceOneResult() throws {
        let adapter = TemplateAudioDocumentPickerAdapter(selectionEnabled: true)
        let request = TemplateAudioDocumentRequest(purpose: .optionAudio(.d))
        var results: [TemplateAudioDocumentSelectionResult] = []
        let picker = try adapter.makePicker(request: request) { results.append($0) }
        adapter.cancel(); adapter.cancel(); adapter.documentPickerWasCancelled(picker)
        adapter.documentPicker(picker, didPickDocumentsAt: [selectedURL])
        XCTAssertEqual(results, [.cancelled(request)])
    }

    func testInspectionReturnsOnlyMetadataAndNeverMutatesReferences() async throws {
        let inspector = ControlledAudioDocumentInspector()
        let adapter = TemplateAudioDocumentPickerAdapter(selectionEnabled: true, inspector: inspector)
        let request = TemplateAudioDocumentRequest(purpose: .narration)
        let expected = try metadata()
        var draft = TemplateAuthoringDraft(title: "Keep references")
        draft.questionAudio = "existing-question"
        draft.audioUrl = "existing-narration"
        draft.audioDuration = 23
        draft.questionOptionMediaJson = #"{"B":{"audio":"existing-option"}}"#
        let before = draft
        var results: [TemplateAudioDocumentSelectionResult] = []
        let done = expectation(description: "Metadata only")
        let picker = try adapter.makePicker(request: request) { results.append($0); done.fulfill() }
        adapter.documentPicker(picker, didPickDocumentsAt: [selectedURL])
        await inspector.waitForCalls(1)
        await inspector.resolveFirst(.success(expected))
        await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(results, [.inspected(request, expected)])
        XCTAssertEqual(draft, before)
        XCTAssertNil(picker.delegate)
    }

    func testTypedFailureAndUnknownErrorDoNotLeakPaths() async throws {
        struct SyntheticFailure: Error {}
        for (error, expected) in [(TemplateAudioDocumentFailure.tooLarge as Error, TemplateAudioDocumentFailure.tooLarge),
                                  (SyntheticFailure() as Error, .unreadable)] {
            let inspector = ControlledAudioDocumentInspector()
            let adapter = TemplateAudioDocumentPickerAdapter(selectionEnabled: true, inspector: inspector)
            let request = TemplateAudioDocumentRequest(purpose: .questionAudio)
            var results: [TemplateAudioDocumentSelectionResult] = []
            let done = expectation(description: "Safe failure")
            let picker = try adapter.makePicker(request: request) { results.append($0); done.fulfill() }
            adapter.documentPicker(picker, didPickDocumentsAt: [selectedURL])
            await inspector.waitForCalls(1)
            await inspector.resolveFirst(.failure(error))
            await fulfillment(of: [done], timeout: 1)
            XCTAssertEqual(results, [.failed(request, expected)])
        }
    }

    func testInspectorCancellationMapsToCancelled() async throws {
        let inspector = ControlledAudioDocumentInspector()
        let adapter = TemplateAudioDocumentPickerAdapter(selectionEnabled: true, inspector: inspector)
        let request = TemplateAudioDocumentRequest(purpose: .narration)
        let done = expectation(description: "Cancelled")
        var results: [TemplateAudioDocumentSelectionResult] = []
        let picker = try adapter.makePicker(request: request) { results.append($0); done.fulfill() }
        adapter.documentPicker(picker, didPickDocumentsAt: [selectedURL])
        await inspector.waitForCalls(1)
        await inspector.resolveFirst(.failure(CancellationError()))
        await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(results, [.cancelled(request)])
    }

    func testDuplicateSelectionDelegateCallbackDoesNotStartSecondRead() async throws {
        let inspector = ControlledAudioDocumentInspector()
        let adapter = TemplateAudioDocumentPickerAdapter(selectionEnabled: true, inspector: inspector)
        let picker = try adapter.makePicker(request: .init(purpose: .questionAudio)) { _ in }
        adapter.documentPicker(picker, didPickDocumentsAt: [selectedURL])
        adapter.documentPicker(picker, didPickDocumentsAt: [selectedURL])
        await inspector.waitForCalls(1)
        let calls = await inspector.callCount
        XCTAssertEqual(calls, 1)
        adapter.cancel()
        await inspector.resolveFirst(.success(try metadata()))
    }

    func testLateOldSuccessAndFailureCannotCompleteReplacementPicker() async throws {
        for oldResult in [Result<TemplateAudioDocumentMetadata, Error>.success(try metadata()), .failure(TemplateAudioDocumentFailure.unreadable)] {
            let inspector = ControlledAudioDocumentInspector()
            let adapter = TemplateAudioDocumentPickerAdapter(selectionEnabled: true, inspector: inspector)
            let old = TemplateAudioDocumentRequest(purpose: .optionAudio(.b))
            var oldResults: [TemplateAudioDocumentSelectionResult] = []
            let oldPicker = try adapter.makePicker(request: old) { oldResults.append($0) }
            adapter.documentPicker(oldPicker, didPickDocumentsAt: [selectedURL])
            await inspector.waitForCalls(1)
            adapter.cancel()
            let new = TemplateAudioDocumentRequest(purpose: .optionAudio(.c))
            var newResults: [TemplateAudioDocumentSelectionResult] = []
            let done = expectation(description: "Current request completed")
            let newPicker = try adapter.makePicker(request: new) { newResults.append($0); done.fulfill() }
            adapter.documentPickerWasCancelled(oldPicker)
            adapter.documentPicker(oldPicker, didPickDocumentsAt: [selectedURL])
            adapter.documentPicker(newPicker, didPickDocumentsAt: [selectedURL])
            await inspector.waitForCalls(2)
            await inspector.resolveFirst(oldResult)
            let expected = try metadata()
            await inspector.resolveFirst(.success(expected))
            await fulfillment(of: [done], timeout: 1)
            XCTAssertEqual(oldResults, [.cancelled(old)])
            XCTAssertEqual(newResults, [.inspected(new, expected)])
        }
    }

    func testCompletionCanCreateNewRequestWithoutOldCleanupCancellingIt() throws {
        let adapter = TemplateAudioDocumentPickerAdapter(selectionEnabled: true)
        let new = TemplateAudioDocumentRequest(purpose: .narration)
        var replacement: UIDocumentPickerViewController?
        var results: [TemplateAudioDocumentSelectionResult] = []
        _ = try adapter.makePicker(request: .init(purpose: .questionAudio)) { _ in
            replacement = try? adapter.makePicker(request: new) { results.append($0) }
        }
        adapter.cancel()
        XCTAssertNotNil(replacement)
        XCTAssertTrue(results.isEmpty)
        adapter.cancel()
        XCTAssertEqual(results, [.cancelled(new)])
    }
}

private actor ControlledAudioDocumentInspector: TemplateAudioSelectedDocumentInspecting {
    private(set) var callCount = 0
    private var pending: [CheckedContinuation<TemplateAudioDocumentMetadata, Error>] = []
    private var waits: [(Int, CheckedContinuation<Void, Never>)] = []
    func inspect(selectedURL: URL) async throws -> TemplateAudioDocumentMetadata {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation); callCount += 1
            let ready = waits.filter { $0.0 <= callCount }
            waits.removeAll { $0.0 <= callCount }
            for item in ready { item.1.resume() }
        }
    }
    func waitForCalls(_ count: Int) async {
        if callCount >= count { return }
        await withCheckedContinuation { waits.append((count, $0)) }
    }
    func resolveFirst(_ result: Result<TemplateAudioDocumentMetadata, Error>) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(with: result)
    }
}

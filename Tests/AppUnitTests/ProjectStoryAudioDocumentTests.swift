import XCTest
import UIKit
@testable import Questify

@MainActor final class ProjectStoryAudioDocumentTests: XCTestCase {
    #if DEBUG
    private func audio() throws -> ProjectStorySelectedAudio {
        let session = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "audio-document-tests")
        return try ProjectStoryAudioSynthetic(session: session, currentSession: { session }).picked
    }
    #endif
    private actor HeldReader: ProjectStoryAudioSelectedDocumentReading {
        var calls = 0
        var pending: CheckedContinuation<ProjectStorySelectedAudio, Error>?
        func read(selectedURL: URL) async throws -> ProjectStorySelectedAudio {
            calls += 1; return try await withCheckedThrowingContinuation { pending = $0 }
        }
        func wait() async { for _ in 0..<1000 where pending == nil { await Task.yield() } }
        func finish(_ value: ProjectStorySelectedAudio) { let old = pending; pending = nil; old?.resume(returning: value) }
    }
    func testDefaultOffNeverPresentsOrReads() async {
        let reader = HeldReader(); var presentations = 0
        let picker = ProjectStoryAudioDocumentPicker(present: { _ in presentations += 1; return true }, dismiss: {}, reader: reader)
        do { _ = try await picker.select(); XCTFail() } catch { XCTAssertEqual(error as? TemplateAudioDocumentFailure, .notConfigured) }
        let reads = await reader.calls; XCTAssertEqual(reads, 0); XCTAssertEqual(presentations, 0)
    }
    func testOneDocumentAndCancelKeepNoCopiedBody() async throws {
        let reader = HeldReader(); var shown: UIDocumentPickerViewController?, dismissals = 0
        let picker = ProjectStoryAudioDocumentPicker(selectionAllowed: { true }, present: { shown = $0 as? UIDocumentPickerViewController; return true }, dismiss: { dismissals += 1 }, reader: reader)
        let task = Task { try await picker.select() }
        for _ in 0..<100 where shown == nil { await Task.yield() }
        let controller = try XCTUnwrap(shown); XCTAssertFalse(controller.allowsMultipleSelection)
        picker.documentPickerWasCancelled(controller); let value = try await task.value
        XCTAssertNil(value); let reads = await reader.calls; XCTAssertEqual(reads, 0); XCTAssertEqual(dismissals, 1)
        picker.documentPicker(controller, didPickDocumentsAt: [URL(fileURLWithPath: "/synthetic/late.mp3")])
        let laterReads = await reader.calls; XCTAssertEqual(laterReads, 0)
    }
    func testInvalidSelectionCountNeverStartsReader() async throws {
        for urls in [[], [URL(fileURLWithPath: "/synthetic/a.mp3"), URL(fileURLWithPath: "/synthetic/b.m4a")]] {
            let reader = HeldReader(); var shown: UIDocumentPickerViewController?
            let picker = ProjectStoryAudioDocumentPicker(selectionAllowed: { true }, present: { shown = $0 as? UIDocumentPickerViewController; return true }, dismiss: {}, reader: reader)
            let task = Task { try await picker.select() }
            for _ in 0..<100 where shown == nil { await Task.yield() }
            picker.documentPicker(try XCTUnwrap(shown), didPickDocumentsAt: urls)
            do { _ = try await task.value; XCTFail() } catch { XCTAssertEqual(error as? TemplateAudioDocumentFailure, .invalidSelectionCount) }
            let reads = await reader.calls; XCTAssertEqual(reads, 0)
        }
    }
    #if DEBUG
    func testDocumentSurfaceDismissalAfterSelectionDoesNotDiscardProviderRead() async throws {
        let reader = HeldReader(); var shown: UIDocumentPickerViewController?
        let picker = ProjectStoryAudioDocumentPicker(selectionAllowed: { true }, present: { shown = $0 as? UIDocumentPickerViewController; return true }, dismiss: {}, reader: reader)
        let task = Task { try await picker.select() }
        for _ in 0..<100 where shown == nil { await Task.yield() }
        let controller = try XCTUnwrap(shown), expected = try audio()
        picker.documentPicker(controller, didPickDocumentsAt: [URL(fileURLWithPath: "/synthetic/a.m4a")]); await reader.wait()
        picker.presentationControllerDidDismiss(UIPresentationController(presentedViewController: controller, presenting: nil))
        await reader.finish(expected); let selected = try await task.value
        XCTAssertEqual(selected, expected); let reads = await reader.calls; XCTAssertEqual(reads, 1)
    }
    #endif
    #if DEBUG
    func testParentCancellationAndLateOldReadCannotConsumeReplacement() async throws {
        let reader = HeldReader(); var shown: UIDocumentPickerViewController?
        let picker = ProjectStoryAudioDocumentPicker(selectionAllowed: { true }, present: { shown = $0 as? UIDocumentPickerViewController; return true }, dismiss: {}, reader: reader)
        let old = Task { try await picker.select() }
        for _ in 0..<100 where shown == nil { await Task.yield() }
        let oldController = try XCTUnwrap(shown)
        picker.documentPicker(oldController, didPickDocumentsAt: [URL(fileURLWithPath: "/synthetic/old.m4a")]); await reader.wait()
        picker.cancel(); let cancelled = try await old.value; XCTAssertNil(cancelled)
        shown = nil; let next = Task { try await picker.select() }
        for _ in 0..<100 where shown == nil { await Task.yield() }
        let nextController = try XCTUnwrap(shown); XCTAssertFalse(oldController === nextController)
        await reader.finish(try audio()); picker.documentPickerWasCancelled(oldController)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(nextController.delegate === picker)
        picker.documentPickerWasCancelled(nextController); let value = try await next.value; XCTAssertNil(value)
    }
    #endif
    #if DEBUG
    func testPermissionRevokedWhileProviderWaitsDropsSelectedBytes() async throws {
        let reader = HeldReader(); var allowed = true, shown: UIDocumentPickerViewController?
        let picker = ProjectStoryAudioDocumentPicker(selectionAllowed: { allowed }, present: { shown = $0 as? UIDocumentPickerViewController; return true }, dismiss: {}, reader: reader)
        let task = Task { try await picker.select() }
        for _ in 0..<100 where shown == nil { await Task.yield() }
        picker.documentPicker(try XCTUnwrap(shown), didPickDocumentsAt: [URL(fileURLWithPath: "/synthetic/a.m4a")]); await reader.wait()
        allowed = false; await reader.finish(try audio()); let value = try await task.value; XCTAssertNil(value)
    }
    #endif
    private struct MovedCoordination: TemplateAudioDocumentReadCoordinating {
        let moved: URL
        func coordinateRead(selectedURL: URL, accessor: @escaping TemplateAudioDocumentReadAccessor) async throws -> TemplateAudioDocumentMetadata {
            try accessor(moved, { try Task.checkCancellation() })
        }
    }
    private func temporaryDocument(_ name: String, bytes: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name); try bytes.write(to: url); return url
    }
    func testActualReaderUsesCoordinatedProviderURLAndExactBytesAndName() async throws {
        let bytes = Data([0, 1, 2, 3, 255]), moved = try temporaryDocument("Moved e\u{301}.aac", bytes: bytes)
        let reader = AppleProjectStoryAudioSelectedDocumentReader(coordination: MovedCoordination(moved: moved))
        let selected = try await reader.read(selectedURL: URL(fileURLWithPath: "/does-not-exist/original.mp3"))
        XCTAssertEqual(selected.bytes, bytes); XCTAssertEqual(Array(selected.filename.utf8), Array(moved.lastPathComponent.utf8))
        XCTAssertEqual(selected.metadata.format, .aac); XCTAssertEqual(selected.metadata.evidence, .extensionAndByteCountOnly)
    }
    func testActualReaderRejectsSymlinkDirectoryEmptyAndTooLargeFiles() async throws {
        let target = try temporaryDocument("target.mp3", bytes: Data([1, 2]))
        let link = target.deletingLastPathComponent().appendingPathComponent("link.mp3")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let directory = target.deletingLastPathComponent().appendingPathComponent("directory.mp3")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let empty = try temporaryDocument("empty.aac", bytes: Data())
        let large = try temporaryDocument("large.m4a", bytes: Data(repeating: 1, count: TemplateAudioDocumentInspection.maximumBytes + 1))
        for url in [link, directory, empty, large] {
            let reader = AppleProjectStoryAudioSelectedDocumentReader(coordination: MovedCoordination(moved: url))
            do { _ = try await reader.read(selectedURL: url); XCTFail("Expected rejection") } catch {}
        }
    }
}

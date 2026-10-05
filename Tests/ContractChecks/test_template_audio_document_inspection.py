"""Offline source assertions. These do not compile or execute the Swift/Apple adapter."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'Core/TemplateAudioDocumentInspection.swift'
APP = ROOT / 'App/TemplateAudioDocumentPickerAdapter.swift'
COORDINATION = ROOT / 'App/TemplateAudioDocumentReadCoordination.swift'


class TemplateAudioDocumentInspectionChecks(unittest.TestCase):
    def test_source_formats_cap_and_bounded_measurement_are_explicit(self):
        code = CORE.read_text()
        for text in ['case mp3, m4a, aac', 'maximumBytes = 10 * 1024 * 1024',
                     'chunkBytes = 64 * 1024', 'maximumBytes - total + 1',
                     'chunk.count <= requested', 'total <= maximumBytes', 'total > 0',
                     'total != reportedByteCount', 'try checkCancellation()']:
            self.assertIn(text, code)
        self.assertNotIn('Data(contentsOf:', code + APP.read_text())
        self.assertNotIn('readToEnd', code + APP.read_text())

    def test_metadata_has_no_payload_path_reference_or_false_decode_claim(self):
        metadata = CORE.read_text().split('public struct TemplateAudioDocumentMetadata:')[1].split('\npublic enum TemplateAudioDocumentSelectionResult:')[0]
        self.assertIn('case extensionAndByteCountOnly', metadata)
        self.assertIn('fileprivate init(', metadata)
        for text in ['Data', 'URL', 'filename', 'path', 'duration', 'Codable']:
            self.assertNotIn(text, metadata)
        result = CORE.read_text().split('public enum TemplateAudioDocumentSelectionResult:')[1].split('\n///')[0]
        self.assertIn('case inspected(', result)
        for text in ['uploaded', 'attached', 'imported', 'URL', 'Data']:
            self.assertNotIn(text, result)

    def test_default_off_no_grants_or_side_effecting_dependencies(self):
        code = APP.read_text()
        self.assertIn('selectionEnabled: Bool = false', code)
        self.assertIn('guard selectionEnabled else', code)
        self.assertIn('guard activeRequest == nil else', code)
        self.assertLess(code.index('guard selectionEnabled else'), code.index('UIDocumentPickerViewController(forOpeningContentTypes:'))
        for text in ['URLSession', 'URLRequest', 'HTTPTransport', 'uploadOSS', 'AVAudioRecorder',
                     'AVAudioSession', 'requestRecordPermission', 'requestAccess', 'PhotosPicker',
                     'Merchant', 'Keychain', 'UserDefaults', 'bookmarkData', 'setChoiceOptionMedia',
                     '.questionAudio =', '.audioUrl =', '.audioDuration =', 'present(']:
            self.assertNotIn(text, code)

    def test_adapter_is_unmounted_from_existing_composition(self):
        for source in (ROOT / 'App').glob('*.swift'):
            if source != APP:
                self.assertNotIn('TemplateAudioDocumentPickerAdapter', source.read_text(), source.name)

    def test_exact_single_document_and_lifecycle_fences(self):
        code = APP.read_text()
        for text in ['picker.allowsMultipleSelection = false', 'urls.count == 1',
                     'controller === activePicker', 'inspectionTask == nil', 'self.generation == run',
                     'self.activeRequest == request', 'generation = UUID()', 'inspectionTask?.cancel()',
                     'activePicker?.delegate = nil', 'completion = nil', 'callback?(result)']:
            self.assertIn(text, code)
        finish = code.split('private func finish(')[1]
        self.assertLess(finish.index('completion = nil'), finish.index('callback?(result)'))
        self.assertLess(finish.index('inspectionTask = nil'), finish.index('callback?(result)'))

    def test_scoped_stream_releases_resources_and_refuses_nonregular_files(self):
        code = APP.read_text() + COORDINATION.read_text()
        for text in ['queue.qualityOfService = .userInitiated', 'withTaskCancellationHandler',
                     'guard coordinatedURL.isFileURL', 'startAccessingSecurityScopedResource()',
                     'stopAccessingSecurityScopedResource()',
                     'O_RDONLY | O_NOFOLLOW | O_NONBLOCK', 'fstat(handle.fileDescriptor', 'mode_t(S_IFREG)',
                     'defer { try? handle.close() }', 'handle.read(upToCount: $0)',
                     'initial.st_size == final.st_size', 'initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec']:
            self.assertIn(text, code)

    def test_external_document_open_is_inside_coordinated_accessor_and_uses_updated_url(self):
        code = COORDINATION.read_text()
        app = APP.read_text()
        for text in ['NSFileCoordinator(filePresenter: nil)', 'NSFileAccessIntent.readingIntent(with: url, options: [])',
                     'coordinator.coordinate(with: [intent], queue: queue)', 'accessor(intent.url, error)',
                     'if let error', 'throw TemplateAudioDocumentFailure.coordinationFailed',
                     'let metadata = try accessor(coordinatedURL, { try self.checkCancellation() })']:
            self.assertIn(text, code)
        self.assertLess(code.index('if let error'), code.index('let metadata = try accessor(coordinatedURL'))
        self.assertIn('coordination.coordinateRead(selectedURL: selectedURL)', app)
        self.assertIn('Self.inspectCoordinated(coordinatedURL, checkCancellation: checkCancellation)', app)
        self.assertIn('coordinatedURL.withUnsafeFileSystemRepresentation', app)
        self.assertNotIn('selectedURL.withUnsafeFileSystemRepresentation', app)
        self.assertNotIn('FileHandle(forReadingFrom: selectedURL)', app)

    def test_pending_cancel_and_active_read_keep_one_shot_delivery_and_scope_ownership(self):
        code = COORDINATION.read_text()
        for text in ['private let lock = NSLock()', 'cancelled = true; settled = true',
                     'let scope = reading ? nil : scope', 'if !reading { self.scope = nil }',
                     'driver?.cancel()', 'continuation?.resume(throwing: CancellationError())',
                     'guard !settled, !reading else', 'continuation?.resume(with: result)',
                     'scope?.close()', 'if shouldStop { scoping.stop(url) }']:
            self.assertIn(text, code)
        registration = code.split('private func register(')[1].split('private func access(')[0]
        self.assertLess(registration.index('lock.lock()'), registration.index('driver.coordinateRead('))
        self.assertLess(registration.index('driver.coordinateRead('), registration.rindex('lock.unlock()'))
        for forbidden in ['removeItem', 'copyItem', 'moveItem', 'bookmarkData', 'UserDefaults', 'URLSession']:
            self.assertNotIn(forbidden, APP.read_text() + code)

    def test_authored_coordination_tests_cover_failure_pending_cancel_and_late_accessor(self):
        tests = (ROOT / 'Tests/AppUnitTests/TemplateAudioDocumentReadCoordinationTests.swift').read_text()
        self.assertEqual(tests.count('    func test'), 11)
        for name in ['testProviderSuppliedURLIsUsedInsteadOfOriginalSelection',
                     'testCoordinationFailureDoesNotInvokeAccessorAndBalancesScope',
                     'testCancellationWhileProviderIsPendingReturnsWithoutAccessorCallback',
                     'testLateSuccessAndFailureAfterPendingCancelNeverOpenStream',
                     'testCancelDuringAccessorKeepsScopeUntilReadCleanupThenDropsResult',
                     'testDuplicateProviderCallbackDoesNotReadTwiceOrResumeTwice']:
            self.assertIn(name, tests)

    def test_authored_swift_boundary_and_lifecycle_vectors_are_present(self):
        core = (ROOT / 'Tests/CoreTests/TemplateAudioDocumentInspectionTests.swift').read_text()
        app = (ROOT / 'Tests/AppUnitTests/TemplateAudioDocumentPickerAdapterTests.swift').read_text()
        self.assertEqual(core.count('    func test'), 13)
        self.assertEqual(app.count('    func test'), 11)
        for text in ['testUnknownAndDishonestMetadataCannotBypassMeasuredCap',
                     'testMetadataMismatchRejectsChangingDocument', 'testShortReadsContinueUntilEOF',
                     'testInspectionIsExplicitlyNotAudioDecodeOrAttachmentEvidence']:
            self.assertIn(text, core)
        for text in ['testDefaultOffDoesNotCreatePickerOrInvokeInspector',
                     'testLateOldSuccessAndFailureCannotCompleteReplacementPicker',
                     'testCompletionCanCreateNewRequestWithoutOldCleanupCancellingIt']:
            self.assertIn(text, app)





if __name__ == '__main__':
    unittest.main()

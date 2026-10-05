import io
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock
from tools import ui_failure_evidence as evidence
from tools import export_ui_evidence as exporter


def packet():
    return {'version': 1, 'fixture': 'registration-waitlist', 'sourceTruncated': False,
            'rows': [{'type': 'StaticText', 'knownStrings': ['订单号', 'OFFLINE-WAITLIST-9417']}]}

class UIFailureEvidenceTests(unittest.TestCase):
    def test_valid_projection(self):
        self.assertEqual(evidence.validate(json.dumps(packet()).encode()), packet())

    def test_raw_strings_and_unexpected_fields_fail_closed(self):
        for value in ['secret', 'user@example.com', 'https://private.example', 'Bearer token']:
            item = packet(); item['rows'][0]['knownStrings'].append(value)
            self.assertIsNone(evidence.validate(json.dumps(item).encode()))
        item = packet(); item['rawAX'] = 'secret'
        self.assertIsNone(evidence.validate(json.dumps(item).encode()))

    def test_malformed_and_oversized_packets(self):
        for raw in [b'{}', b'null', b'[]', b'{', b'x' * 32769]:
            self.assertIsNone(evidence.validate(raw))
        item = packet(); item['rows'] *= 129
        self.assertIsNone(evidence.validate(json.dumps(item).encode()))

    def test_bounded_atomic_records_survive_without_result_bundle(self):
        with tempfile.TemporaryDirectory() as root:
            sink = evidence.EvidenceStream(root)
            for _ in range(20):
                sink.accept(evidence.PREFIX + json.dumps(packet()).encode())
            saved = json.loads((pathlib.Path(root) / 'failure-ax.json').read_text())
            self.assertEqual(len(saved['records']), 8)
            self.assertFalse(saved['complete'])
            self.assertLess((pathlib.Path(root) / 'failure-ax.json').stat().st_size, 2 * 1024 * 1024)
            self.assertEqual(list(pathlib.Path(root).glob('*.tmp')), [])

    def test_real_pipe_is_persisted_before_process_termination(self):
        with tempfile.TemporaryDirectory() as root:
            sink = evidence.EvidenceStream(root)
            process = subprocess.Popen(['python3', '-c', 'print(' + repr((evidence.PREFIX + json.dumps(packet()).encode()).decode()) + ')'], stdout=subprocess.PIPE)
            stdout = mock.Mock(); stdout.buffer = io.BytesIO()
            with mock.patch.object(evidence.sys, 'stdout', stdout):
                sink.start(process.stdout); process.wait(timeout=5); sink.finish(124)
            saved = json.loads((pathlib.Path(root) / 'failure-ax.json').read_text())
            self.assertEqual(saved['exit_code'], 124)
            self.assertEqual(len(saved['records']), 1)
            process.stdout.close()

    def test_marker_in_arbitrary_log_not_accepted(self):
        with tempfile.TemporaryDirectory() as root:
            sink = evidence.EvidenceStream(root)
            sink.accept(b'raw log ' + evidence.PREFIX + json.dumps(packet()).encode())
            self.assertEqual(sink.records, [])

    def test_no_bundle_still_has_status_and_never_calls_simulator(self):
        with tempfile.TemporaryDirectory() as root, mock.patch.object(exporter.subprocess, 'Popen') as run:
            status = exporter.export(root)
            run.assert_not_called()
            self.assertEqual(status['export'], 'not-finalized')
            self.assertFalse(status['test_success_claimed'])
            self.assertTrue((pathlib.Path(root) / 'questify-ui-evidence/export-status.json').is_file())

    def test_export_timeout_still_has_status_and_preserves_bounded_images(self):
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            (root/'questify-ui-results.xcresult').mkdir()
            (root/'questify-ui-results.xcresult/Info.plist').touch()
            output = root/'questify-ui-attachments'; output.mkdir()
            (output/'synthetic.png').write_bytes(b'fixture')
            (output/'raw.txt').write_text('SECRET')
            process = mock.Mock(pid=123)
            process.wait.side_effect = [subprocess.TimeoutExpired('xcrun', 35), 0, 0]
            with mock.patch.object(exporter.subprocess, 'Popen', return_value=process) as run, mock.patch.object(exporter.os, 'killpg') as kill:
                status = exporter.export(root)
            self.assertTrue(run.call_args.kwargs['start_new_session'])
            self.assertEqual(process.wait.call_args_list, [mock.call(timeout=35), mock.call(timeout=5), mock.call(timeout=5)])
            self.assertEqual(kill.call_args_list, [mock.call(123, exporter.signal.SIGTERM), mock.call(123, exporter.signal.SIGKILL)])
            self.assertEqual(status['export'], 'timeout')
            self.assertEqual(status['retained_files'], 1)
            self.assertFalse((output/'raw.txt').exists())
            self.assertNotIn('SECRET', (root/'questify-ui-evidence/export-status.json').read_text())

    def test_export_bytes_and_file_caps(self):
        with tempfile.TemporaryDirectory() as root:
            output = pathlib.Path(root)/'questify-ui-attachments'; output.mkdir()
            with (output/'large.png').open('wb') as f: f.truncate(25*1024*1024)
            for index in range(130): (output/f'{index:03}.png').write_bytes(b'fixture')
            status = exporter.export(root)
            self.assertEqual(status['retained_files'], 128)
            self.assertFalse((output/'large.png').exists())

    def test_workflow_keeps_failure_gate_and_same_deadline(self):
        root = pathlib.Path(__file__).resolve().parents[2]
        workflow = (root/'.github/workflows/native-ios.yml').read_text()
        self.assertIn('--deadline-seconds 1800', workflow)
        self.assertIn('timeout-minutes: 37', workflow)
        self.assertIn('Retain bounded UI failure evidence even without finalized results\n        if: always()', workflow)
        self.assertNotIn('continue-on-error', workflow)
        helper = (root/'Tests/AppUITests/FailureScreenshot.swift').read_text()
        self.assertLess(helper.index('emitRegistrationFailureEvidence(app)'), helper.index('app.screenshot()'))
        self.assertIn('--uitesting-registration-fixture', helper)

    def test_persistence_errors_do_not_stop_draining(self):
        with tempfile.TemporaryDirectory() as root:
            sink = evidence.EvidenceStream(root)
            stream = io.BytesIO((evidence.PREFIX + json.dumps(packet()).encode() + b'\n') * 2 + b'after failure\n')
            stdout = mock.Mock(); stdout.buffer = io.BytesIO()
            with mock.patch.object(sink, '_write', side_effect=OSError('secret')), mock.patch.object(evidence.sys, 'stdout', stdout), mock.patch.object(evidence.sys, 'stderr', io.StringIO()):
                sink.start(stream); sink.finish(65)
            self.assertTrue(sink.persistence_failed)
            self.assertTrue(stdout.buffer.getvalue().endswith(b'after failure\n'))
            self.assertEqual(sink.code, 65)

    def test_symlink_directories_rejected_without_modifying_target(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as other:
            root = pathlib.Path(root); other = pathlib.Path(other)
            sentinel = other/'raw.txt'; sentinel.write_text('unchanged')
            (root/'questify-ui-attachments').symlink_to(other, target_is_directory=True)
            with self.assertRaises(ValueError): exporter.export(root)
            with self.assertRaises(ValueError): evidence.EvidenceStream(root/'questify-ui-attachments')
            self.assertEqual(sentinel.read_text(), 'unchanged')

    def test_status_symlink_is_rejected_without_modification(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as other:
            root = pathlib.Path(root); sentinel = pathlib.Path(other)/'sentinel'
            sentinel.write_text('unchanged')
            directory = root/'questify-ui-evidence'; directory.mkdir()
            (directory/'export-status.json').symlink_to(sentinel)
            with self.assertRaises(ValueError): exporter.export(root)
            self.assertEqual(sentinel.read_text(), 'unchanged')

    def test_unconfirmed_termination_still_writes_honest_status(self):
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            bundle = root/'questify-ui-results.xcresult'; bundle.mkdir(); (bundle/'Info.plist').touch()
            process = mock.Mock(pid=123)
            process.wait.side_effect = subprocess.TimeoutExpired('xcrun', 5)
            with mock.patch.object(exporter.subprocess, 'Popen', return_value=process), mock.patch.object(exporter.os, 'killpg'):
                status = exporter.export(root)
            self.assertEqual(status['export'], 'timeout')
            self.assertIs(status['termination_confirmed'], False)
            self.assertEqual(json.loads((root/'questify-ui-evidence/export-status.json').read_text()), status)

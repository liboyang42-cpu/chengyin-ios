import base64
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from tools import export_current_ui_audit as audit


class ExportCurrentUIAuditTests(unittest.TestCase):
    method = 'QuestifyUITests/ModuleFlowTests/testProfileOrderReadbackAndBack'
    image = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6SAAAAABJRU5ErkJggg==')

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.output = Path(temporary.name).resolve() / 'current-native'; self.output.mkdir()
        self.bundle = self.output / 'ui.xcresult'; self.bundle.mkdir()
        (self.bundle / 'Info.plist').write_text('synthetic result marker')
        self.identity = {'sha': 'a' * 40, 'tree': 'b' * 40, 'run_id': '123', 'attempt': '1'}
        self.plan = {'scope': 'full-current-regression', 'identity': self.identity}
        self.receipt = {'identity': self.identity, 'plan_sha256': audit.n.control.digest(audit.n.control.encode(self.plan)),
                        'role': 'ui', 'index': 0, 'actual': [{'method': self.method}],
                        'toolchain': {'developer': '/Applications/Xcode.app/Contents/Developer'}}
        audit.n.write_json(self.output / 'receipt.json', self.receipt)
        self.commands = [{'stem': 'native-test', 'argv': ['xcodebuild', '-resultBundlePath', str(self.bundle)]}]
        audit.n.write_json(self.output / 'commands.json', self.commands)
        self.packet = self.output.parent / 'current-ui-audit-evidence'

    def probe(self, argv, root, deadline, stage, developer, capture_help=False):
        if argv[-1] == 'version': return 'OK', b'xcresulttool version 24757, schema version: 0.1.0'
        if 'help' in argv: return 'OK', b'--path --output-path --test-id'
        folder = Path(argv[argv.index('--output-path') + 1])
        names = {
            'QuestifyUITests/ModuleFlowTests/testProfileOrderReadbackAndBack': ['Order detail – synthetic data'],
            'QuestifyUITests/HomeFeedFlowTests/testEmptyStateIsNotAnError': ['Home feed known empty state – synthetic fixture'],
            'QuestifyUITests/TicketWalletFlowTests/testWalletDetailEntitlementsBackAndReopenNeverOffersCodeOrPayment': [
                'Ticket wallet initial content – synthetic fixture', 'Ticket detail entitlements – synthetic fixture'],
        }[self.method]
        names = getattr(self, 'attachment_names', names)
        attachments = []
        for index, name in enumerate(names + ['Unrequested automatic screenshot']):
            filename = str(index) + '.png'
            data = self.image if getattr(self, 'same_image_bytes', False) else self.image + bytes([index])
            (folder / filename).write_bytes(data)
            attachments.append({'exportedFileName': filename, 'suggestedHumanReadableName': name})
        audit.n.write_json(folder / 'manifest.json', [{'testIdentifier': self.method, 'attachments': attachments}])
        return 'OK', b''

    def export_fixture(self):
        with patch.object(audit.n, 'reparse_actual_result', return_value=self.receipt), \
                patch.object(audit.n, 'screenshot_probe_command', side_effect=self.probe), \
                patch.object(audit.n.control, 'source_identity', return_value=self.identity), \
                contextlib.redirect_stdout(io.StringIO()) as captured:
            self.export_stdout = captured
            audit.export(self.plan, self.output)
        return captured.getvalue()

    def testForeignSourceOrRunIdentityIsRejectedBeforeExport(self):
        for key in ('sha', 'tree', 'run_id', 'attempt'):
            with self.subTest(key=key):
                foreign = dict(self.receipt, identity=dict(self.identity, **{key: 'foreign'}))
                audit.n.write_json(self.output / 'receipt.json', foreign)
                with patch.object(audit.n, 'screenshot_probe_command') as probe:
                    with self.assertRaisesRegex(ValueError, 'Foreign current result provenance'):
                        audit.export(self.plan, self.output)
                    probe.assert_not_called()
                self.assertFalse(self.packet.exists())

    def testForeignResultBundleIsRejectedBeforeExport(self):
        self.commands[0]['argv'][-1] = str(self.output / 'foreign.xcresult')
        audit.n.write_json(self.output / 'commands.json', self.commands)
        with self.assertRaisesRegex(ValueError, 'Wrong or unfinished result bundle'):
            self.export_fixture()
        self.assertFalse(self.packet.exists())

    def testExactAttachmentNamesAreSelectedAndReceiptIsUnchanged(self):
        original = (self.output / 'receipt.json').read_bytes()
        for clock, deadlines in (([100, 101, 102], [116, 117, 160]),
                                 ([100, 149, 149], [160, 160, 160])):
            with self.subTest(clock=clock):
                if self.packet.exists():
                    for path in self.packet.iterdir(): path.unlink()
                    self.packet.rmdir()
                with patch.object(self, 'probe', side_effect=self.probe) as probe, \
                        patch.object(audit.time, 'monotonic', side_effect=clock):
                    self.export_fixture()
                self.assertEqual([call.args[2] for call in probe.call_args_list], deadlines)
        report = audit.n.read_json(self.packet / 'audit-index.json')
        self.assertEqual(report['status'], 'COMPLETE')
        self.assertEqual(report['probes'], {
            'version': {'status': 'OK', 'output_bytes': len(b'xcresulttool version 24757, schema version: 0.1.0')},
            'attachments_help': {'status': 'OK', 'output_bytes': len(b'--path --output-path --test-id')}})
        expected = {'Order detail – synthetic data'}
        self.assertEqual({item['attachment'] for item in report['files']}, expected)
        self.assertEqual(len(report['files']), 1)
        for item in report['files']:
            self.assertEqual(audit.n.digest(self.packet / item['path']), item['sha256'])
        self.assertEqual((self.output / 'receipt.json').read_bytes(), original)

    def testBothHelperAttachmentsExportWithHashesAndUnchangedReceipt(self):
        self.method = 'QuestifyUITests/TicketWalletFlowTests/testWalletDetailEntitlementsBackAndReopenNeverOffersCodeOrPayment'
        self.receipt['actual'] = [{'method': self.method}]
        audit.n.write_json(self.output / 'receipt.json', self.receipt)
        original = (self.output / 'receipt.json').read_bytes()
        self.export_fixture()
        report = audit.n.read_json(self.packet / 'audit-index.json')
        self.assertEqual(report['status'], 'COMPLETE')
        self.assertEqual({item['attachment'] for item in report['files']}, {
            'Ticket wallet initial content – synthetic fixture', 'Ticket detail entitlements – synthetic fixture'})
        self.assertEqual(len(report['files']), 2)
        for item in report['files']:
            self.assertEqual(audit.n.digest(self.packet / item['path']), item['sha256'])
        self.assertEqual((self.output / 'receipt.json').read_bytes(), original)

    def testStdoutChunksRebuildBothOriginalImages(self):
        self.method = 'QuestifyUITests/TicketWalletFlowTests/testWalletDetailEntitlementsBackAndReopenNeverOffersCodeOrPayment'
        self.receipt['actual'] = [{'method': self.method}]
        audit.n.write_json(self.output / 'receipt.json', self.receipt)
        self.image += b'synthetic chunk boundary' * 1500
        lines = self.export_fixture().splitlines()
        report = audit.n.read_json(self.packet / 'audit-index.json')
        self.assertEqual(json.loads(lines[0].removeprefix('QUESTIFY_UI_AUDIT_INDEX_V1 ')), report)
        chunks = {}
        for line in lines[1:-1]:
            self.assertLessEqual(len(line), 16000)
            self.assertTrue(line.startswith('QUESTIFY_UI_AUDIT_IMAGE_V1 '))
            row = json.loads(line.removeprefix('QUESTIFY_UI_AUDIT_IMAGE_V1 '))
            chunks.setdefault(row['sha256'], []).append(row)
        self.assertEqual(set(chunks), {item['sha256'] for item in report['files']})
        self.assertEqual(len(report['files']), 2)
        for item in report['files']:
            rows = chunks[item['sha256']]
            self.assertGreater(len(rows), 1)
            self.assertEqual([row['chunkIndex'] for row in rows], list(range(rows[0]['total'])))
            self.assertTrue(all(row['total'] == len(rows) for row in rows))
            data = base64.b64decode(''.join(row['base64'] for row in rows), validate=True)
            self.assertEqual(data, (self.packet / item['path']).read_bytes())
            self.assertEqual(audit.n.control.digest(data), item['sha256'])
        self.assertEqual(json.loads(lines[-1].removeprefix('QUESTIFY_UI_AUDIT_COMPLETE_V1 ')), {
            'identity': self.identity, 'index': 0, 'files': 2})

    def testCorruptionAndFailedExportNeverEmitComplete(self):
        self.export_fixture()
        report = audit.n.read_json(self.packet / 'audit-index.json')
        (self.packet / report['files'][0]['path']).write_bytes(b'changed')
        with contextlib.redirect_stdout(io.StringIO()) as captured:
            with self.assertRaisesRegex(ValueError, 'Image bytes changed'):
                audit.emit_stdout_images(self.packet, report)
        self.assertNotIn('QUESTIFY_UI_AUDIT_COMPLETE_V1 ', captured.getvalue())
        for path in self.packet.iterdir(): path.unlink()
        self.packet.rmdir()
        original_probe = self.probe
        for phase, status, payload, message in (
                ('version', 'EXPORT_FAILED', b'', 'Unknown xcresulttool'),
                ('version', 'TIME_LIMIT', b'xcresulttool version 24757', 'Unknown xcresulttool'),
                ('attachments_help', 'EXPORT_FAILED', b'--path --output-path --test-id', 'Unsupported attachment exporter')):
            with self.subTest(phase=phase, status=status):
                def failed_probe(argv, *args, **kwargs):
                    if (phase == 'version' and argv[-1] == 'version') or (phase == 'attachments_help' and 'help' in argv):
                        return status, payload
                    return original_probe(argv, *args, **kwargs)
                with patch.object(self, 'probe', side_effect=failed_probe), \
                        patch.object(audit, 'emit_stdout_images') as emit:
                    with self.assertRaisesRegex(ValueError, message):
                        self.export_fixture()
                emit.assert_not_called()
                report = audit.n.read_json(self.packet / 'audit-index.json')
                self.assertEqual(report['status'], 'INCOMPLETE')
                self.assertEqual(report['probes'][phase], {'status': status, 'output_bytes': len(payload)})
                self.assertEqual(report['methods'], [])
                self.assertNotIn('QUESTIFY_UI_AUDIT_COMPLETE_V1 ', self.export_stdout.getvalue())
                for path in self.packet.iterdir(): path.unlink()
                self.packet.rmdir()

    def testExactNameAndFilenameExtensionsKeepCanonicalLabel(self):
        label = 'Order detail – synthetic data'
        uuid = 'C52033D6-9B99-4918-891E-3575FBC6E417'
        for suffix in ('', '.png', '.jpg', '.jpeg', '_0_' + uuid + '.png',
                       '_1_' + uuid.lower() + '.jpg', '_23_' + uuid + '.jpeg'):
            with self.subTest(suffix=suffix):
                self.attachment_names = [label + suffix]
                self.export_fixture()
                report = audit.n.read_json(self.packet / 'audit-index.json')
                self.assertEqual(report['status'], 'COMPLETE')
                self.assertEqual([item['attachment'] for item in report['files']], [label])
                for path in self.packet.iterdir(): path.unlink()
                self.packet.rmdir()

        self.method = 'QuestifyUITests/HomeFeedFlowTests/testEmptyStateIsNotAnError'
        self.receipt['actual'] = [{'method': self.method}]
        audit.n.write_json(self.output / 'receipt.json', self.receipt)
        original = (self.output / 'receipt.json').read_bytes()
        self.attachment_names = ['Home feed known empty state – synthetic fixture_0_C52033D6-9B99-4918-891E-3575FBC6E417.png']
        self.export_fixture()
        report = audit.n.read_json(self.packet / 'audit-index.json')
        self.assertEqual(report['status'], 'COMPLETE')
        self.assertEqual([item['attachment'] for item in report['files']], ['Home feed known empty state – synthetic fixture'])
        self.assertEqual((self.output / 'receipt.json').read_bytes(), original)
        self.assertEqual(audit.n.digest(self.packet / report['files'][0]['path']), report['files'][0]['sha256'])

    def testWrongNamesAndDuplicateAliasesStayIncompleteWithDiagnostics(self):
        label = 'Order detail – synthetic data'
        uuid = 'C52033D6-9B99-4918-891E-3575FBC6E417'
        for names in (['Wrong screenshot'], [label + '.png.extra'], [label + '.PNG'], [label, label + '.png'],
                      [label + '_0_bad-uuid.png'], [label + '_-1_' + uuid + '.png'],
                      [label + '_00_' + uuid + '.png'], [label + '_0_' + uuid + '.png.extra'],
                      [label + '_0_' + uuid + '.PNG'], ['Wrong screenshot_0_' + uuid + '.png'],
                      [label + '_0_' + uuid + '.png', label + '_1_' + uuid + '.png']):
            with self.subTest(names=names):
                self.attachment_names = names
                self.same_image_bytes = True
                with self.assertRaises(ValueError):
                    self.export_fixture()
                report = audit.n.read_json(self.packet / 'audit-index.json')
                self.assertEqual(report['status'], 'INCOMPLETE')
                self.assertNotIn('QUESTIFY_UI_AUDIT_COMPLETE_V1 ', self.export_stdout.getvalue())
                if len(names) == 1:
                    prefix = 'QUESTIFY_UI_AUDIT_DIAGNOSTIC_V1 '
                    lines = self.export_stdout.getvalue().splitlines()
                    self.assertEqual(len(lines), 1)
                    self.assertTrue(lines[0].startswith(prefix))
                    diagnostic = json.loads(lines[0][len(prefix):])
                    self.assertEqual(diagnostic['requestedLabel'], label)
                    self.assertEqual(diagnostic['actualTestIdentifier'], self.method)
                    self.assertEqual(diagnostic['attachments'][0]['friendlyName'], names[0])
                    self.assertEqual(diagnostic['attachments'][0]['exportedBasename'], '0.png')
                    self.assertEqual(diagnostic['attachments'][0]['magic'], 'PNG')
                    self.assertEqual(diagnostic['attachments'][0]['bytes'], len(self.image))
                    self.assertEqual(report['diagnostics'][0]['requestedLabel'], label)
                for path in self.packet.iterdir(): path.unlink()
                self.packet.rmdir()

    def testFailureNameDefaultIsUnchangedAndSelectionHasTwentySixImages(self):
        folder = self.output / 'attachments'; folder.mkdir()
        (folder / 'image.png').write_bytes(self.image)
        audit.n.write_json(folder / 'manifest.json', [{'attachments': [{'exportedFileName': 'image.png',
            'suggestedHumanReadableName': 'Success – synthetic fixture'}]}])
        self.assertEqual(audit.n.bounded_failure_images(folder, self.method, 1024 * 1024, 1), [])
        self.assertEqual(len(audit.n.bounded_failure_images(folder, self.method, 1024 * 1024, 1,
            allowed_names=['Success – synthetic fixture'])), 1)
        self.assertEqual(sum(map(len, audit.WANTED.values())), 28)

    def testRelatedPlanSkipsInsteadOfDependingOnWorkflowDispatchInput(self):
        with patch('sys.argv', ['export_current_ui_audit', '--plan', 'plan.json', '--output', 'output']), \
                patch.object(audit.n, 'verify_plan', return_value={'scope': 'related-current-regression'}), \
                patch.object(audit, 'export') as export, contextlib.redirect_stdout(io.StringIO()):
            audit.main()
        export.assert_not_called()

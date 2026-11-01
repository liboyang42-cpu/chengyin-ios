import base64
import contextlib
import io
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
            'QuestifyUITests/TicketWalletFlowTests/testWalletDetailEntitlementsBackAndReopenNeverOffersCodeOrPayment': [
                'Ticket wallet initial content – synthetic fixture', 'Ticket detail entitlements – synthetic fixture'],
        }[self.method]
        attachments = []
        for index, name in enumerate(names + ['Unrequested automatic screenshot']):
            filename = str(index) + '.png'; (folder / filename).write_bytes(self.image + bytes([index]))
            attachments.append({'exportedFileName': filename, 'suggestedHumanReadableName': name})
        audit.n.write_json(folder / 'manifest.json', [{'testIdentifier': self.method, 'attachments': attachments}])
        return 'OK', b''

    def export_fixture(self):
        with patch.object(audit.n, 'reparse_actual_result', return_value=self.receipt), \
                patch.object(audit.n, 'screenshot_probe_command', side_effect=self.probe), \
                patch.object(audit.n.control, 'source_identity', return_value=self.identity):
            audit.export(self.plan, self.output)

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
        self.export_fixture()
        report = audit.n.read_json(self.packet / 'audit-index.json')
        self.assertEqual(report['status'], 'COMPLETE')
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

    def testFailureNameDefaultIsUnchangedAndSelectionHasTwentySixImages(self):
        folder = self.output / 'attachments'; folder.mkdir()
        (folder / 'image.png').write_bytes(self.image)
        audit.n.write_json(folder / 'manifest.json', [{'attachments': [{'exportedFileName': 'image.png',
            'suggestedHumanReadableName': 'Success – synthetic fixture'}]}])
        self.assertEqual(audit.n.bounded_failure_images(folder, self.method, 1024 * 1024, 1), [])
        self.assertEqual(len(audit.n.bounded_failure_images(folder, self.method, 1024 * 1024, 1,
            allowed_names=['Success – synthetic fixture'])), 1)
        self.assertEqual(sum(map(len, audit.WANTED.values())), 26)

    def testRelatedPlanSkipsInsteadOfDependingOnWorkflowDispatchInput(self):
        with patch('sys.argv', ['export_current_ui_audit', '--plan', 'plan.json', '--output', 'output']), \
                patch.object(audit.n, 'verify_plan', return_value={'scope': 'related-current-regression'}), \
                patch.object(audit, 'export') as export, contextlib.redirect_stdout(io.StringIO()):
            audit.main()
        export.assert_not_called()

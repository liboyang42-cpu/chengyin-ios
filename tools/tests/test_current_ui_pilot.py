"""Local negative controls for the fixed screenshot pilot; no native execution."""
import copy
import hashlib
import json
import os
import plistlib
import re
from pathlib import Path
import struct
import tempfile
import time
import unittest
from unittest.mock import patch
import zlib
from tools import current_ui_pilot as p


LEGACY_TEST_SELECTION = {
    'QuestifyUITests/TeamFlowTests/testCreatePrivateTeamReviewCancelPreservesForm': {
        'Team create review target before one tap – synthetic fixture': 2},
    'QuestifyUITests/MerchantRegistrationAvailabilityFlowTests/testGroupReviewCancelAndExistingSaveReadBackServerValues': {
        'Synthetic registration availability source readback – synthetic fixture': 1},
    'QuestifyUITests/ClubOperationsFlowTests/testPopulatedMemberQuotaKeepsItsVisibleLabelInBothLanguages': {
        'Populated member quota English – synthetic fixture': 1,
        'Populated member quota Chinese – synthetic fixture': 1},
}


def png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b'\0\0\0\0\xff')) + chunk(b'IEND', b''))


class BoundedPilotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / 'images'; self.output.mkdir()
        self.method = next(iter(LEGACY_TEST_SELECTION))
        self.label = next(iter(LEGACY_TEST_SELECTION[self.method]))

    def export(self, method=None, count=None, names=None, content=None):
        method = method or self.method
        folder = self.root / ('export-' + str(len(list(self.root.glob('export-*'))))); folder.mkdir()
        if names is None:
            names = [label for label, expected in LEGACY_TEST_SELECTION[method].items() for _ in range(expected)]
        if count is not None: names = [self.label] * count
        rows = []
        for index, name in enumerate(names):
            file = str(index) + '.png'; (folder / file).write_bytes(content or png())
            rows.append({'suggestedHumanReadableName': name, 'exportedFileName': file})
        data = [{'testIdentifier': method.split('/', 1)[1] + '()', 'attachments': rows}]
        (folder / 'manifest.json').write_text(json.dumps(data))
        return folder

    def env(self):
        return {'GITHUB_REPOSITORY': 'liboyang42-cpu/chengyin-ios', 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                'GITHUB_REF': 'refs/heads/' + p.BRANCH, 'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_SHA': 'a' * 40,
                'GITHUB_WORKFLOW_SHA': 'a' * 40, 'RUNNER_OS': 'macOS', 'PILOT_REPOSITORY_PRIVATE': 'false', 'PILOT_MODE': 'screenshot-pilot'}

    def test_two_g05_occurrences_keep_equal_labels_and_hashes(self):
        folder = self.export()
        rows = p.collect_attachments(folder, self.method, self.output, LEGACY_TEST_SELECTION)
        self.assertEqual([1, 2], [r['occurrence'] for r in rows])
        self.assertEqual(1, len({r['sha256'] for r in rows}))
        self.assertEqual(2, len({r['path'] for r in rows}))
        self.assertEqual(p.n.digest(folder / 'manifest.json'), rows[0]['export_manifest_sha256'])
        self.assertEqual([1, 1], rows[0]['dimensions'])

    def test_missing_duplicate_does_not_pass(self):
        with self.assertRaisesRegex(ValueError, 'Missing requested'):
            p.collect_attachments(self.export(count=1), self.method, self.output, LEGACY_TEST_SELECTION)

    def test_extra_duplicate_does_not_pass(self):
        with self.assertRaisesRegex(ValueError, 'Too many matching'):
            p.collect_attachments(self.export(count=3), self.method, self.output, LEGACY_TEST_SELECTION)

    def test_same_export_filename_is_not_two_occurrences(self):
        folder = self.export(); path = folder / 'manifest.json'; data = json.loads(path.read_text())
        data[0]['attachments'][1]['exportedFileName'] = '0.png'; path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'Repeated export file'):
            p.collect_attachments(folder, self.method, self.output, LEGACY_TEST_SELECTION)

    def test_decorated_xcode_names_are_recognized(self):
        suffix = '_0_12345678-1234-1234-1234-123456789abc.png'
        rows = p.collect_attachments(self.export(names=[self.label + suffix, self.label + '.png']), self.method, self.output, LEGACY_TEST_SELECTION)
        self.assertEqual([self.label] * 2, [r['attachment'] for r in rows])

    def test_foreign_or_missing_test_identity_rejected(self):
        for identity in ('Another/testOther()', None):
            folder = self.export(); path = folder / 'manifest.json'; data = json.loads(path.read_text())
            data[0]['testIdentifier'] = identity; path.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, 'foreign attachment method'):
                p.collect_attachments(folder, self.method, self.output, LEGACY_TEST_SELECTION)

    def test_path_escape_and_symlink_rejected(self):
        folder = self.export(); path = folder / 'manifest.json'; data = json.loads(path.read_text())
        data[0]['attachments'][0]['exportedFileName'] = '../escape.png'; path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'Unsafe exported image path'):
            p.collect_attachments(folder, self.method, self.output, LEGACY_TEST_SELECTION)
        folder = self.export(); image = folder / '0.png'; image.unlink(); image.symlink_to(folder / '1.png')
        with self.assertRaisesRegex(ValueError, 'Invalid bounded image'):
            p.collect_attachments(folder, self.method, self.output, LEGACY_TEST_SELECTION)

    def test_packet_size_cap_is_enforced_before_writing(self):
        with patch.object(p, 'TOTAL_IMAGE_LIMIT', len(png())):
            with self.assertRaisesRegex(ValueError, 'exceeds size limit'):
                p.collect_attachments(self.export(), self.method, self.output, LEGACY_TEST_SELECTION)
        self.assertEqual(len(png()), sum(f.stat().st_size for f in self.output.iterdir()))

    def test_corrupt_png_rejected(self):
        data = bytearray(png()); data[20] ^= 1
        with self.assertRaisesRegex(ValueError, 'PNG CRC mismatch'):
            p.collect_attachments(self.export(content=bytes(data)), self.method, self.output, LEGACY_TEST_SELECTION)

    def packet(self):
        rows = []
        for method in LEGACY_TEST_SELECTION:
            rows.extend(p.collect_attachments(self.export(method=method), method, self.output, LEGACY_TEST_SELECTION))
        return {'kind': 'SYNTHETIC_UI_PILOT_NOT_VISUAL_ACCEPTANCE', 'files': rows}

    def test_all_five_manifest_hashes_are_verified(self):
        report = self.packet()
        self.assertEqual(5 * len(png()), p.validate_packet(report, self.output, LEGACY_TEST_SELECTION))
        for row in report['files']:
            self.assertEqual(hashlib.sha256((self.output / row['path']).read_bytes()).hexdigest(), row['sha256'])
        (self.output / report['files'][0]['path']).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Image changed'):
            p.validate_packet(report, self.output, LEGACY_TEST_SELECTION)

    def test_missing_or_foreign_packet_cannot_pass(self):
        report = self.packet(); report['files'].pop()
        with self.assertRaisesRegex(ValueError, 'all manifest-selected'):
            p.validate_packet(report, self.output, LEGACY_TEST_SELECTION)
        report['files'].append(copy.deepcopy(report['files'][0])); report['files'][0]['method'] = 'Foreign/test'
        with self.assertRaisesRegex(ValueError, 'selection differs'):
            p.validate_packet(report, self.output, LEGACY_TEST_SELECTION)

    def test_manual_public_exact_sha_first_attempt_guard(self):
        p.guard_context('a' * 40, self.env())
        cases = {'PILOT_REPOSITORY_PRIVATE': 'true', 'GITHUB_REPOSITORY': 'liboyang42-cpu/chengyin-app', 'GITHUB_EVENT_NAME': 'push',
                 'GITHUB_REF': 'refs/heads/main', 'GITHUB_RUN_ATTEMPT': '2', 'GITHUB_SHA': 'b' * 40,
                 'GITHUB_WORKFLOW_SHA': 'b' * 40, 'RUNNER_OS': 'Linux'}
        for key, value in cases.items():
            env = self.env(); env[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): p.guard_context('a' * 40, env)
        with self.assertRaises(ValueError): p.guard_context('', self.env())

    def push_env(self):
        env = self.env()
        env.update(GITHUB_EVENT_NAME='push', PILOT_MODE='', PILOT_PUSH_REF='refs/heads/' + p.BRANCH,
                   PILOT_PUSH_CREATED='false', PILOT_PUSH_DELETED='false', PILOT_PUSH_FORCED='false',
                   PILOT_PUSH_BEFORE=p.PUSH_BASE, PILOT_PUSH_AFTER='a' * 40, PILOT_PUSH_HEAD_SHA='a' * 40,
                   PILOT_PUSH_HEAD_MESSAGE=p.PUSH_MARKER)
        return env

    def test_only_exact_intentional_publication_update_is_accepted(self):
        receipt = p.guard_context('a' * 40, self.push_env())
        self.assertEqual('push_event.after', receipt['expected_sha_origin'])
        self.assertEqual(p.PUSH_BASE, receipt['before'])
        self.assertEqual('a' * 40, receipt['after'])
        self.assertFalse(receipt['created']); self.assertFalse(receipt['forced'])

    def test_manual_mode_stays_explicit_and_independent_of_push_metadata(self):
        receipt = p.guard_context('a' * 40, self.env())
        self.assertEqual('manual_pilot_sha', receipt['expected_sha_origin'])
        for value in ['', 'related', 'full']:
            env = self.env(); env['PILOT_MODE'] = value
            with self.subTest(value=value), self.assertRaises(ValueError): p.guard_context('a' * 40, env)

    def test_creation_repeat_forced_deleted_foreign_and_unmarked_pushes_fail(self):
        cases = {'GITHUB_EVENT_NAME': 'create', 'GITHUB_REF': 'refs/heads/main',
                 'PILOT_PUSH_REF': 'refs/heads/other', 'PILOT_PUSH_CREATED': 'true',
                 'PILOT_PUSH_DELETED': 'true', 'PILOT_PUSH_FORCED': 'true',
                 'PILOT_PUSH_BEFORE': 'a' * 40, 'PILOT_PUSH_AFTER': 'b' * 40,
                 'PILOT_PUSH_HEAD_SHA': 'b' * 40, 'GITHUB_RUN_ATTEMPT': '2',
                 'PILOT_PUSH_HEAD_MESSAGE': 'prefix ' + p.PUSH_MARKER + ' suffix',
                 'PILOT_REPOSITORY_PRIVATE': 'true', 'GITHUB_WORKFLOW_SHA': 'b' * 40}
        for key, value in cases.items():
            env = self.push_env(); env[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): p.guard_context('a' * 40, env)
        for key in ['PILOT_PUSH_CREATED', 'PILOT_PUSH_DELETED', 'PILOT_PUSH_FORCED', 'PILOT_PUSH_HEAD_MESSAGE']:
            env = self.push_env(); env.pop(key)
            with self.subTest(missing=key), self.assertRaises(ValueError): p.guard_context('a' * 40, env)
        env = self.push_env(); env['PILOT_PUSH_BEFORE'] = '0' * 40
        with self.assertRaises(ValueError): p.guard_context('a' * 40, env)

    def test_publication_noop_and_unbound_expected_sha_fail(self):
        env = self.push_env()
        for key in ['GITHUB_SHA', 'GITHUB_WORKFLOW_SHA', 'PILOT_PUSH_AFTER', 'PILOT_PUSH_HEAD_SHA']: env[key] = p.PUSH_BASE
        with self.assertRaises(ValueError): p.guard_context(p.PUSH_BASE, env)
        with self.assertRaises(ValueError): p.guard_context('b' * 40, self.push_env())

    def test_exact_three_tests_serial_no_retry(self):
        command = p.test_command('/run.xctestrun', 'id', '/result.xcresult', LEGACY_TEST_SELECTION)
        self.assertEqual(['-only-testing:' + m for m in LEGACY_TEST_SELECTION], [s for s in command if s.startswith('-only-testing:')])
        self.assertEqual('NO', command[command.index('-parallel-testing-enabled') + 1])
        self.assertEqual('1', command[command.index('-maximum-concurrent-test-simulator-destinations') + 1])
        self.assertFalse(any('retry' in s or 'iteration' in s for s in command))

    def test_reviewed_source_hash_and_mutation_guard(self):
        file = self.root / 'capture.swift'; data = b'offline capture'; file.write_bytes(data)
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if True:
            self.assertEqual(hashlib.sha256(data).hexdigest(), p.source_hashes(self.root, {'capture.swift': blob})['capture.swift']['sha256'])
            file.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'renewed review'): p.source_hashes(self.root, {'capture.swift': blob})

    def manifest(self):
        root = Path(p.__file__).resolve().parents[1]
        return json.loads((root / p.MANIFEST_PATH).read_text())

    def test_exact_delivered_manifest_has_six_methods_and_seventeen_occurrences(self):
        manifest = self.manifest()
        selection, sources = p.selection_from_manifest(manifest)
        self.assertEqual(6, len(selection))
        self.assertEqual(17, sum(sum(labels.values()) for labels in selection.values()))
        counts = {row['owner']: sum(item['count'] for method in row['methods'] for item in method['attachments']) for row in manifest['owners']}
        self.assertEqual({'G05': 6, 'M04': 4, 'CL02': 7}, counts)
        self.assertEqual('316a4b1e03326d79551af4ab6c4dae3addec2143', sources['App/MerchantContentFixtureScenarioView.swift'])
        self.assertEqual(7, len(sources))
        self.assertFalse(any('AI' in method for method in selection))
        command = p.test_command('/run.xctestrun', 'id', '/result.xcresult', selection)
        self.assertEqual(6, len([arg for arg in command if arg.startswith('-only-testing:')]))

    def test_manifest_rejects_pending_foreign_unbound_or_changed_source_contract(self):
        cases = []
        d = self.manifest(); d['status'] = 'PENDING'; cases.append(d)
        d = self.manifest(); d['owners'][0]['status'] = 'PENDING'; cases.append(d)
        d = self.manifest(); d['owners'][0]['capture_patch_sha256'] = None; cases.append(d)
        d = self.manifest(); d['owners'][0]['methods'][0]['method'] = 'QuestifyUITests/Foreign/testUnreviewed'; cases.append(d)
        d = self.manifest(); d['owners'][0]['source_blobs'] = {}; cases.append(d)
        d = self.manifest(); d['owners'][0]['source_blobs']['../private'] = 'a' * 40; cases.append(d)
        d = self.manifest(); d['owners'][1]['owner'] = 'G05'; cases.append(d)
        d = self.manifest(); d['common_source_blobs']['Tests/AppUITests/FailureScreenshot.swift'] = 'a' * 40; cases.append(d)
        for number, data in enumerate(cases):
            with self.subTest(number=number), self.assertRaises(ValueError): p.selection_from_manifest(data)

    def test_manifest_bounds_duplicate_methods_labels_and_occurrences(self):
        cases = []
        d = self.manifest(); d['owners'][0]['methods'] *= 2; cases.append(d)
        d = self.manifest(); d['owners'][0]['methods'][0]['attachments'] *= 2; cases.append(d)
        d = self.manifest(); d['owners'][0]['methods'][0]['attachments'][0]['count'] = True; cases.append(d)
        d = self.manifest(); d['owners'][0]['methods'][0]['attachments'][0]['count'] = 5; cases.append(d)
        d = self.manifest()
        for row in d['owners']:
            for method in row['methods']:
                for item in method['attachments']: item['count'] = 4
        cases.append(d)
        for number, data in enumerate(cases):
            with self.subTest(number=number), self.assertRaises(ValueError): p.selection_from_manifest(data)

    def test_pending_manifest_stops_before_native_tools(self):
        data = self.manifest(); data['status'] = 'PENDING'
        target = self.root / p.MANIFEST_PATH; target.parent.mkdir(); target.write_text(json.dumps(data))
        start = self.root / 'start'; start.write_text(str(time.monotonic()))
        env = dict(self.env(), RUNNER_TEMP=str(self.root))
        with patch.dict(os.environ, env), patch.object(p.n, 'toolchain') as native_tools:
            result = p.execute(self.root, self.root / 'pilot-output', 'a' * 40, start)
        self.assertEqual(1, result); native_tools.assert_not_called()
        report = json.loads((self.root / 'pilot-output/pilot-manifest.json').read_text())
        self.assertEqual('FAIL', report['status']); self.assertIn('pending', report['error'])

    def test_all_seventeen_requested_occurrences_are_retained_and_rehashed(self):
        selection, _ = p.selection_from_manifest(self.manifest()); rows = []
        for ordinal, (method, labels) in enumerate(selection.items()):
            folder = self.root / ('capture-' + str(ordinal)); folder.mkdir(); attachments = []
            for label, count in labels.items():
                for _ in range(count):
                    filename = str(len(attachments)) + '.png'; (folder / filename).write_bytes(png())
                    attachments.append({'suggestedHumanReadableName': label, 'exportedFileName': filename})
            (folder / 'manifest.json').write_text(json.dumps([{'testIdentifier': method.split('/', 1)[1] + '()', 'attachments': attachments}]))
            rows.extend(p.collect_attachments(folder, method, self.output, selection))
        report = {'kind': 'SYNTHETIC_UI_PILOT_NOT_VISUAL_ACCEPTANCE', 'files': rows}
        self.assertEqual(17, len(rows)); self.assertEqual(17, len({row['path'] for row in rows}))
        self.assertEqual(17 * len(png()), p.validate_packet(report, self.output, selection))

    def test_existing_product_guard_rejects_live_api_device_or_signing(self):
        products = self.root / 'Products'; app = products / 'Debug-iphonesimulator/Questify.app'; app.mkdir(parents=True)
        good = {'QuestifyAPIBaseURL': '', 'CFBundleSupportedPlatforms': ['iPhoneSimulator']}
        with patch.object(p.n, 'select_xctestrun', return_value=products / 'test.xctestrun'):
            (app / 'Info.plist').write_bytes(plistlib.dumps(good))
            p.n.normalized_ui_products(products)
            for key, value in [('QuestifyAPIBaseURL', 'https://live.example'), ('CFBundleSupportedPlatforms', ['iPhoneOS'])]:
                bad = dict(good); bad[key] = value; (app / 'Info.plist').write_bytes(plistlib.dumps(bad))
                with self.assertRaisesRegex(ValueError, 'isolated unsigned'): p.n.normalized_ui_products(products)
            (app / 'Info.plist').write_bytes(plistlib.dumps(good)); (app / 'embedded.mobileprovision').write_bytes(b'profile')
            with self.assertRaisesRegex(ValueError, 'isolated unsigned'): p.n.normalized_ui_products(products)
        self.assertIn('xctestrun = n.normalized_ui_products(products)', Path(p.__file__).read_text())

    def test_workflow_bounds_and_existing_mode_guards(self):
        workflow = Path(p.__file__).resolve().parents[1] / '.github/workflows/native-ios.yml'
        source = workflow.read_text()
        self.assertIn('options: [related, full, screenshot-pilot]', source)
        pilot = source.split('  screenshot_pilot:\n')[1]
        self.assertEqual(1, pilot.count('runs-on: macos-26'))
        self.assertIn('timeout-minutes: 35', pilot)
        self.assertNotIn('matrix:', pilot)
        self.assertIn('retention-days: 1', pilot)
        self.assertIn("github.event.before == '" + p.PUSH_BASE + "'", pilot)
        self.assertIn("github.event.created == false", pilot)
        self.assertIn("github.event.forced == false", pilot)
        self.assertIn("github.event.after == github.sha", pilot)
        self.assertIn("github.event.head_commit.id == github.sha", pilot)
        self.assertIn(p.PUSH_MARKER, pilot)
        self.assertIn("github.event_name == 'workflow_dispatch'", pilot)
        self.assertIn("github.event_name == 'push'", pilot)
        before = source.split('  screenshot_pilot:\n')[0]
        for name in ['controls', 'secrets', 'native', 'ui_build', 'ui', 'platforms', 'current-checks']:
            block = re.split(r'\n  [A-Za-z_-]+:\n', before.split('  ' + name + ':\n')[1])[0]
            self.assertIn("inputs.mode != 'screenshot-pilot'", block, name)
            self.assertIn("github.ref_name != 'screenshot/codex-ui-20261103'", block, name)


if __name__ == '__main__': unittest.main()

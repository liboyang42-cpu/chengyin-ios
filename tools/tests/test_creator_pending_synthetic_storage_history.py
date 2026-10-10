"""Negative controls for historical byte identity, not current storage behavior."""
import hashlib
import json
from itertools import product
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.tests import creator_pending_synthetic_storage_history as history
from tools.tests.creator_pending_budget_history import source_index


ROOT = Path(__file__).resolve().parents[2]
COMPOSITION = 'App/AppCompositionRoot.swift'
SESSION = 'App/AppSession.swift'
FIXTURE = history.FIXTURE_SOURCE

# Independent, exact pre/post regions for constructing the two other historical
# test inputs. No extra preimage files or external checkout are needed by CI.
OTHER_DELTAS = {
    COMPOSITION: (
        (
            b'#if DEBUG\n'
            b'    /// Explicit fixture-only override. Ordinary and Release composition keep system storage.\n'
            b'    var syntheticWorkshopCreatorPendingRecoveryStorage: (any TemplateAuthoringStorage)? = nil\n'
            b'#endif\n',
            b'',
        ),
    ),
    SESSION: (
        (
            b'    private var workshopCreatorPendingRecoveryStorage: any TemplateAuthoringStorage {\n'
            b'#if DEBUG\n'
            b'        if let storage = composition.storage.syntheticWorkshopCreatorPendingRecoveryStorage { return storage }\n'
            b'#endif\n'
            b'        return templateAuthoringSecureStorage\n'
            b'    }\n',
            b'',
        ),
        (
            b'                  let store = try? WorkshopCreatorPendingStore(storage: workshopCreatorPendingRecoveryStorage, context: captured, sourceTemplateId: sourceTemplateId),\n',
            b'                  let store = try? WorkshopCreatorPendingStore(storage: templateAuthoringSecureStorage, context: captured, sourceTemplateId: sourceTemplateId),\n',
        ),
        (
            b'                  let declarationStore = try? WorkshopCreatorConsentPendingStore(storage: workshopCreatorPendingRecoveryStorage, context: captured, sourceTemplateId: sourceTemplateId) else { return nil }\n',
            b'                  let declarationStore = try? WorkshopCreatorConsentPendingStore(storage: templateAuthoringSecureStorage, context: captured, sourceTemplateId: sourceTemplateId) else { return nil }\n',
        ),
        (
            b'                          let consentStore = try? WorkshopCreatorConsentPendingStore(storage: self.workshopCreatorPendingRecoveryStorage, context: captured, sourceTemplateId: sourceTemplateId) else { return nil }\n',
            b'                          let consentStore = try? WorkshopCreatorConsentPendingStore(storage: self.templateAuthoringSecureStorage, context: captured, sourceTemplateId: sourceTemplateId) else { return nil }\n',
        ),
    ),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


class CreatorPendingSyntheticStorageHistoryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.currentimages = {name: (ROOT / name).read_bytes() for name in history.APP_SHA256}
        self.manifest = (ROOT / history.EVOLUTION_FILE).read_bytes()
        self.evolution = json.loads(self.manifest)['files']
        self.postimages = dict(self.currentimages)
        for name, row in self.evolution.items():
            data = self.postimages[name]
            self.assertEqual(digest(data), row['reviewed_sha256'])
            for delta in reversed(row['inverse_deltas']):
                offset = delta['postimage_offset']
                after, before = bytes.fromhex(delta['postimage_hex']), bytes.fromhex(delta['preimage_hex'])
                self.assertEqual(data[offset:offset + len(after)], after)
                data = data[:offset] + before + data[offset + len(after):]
            self.postimages[name] = data
        self.preimage = (ROOT / history.PREIMAGE_FILE).read_bytes()
        self.preimages = {FIXTURE: self.preimage}
        for name, deltas in OTHER_DELTAS.items():
            data = self.postimages[name]
            for after, before in deltas:
                self.assertEqual(data.count(after), 1, name)
                data = data.replace(after, before, 1)
            self.preimages[name] = data
        for name, (before, after) in history.APP_SHA256.items():
            self.assertEqual(digest(self.preimages[name]), before, name)
            self.assertEqual(digest(self.postimages[name]), after, name)
        for name, raw in self.preimages.items():
            self.assertEqual(raw, (ROOT / history.PREIMAGE_FILES[name]).read_bytes())
        self.install(self.postimages)

    def install(self, sources):
        inputs = {history.PREIMAGE_FILES[name]: data for name, data in self.preimages.items()}
        for name, raw in {**sources, **inputs, history.EVOLUTION_FILE: self.manifest}.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)

    def project(self, relative=FIXTURE):
        return history.historical_pre_synthetic_storage_helper_bytes(
            self.root / relative, root=self.root)

    def rejects(self, sources, message='Mixed or unreviewed'):
        self.install(sources)
        with self.assertRaisesRegex(ValueError, message):
            self.project()

    def test_approved_bundle_restores_complete_preimage_and_original_hash(self):
        expected_hash = 'a7fe8e68a972c3ffc0eb4390654669d85c78771c24237c9b2c09b34a68bfcf75'
        self.assertEqual(history.APP_SHA256[FIXTURE][0], expected_hash)
        row = next(row for row in source_index()['helper_sources'] if row['path'] == FIXTURE)
        self.assertEqual(row['sha256'], expected_hash)
        restored = self.project()
        self.assertIsInstance(restored, bytes)
        self.assertEqual(restored, self.preimage)
        self.assertEqual(digest(restored), row['sha256'])
        self.assertNotEqual(restored, self.postimages[FIXTURE])
        # The fixed deltas account for every single differing byte.
        reconstructed = restored
        for offset, after, before in history.FIXTURE_INVERSE_DELTAS:
            self.assertEqual(reconstructed[offset:offset + len(before)], before)
            reconstructed = reconstructed[:offset] + after + reconstructed[offset + len(before):]
        self.assertEqual(reconstructed, self.postimages[FIXTURE])

    def test_complete_original_bundle_is_byte_exact_and_idempotent(self):
        self.install(self.preimages)
        self.assertEqual(self.project(), self.preimage)
        self.assertEqual(self.project(), self.preimage)

    def test_all_six_mixed_original_changed_bundles_fail_closed(self):
        names = tuple(history.APP_SHA256)
        for states in product((False, True), repeat=len(names)):
            if all(states) or not any(states):
                continue
            with self.subTest(states=states):
                self.rejects({name: (self.postimages if changed else self.preimages)[name]
                              for name, changed in zip(names, states)})

    def test_each_changed_region_missing_duplicated_or_moved_fails_closed(self):
        regions = {name: [after for after, _ in deltas]
                   for name, deltas in OTHER_DELTAS.items()}
        regions[FIXTURE] = [after for _, after, _ in history.FIXTURE_INVERSE_DELTAS]
        for name, blocks in regions.items():
            for number, block in enumerate(blocks):
                original = self.postimages[name]
                self.assertEqual(original.count(block), 1)
                offset = original.index(block)
                missing = original[:offset] + original[offset + len(block):]
                mutations = {
                    'missing': missing,
                    'duplicate': original[:offset] + block + original[offset:],
                    'moved': block + missing,
                }
                for mutation, data in mutations.items():
                    with self.subTest(path=name, region=number, mutation=mutation):
                        self.assertNotEqual(data, original)
                        self.rejects({**self.postimages, name: data})

    def test_unrelated_changes_in_each_bound_file_fail_in_both_states(self):
        for label, sources in [('original', self.preimages), ('changed', self.postimages)]:
            for name, raw in sources.items():
                with self.subTest(state=label, path=name):
                    self.rejects({**sources, name: b'// Unrelated change.\n' + raw})

    def test_raw_crlf_mutations_in_each_bound_file_fail_in_both_states(self):
        for label, sources in [('original', self.preimages), ('changed', self.postimages)]:
            for name, raw in sources.items():
                with self.subTest(state=label, path=name):
                    self.assertNotIn(b'\r', raw)
                    self.rejects({**sources, name: raw.replace(b'\n', b'\r\n')})

    def test_default_nil_override_cannot_be_enabled(self):
        original = self.postimages[COMPOSITION]
        marker = b'var syntheticWorkshopCreatorPendingRecoveryStorage: (any TemplateAuthoringStorage)? = nil'
        self.assertEqual(original.count(marker), 1)
        enabled = marker.removesuffix(b'nil') + b'TemplateAuthoringMemoryStorage()'
        self.rejects({**self.postimages, COMPOSITION: original.replace(marker, enabled, 1)})

    def test_production_secure_storage_fallback_cannot_be_replaced(self):
        original = self.postimages[SESSION]
        marker = b'        return templateAuthoringSecureStorage\n'
        self.assertEqual(original.count(marker), 1)
        replacement = b'        return TemplateAuthoringMemoryStorage()\n'
        self.rejects({**self.postimages, SESSION: original.replace(marker, replacement, 1)})

    def test_missing_bound_file_fails_closed(self):
        for name in history.APP_SHA256:
            with self.subTest(path=name):
                self.install(self.postimages)
                (self.root / name).unlink()
                with self.assertRaisesRegex(ValueError, 'Missing or unreadable'):
                    self.project()

    def test_missing_or_tampered_preimage_fails_in_both_states(self):
        mutations = {
            'missing': None,
            'truncated': self.preimage[:-1],
            'unrelated': b'// Changed preimage.\n' + self.preimage,
            'crlf': self.preimage.replace(b'\n', b'\r\n'),
            'postimage': self.postimages[FIXTURE],
        }
        for label, sources in [('original', self.preimages), ('changed', self.postimages)]:
            for mutation, data in mutations.items():
                with self.subTest(state=label, mutation=mutation):
                    self.install(sources)
                    path = self.root / history.PREIMAGE_FILE
                    if data is None:
                        path.unlink()
                    else:
                        path.write_bytes(data)
                    with self.assertRaises(ValueError):
                        self.project()

    def test_later_mutations_are_not_hidden_by_cached_history(self):
        self.assertEqual(self.project(), self.preimage)
        path = self.root / COMPOSITION
        path.write_bytes(path.read_bytes() + b'\n')
        with self.assertRaisesRegex(ValueError, 'Mixed or unreviewed'):
            self.project()
        self.install(self.postimages)
        self.assertEqual(self.project(), self.preimage)
        (self.root / history.PREIMAGE_FILE).write_bytes(self.preimage + b'\n')
        with self.assertRaisesRegex(ValueError, 'preimage changed'):
            self.project()

    def test_other_helpers_keep_the_existing_historical_reader(self):
        for row in source_index()['helper_sources']:
            if row['path'] == FIXTURE:
                continue
            if row['path'] == 'App/TemplateAuthoringMineView.swift':
                from tools.tests.creator_shelf_refresh_history import SOURCE_SHA256
                for name in SOURCE_SHA256:
                    path = self.root / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes((ROOT / name).read_bytes())
                with patch.object(history, 'historical_pre_club_source') as reader:
                    restored = self.project(row['path'])
                    self.assertEqual(digest(restored), row['sha256'])
                    reader.assert_not_called()
                continue
            with self.subTest(path=row['path']):
                raw = history.historical_pre_club_source(ROOT / row['path']).read_bytes()
                path = self.root / row['path']
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
                with patch.object(history, 'historical_pre_club_source', wraps=history.historical_pre_club_source) as reader:
                    self.assertEqual(self.project(row['path']), raw)
                    reader.assert_called_once_with(path)
                self.assertEqual(digest(raw), row['sha256'])

    def test_unchanged_helper_cannot_bypass_three_file_validation(self):
        helper = 'App/TemplateAuthoringFixtureSupport.swift'
        path = self.root / helper
        path.write_bytes((ROOT / helper).read_bytes())
        (self.root / SESSION).write_bytes(self.postimages[SESSION] + b'\n')
        with self.assertRaisesRegex(ValueError, 'Mixed or unreviewed'):
            self.project(helper)

    def test_original_guard_changes_are_limited_to_helper_byte_read_connection(self):
        raw = (ROOT / 'tools/tests/test_creator_pending_budget.py').read_bytes()
        added_import = b'from tools.tests.creator_pending_synthetic_storage_history import historical_pre_synthetic_storage_helper_bytes\n'
        current_read = b"historical_pre_synthetic_storage_helper_bytes(ROOT / row['path'])"
        previous_read = b"historical_pre_club_source(ROOT / row['path']).read_bytes()"
        self.assertEqual(raw.count(added_import), 1)
        self.assertEqual(raw.count(current_read), 1)
        historical_guard = raw.replace(added_import, b'', 1).replace(current_read, previous_read, 1)
        # Exact guard file from reviewed tree 82e9abd1afa6180815ef7ea5ea314d6eb692e036.
        self.assertEqual(digest(historical_guard),
                         'ea2dd4b7a5e4854a713eca620cda046b28b9091bd272006dc88466bb1bb716a4')

    def test_current_complete_bundle_restores_the_same_original_helper_hash(self):
        self.install(self.currentimages)
        self.assertEqual(self.project(), self.preimage)
        self.assertEqual(digest(self.project()),
                         'a7fe8e68a972c3ffc0eb4390654669d85c78771c24237c9b2c09b34a68bfcf75')
        for name, row in self.evolution.items():
            original = self.preimages[name]
            restored = original
            for offset, after, before in history.STORAGE_INVERSE_DELTAS[name]:
                self.assertEqual(restored[offset:offset + len(before)], before)
                restored = restored[:offset] + after + restored[offset + len(before):]
            self.assertEqual(restored, self.postimages[name])
            for delta in row['inverse_deltas']:
                offset = delta['postimage_offset']
                before, after = bytes.fromhex(delta['preimage_hex']), bytes.fromhex(delta['postimage_hex'])
                self.assertEqual(restored[offset:offset + len(before)], before)
                restored = restored[:offset] + after + restored[offset + len(before):]
            self.assertEqual(restored, self.currentimages[name])
            self.assertEqual(digest(original), history.APP_SHA256[name][0])

    def test_every_distinct_mixed_three_generation_bundle_fails_closed(self):
        names = tuple(history.APP_SHA256)
        states = (self.preimages, self.postimages, self.currentimages)
        accepted = {tuple(state[name] for name in names) for state in states}
        tested = set()
        for generations in product(states, repeat=len(names)):
            bundle = tuple(state[name] for state, name in zip(generations, names))
            if bundle in accepted or bundle in tested:
                continue
            tested.add(bundle)
            with self.subTest(hashes=tuple(map(digest, bundle))):
                self.rejects(dict(zip(names, bundle)))
        self.assertEqual(len(accepted), 3)
        self.assertEqual(len(tested), 15)

    def test_each_evolution_region_missing_duplicated_moved_or_partially_inverted_fails(self):
        for name, row in self.evolution.items():
            raw = self.currentimages[name]
            for number, delta in enumerate(row['inverse_deltas']):
                offset = delta['postimage_offset']
                after, before = bytes.fromhex(delta['postimage_hex']), bytes.fromhex(delta['preimage_hex'])
                self.assertEqual(raw.count(after), 1)
                missing = raw[:offset] + raw[offset + len(after):]
                mutations = {'missing': missing, 'duplicated': raw[:offset] + after + raw[offset:],
                             'moved': after + missing,
                             'partial_inverse': raw[:offset] + before + raw[offset + len(after):]}
                for mutation, data in mutations.items():
                    with self.subTest(path=name, region=number, mutation=mutation):
                        self.rejects({**self.currentimages, name: data})

    def test_current_bundle_unrelated_crlf_storage_and_default_mutations_fail(self):
        for name, raw in self.currentimages.items():
            for label, data in [('unrelated', b'// Added.\n' + raw),
                                ('crlf', raw.replace(b'\n', b'\r\n'))]:
                with self.subTest(path=name, mutation=label):
                    self.rejects({**self.currentimages, name: data})
        for name, old, new in [
            (COMPOSITION, b'= nil\n#endif', b'= TemplateAuthoringMemoryStorage()\n#endif'),
            (SESSION, b'        return templateAuthoringSecureStorage\n',
             b'        return TemplateAuthoringMemoryStorage()\n'),
        ]:
            raw = self.currentimages[name]
            self.assertEqual(raw.count(old), 1)
            self.rejects({**self.currentimages, name: raw.replace(old, new, 1)})
        for name, deltas in OTHER_DELTAS.items():
            for after, before in deltas:
                raw = self.currentimages[name]
                self.assertEqual(raw.count(after), 1)
                self.rejects({**self.currentimages, name: raw.replace(after, before, 1)})

    def test_only_evolved_bundle_requires_each_later_complete_app_preimage(self):
        for label, sources in [('original', self.preimages), ('changed', self.postimages),
                               ('evolved', self.currentimages)]:
            for name, original in self.preimages.items():
                mutations = [None, original[:-1], original + b'\n',
                             original.replace(b'\n', b'\r\n'), self.postimages[name]]
                for number, data in enumerate(mutations):
                    with self.subTest(state=label, path=name, mutation=number):
                        self.install(sources)
                        path = self.root / history.PREIMAGE_FILES[name]
                        if data is None:
                            path.unlink()
                        else:
                            path.write_bytes(data)
                        if label == 'evolved' or name == FIXTURE:
                            with self.assertRaises(ValueError):
                                self.project()
                        else:
                            self.assertEqual(self.project(), self.preimage)

    def test_manifest_missing_or_mutated_is_never_hidden_by_cached_history(self):
        changed = json.loads(self.manifest)
        changed['files'][COMPOSITION]['inverse_deltas'].pop()
        mutations = [None, self.manifest[:-1], self.manifest + b'\n',
                     self.manifest.replace(b'\n', b'\r\n'), json.dumps(changed).encode()]
        for sources in (self.preimages, self.postimages, self.currentimages):
            for number, raw in enumerate(mutations):
                with self.subTest(state=digest(sources[SESSION]), mutation=number):
                    self.install(sources)
                    self.assertEqual(self.project(), self.preimage)
                    path = self.root / history.EVOLUTION_FILE
                    if raw is None:
                        path.unlink()
                    else:
                        path.write_bytes(raw)
                    if sources is self.currentimages:
                        with self.assertRaises(ValueError):
                            self.project()
                    else:
                        self.assertEqual(self.project(), self.preimage)

    def test_legacy_minimal_bundle_needs_no_later_manifest_or_app_preimages(self):
        for label, sources in [('original', self.preimages), ('changed', self.postimages)]:
            for mutation in ('missing', 'corrupt'):
                with self.subTest(state=label, later_inputs=mutation):
                    self.install(sources)
                    later = [history.EVOLUTION_FILE, history.PREIMAGE_FILES[COMPOSITION],
                             history.PREIMAGE_FILES[SESSION]]
                    for relative in later:
                        path = self.root / relative
                        if mutation == 'missing':
                            path.unlink()
                        else:
                            path.write_bytes(b'Corrupt later-generation evidence.\n')
                    self.assertEqual(self.project(), self.preimage)
                    self.assertEqual(self.project(), self.preimage)
                    (self.root / history.PREIMAGE_FILE).write_bytes(self.preimage + b'\n')
                    with self.assertRaisesRegex(ValueError, 'preimage changed'):
                        self.project()

    def test_same_absent_later_inputs_cannot_admit_the_evolved_bundle(self):
        for relative in (history.EVOLUTION_FILE, history.PREIMAGE_FILES[COMPOSITION],
                         history.PREIMAGE_FILES[SESSION]):
            with self.subTest(path=relative):
                self.install(self.currentimages)
                (self.root / relative).unlink()
                with self.assertRaises(ValueError):
                    self.project()

    def test_current_sources_are_read_only_and_later_mutations_remain_visible(self):
        self.install(self.currentimages)
        before = {path: path.read_bytes() for path in self.root.rglob('*') if path.is_file()}
        self.assertEqual(self.project(), self.preimage)
        after = {path: path.read_bytes() for path in self.root.rglob('*') if path.is_file()}
        self.assertEqual(before, after)
        for name in history.APP_SHA256:
            with self.subTest(path=name):
                self.install(self.currentimages)
                self.assertEqual(self.project(), self.preimage)
                path = self.root / name
                path.write_bytes(path.read_bytes() + b'\n')
                with self.assertRaisesRegex(ValueError, 'Mixed or unreviewed'):
                    self.project()

    def test_all_old_sha_anchors_and_original_guard_bytes_stay_exact(self):
        self.assertEqual(history.APP_SHA256[COMPOSITION], (
            '2c1d87087325898aaa78cb644b780c3132736536c1971318c473eddabdf439d4',
            '006923cb90a730259ba135784ae802350125c31cfb584d89a88d4209f8986dbb'))
        self.assertEqual(history.APP_SHA256[SESSION], (
            'e2f082a23132df938bebd49972eb4a1eab79c1070a76f04348cae080a28a377f',
            '5ac846ff656a7b74f0c9bd28200f11a257ae260f5c881f201c2a3b026af6dd09'))
        self.assertEqual(history.APP_SHA256[FIXTURE], (
            'a7fe8e68a972c3ffc0eb4390654669d85c78771c24237c9b2c09b34a68bfcf75',
            '4084ba4106fb94630ba3091ef7eb754e29864a21a85c38123b82ec58e4f7ebee'))
        self.test_original_guard_changes_are_limited_to_helper_byte_read_connection()


if __name__ == '__main__':
    unittest.main()

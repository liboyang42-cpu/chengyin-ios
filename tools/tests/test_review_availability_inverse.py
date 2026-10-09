from pathlib import Path
import importlib.util
import shutil
import tempfile
import unittest

from tools import review_availability_inverse as inverse

CURRENT = Path(__file__).resolve().parents[2]


class ReviewAvailabilityInverseTests(unittest.TestCase):
    def test_exact_forward_inverse_and_original_inventory(self):
        inverse.verify_current(CURRENT)
        for relative, item in inverse.contract()['scope'].items():
            current = (CURRENT / relative).read_bytes()
            previous = inverse.original_source(relative, current, CURRENT) if item['before_sha256'] else b''
            self.assertEqual(inverse.digest(previous) if previous else None, item['before_sha256'])
            self.assertEqual(inverse.candidate_source(relative, previous), current)
            if item['before_sha256']:
                self.assertEqual(inverse.original_source(relative, current, CURRENT), previous)
                self.assertEqual(inverse.original_source(relative, current.decode(), CURRENT), previous.decode())
        relative = 'Tests/AppUnitTests/ProjectEditPreparedReviewTests.swift'
        original = inverse.original_source(relative, (CURRENT / relative).read_text(), CURRENT)
        self.assertEqual(original.count('func test'), 7)
        self.assertEqual((CURRENT / 'Tests/AppUnitTests/ProjectEditPreparedReviewTests.swift').read_text().count('func test'), 10)

    def test_partial_duplicate_moved_crlf_and_unrelated_sources_fail_closed(self):
        relative = 'App/ProjectEditView.swift'
        source = (CURRENT / relative).read_text()
        addition = '    var canReview: Bool { currentReviewLease() != nil }\n'
        for changed in [source + '\n', source.replace('\n', '\r\n'), source.replace(addition, ''),
                        source.replace(addition, addition + addition), source.replace(addition, '') + addition,
                        source.replace('.disabled(!model.canReview)', '.disabled(!model.canEdit)'),
                        source.replace('loadedSession == coordinator.session', 'true')]:
            with self.subTest(sha=inverse.digest(changed.encode())):
                with self.assertRaises(ValueError):
                    inverse.original_source(relative, changed, CURRENT)

    def test_missing_or_changed_regression_authority_or_inventory_is_rejected(self):
        plan = inverse.contract()
        relatives = list(plan['scope']) + list(plan['unchanged_dependencies'])
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for relative in relatives:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(CURRENT / relative, path)
            for relative in relatives:
                path = root / relative
                original = path.read_bytes()
                path.write_bytes(original + b'\n')
                with self.subTest(relative=relative), self.assertRaises(ValueError):
                    inverse.verify_current(root)
                path.unlink()
                with self.assertRaises(FileNotFoundError):
                    inverse.verify_current(root)
                path.write_bytes(original)

    def test_new_check_cannot_be_misrepresented_as_historical_source(self):
        relative = 'Tests/ContractChecks/test_project_edit_review_availability.py'
        with self.assertRaises(ValueError):
            inverse.original_source(relative, (CURRENT / relative).read_bytes(), CURRENT)

    def test_unowned_inputs_are_unchanged(self):
        self.assertEqual(inverse.original_source('unowned.swift', b'abc', CURRENT), b'abc')

    def test_exact_inverse_feeds_existing_version_row_guard(self):
        path = CURRENT / 'Tests/ContractChecks/test_ci138_version_row_source.py'
        spec = importlib.util.spec_from_file_location('existing_version_row_guard', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        relative = 'App/ProjectEditView.swift'
        current = (CURRENT / relative).read_text()
        self.assertEqual(module.digest(module.restore_version_row(current)), module.PREVIOUS_SHA)
        with self.assertRaises(AssertionError):
            module.restore_version_row(current + '\n')
        previous = inverse.original_source(relative, current, CURRENT)
        self.assertEqual(module.digest(previous), module.CURRENT_SHA)
        self.assertEqual(module.digest(module.restore_version_row(previous)), module.PREVIOUS_SHA)


if __name__ == '__main__':
    unittest.main()

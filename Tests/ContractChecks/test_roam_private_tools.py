"""Run the roam private tools source contracts with lexical negative controls.
These checks do not compile or run Swift, XCUITest, or any backend.
"""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RoamPrivateToolsContracts(unittest.TestCase):
    def run_checker(self, root):
        return subprocess.run([sys.executable, str(ROOT / 'tools/check_roam_private_tools.py'), '--root', str(root), '--base', str(ROOT)],
                              capture_output=True, text=True)

    def test_reviewed_source_contracts_all_pass(self):
        result = self.run_checker(ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS: 30 roam private tools source contracts', result.stdout)

    def test_catalog_has_every_reviewed_key(self):
        result = subprocess.run([sys.executable, str(ROOT / 'tools/build_roam_private_tools_localizations.py'), '--root', str(ROOT), '--check'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def check_mutant(self, path, before, after, expected):
        source = (ROOT / path).read_text()
        self.assertEqual(source.count(before), 1, before)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / path).parent.mkdir(parents=True)
            (root / path).write_text(source.replace(before, after))
            result = self.run_checker(root)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertEqual(result.stderr.strip().splitlines()[-1], 'AssertionError: ' + expected)

    def test_production_cannot_ship_an_approval(self):
        self.check_mutant('App/AppCompositionRoot.swift',
                          'roamPrivateToolsReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamPrivateToolsAccess? = { _ in nil },',
                          'roamPrivateToolsReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamPrivateToolsAccess? = { try? RoamPrivateToolsAccess(context: $0, approval: .init(baseURL: $0.baseURL, namespace: "x", accountID: 1, paths: RoamPrivateToolsRoute.reads)) },',
                          'Production composition supplies no approval')

    def test_409_capsule_conflict_must_not_become_a_refusal(self):
        self.check_mutant('Core/RoamPassportPrivateToolsReading.swift', 'body: .json(draft.json), rejectedCodes: [400], token: token)',
                          'body: .json(draft.json), rejectedCodes: [400, 409], token: token)', 'Capsule refusals are 400 only; 409 stays unconfirmed')

    def test_writes_cannot_skip_their_approval(self):
        self.check_mutant('Core/RoamPassportPrivateToolsReading.swift',
                          'if write { guard access.allowsWrites else { throw RoamPrivateWriteError.writesDisabled } }', '',
                          'Writes need their own approval')

    def test_create_cannot_dispatch_from_the_form_button(self):
        self.check_mutant('App/RoamPassportPrivateToolsViews.swift',
                          'Button("roam.capsule.seal") { model.prepareCreate(body: text, unlockDate: unlockDate) }',
                          'Button("roam.capsule.seal") { Task { _ = await model.confirmCreate() } }',
                          'Create dispatches only from the confirmation dialog')

    def test_locked_capsules_never_keep_body_text(self):
        self.check_mutant('Core/RoamPassportPrivateTools.swift', 'body: open ? raw.body : nil', 'body: raw.body',
                          'Capsule bodies only survive for OPEN capsules')

    def test_partial_export_is_never_shareable(self):
        self.check_mutant('Core/RoamPassportPrivateCoordinators.swift',
                          'guard live(), phase == .complete, let file, file.rows > 0, !file.isExpired(now: tools.now) else { return nil }',
                          'guard let file else { return nil }',
                          'Export file only after the final chunk and never for zero rows')


if __name__ == '__main__':
    unittest.main()

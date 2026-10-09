"""Exact combined follow-on boundaries, including current and cached rejection.

These portable source checks do not claim Apple execution or measured timing.
All mutation probes use copied inputs or restore scoped historical-cache bytes.
"""
from contextlib import contextmanager
from pathlib import Path
import os
import shutil
import sys
import unittest
from unittest.mock import patch

from tools import ci138_followon_projection as followons
from tools import run138_current_source_projection as entry
from tools import run138_editor_readiness as readiness
from tools import run129_repair_planning as run129
from tools.tests.test_run138_editor_readiness import copied_inputs


ROOT = readiness.ROOT
TEMPLATE = 'Tests/AppUITests/ProjectStoryTemplateFlowSupport.swift'
HANDSHAKE = 'tools/branch_history_handshake_planning.py'
BRIDGE = 'tools/ci138_followon_handshake_contract.json'
TEMPLATE_CURRENT275_SHA = '064ab31b2caa2823c40c695a57a44c89668abc1cc2e44a2ddc1a9616725353ed'
TEMPLATE_ROOT6_SHA = '13d1f72711fe6341af73f049c180cfaa036c8b7084ae7ec20d8a168d1c821171'
HANDSHAKE_LIFETIME_SHA = 'bd68eb5ee193b0fee283a86139adf965a591878fcba556865dd187db893c79bc'
HANDSHAKE_COUPON_SHA = 'ae81fc1b5d9a5e4558931d5b31bd083593ac45b215a03923da47f9df991fd592'


@contextmanager
def component_inputs():
    """Include the coupon package's independently frozen production boundaries."""
    with copied_inputs() as root:
        for relative in followons.coupon().contract()['protected_source_sha256']:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        yield root


class CI138FollowonIntegrationTests(unittest.TestCase):
    def admit(self, root):
        return readiness.validate_current(root / 'Tests/AppUITests',
                                          root / 'tools/ui_duration_weights.json', root)

    def previous_ui(self, root):
        return readiness.previous_directory(root / 'Tests/AppUITests',
                                            root / 'tools/ui_duration_weights.json', root)

    def test_template_inverts_arrival_before_direction_to_fixed_preimages(self):
        live = (ROOT / TEMPLATE).read_bytes()
        intermediate = followons.source_before_followons(TEMPLATE, live)
        original = readiness.original_source(TEMPLATE, live)
        self.assertEqual(readiness.digest(intermediate), TEMPLATE_CURRENT275_SHA)
        self.assertEqual(readiness.digest(original), TEMPLATE_ROOT6_SHA)
        self.assertEqual(followons.story().forward(TEMPLATE, intermediate), live)
        old = b'tap("projectStoryMedia.gap." + anchor, app, top: true)'
        new = b'tap("projectStoryMedia.gap." + anchor, app)'
        self.assertEqual(intermediate.count(new), 1)
        self.assertEqual(intermediate.replace(new, old, 1), original)
        # A historical or partially reverted input is never accepted as live.
        for wrong in (intermediate, original, live + b'\n', live.replace(new, old, 1)):
            with self.subTest(sha=readiness.digest(wrong)), self.assertRaises(ValueError):
                readiness.original_source(TEMPLATE, wrong)

    def test_coupon_context_keeps_its_postimages_and_restores_other_layers(self):
        with component_inputs() as root:
            context = entry.frozen_context('coupon', root)
            self.assertFalse((context.root / 'Tests/AppUITests/ProjectEditReviewReadinessFlowTests.swift').exists())
            keys, classes = readiness.inventory(context.root / 'Tests/AppUITests')
            self.assertEqual((len(keys), len(classes)), (736, 162))
            previous = readiness.contract(root)['previous_ui_sources']
            coupon = followons.coupon().contract()
            for name, expected in previous.items():
                relative = 'Tests/AppUITests/' + name
                if relative in coupon['files']:
                    expected = coupon['files'][relative]['after_sha256']
                self.assertEqual(readiness.digest((context.root / relative).read_bytes()), expected, relative)
            self.assertEqual(readiness.digest((context.root / HANDSHAKE).read_bytes()), HANDSHAKE_COUPON_SHA)
            self.assertEqual(entry.validate_coupon_component(root), coupon)
            self.assertEqual(followons.coupon().validate_current(context.root), coupon)
            self.assertEqual(followons.coupon().complete_method_costs(), {
                'OwnedCouponCodeJourneyUITests.testOwnedListDetailCancelConfirmBackAndReopenRequireFreshConsent': 380,
                'SquareWorkspaceFlowTests.testChineseComposerAndLocalDraftEntry': 110,
                'SquareWorkspaceFlowTests.testSuspendedRecoveryDisablesNewDraftTypingAndCompetingResume': 120,
                'ApprovedTopicFrozenCoverPublicationFlowTests.testApprovedCoverConfirmationAndUnknownPublicationRestoreOriginalManifest': 940,
            })

    def test_coupon_older_handshake_is_separate_from_all_and_ui52_contexts(self):
        with component_inputs() as root:
            contexts = {stage: entry.frozen_context(stage, root) for stage in ('all', 'ui52', 'coupon')}
            self.assertEqual(len({context.root for context in contexts.values()}), 3)
            self.assertEqual(readiness.digest(entry.historical_entry_bytes(root, HANDSHAKE)), HANDSHAKE_LIFETIME_SHA)
            self.assertEqual(readiness.digest(entry.oldest_handshake_bytes(root)), HANDSHAKE_COUPON_SHA)
            for stage in ('all', 'ui52'):
                self.assertEqual(readiness.digest((contexts[stage].root / HANDSHAKE).read_bytes()), HANDSHAKE_LIFETIME_SHA)
            for relative, row in readiness.ui52_layer().contract(root)['files'].items():
                for stage, expected in (('ui52', row['after_sha256']), ('all', row['before_sha256']), ('coupon', row['before_sha256'])):
                    self.assertEqual(readiness.digest((contexts[stage].root / relative).read_bytes()), expected)

    def test_every_owned_ui_postimage_and_historical_input_is_fail_closed(self):
        with copied_inputs() as root:
            self.admit(root)
            for relative in sorted(followons.owned_ui_paths()):
                path = root / relative
                saved = path.read_bytes()
                historical = followons.source_before_followons(relative, saved)
                for mode, changed in (('unknown', saved + b'\n'), ('historical', historical)):
                    with self.subTest(path=relative, mode=mode):
                        try:
                            path.write_bytes(changed)
                            with self.assertRaises(ValueError):
                                self.admit(root)
                            with self.assertRaises(ValueError):
                                self.previous_ui(root)
                        finally:
                            path.write_bytes(saved)
            self.admit(root)

    def test_current_ui_and_availability_dependencies_are_rechecked_before_cache_reuse(self):
        with component_inputs() as root:
            previous = self.previous_ui(root)
            contexts = {stage: entry.frozen_context(stage, root) for stage in ('all', 'ui52', 'coupon')}
            availability = followons.availability().contract()
            paths = (followons.owned_ui_paths() | set(availability['scope']) |
                     set(availability['unchanged_dependencies']) |
                     set(followons.coupon().contract()['protected_source_sha256']) |
                     {p for p in readiness.ui52_layer().contract()['protected_sha256']
                      if not p.startswith('Tests/AppUITests/')})
            for relative in sorted(paths):
                with self.subTest(path=relative):
                    path = root / relative
                    saved = path.read_bytes()
                    try:
                        path.write_bytes(saved + b'\n')
                        with self.assertRaises(ValueError):
                            self.previous_ui(root)
                        for stage in contexts:
                            with self.assertRaises(ValueError):
                                entry.frozen_context(stage, root)
                    finally:
                        path.write_bytes(saved)
            self.assertEqual(self.previous_ui(root), previous)
            for stage, context in contexts.items():
                self.assertIs(entry.frozen_context(stage, root), context)

    def test_every_direct_context_dependency_rejects_same_timestamp_mutation(self):
        with component_inputs() as root:
            contexts = {stage: entry.frozen_context(stage, root) for stage in ('all', 'ui52', 'coupon')}
            plan = readiness.contract(root)
            paths = set(plan['followon_support_sha256']) | {'tools/run138_editor_readiness.py'}
            for relative in sorted(paths):
                path = root / relative
                saved = path.read_bytes()
                metadata = path.stat()
                try:
                    # Same size and original timestamps; raw-byte admission is mandatory.
                    path.write_bytes(saved[:-1] + bytes([saved[-1] ^ 1]))
                    os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
                    with self.subTest(path=relative), self.assertRaises(ValueError):
                        self.admit(root)
                    for stage in contexts:
                        with self.subTest(path=relative, stage=stage), self.assertRaises(ValueError):
                            entry.frozen_context(stage, root)
                finally:
                    path.write_bytes(saved)
                    os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
            for stage, context in contexts.items():
                self.assertIs(entry.frozen_context(stage, root), context)

    def test_all_copied_context_inputs_are_rehashed_before_every_cache_reuse(self):
        # The full copied tree includes historical guards beyond the direct
        # current admission dependency set; none may become stale in a cache.
        with component_inputs() as root:
            relative = 'Core/UnownedContextProof.swift'
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'enum UnownedContextProof {}\n')
            contexts = {stage: entry.frozen_context(stage, root) for stage in ('all', 'ui52', 'coupon')}
            for mode in ('changed', 'missing', 'additional'):
                try:
                    if mode == 'changed':
                        path.write_bytes(b'enum MutatedContextProof {}\n')
                    elif mode == 'missing':
                        path.unlink()
                    else:
                        (root / 'tools/unlisted_history_contract.json').write_bytes(b'{"new":true}\n')
                    for stage in contexts:
                        with self.subTest(mode=mode, stage=stage), self.assertRaisesRegex(ValueError, 'Current historical-context input tree'):
                            entry.frozen_context(stage, root)
                finally:
                    path.write_bytes(b'enum UnownedContextProof {}\n')
                    (root / 'tools/unlisted_history_contract.json').unlink(missing_ok=True)
            for stage, context in contexts.items():
                self.assertIs(entry.frozen_context(stage, root), context)

    def test_unreadable_subtrees_fail_closed_in_current_cached_and_fresh_contexts(self):
        from unittest.mock import patch
        with component_inputs() as root:
            contexts = {stage: entry.frozen_context(stage, root) for stage in ('all', 'ui52', 'coupon')}
            real_scandir = entry.os.scandir
            for tree in (root, *(context.root for context in contexts.values())):
                blocked = tree / 'tools/unreadable-context-input'
                blocked.mkdir(parents=True)
                (blocked / 'real_fixture.json').write_text('{"source":true}\n')
                def fail_only_blocked(path):
                    if Path(path) == blocked:
                        raise PermissionError('simulated unreadable source subtree')
                    return real_scandir(path)
                try:
                    with patch.object(entry.os, 'scandir', side_effect=fail_only_blocked):
                        with self.assertRaisesRegex(ValueError, 'Unreadable historical-context input tree'):
                            entry.tree_sha256(tree)
                        stages = contexts if tree == root else [stage for stage, context in contexts.items() if context.root == tree]
                        for stage in stages:
                            with self.subTest(stage=stage, tree=str(tree)), self.assertRaisesRegex(ValueError, 'Unreadable historical-context input tree'):
                                entry.frozen_context(stage, root)
                finally:
                    shutil.rmtree(blocked)
            for stage, context in contexts.items():
                self.assertIs(entry.frozen_context(stage, root), context)
        with component_inputs() as root:
            blocked = root / 'tools/unreadable-context-input'
            blocked.mkdir(parents=True)
            real_scandir = entry.os.scandir
            def fail_only_fresh_blocked(path):
                if Path(path) == blocked:
                    raise PermissionError('simulated unreadable source subtree')
                return real_scandir(path)
            with patch.object(entry.os, 'scandir', side_effect=fail_only_fresh_blocked):
                with self.assertRaisesRegex(ValueError, 'Unreadable historical-context input tree'):
                    entry.frozen_context('coupon', root)

    def test_non_generated_symlinks_cannot_escape_current_or_cached_tree_validation(self):
        with component_inputs() as root:
            contexts = {stage: entry.frozen_context(stage, root) for stage in ('all', 'ui52', 'coupon')}
            target_file = root / 'tools/review_availability_contract.json'
            targets = [(root / 'Core', True), (target_file, False), (root / 'missing-target', False)]
            for target, directory in targets:
                link = root / 'unreviewed-source-link'
                try:
                    link.symlink_to(target, target_is_directory=directory)
                    with self.assertRaisesRegex(ValueError, 'Unreviewed symlink'):
                        entry.tree_sha256(root)
                    for stage in contexts:
                        with self.subTest(target=str(target), stage=stage), self.assertRaisesRegex(ValueError, 'Unreviewed symlink'):
                            entry.frozen_context(stage, root)
                finally:
                    link.unlink(missing_ok=True)
            for stage, context in contexts.items():
                self.assertIs(entry.frozen_context(stage, root), context)
        # A link already present at first construction must fail too.
        with component_inputs() as root:
            link = root / 'preexisting-source-link'
            try:
                link.symlink_to(root / 'Core', target_is_directory=True)
                with self.assertRaisesRegex(ValueError, 'Unreviewed symlink'):
                    entry.frozen_context('coupon', root)
            finally:
                link.unlink(missing_ok=True)

    def test_nested_generated_names_and_unlisted_valid_sources_remain_input(self):
        with component_inputs() as root:
            # These are ordinary fixture/preimage/source paths, not the exact
            # repository-root generated destinations named by the policy.
            inputs = {
                'Tests/ContractChecks/fixtures/DerivedData/source-contract.json': b'{"original":true}\n',
                'tools/tests/fixtures/.build/original-preimage.txt': b'exact historical preimage\n',
                'tools/tests/fixtures/.git/reviewed-source.py': b'VALUE = 1\n',
                'Core/UnlistedInput.swift': b'enum UnlistedInput {}\n',
                'tools/unlisted_input_contract.json': b'{"version":1}\n',
            }
            contexts = {stage: entry.frozen_context(stage, root) for stage in ('all', 'ui52', 'coupon')}
            for relative, raw in inputs.items():
                path = root / relative
                try:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(raw)
                    self.assertIn(relative, entry.tree_sha256(root))
                    for stage in contexts:
                        with self.subTest(path=relative, stage=stage), self.assertRaisesRegex(ValueError, 'Current historical-context input tree'):
                            entry.frozen_context(stage, root)
                finally:
                    path.unlink(missing_ok=True)
            for stage, context in contexts.items():
                self.assertIs(entry.frozen_context(stage, root), context)

    def test_generated_outputs_are_excluded_consistently_without_source_extension_filter(self):
        with component_inputs() as root:
            contexts = {stage: entry.frozen_context(stage, root) for stage in ('all', 'ui52', 'coupon')}
            artifacts = ['.git/config', '__pycache__/module.pyc', '.build/debug/Module.swiftmodule',
                         'DerivedData/Build/generated.swift', 'Questify.xcodeproj/xcuserdata/state.xcuserstate',
                         '.DS_Store', 'tools/__pycache__/loose.pyc',
                         'Questify.xcodeproj/project.xcworkspace/xcuserdata/state.xcuserstate']
            for stage, context in contexts.items():
                for tree in (root, context.root):
                    for relative in artifacts:
                        path = tree / relative
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_bytes(b'generated artifact')
                self.assertIs(entry.frozen_context(stage, root), context)
                for relative in artifacts:
                    (root / relative).write_bytes(b'changed generated artifact')
                self.assertIs(entry.frozen_context(stage, root), context)
                inventory = entry.tree_sha256(root)
                self.assertFalse(set(artifacts) & set(inventory))
                self.assertIn('tools/run138_editor_readiness.py', inventory)
                self.assertIn('tools/review_availability_contract.json', inventory)
            # Fresh contexts copy exactly the same source scope, not artifacts.
            with component_inputs() as fresh:
                for relative in artifacts:
                    path = fresh / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(b'generated artifact')
                context = entry.frozen_context('coupon', fresh)
                self.assertTrue(all(not (context.root / path).exists() for path in artifacts))

    def test_changed_current_bridge_is_rejected_even_with_cached_coupon_context(self):
        with component_inputs() as root:
            context = entry.frozen_context('coupon', root)
            path = root / BRIDGE
            saved = path.read_bytes()
            try:
                path.write_bytes(saved + b'\n')
                with self.assertRaises(ValueError):
                    entry.oldest_handshake_bytes(root)
                with self.assertRaises(ValueError):
                    self.admit(root)
                with self.assertRaises(ValueError):
                    entry.frozen_context('coupon', root)
            finally:
                path.write_bytes(saved)
            self.assertIs(entry.frozen_context('coupon', root), context)

    def test_scoped_historical_cache_mutations_are_rejected_and_restored(self):
        with component_inputs() as root:
            previous = self.previous_ui(root)
            path = previous / Path(TEMPLATE).name
            saved = path.read_bytes()
            try:
                path.write_bytes(saved + b'\n')
                with self.assertRaisesRegex(ValueError, 'Cached exact historical UI'):
                    self.previous_ui(root)
            finally:
                path.write_bytes(saved)
            self.assertEqual(self.previous_ui(root), previous)
            for stage in ('all', 'ui52', 'coupon'):
                context = entry.frozen_context(stage, root)
                for relative in (TEMPLATE, 'App/ProjectEditView.swift', HANDSHAKE):
                    with self.subTest(stage=stage, path=relative):
                        path = context.root / relative
                        saved = path.read_bytes()
                        try:
                            path.write_bytes(saved + b'\n')
                            with self.assertRaisesRegex(ValueError, 'Cached historical review context'):
                                entry.frozen_context(stage, root)
                        finally:
                            path.write_bytes(saved)
                self.assertIs(entry.frozen_context(stage, root), context)

    def test_run129_materialization_admits_once_then_reads_projected_sources(self):
        with copied_inputs() as root:
            ui = root / 'Tests/AppUITests'
            target = root / 'materialized-baseline'
            # Normalize the supported direct/package import alias, retaining the
            # real validator and real historical reads behind both spies.
            with patch.dict(sys.modules, {'run138_current_source_projection': entry}), \
                    patch.object(entry, 'previous_directory', wraps=entry.previous_directory) as project, \
                    patch.object(readiness, 'validate_current', wraps=readiness.validate_current) as admit, \
                    patch.object(run129, 'historical_source', wraps=run129.historical_source) as historical:
                run129.materialize_baseline_ui(target, ui)
            project.assert_called_once_with(ui)
            admit.assert_called_once()
            self.assertEqual(historical.call_count, 164)
            source_directories = {call.args[0].parent for call in historical.call_args_list}
            self.assertEqual(len(source_directories), 1)
            projected = source_directories.pop()
            self.assertNotEqual(projected, ui)
            self.assertEqual(projected.name, 'AppUITests')
            self.assertFalse((projected / 'ProjectEditReviewReadinessFlowTests.swift').exists())
            index = run129.source_index()['historical_ui_sources']
            self.assertEqual({path.name for path in target.iterdir()}, {Path(name).name for name in index})
            for relative, row in index.items():
                self.assertEqual(readiness.digest((target / Path(relative).name).read_bytes()), row['sha256'])

    def test_run129_materialization_rejects_current_mutation_before_writing_files(self):
        with copied_inputs() as root:
            ui = root / 'Tests/AppUITests'
            path = root / TEMPLATE
            path.write_bytes(path.read_bytes() + b'\n')
            target = root / 'rejected-baseline'
            with patch.dict(sys.modules, {'run138_current_source_projection': entry}), \
                    patch.object(entry, 'previous_directory', wraps=entry.previous_directory) as project, \
                    patch.object(run129, 'historical_source', wraps=run129.historical_source) as historical:
                with self.assertRaises(ValueError):
                    run129.materialize_baseline_ui(target, ui)
            project.assert_called_once_with(ui)
            historical.assert_not_called()
            self.assertFalse(any(target.rglob('*')))


if __name__ == '__main__':
    unittest.main()

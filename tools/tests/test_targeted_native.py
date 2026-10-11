"""Small, synthetic diagnostic controls; no Apple execution or repository copies."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('targeted_native_runner', TOOLS / 'run_targeted_native.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
SELECTION = runner.read_json(TOOLS / 'targeted_native_selection.json')
SOURCE = Path(os.environ.get('TARGETED_NATIVE_SOURCE_ROOT', str(TOOLS.parent)))
UUID = '01234567-0123-0123-0123-012345678901'


def static_tree_records(root, before):
    records = []
    for row in SELECTION['static_repair_changes']:
        if not before or row['status'] == 'M':
            records.append('100644 blob ' + row['before_blob' if before else 'after_blob'] + '\t' + row['path'])
    for relative, baseline in runner.STATIC_DIAGNOSTIC_BASE_BLOBS.items():
        raw = (root / relative).read_bytes()
        blob = baseline if before else runner.hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
        records.append('100644 blob ' + blob + '\t' + relative)
    return records


def scope_transport(command, root):
    if command[1:3] == ['rev-parse', 'HEAD']: return 'a' * 40
    if command[1:3] == ['rev-parse', 'HEAD^{tree}']: return 'b' * 40
    if command[1:3] == ['rev-parse', runner.BASE_COMMIT + '^{tree}']: return runner.BASE_TREE
    if command[1:3] == ['rev-parse', runner.HISTORICAL_BASE_COMMIT + '^{tree}']: return runner.HISTORICAL_BASE_TREE
    if command[1] == 'rev-list': return 'a' * 40 + ' ' + runner.BASE_COMMIT
    if command[1:3] == ['cat-file', '-e']: return ''
    if command[1:3] == ['cat-file', '-p']:
        return 'tree ' + runner.CREATOR_TREE + '\nparent ' + runner.HISTORICAL_BASE_COMMIT + '\n\nPublished creator witness'
    if command[1] == 'status': return ''
    if command[1] == 'diff':
        changes = (runner.ALLOWED_CHANGES if command[3] == runner.BASE_COMMIT else
                   runner.PARENT_HISTORY_CHANGES if command[3] == runner.CREATOR_COMMIT else
                   runner.HISTORICAL_ALLOWED_CHANGES)
        return '\n'.join(changes)
    if command[1] == 'ls-tree':
        if tuple(command[5:]) == runner.CREATOR_PATHS:
            before = command[3] == runner.HISTORICAL_BASE_TREE
            rows = ['100644 blob ' + r['before_blob' if before else 'after_blob'] + '\t' + r['path']
                    for r in SELECTION['creator_changes'] if not before or r['status'] == 'M']
        elif tuple(command[5:]) == runner.CREATOR_PARENT_PATHS:
            before = command[3] == runner.CREATOR_TREE
            rows = ['100644 blob ' + r['before_blob' if before else 'after_blob'] + '\t' + r['path']
                    for r in SELECTION['creator_parent_changes']]
        else:
            rows = static_tree_records(root, command[3] == runner.BASE_TREE)
        return '\0'.join(rows) + '\0'
    raise AssertionError(command)


def xctests(methods, target):
    return {'testNodes': [{'nodeType': 'Test Plan', 'name': 'Questify', 'children': [
        {'nodeType': 'Unit test bundle', 'name': target, 'children': [
            {'nodeType': 'Test Case', 'name': method.rsplit('/', 1)[-1] + '()',
             'nodeIdentifier': '/'.join(method.split('/')[1:]) + '()', 'result': 'Passed'} for method in methods]}]}]}


def core_transcript(methods, status='passed'):
    lines = []
    for method in methods:
        target, cls, name = method.split('/')
        identity = f"Test Case '-[{target}.{cls} {name}]' "
        lines.extend([identity + 'started.', identity + status + ' (0.001 seconds).'])
    return ('\n'.join(lines) + '\n').encode()


def summary(count):
    return {'totalTestCount': count, 'passedTests': count, 'failedTests': 0, 'skippedTests': 0,
            'expectedFailures': 0, 'devicesAndConfigurations': [{'device': {'deviceId': UUID}}]}


class SelectionAndCommands(unittest.TestCase):
    def test_actual_bound_source_and_all_65_declarations(self):
        self.assertEqual(runner.validate_selection(copy.deepcopy(SELECTION), SOURCE), SELECTION)
        self.assertEqual([len(g['methods']) for g in SELECTION['groups']], [44, 14, 7])
        self.assertEqual(len(set(m for g in SELECTION['groups'] for m in g['methods'])), 65)

    def test_original_29_methods_are_preserved_and_only_16_added(self):
        legacy = ['QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedRefreshNeverSurvivesOwnerLeaseABAExpiryOrCancellation', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedSnapshotPreparationClearsRevokedScopeBeforeAnotherRequest', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testClonedTransportRejectsLateLeaseReplacementTokenRoleAndErrors', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCurrent401ExpiresOnlyCurrentOwner', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testGuestDefaultNilRevokedReaderAndReplacementNeverAdoptLease', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLateShelfAndDetailSuccess401ErrorNeverApplyAcrossLifetimeChanges', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLoadedReadOnlyRefreshSnapshotSurvives503ThenReplacesAndClears', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testNormalFactoryPagedShelfDetailAndEveryWriterRemainOff', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOuterClonesOnlyAdmitExactReadsAndDenyAllAdjacentMutations', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOwnerConfigurationFactoryDoesNotAlterLocalDraftAndClearsOnLeaseChange', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testSearchedPageElevenLegacyStoryRequiresFreshOwnedDetail', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testShelfLeaseChangesPreserveUnsavedLocalEditorAndDormantAuthority', 'QuestifyCoreTests/TemplateAuthoringHTTPTests/testRefreshSnapshotCannotReplaceHundredRowWritePreflightOrOldReview', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAlreadyCancelledRefreshClearsSnapshotWithoutDispatch', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAuthContractUnknownAndCancellationFailuresClearRefreshSnapshot', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testCachedRefreshLifetimeTransitionsAndABAFenceAllLateResults', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testContinuationAuthAndContractErrorsClearRowsButOverlapRemainsRetryable', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testNewKeywordNeverDisplaysPreviousQuerySnapshot', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testOnlyExplicitTransientFailuresRetainSnapshotAndRequireFirstPageRetry', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshAtHundredPageBoundaryRestartsAtOneWithoutPage101', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshReplacesOverlappingIDsAndValidEmptyClearsSnapshot', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testSameKeywordNewGenerationRejectsOldSuccessAndError', 'QuestifyUITests/TemplateOwnShelfFlowTests/testAccountChangeDismissesReviewAndSignoutClearsShelf', 'QuestifyUITests/TemplateOwnShelfFlowTests/testChineseLargeTextCanCancelReview', 'QuestifyUITests/TemplateOwnShelfFlowTests/testDefaultDisabledHasNoMutationConfirmation', 'QuestifyUITests/TemplateOwnShelfFlowTests/testDeleteRequiresSeparateReviewAndSimulationIsLabelled', 'QuestifyUITests/TemplateOwnShelfFlowTests/testLibraryReviewShowsIdentityAndCancellationDoesNotSubmit', 'QuestifyUITests/TemplateOwnShelfFlowTests/testOwnedDetailBackAndReopenKeepsStableDestination', 'QuestifyUITests/TemplateOwnShelfFlowTests/testUnknownLocksBothActionsAcrossReopen']
        actual = {m for g in SELECTION['groups'] for m in g['methods'] if '/TemplateOwnShelfStateProjectionTests/' not in m}
        self.assertEqual(len(legacy), 29)
        self.assertTrue(set(legacy).issubset(actual))
        self.assertEqual(len(actual - set(legacy)), 16)
        expected = (('QuestifyAppUnitTests/MerchantDecorTagPickerTests/testDuplicateOverLimitHistoricalTagsStayUnchangedOnOpenCancelAndInvalidOwner', 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'), ('QuestifyAppUnitTests/MerchantDecorTagPickerTests/testSemicolonTagApplyCancelAndReopenPreserveExactLabels', 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedRefreshNeverSurvivesOwnerLeaseABAExpiryOrCancellation', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedSnapshotPreparationClearsRevokedScopeBeforeAnotherRequest', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testClonedTransportRejectsLateLeaseReplacementTokenRoleAndErrors', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCurrent401ExpiresOnlyCurrentOwner', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testGuestDefaultNilRevokedReaderAndReplacementNeverAdoptLease', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLateShelfAndDetailSuccess401ErrorNeverApplyAcrossLifetimeChanges', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLoadedReadOnlyRefreshSnapshotSurvives503ThenReplacesAndClears', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testNormalFactoryPagedShelfDetailAndEveryWriterRemainOff', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOuterClonesOnlyAdmitExactReadsAndDenyAllAdjacentMutations', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOwnerConfigurationFactoryDoesNotAlterLocalDraftAndClearsOnLeaseChange', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testSearchedPageElevenLegacyStoryRequiresFreshOwnedDetail', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testShelfLeaseChangesPreserveUnsavedLocalEditorAndDormantAuthority', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyCoreTests/MerchantDecorTagDraftTests/testHistoricalLabelsRemainByteExactUntilExplicitRemoval', 'Tests/CoreTests/MerchantDecorTagDraftTests.swift'), ('QuestifyCoreTests/MerchantDecorTagDraftTests/testSemicolonCustomLabelRemainsOneLiteralTag', 'Tests/CoreTests/MerchantDecorTagDraftTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testAcknowledgedWriteReadbackFailureKeepsLockUntilReadOnlyRetry', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testCancelledReadDoesNotPublishLateServerExplanation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testFailedRefreshRetainsSnapshotAndShowsExplanation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testFinalPreWriteReadFailureDoesNotDispatchOrReuseConfirmation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testInitialReadFailureShowsExactServerMessageAndRetryClearsItWithoutWriting', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testLateFailureCannotPublishAfterSameAccountTokenReplacement', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testNewReadClearsPriorExplanationBeforeResponse', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testPrepareFailureKeepsSnapshotAndRequiresANewReview', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testSessionResetClearsPreviouslyDisplayedExplanation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testUnauthorizedCallbackInvalidatesFailureBeforePresentation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testUnknownWriteReadbackFailureAndMatchingRetryNeverUnlockOrResend', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testWhitespaceAndNonServerErrorsNeverBecomeUserText', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/TemplateAuthoringHTTPTests/testRefreshSnapshotCannotReplaceHundredRowWritePreflightOrOldReview', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAlreadyCancelledRefreshClearsSnapshotWithoutDispatch', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAuthContractUnknownAndCancellationFailuresClearRefreshSnapshot', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testCachedRefreshLifetimeTransitionsAndABAFenceAllLateResults', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testContinuationAuthAndContractErrorsClearRowsButOverlapRemainsRetryable', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testNewKeywordNeverDisplaysPreviousQuerySnapshot', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testOnlyExplicitTransientFailuresRetainSnapshotAndRequireFirstPageRetry', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshAtHundredPageBoundaryRestartsAtOneWithoutPage101', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshReplacesOverlappingIDsAndValidEmptyClearsSnapshot', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testSameKeywordNewGenerationRejectsOldSuccessAndError', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testAccountChangeDismissesReviewAndSignoutClearsShelf', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testChineseLargeTextCanCancelReview', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testDefaultDisabledHasNoMutationConfirmation', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testDeleteRequiresSeparateReviewAndSimulationIsLabelled', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testLibraryReviewShowsIdentityAndCancellationDoesNotSubmit', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testOwnedDetailBackAndReopenKeepsStableDestination', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testUnknownLocksBothActionsAcrossReopen', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'))
        actual_bindings = sorted((row['method'], row['source']) for g in SELECTION['groups'] for row in g['method_sources'] if '/TemplateOwnShelfStateProjectionTests/' not in row['method'])
        self.assertEqual(actual_bindings, list(expected))

    def test_per_method_source_binding_rejects_missing_swapped_duplicate_and_wrong_target(self):
        for mode in ['missing', 'duplicate', 'swapped', 'wrong-target', 'extra', 'unknown']:
            mutant = copy.deepcopy(SELECTION); rows = mutant['groups'][0]['method_sources']
            if mode == 'missing': rows.pop()
            elif mode == 'duplicate': rows[0] = rows[1]
            elif mode == 'swapped': rows[0]['source'] = 'Tests/CoreTests/ProfileEditTests.swift' if rows[0]['source'] != 'Tests/CoreTests/ProfileEditTests.swift' else 'Tests/CoreTests/MerchantDecorTagDraftTests.swift'
            elif mode == 'wrong-target': rows[0]['source'] = 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'
            elif mode == 'extra': rows.append(copy.deepcopy(rows[0]))
            else: rows[0]['source'] = 'Tests/CoreTests/Unknown.swift'
            pin = runner.hashlib.sha256(runner.encode(mutant).encode()).hexdigest()
            with self.subTest(mode=mode), mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', pin), self.assertRaises(ValueError):runner.validate_selection(mutant, SOURCE)

    def test_repinned_changed_method_and_duplicate_source_declaration_fail(self):
        mutant = copy.deepcopy(SELECTION); group = mutant['groups'][0]
        old = group['methods'][0]; changed = old + 'Other'
        group['methods'][0] = changed
        group['method_sources'][0]['method'] = changed
        group['methods'].sort(); group['method_sources'].sort(key=lambda row: row['method'])
        pin = runner.hashlib.sha256(runner.encode(mutant).encode()).hexdigest()
        with mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', pin), self.assertRaisesRegex(ValueError, 'fixed method/source identity'):
            runner.validate_selection(mutant, SOURCE)
        mutant = copy.deepcopy(SELECTION); path = SOURCE / mutant['groups'][0]['method_sources'][0]['source']
        text = path.read_text(); duplicate = text + '\n' + text
        for row in mutant['source_files']:
            if row['path'] == str(path.relative_to(SOURCE)): row['sha256'] = runner.hashlib.sha256(duplicate.encode()).hexdigest()
        pin = runner.hashlib.sha256(runner.encode(mutant).encode()).hexdigest()
        original_read = Path.read_text; original_digest = runner.digest
        def read(p, *args, **kwargs):return duplicate if p == path else original_read(p, *args, **kwargs)
        def digest(p):return runner.hashlib.sha256(duplicate.encode()).hexdigest() if p == path else original_digest(p)
        with mock.patch.object(Path, 'read_text', read), mock.patch.object(runner, 'digest', digest), mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', pin), self.assertRaisesRegex(ValueError, 'not uniquely declared'):
            runner.validate_selection(mutant, SOURCE)

    def test_duplicate_declaration_is_not_a_unique_method(self):
        source = 'final class Example: XCTestCase {\nfunc testOne() {}\nfunc testOne() {}\n}'
        self.assertEqual(runner.declared_methods(source, 'QuestifyCoreTests')['QuestifyCoreTests/Example/testOne'], 2)

    def test_nonboolean_version_and_exact_contract(self):
        for key, value in [('version', True), ('base_commit', 'a' * 40), ('base_tree', 'b' * 40),
                           ('name', 'all-tests'), ('branch', 'main'), ('repository', 'other/repo')]:
            mutant = copy.deepcopy(SELECTION); mutant[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                runner.validate_selection(mutant, SOURCE)

    def test_changed_source_hash_and_missing_guard_rejected(self):
        for mutation in ['change', 'missing', 'extra']:
            mutant = copy.deepcopy(SELECTION)
            if mutation == 'change': mutant['source_files'][0]['sha256'] = '0' * 64
            elif mutation == 'missing': mutant['source_files'].pop()
            else: mutant['source_files'].append({'path': '../private', 'sha256': '0' * 64})
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                runner.validate_selection(mutant, SOURCE)

    def test_empty_duplicate_target_and_wildcard_selectors_rejected(self):
        for mutation in ['empty', 'duplicate', 'target', 'wildcard', 'class', 'other-source', 'new-method']:
            mutant = copy.deepcopy(SELECTION); group = mutant['groups'][1]
            if mutation == 'empty': group['methods'] = []
            elif mutation == 'duplicate': group['methods'][0] = group['methods'][1]
            elif mutation == 'target': group['target'] = 'QuestifyUITests'
            elif mutation == 'wildcard': group['methods'][0] = 'QuestifyAppUnitTests/*/*'
            elif mutation == 'class': group['methods'][0] = 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests'
            elif mutation == 'other-source': group['method_sources'][0]['source'] = 'Core/TemplateAuthoringShelf.swift'
            else: group['methods'][0] += 'Other'
            group['methods'].sort()
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                runner.validate_selection(mutant, SOURCE)

    def test_core_filter_is_exact_set_without_full_suite_fallback(self):
        group = SELECTION['groups'][0]; command = runner.core_command(group, '/tmp/result.xml')
        pattern = re.compile(command[command.index('--filter') + 1])
        for method in group['methods']:
            swift_id = method.replace('/', '.', 1)
            self.assertIsNotNone(pattern.fullmatch(swift_id))
            for extra in ['Extra', '/extra', '()']:
                self.assertIsNone(pattern.fullmatch(swift_id + extra))
        self.assertIsNone(pattern.fullmatch('QuestifyCoreTests.TemplateAuthoringHTTPTests/testChangedBaselinePreventsWrite'))
        self.assertEqual(command[command.index('--num-workers') + 1], '1')
        with self.assertRaises(ValueError): runner.core_command({'methods': []}, '/tmp/result.xml')

    def test_every_xcode_method_has_its_own_exact_filter(self):
        for group in SELECTION['groups'][1:]:
            command = runner.xcode_test_command(group, '/tmp/one.xctestrun', UUID, '/tmp/one.xcresult')
            self.assertEqual([s for s in command if s.startswith('-only-testing:')], ['-only-testing:' + m for m in group['methods']])
            self.assertEqual(command.count('-destination'), 1)
            self.assertEqual(command[command.index('-parallel-testing-enabled') + 1], 'NO')
            self.assertEqual(command[command.index('-maximum-concurrent-test-simulator-destinations') + 1], '1')
            self.assertEqual(command[-1], 'test-without-building')
            self.assertNotIn('-allowProvisioningUpdates', command)

    def test_workflow_remains_additive_standard_and_independent(self):
        path = TOOLS.parent / '.github/workflows/native-targeted.yml'; text = path.read_text()
        active = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))
        self.assertEqual(re.findall(r'^    runs-on: (.*)$', active, re.M), ['macos-26'])
        self.assertEqual(re.findall(r'^  (\w+):$', active.split('jobs:', 1)[1], re.M), ['targeted'])
        self.assertIn('branches: [migration/native-ios]', active)
        self.assertEqual(re.findall(r'^      - (.+)$', active.split('permissions:', 1)[0], re.M), list(runner.PATHS))
        self.assertIn('  workflow_dispatch:', active)
        self.assertIn('  contents: read', active)
        self.assertIn('persist-credentials: false', active)
        self.assertIn('GIT_TERMINAL_PROMPT=0 git -c credential.helper= fetch --no-tags --depth=1 https://github.com/liboyang42-cpu/chengyin-ios.git ' + runner.HISTORICAL_BASE_COMMIT, active)
        self.assertIn('timeout-minutes: 45', active)
        self.assertIn('name: native-targeted-diagnostic', active)
        for forbidden in ['needs:', 'matrix:', 'upload-artifact', 'download-artifact', 'secrets.', 'required-native-gates', 'run_static_checks.py', 'ci_gates.py aggregate']:
            self.assertNotIn(forbidden, active)
        self.assertNotIn('group: native-ios-', active)

    def test_original_gates_project_schemes_and_product_sources_are_unchanged(self):
        for row in SELECTION['source_files']:
            self.assertEqual(runner.digest(SOURCE / row['path']), row['sha256'], row['path'])
        old = (SOURCE / '.github/workflows/native-ios.yml').read_text()
        self.assertIn('needs: static-checks', old)
        self.assertIn('needs: [static-checks, native, device-build, us-build, secrets, app-unit-tests, ui-tests]', old)
        self.assertIn('name: native\n', old)
        self.assertIn('SHARD_COUNT = 79', (SOURCE / 'tools/ci_gates.py').read_text())


class ReviewedCompileRepair(unittest.TestCase):
    def test_complete_predecessors_and_unrelated_contract_semantics_are_preserved(self):
        restored = runner.validate_reviewed_repairs(SELECTION, SOURCE)
        self.assertEqual(set(restored), set(runner.REPAIR_PATHS))
        self.assertEqual(runner.hashlib.sha256(restored[runner.REPAIR_PATHS[1]]).hexdigest(),
                         'b5dff5b209ce495bb46075dcc514a20ebd2e4561a9d1ea3aadb02b02f8d393c9')
        old = restored[runner.REPAIR_PATHS[0]].decode()
        current = (SOURCE / runner.REPAIR_PATHS[0]).read_text()
        hunk = SELECTION['reviewed_repairs'][0]['hunks'][0]
        self.assertEqual(current.replace(hunk['after'], '<STATE>'), old.replace(hunk['before'], '<STATE>'))
        self.assertEqual(re.findall(r'@State private var (\w+)=(\d+\.\d+)', current), [('horizontal', '0.5'), ('vertical', '0.5'), ('zoom', '1.0')])
        self.assertNotRegex(current, r'@State[^\n]*,')
        self.assertEqual(runner.digest(SOURCE / 'tools/run138_current_source_projection.py'),
                         'c0e6a5351bd024bdcbf8d1152bb4e8cb683cc5ff15e370627a14e229a1158727')

    def test_real_central_projection_accepts_current_support_and_exact_inverse(self):
        def load(path, name):
            spec = importlib.util.spec_from_file_location(name, path)
            module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
            return module
        current = load(TOOLS / 'run138_editor_readiness.py', 'targeted_current_readiness')
        projection = load(SOURCE / 'tools/run138_current_source_projection.py', 'targeted_current_projection')
        path = runner.REPAIR_PATHS[0]; row = SELECTION['reviewed_repairs'][0]
        with mock.patch.object(projection, 'planning', return_value=current):
            projection.validate_feature_batch_sources(SOURCE)
            old = projection.original_feature_batch_bytes(path, (SOURCE / path).read_bytes(), SOURCE)
            self.assertEqual(runner.hashlib.sha256(old).hexdigest(), row['before_sha256'])
            for raw in [old, (SOURCE / path).read_bytes() + b'\n']:
                with self.assertRaises(ValueError): projection.original_feature_batch_bytes(path, raw, SOURCE)
            changed = copy.deepcopy(current.contract(SOURCE))
            changed['feature_batch_support_sha256'][path] = row['before_sha256']
            with mock.patch.object(current, 'contract', return_value=changed), self.assertRaises(ValueError):
                projection.validate_feature_batch_sources(SOURCE)
            changed = copy.deepcopy(current.contract(SOURCE)); del changed['feature_batch_sources'][path]
            with mock.patch.object(runner, 'read_json', return_value=changed), self.assertRaises((ValueError, KeyError)):
                runner.validate_reviewed_repairs(SELECTION, SOURCE)

    def test_repair_inverse_rejects_off_hunk_changes_even_with_rehashed_postimage(self):
        for row in SELECTION['reviewed_repairs']:
            raw = (SOURCE / row['path']).read_bytes()
            for mutant in [raw + b'\n', raw.replace(row['hunks'][0]['after'].encode(), b'', 1),
                           raw + row['hunks'][0]['after'].encode()]:
                forged = copy.deepcopy(row); forged['after_sha256'] = runner.hashlib.sha256(mutant).hexdigest()
                with self.subTest(path=row['path']), self.assertRaises(ValueError):
                    runner.inverse_reviewed_repair(forged, mutant)
        for mode in ['missing', 'extra', 'support']:
            changed = copy.deepcopy(SELECTION)
            if mode == 'missing': changed['reviewed_repairs'].pop()
            elif mode == 'extra': changed['reviewed_repairs'].append(copy.deepcopy(changed['reviewed_repairs'][0]))
            else: changed['reviewed_repairs'][0]['after_sha256'] = '0' * 64
            with self.assertRaises(ValueError): runner.validate_selection(changed, SOURCE)


class Results(unittest.TestCase):
    def setUp(self):
        self.group = SELECTION['groups'][1]
        self.rows = [{'method': m, 'status': 'Passed'} for m in self.group['methods']]

    def test_xunit_reads_all_forty_four_real_cases(self):
        methods = SELECTION['groups'][0]['methods']
        xml = '<testsuites><testsuite>' + ''.join('<testcase classname="' + m.split('/')[0] + '.' + m.split('/')[1] + '" name="' + m.split('/')[2] + '()" />' for m in methods) + '</testsuite></testsuites>'
        rows = runner.parse_xunit(xml.encode()); runner.validate_outcomes(rows, methods, 0)
        self.assertEqual(len(rows), 44)

    def test_core_transcript_proves_execution_beyond_swiftpm_xunit(self):
        methods = SELECTION['groups'][0]['methods']
        xml = ('<testsuite>' + ''.join('<testcase classname="' + m.split('/')[0] + '.' + m.split('/')[1] + '" name="' + m.split('/')[2] + '" />' for m in methods) + '</testsuite>').encode()
        rows = runner.validate_core_evidence(xml, core_transcript(methods), methods, 0)
        self.assertEqual(len(rows), 44)
        # SwiftPM's successful child process xUnit looks identical for XCTSkip
        # and for a discovered method whose child process executes zero cases.
        mutants = [b'', b'Executed 0 tests, with 0 failures.\n', core_transcript(methods, 'skipped'),
                   core_transcript(methods, 'failed'), core_transcript(methods[:-1]),
                   core_transcript(methods + methods[:1]), core_transcript(methods).replace(b'started.', b'unknown.'),
                   core_transcript(methods).replace(b'QuestifyCoreTests.', b'OtherTarget.'),
                   core_transcript(methods).replace(b'started.\n', b'')]
        for transcript in mutants:
            with self.subTest(transcript=transcript[:90]), self.assertRaises(ValueError):
                runner.validate_core_evidence(xml, transcript, methods, 0)
        self.assertIn('--verbose', runner.core_command(SELECTION['groups'][0], '/tmp/result.xml'))
        self.assertIn('--skip-build', runner.core_command(SELECTION['groups'][0], '/tmp/result.xml'))

    def test_xunit_failures_skips_and_unknown_status_cannot_pass(self):
        for child in ['<failure/>', '<error/>', '<skipped/>']:
            xml = '<testsuite><testcase classname="QuestifyCoreTests.Example" name="testOne">' + child + '</testcase></testsuite>'
            rows = runner.parse_xunit(xml.encode())
            with self.assertRaises(ValueError): runner.validate_outcomes(rows, ['QuestifyCoreTests/Example/testOne'], 0)
        for xml in [b'<unknown/>', b'<testsuite><testcase classname="Wrong.Example" name="testOne"/></testsuite>', b'<testsuite><testcase classname="QuestifyCoreTests.Example" name="testOne" status="skipped"/></testsuite>']:
            with self.assertRaises(ValueError): runner.parse_xunit(xml)

    def test_modern_xcresult_exact_target_and_method_set(self):
        rows = runner.parse_xcresult(xctests(self.group['methods'], self.group['target']), self.group['target'])
        self.assertEqual(rows, self.rows)
        runner.validate_outcomes(rows, self.group['methods'], 0)
        runner.validate_summary(summary(12), 12, UUID)

    def test_xcresult_missing_wrong_target_bad_identifier_and_unknown_schema(self):
        for mutation in ['schema', 'target', 'method', 'status']:
            data = xctests(self.group['methods'], self.group['target'])
            bundle = data['testNodes'][0]['children'][0]; case = bundle['children'][0]
            if mutation == 'schema': data = {'other': data['testNodes']}
            elif mutation == 'target': bundle['name'] = 'QuestifyUITests'
            elif mutation == 'method': case['nodeIdentifier'] = 'UnknownTarget/Class/testOther'
            else: del case['result']
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): runner.parse_xcresult(data, self.group['target'])

    def test_target_url_binding_must_not_override_wrong_bundle(self):
        data = xctests(self.group['methods'], self.group['target']); case = data['testNodes'][0]['children'][0]['children'][0]
        case['nodeIdentifierURL'] = 'test://com.apple.xcode/Questify/' + self.group['methods'][0] + '()'
        self.assertEqual(runner.parse_xcresult(data, self.group['target']), self.rows)
        case['nodeIdentifierURL'] = case['nodeIdentifierURL'].replace('QuestifyAppUnitTests', 'QuestifyUITests')
        with self.assertRaises(ValueError): runner.parse_xcresult(data, self.group['target'])

    def test_zero_omitted_extra_duplicate_failed_skipped_timeout_and_cancel_fail(self):
        mutants = [[], self.rows[:-1], self.rows + self.rows[:1], self.rows + [{'method': 'QuestifyAppUnitTests/Other/testExtra', 'status': 'Passed'}]]
        for status in ['Skipped', 'Failed', 'Expected Failure', 'Unknown', 'Cancelled']:
            rows = copy.deepcopy(self.rows); rows[0]['status'] = status; mutants.append(rows)
        for rows in mutants:
            with self.assertRaises(ValueError): runner.validate_outcomes(rows, self.group['methods'], 0)
        for code in [1, 65, 124, -2, -9]:
            with self.assertRaises(ValueError): runner.validate_outcomes(self.rows, self.group['methods'], code)

    def test_hidden_repetitions_and_xunit_summary_disagreement_fail(self):
        data = xctests(self.group['methods'], self.group['target'])
        case = data['testNodes'][0]['children'][0]['children'][0]
        case['children'] = [{'nodeType': 'Test Case', 'name': 'hidden', 'result': 'Failed'}]
        with self.assertRaises(ValueError): runner.parse_xcresult(data, self.group['target'])
        for attributes in ['tests="0"', 'tests="1" failures="1"', 'tests="1" skipped="1"']:
            raw = ('<testsuite ' + attributes + '><testcase classname="QuestifyCoreTests.Example" name="testOne"/></testsuite>').encode()
            with self.assertRaises(ValueError): runner.parse_xunit(raw)
        with self.assertRaises(ValueError): runner.validate_outcomes(self.rows, self.group['methods'], False)

    def test_summary_counts_actual_device_and_no_boolean_counts(self):
        for key, value in [('totalTestCount', 0), ('passedTests', 11), ('failedTests', 1), ('skippedTests', 1), ('expectedFailures', 1), ('totalTestCount', True), ('devicesAndConfigurations', [])]:
            mutant = summary(12); mutant[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): runner.validate_summary(mutant, 12, UUID)
        with self.assertRaises(ValueError): runner.validate_summary(summary(12), 12, 'OTHER')


class RuntimeBoundaries(unittest.TestCase):
    def test_single_installed_iphone_and_no_automatic_other_device(self):
        data = {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [{'name': 'iPhone 17', 'udid': UUID, 'isAvailable': True}],
                            'com.apple.CoreSimulator.SimRuntime.tvOS-26-0': [{'name': 'iPhone wrong', 'udid': UUID, 'isAvailable': True}]}}
        self.assertEqual(runner.choose_simulator(data)['udid'], UUID)
        for mutant in [{}, {'devices': {}}, {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [{'name': 'iPad', 'udid': UUID, 'isAvailable': True}]}}]:
            with self.assertRaises(ValueError): runner.choose_simulator(mutant)

    def test_run_requires_hosted_mac_exact_repo_branch_and_event(self):
        environment = {'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted', 'GITHUB_REPOSITORY': 'liboyang42-cpu/chengyin-ios', 'GITHUB_REF': 'refs/heads/migration/native-ios', 'GITHUB_EVENT_NAME': 'push', 'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '1'}
        with mock.patch.object(sys, 'platform', 'darwin'):
            runner.runtime_environment(environment)
            for key, value in [('RUNNER_ENVIRONMENT', 'self-hosted'), ('GITHUB_REF', 'refs/heads/main'), ('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_RUN_ID', '0'), ('GITHUB_RUN_ATTEMPT', '')]:
                mutant = dict(environment); mutant[key] = value
                with self.assertRaises(ValueError): runner.runtime_environment(mutant)
        with mock.patch.object(sys, 'platform', 'linux'), self.assertRaises(ValueError): runner.runtime_environment(environment)

    def test_process_exit_is_real_and_timeout_never_passes(self):
        code, data = runner.execute([sys.executable, '-c', 'print("small")'], SOURCE, 5, True)
        self.assertEqual((code, data.strip()), (0, b'small'))
        code, _ = runner.execute([sys.executable, '-c', 'import time; time.sleep(60)'], SOURCE, .03, True)
        self.assertEqual(code, 124)
        with self.assertRaises(ValueError): runner.execute(['not-run'], SOURCE, 0)

    def test_core_build_is_once_before_exact_execution_and_failure_stops(self):
        class StopAfterCore(Exception):
            pass
        identity = {'source_sha': 'a' * 40, 'source_tree': 'b' * 40}
        environment = {'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_WORKFLOW_SHA': 'a' * 40}
        for code in [0, 1, 124]:
            with tempfile.TemporaryDirectory() as temporary:
                job = runner.Diagnostic(TOOLS.parent, Path(temporary), SELECTION)
                order = []
                def command(args, seconds, capture=False):
                    order.append(('build', args, seconds, capture))
                    return code, b''
                def collect(group, args, seconds, result):
                    order.append(('test', args, seconds))
                    raise StopAfterCore()
                with mock.patch.object(runner, 'runtime_environment'), mock.patch.object(runner, 'verify_scope', return_value=identity), mock.patch.dict(os.environ, environment), mock.patch.object(job, 'toolchain', return_value={}), mock.patch.object(job, 'command', side_effect=command), mock.patch.object(job, 'collect', side_effect=collect):
                    with self.assertRaises(StopAfterCore if code == 0 else ValueError): job.run()
                self.assertEqual(order[0], ('build', ['swift', 'build', '--build-tests'], 720, False))
                self.assertEqual([item[0] for item in order], ['build', 'test'] if code == 0 else ['build'])
                self.assertEqual(job.receipt['groups']['core']['build_returncode'], code)
                if code == 0:
                    self.assertEqual(order[1][1], runner.core_command(SELECTION['groups'][0], Path(temporary) / 'core.xml'))
                    self.assertEqual(order[1][2], 180)
                self.assertEqual(job.receipt['groups']['core']['actual_count'], 0)

    def test_core_capture_keeps_stderr_live_and_limits_only_evidence(self):
        process = mock.Mock(); process.returncode = 0
        process.communicate.return_value = (b'small XCTest transcript', None)
        with mock.patch.object(runner.subprocess, 'Popen', return_value=process) as popen:
            self.assertEqual(runner.execute(['swift', 'test', '--skip-build'], SOURCE, 5, 'stdout'),
                             (0, b'small XCTest transcript'))
            self.assertEqual(popen.call_args.kwargs['stdout'], subprocess.PIPE)
            self.assertIsNone(popen.call_args.kwargs['stderr'])
        process.communicate.return_value = (b'x' * (runner.LIMIT + 1), None)
        with mock.patch.object(runner.subprocess, 'Popen', return_value=process), self.assertRaises(ValueError):
            runner.execute(['fake'], SOURCE, 5, 'stdout')
        source = (TOOLS / 'run_targeted_native.py').read_text()
        self.assertIn("self.command(['swift', 'build', '--build-tests'], 720)", source)
        self.assertIn("self.collect(groups['core'], core_command(groups['core'], core), 180, core)", source)

    def test_every_cleanup_wait_is_bounded_even_after_kill(self):
        process = mock.Mock(); process.pid = 10
        process.communicate.side_effect = [subprocess.TimeoutExpired('fake', 1)] * 4
        with mock.patch.object(runner.subprocess, 'Popen', return_value=process), mock.patch.object(runner.os, 'killpg') as kill:
            with self.assertRaises(RuntimeError): runner.execute(['fake'], SOURCE, 1)
            self.assertEqual([c.kwargs['timeout'] for c in process.communicate.call_args_list], [1, 20, 10, 5])
            self.assertEqual([c.args[1] for c in kill.call_args_list], [signal.SIGINT, signal.SIGTERM, signal.SIGKILL])

    def test_product_target_selection_supports_only_safe_testhost_tokens(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); host = root / 'Debug/Questify.app'; bundle = host / 'PlugIns/QuestifyAppUnitTests.xctest'; bundle.mkdir(parents=True)
            path = root / 'app.xctestrun'
            value = {'TestTargets': [{'TestBundlePath': '__TESTHOST__/PlugIns/QuestifyAppUnitTests.xctest', 'TestHostPath': '__TESTROOT__/Debug/Questify.app'}]}
            path.write_bytes(plistlib.dumps(value))
            self.assertEqual(runner.select_xctestrun(root, 'QuestifyAppUnitTests'), path.resolve())
            for target in ['QuestifyUITests', 'Other']:
                with self.assertRaises(ValueError): runner.select_xctestrun(root, target)
            value['TestTargets'][0]['TestHostPath'] = '/etc'; path.write_bytes(plistlib.dumps(value))
            with self.assertRaises(ValueError): runner.select_xctestrun(root, 'QuestifyAppUnitTests')

    def test_product_directory_alias_returns_canonical_safe_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); products = root / 'actual'; products.mkdir()
            (products / 'QuestifyUITests.xctest').mkdir()
            run = products / 'ui.xctestrun'
            run.write_bytes(plistlib.dumps({'tests': [{'TestBundlePath': '__TESTROOT__/QuestifyUITests.xctest'}]}))
            alias = root / 'alias'; alias.symlink_to(products, target_is_directory=True)
            self.assertEqual(runner.select_xctestrun(alias, 'QuestifyUITests'), run.resolve())
            escaped = products / 'linked.xctestrun'; escaped.symlink_to(run)
            with self.assertRaises(ValueError): runner.select_xctestrun(alias, 'QuestifyUITests')

    def test_ambiguous_products_and_extra_target_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / 'QuestifyUITests.xctest').mkdir()
            value = {'tests': [{'TestBundlePath': str(root / 'QuestifyUITests.xctest')}]}
            for name in ['one', 'two']: (root / (name + '.xctestrun')).write_bytes(plistlib.dumps(value))
            with self.assertRaises(ValueError): runner.select_xctestrun(root, 'QuestifyUITests')
            (root / 'two.xctestrun').unlink(); value['tests'].append({'TestBundlePath': '/elsewhere/Other.xctest'})
            (root / 'one.xctestrun').write_bytes(plistlib.dumps(value))
            with self.assertRaises(ValueError): runner.select_xctestrun(root, 'QuestifyUITests')

    def test_inventory_detects_product_mutation_and_escaping_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / 'binary').write_bytes(b'one')
            before = runner.products_digest(root); (root / 'binary').write_bytes(b'two')
            self.assertNotEqual(before, runner.products_digest(root))
            (root / 'escaped').symlink_to('/etc')
            with self.assertRaises(ValueError): runner.products_digest(root)

    def test_scope_requires_exact_sha_base_and_nineteen_exact_statuses(self):
        output = scope_transport
        with mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), mock.patch.object(runner, 'checked', side_effect=output):
            self.assertEqual(runner.verify_scope(SOURCE, SELECTION)['source_tree'], 'b' * 40)
        for field in ['head', 'base', 'diff', 'dirty', 'missing-repair', 'wrong-status', 'old-additions', 'duplicate']:
            def mutated(command, root):
                original = output(command, root)
                if field == 'head' and command[1:3] == ['rev-parse', 'HEAD']: return 'c' * 40
                if field == 'base' and command[1:3] == ['rev-parse', runner.HISTORICAL_BASE_COMMIT + '^{tree}']: return 'c' * 40
                if field == 'diff' and command[1] == 'diff': return original + '\nM\tApp/AppSession.swift'
                if field == 'missing-repair' and command[1] == 'diff': return '\n'.join(original.splitlines()[:-1])
                if field == 'wrong-status' and command[1] == 'diff': return original.replace('M\t' + runner.CREATOR_PATHS[0], 'A\t' + runner.CREATOR_PATHS[0])
                if field == 'old-additions' and command[1] == 'diff': return original.replace('M\t' + runner.PATHS[0], 'A\t' + runner.PATHS[0])
                if field == 'duplicate' and command[1] == 'diff': return original + '\n' + original.splitlines()[0]
                if field == 'dirty' and command[1] == 'status': return ' M App/AppSession.swift'
                return original
            with mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), mock.patch.object(runner, 'checked', side_effect=mutated), self.assertRaises(ValueError):
                runner.verify_scope(SOURCE, SELECTION)

    def test_duplicate_json_keys_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'bad.json'; path.write_text('{"status":"FAIL","status":"PASS"}')
            with self.assertRaises(ValueError): runner.read_json(path)

    def test_missing_receipt_reports_not_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); destination = root / 'summary'
            runner.report(root, destination)
            self.assertIn('NOT_RUN', destination.read_text())
            self.assertNotIn('PASS', destination.read_text())


class ReceiptIdentity(unittest.TestCase):
    def receipt(self):
        identity = {'source_sha': 'a' * 40, 'source_tree': 'b' * 40, 'workflow_sha': 'a' * 40,
                    'run_id': '123', 'run_attempt': '1', 'selection_sha256': 'c' * 64}
        r = {**identity, 'version': 1, 'status': 'PASS', 'scope': 'selected-native-diagnostic-only',
             'base_commit': runner.BASE_COMMIT, 'base_tree': runner.BASE_TREE,
             'historical_base_commit': runner.HISTORICAL_BASE_COMMIT,
             'historical_base_tree': runner.HISTORICAL_BASE_TREE,
             'creator_base_commit': runner.CREATOR_COMMIT, 'creator_base_tree': runner.CREATOR_TREE,
             'selection': SELECTION['name'], 'expected_count': 65, 'actual_count': 65,
             'toolchain': {k: k for k in ['xcode', 'developer', 'swift', 'sdk_version', 'sdk_path']},
             'simulator': {'udid': UUID, 'name': 'iPhone 17', 'runtime': 'com.apple.CoreSimulator.SimRuntime.iOS-26-0'},
             'groups': {g['name']: {'status': 'PASS', 'expected': g['methods'], 'actual_count': len(g['methods']), 'returncode': 0,
                                   'actual': [{'method': m, 'status': 'Passed'} for m in g['methods']]} for g in SELECTION['groups']},
             'products': {}}
        r['groups']['core']['build_returncode'] = 0
        for name, config in [('ui', 'Debug/iphonesimulator/unsigned/ONLY_ACTIVE_ARCH=NO'), ('app-unit', 'Debug/iphonesimulator/isolated-entitlement-section/adhoc-host')]:
            r['products'][name] = {'configuration': config, 'files': 3, 'sha256': 'd' * 64, 'xctestrun_sha256': 'e' * 64}
        for group in SELECTION['groups']:
            for key in (['result_sha256', 'transcript_sha256'] if group['kind'] == 'swift' else ['summary_sha256', 'tests_sha256']):
                r['groups'][group['name']][key] = '9' * 64
        r['products']['app-unit']['manifest'] = {'commit': identity['source_sha'], 'purpose': 'isolated-simulator-app-unit',
            'toolchain': {k: r['toolchain'][k] for k in ['xcode', 'developer']}, 'source_archive_sha256': 'f' * 64}
        return r, identity

    def test_exact_same_run_sha_tree_configuration_and_65_results(self):
        receipt, identity = self.receipt(); runner.validate_pass_receipt(receipt, identity, SELECTION)

    def test_report_revalidates_real_exported_files_not_just_receipt_counts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / 'tools').mkdir(); output = root / 'results'; output.mkdir()
            selection_path = root / runner.PATHS[1]; runner.write_json(selection_path, SELECTION)
            receipt, identity = self.receipt(); receipt['selection_sha256'] = runner.digest(selection_path)
            methods = SELECTION['groups'][0]['methods']
            xml = '<testsuites><testsuite>' + ''.join('<testcase classname="' + m.split('/')[0] + '.' + m.split('/')[1] + '" name="' + m.split('/')[2] + '()" />' for m in methods) + '</testsuite></testsuites>'
            (output / 'core.xml').write_text(xml); receipt['groups']['core']['result_sha256'] = runner.digest(output / 'core.xml')
            (output / 'core-stdout.txt').write_bytes(core_transcript(methods)); receipt['groups']['core']['transcript_sha256'] = runner.digest(output / 'core-stdout.txt')
            for group in SELECTION['groups'][1:]:
                for part, data in [('summary', summary(len(group['methods']))), ('tests', xctests(group['methods'], group['target']))]:
                    path = output / (group['name'] + '-' + part + '.json'); runner.write_json(path, data)
                    receipt['groups'][group['name']][part + '_sha256'] = runner.digest(path)
            runner.write_json(output / 'receipt.json', receipt)
            environment = {'GITHUB_SHA': identity['source_sha'], 'GITHUB_WORKFLOW_SHA': identity['workflow_sha'], 'GITHUB_RUN_ID': identity['run_id'], 'GITHUB_RUN_ATTEMPT': identity['run_attempt']}
            with mock.patch.dict(os.environ, environment), mock.patch.object(runner, 'checked', return_value=identity['source_tree']), mock.patch('builtins.print'):
                runner.report(output, root / 'summary', root)
                self.assertIn('Actual methods: 65 / 65', (root / 'summary').read_text())
                transcript = output / 'core-stdout.txt'
                transcript.write_bytes(core_transcript(methods, 'skipped'))
                receipt['groups']['core']['transcript_sha256'] = runner.digest(transcript)
                runner.write_json(output / 'receipt.json', receipt)
                with self.assertRaises(ValueError): runner.report(output, None, root)
                transcript.write_bytes(core_transcript(methods))
                receipt['groups']['core']['transcript_sha256'] = runner.digest(transcript)
                runner.write_json(output / 'receipt.json', receipt)
                path = output / 'app-unit-tests.json'; changed = runner.read_json(path)
                changed['testNodes'][0]['children'][0]['children'][0]['result'] = 'Failed'; runner.write_json(path, changed)
                with self.assertRaises(ValueError): runner.report(output, None, root)
                receipt['groups']['app-unit']['tests_sha256'] = runner.digest(path); runner.write_json(output / 'receipt.json', receipt)
                with self.assertRaises(ValueError): runner.report(output, None, root)

    def test_other_run_attempt_sha_tree_selection_or_workflow_rejected(self):
        for key in ['run_id', 'run_attempt', 'source_sha', 'source_tree', 'selection_sha256', 'workflow_sha']:
            receipt, identity = self.receipt(); receipt[key] = 'different'
            with self.subTest(key=key), self.assertRaises(ValueError): runner.validate_pass_receipt(receipt, identity, SELECTION)

    def test_missing_or_wrong_configuration_toolchain_simulator_or_group_rejected(self):
        for mode in ['config', 'toolchain', 'simulator', 'count', 'group', 'product-sha', 'archive', 'manifest-sha', 'result-sha', 'core-build']:
            receipt, identity = self.receipt()
            if mode == 'core-build': receipt['groups']['core']['build_returncode'] = 1
            elif mode == 'config': receipt['products']['ui']['configuration'] = 'Release/iphoneos'
            elif mode == 'toolchain': del receipt['toolchain']['sdk_version']
            elif mode == 'simulator': receipt['simulator']['name'] = 'iPad'
            elif mode == 'count': receipt['actual_count'] = 0
            elif mode == 'group': receipt['groups']['ui']['actual'] = []
            elif mode == 'product-sha': receipt['products']['ui']['sha256'] = ''
            elif mode == 'archive': receipt['products']['app-unit']['manifest']['source_archive_sha256'] = ''
            elif mode == 'result-sha': del receipt['groups']['core']['result_sha256']
            else: receipt['products']['app-unit']['manifest']['commit'] = 'z' * 40
            with self.subTest(mode=mode), self.assertRaises(ValueError): runner.validate_pass_receipt(receipt, identity, SELECTION)


class CreatorCurrentTreeAndCounts(unittest.TestCase):
    def test_every_creator_current_tree_mode_blob_and_presence_is_exact(self):
        rows = SELECTION['creator_changes']
        records = ['100644 blob ' + r['after_blob'] + '\t' + r['path'] for r in rows]
        def verify(values):
            with mock.patch.object(runner, 'checked', return_value='\0'.join(values) + '\0') as check:
                result = runner.verify_creator_current_tree(SELECTION, SOURCE, 'a' * 40)
                check.assert_called_once_with(['git', 'ls-tree', '-z', 'a' * 40, '--', *runner.CREATOR_PATHS], SOURCE)
                return result
        self.assertEqual(len(verify(records)), 15)
        for i, row in enumerate(rows):
            for mode in ['missing', 'blob', 'executable', 'symlink', 'duplicate']:
                changed = list(records)
                if mode == 'missing': changed.pop(i)
                elif mode == 'duplicate': changed.append(changed[i])
                elif mode == 'blob': changed[i] = changed[i].replace(row['after_blob'], '0' * 40, 1)
                else: changed[i] = changed[i].replace('100644', '100755' if mode == 'executable' else '120000', 1)
                with self.subTest(path=row['path'], mode=mode), self.assertRaises(ValueError): verify(changed)
        with self.assertRaises(ValueError): verify(records + ['100644 blob ' + '0' * 40 + '\tCore/unknown.swift'])

    def test_receipt_counts_are_real_integers_and_outer_fields_are_exact(self):
        for field in ['expected_count', 'actual_count']:
            receipt, identity = ReceiptIdentity().receipt(); receipt[field] = 65.0
            with self.subTest(field=field), self.assertRaises(ValueError): runner.validate_pass_receipt(receipt, identity, SELECTION)
        for group in ['core', 'app-unit', 'ui']:
            receipt, identity = ReceiptIdentity().receipt(); receipt['groups'][group]['actual_count'] = float(receipt['groups'][group]['actual_count'])
            with self.subTest(group=group), self.assertRaises(ValueError): runner.validate_pass_receipt(receipt, identity, SELECTION)
        changed = copy.deepcopy(SELECTION); changed['unknown_creator_field'] = True
        with mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', runner.hashlib.sha256(runner.encode(changed).encode()).hexdigest()), self.assertRaises(ValueError):
            runner.validate_selection(changed, SOURCE)


# Append before the existing ``if __name__ == '__main__'`` block.
# Expected identities are review-time literals, never derived from runner or SELECTION.
# Uses the existing test module imports, runner, SELECTION, SOURCE, core_transcript,
# UUID, and ReceiptIdentity. No Apple tools are executed.

LEGACY45_METHOD_SOURCES = (('QuestifyAppUnitTests/MerchantDecorTagPickerTests/testDuplicateOverLimitHistoricalTagsStayUnchangedOnOpenCancelAndInvalidOwner',
  'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'),
 ('QuestifyAppUnitTests/MerchantDecorTagPickerTests/testSemicolonTagApplyCancelAndReopenPreserveExactLabels',
  'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedRefreshNeverSurvivesOwnerLeaseABAExpiryOrCancellation',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedSnapshotPreparationClearsRevokedScopeBeforeAnotherRequest',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testClonedTransportRejectsLateLeaseReplacementTokenRoleAndErrors',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCurrent401ExpiresOnlyCurrentOwner',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testGuestDefaultNilRevokedReaderAndReplacementNeverAdoptLease',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLateShelfAndDetailSuccess401ErrorNeverApplyAcrossLifetimeChanges',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLoadedReadOnlyRefreshSnapshotSurvives503ThenReplacesAndClears',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testNormalFactoryPagedShelfDetailAndEveryWriterRemainOff',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOuterClonesOnlyAdmitExactReadsAndDenyAllAdjacentMutations',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOwnerConfigurationFactoryDoesNotAlterLocalDraftAndClearsOnLeaseChange',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testSearchedPageElevenLegacyStoryRequiresFreshOwnedDetail',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testShelfLeaseChangesPreserveUnsavedLocalEditorAndDormantAuthority',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyCoreTests/MerchantDecorTagDraftTests/testHistoricalLabelsRemainByteExactUntilExplicitRemoval',
  'Tests/CoreTests/MerchantDecorTagDraftTests.swift'),
 ('QuestifyCoreTests/MerchantDecorTagDraftTests/testSemicolonCustomLabelRemainsOneLiteralTag',
  'Tests/CoreTests/MerchantDecorTagDraftTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testAcknowledgedWriteReadbackFailureKeepsLockUntilReadOnlyRetry',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testCancelledReadDoesNotPublishLateServerExplanation',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testFailedRefreshRetainsSnapshotAndShowsExplanation',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testFinalPreWriteReadFailureDoesNotDispatchOrReuseConfirmation',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testInitialReadFailureShowsExactServerMessageAndRetryClearsItWithoutWriting',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testLateFailureCannotPublishAfterSameAccountTokenReplacement',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testNewReadClearsPriorExplanationBeforeResponse',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testPrepareFailureKeepsSnapshotAndRequiresANewReview',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testSessionResetClearsPreviouslyDisplayedExplanation',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testUnauthorizedCallbackInvalidatesFailureBeforePresentation',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testUnknownWriteReadbackFailureAndMatchingRetryNeverUnlockOrResend',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testWhitespaceAndNonServerErrorsNeverBecomeUserText',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/TemplateAuthoringHTTPTests/testRefreshSnapshotCannotReplaceHundredRowWritePreflightOrOldReview',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAlreadyCancelledRefreshClearsSnapshotWithoutDispatch',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAuthContractUnknownAndCancellationFailuresClearRefreshSnapshot',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testCachedRefreshLifetimeTransitionsAndABAFenceAllLateResults',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testContinuationAuthAndContractErrorsClearRowsButOverlapRemainsRetryable',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testNewKeywordNeverDisplaysPreviousQuerySnapshot',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testOnlyExplicitTransientFailuresRetainSnapshotAndRequireFirstPageRetry',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshAtHundredPageBoundaryRestartsAtOneWithoutPage101',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshReplacesOverlappingIDsAndValidEmptyClearsSnapshot',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testSameKeywordNewGenerationRejectsOldSuccessAndError',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testAccountChangeDismissesReviewAndSignoutClearsShelf',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testChineseLargeTextCanCancelReview',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testDefaultDisabledHasNoMutationConfirmation',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testDeleteRequiresSeparateReviewAndSimulationIsLabelled',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testLibraryReviewShowsIdentityAndCancellationDoesNotSubmit',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testOwnedDetailBackAndReopenKeepsStableDestination',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testUnknownLocksBothActionsAcrossReopen',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'))

CREATOR20_METHOD_SOURCES = (('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testActualMiniCounterexamplesSeparatePersonalAndMarketplaceStates',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testAlreadyCancelledRefreshCannotDispatchOrKeepSidecars',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testAuthContractAndCancellationErrorsClearEveryCachedState',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testCanonicalOptionalTextAndMissingFieldsRemainCompatible',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testDisplayMetadataNeverChangesSharedDTOOrAcknowledgesPendingMutation',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testEmptyFirstPageClearsRowsAndDisplayStatesTogether',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testExistingBaseDTOValidationIsNotRelaxedByTolerantDisplayColumns',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testFeedbackIsVerbatimOptionalTextAndNeverAnAction',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testMalformedBaseRowsClearStatesWithoutCommittingPartialPage',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testMalformedOptionalColumnsNeverInvalidateAnOtherwiseLegalRow',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testMarketIdentityLongBoundsAreReadFromOriginalBytesWithoutCoercion',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testMarketplaceMatrixIgnoresPersonalPublishStatus',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testNewKeywordCannotRetainOldStateWhenRequestFails',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testOldSuccessAndErrorCannotOverwriteNewSameIDState',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testOverlappingContinuationCannotPartiallyReplaceOrAppendStates',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testPartialMetadataDecodingDoesNotDropOtherFieldsOrOtherRows',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testPersonalReviewPrecedenceMatchesSourceMatrix',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testSameIDsAndEqualBaseRowsStillReplaceChangedDisplayStates',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testScopeTransitionsABARevocationLeaveAndCancelRetireStates',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testTransientRefreshRetainsStatesWithRowsAndRetryReplacesBoth',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'))

# path -> (status, before_sha256, before_blob, after_sha256, after_blob)
CREATOR15_IDENTITIES = {'App/TemplateAuthoringMineView.swift': ('M',
                                         '91d2c740529dd2970568cacfcd68409618c6e2d1d6cda007daccfdb3dc8164d7',
                                         '35e95a15e1863941e78204e3529beb4fec75effd',
                                         '070653140719b1dd37b8cf5b811c0a6cfef9c66eff13fa06d9a78b6634a4c38f',
                                         '08cdc8e932d784043693e0def191b0e075d990ac'),
 'Core/TemplateAuthoringShelf.swift': ('M',
                                       '3d8865b315f1712f0056d1b376f0f7f2b1aa01e8417dab95f438c200cefe2e91',
                                       'bdf056d2be4425e27de9c05835844549e6bbd1e2',
                                       'a9261782a98016cf474bbd9a2b2035fd6fbba6bf5ac9bb5682f85c95f4bbb13a',
                                       '3833f06347f38410a385daeb30bc31137d56d1c8'),
 'Resources/Localizable.xcstrings': ('M',
                                     '6e9a854e14c29ad90a8b4ed88735e5641d15efc53ca810fb49dc366d3509910a',
                                     '941520db879d0dc32d15a66be6f053d07180a8c7',
                                     '8f552d5a3f34a86c19a370c411a08669dfb4440a15f3b3037cd635595b4ff995',
                                     'e7ef7d81d0b523d2c987cecca209b1db47a5e319'),
 'Tests/ContractChecks/test_template_shelf_state_projection.py': ('A',
                                                                  None,
                                                                  None,
                                                                  '92a11a1874c3c442ff7bf76d62ae4e8331e0d7d589f6d55d919e9a4130180dc4',
                                                                  'ce9f2f69217ec41a22b1c8f9162f8f13b29c7e8e'),
 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift': ('A',
                                                                None,
                                                                None,
                                                                'b2b199d73b7045d4c3de9ce7bc0ea41b10bfc233c6b9c180438fd415d5c99b87',
                                                                'e38e099587bfa2f13ce139fc0affec9956796d69'),
 'tools/tests/creator_shelf_state_history.py': ('A',
                                                None,
                                                None,
                                                '63d498f92184bfdf2349849c683347adc5766e73878cc1f5e86790b68799d2e3',
                                                '61690d3d2740f2644afe69bb882598d12ea550e3'),
 'tools/tests/test_creator_shelf_state_history.py': ('A',
                                                     None,
                                                     None,
                                                     '28e14028204276d0277afb29064d0f2ad65bcb05e57aadf226b63d61e606c924',
                                                     '7d87a62a590f0a43d22a50df0c28b82ccd3e1e87'),
 'tools/tests/creator_shelf_refresh_history.py': ('M',
                                                  'a0ccdaf793079c5dd59b5931d8d734f1d16856bbba7f8251125f1bc32b3c5c25',
                                                  'fd71251a812f05d4a0287ca743ee1f77d20c0a1c',
                                                  '55632e1d0235628b55478a6b50a5e5d369bf2c54d73f4d09ec33becf84b6d7e5',
                                                  '371bde68e2f41e19786bd24670daccf1a731eda8'),
 'tools/tests/test_creator_shelf_refresh_history.py': ('M',
                                                       'be30636bb1fde4a4c2d3f03078da7f80b49ab971fded3ededb5f6b80a93619e9',
                                                       '4be67258473f78cbec202c107f1e042304dbe4cc',
                                                       '26b98d87f9c465dd2e6cefbc31734e5925c13a86003a9e695a09f4b83ad36061',
                                                       '10ed339bdef2ed504ed0c1fe8084cc5941f1aecb'),
 'tools/tests/test_creator_pending_synthetic_storage_history.py': ('M',
                                                                   '608cef3c34c5b8590f93de52e787d9ac1e08aa1d6b0aa03e478f89ca31c1d85d',
                                                                   '73245573a05cebe9a9d870991738829f96c8822e',
                                                                   '8d4b8e0bf04a7ce28622b416956af3628348bf3f86d5af5630fe04bb07e7e739',
                                                                   '2f52a335789681737e99bbdb94758bafde49c0a7'),
 'tools/run138_editor_readiness_contract.json': ('M',
                                                 '519006c2f95083423c186d289b8b2a1b6ef9c6327b5fd461718548b8e0fc40ce',
                                                 'c4c827b956c3bb43d26ff17412dbc5ae92a35652',
                                                 'eb80d6bb10463819a30d41530cc00c909d94f6f79fd1108401b22031369b2053',
                                                 'aedee08391f8b84304c7ef23270810466f18b5e7'),
 'tools/run138_editor_readiness.py': ('M',
                                      'ab69d29bd7f410619ebd5b7a051bfe98ef239e4532a8466d5607f36ac24f3b08',
                                      'ef1277041b1cc3ff8a091794ec9e05051e5cbcbe',
                                      'a33058cdac0bfce6fe0c17f02059d0be061c5b3da0cd3df76ace1f856422662c',
                                      '3df054c632b4bb2923d2163cb7c95cba48e7502c'),
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': ('M',
                                                                        'd1d7ad397a76f668f47bcc4243c23a397d560e90220b01bd99dd91a85bfe3163',
                                                                        'a064deddd1f9e7a36c903e19c150b0407b81f227',
                                                                        'df08d6c30bcebd89e901e5ae3a5920b22142dbd8b2cf4a7dfa4c765be5917271',
                                                                        'ec967979d5473c2a07731e502c66ca3362611b75'),
 'App/MerchantBusinessEditor.swift': ('M',
                                      '37e4fb670565770a72f1c1ad0e1c5b2ac4affc35669514597c80790d4e8f394d',
                                      '5365e829dc0e668f407a0fd2411c1ac7a002352a',
                                      '13ff93a1d1608d0fc10cbbb1e2aa31b6f7b5496ea37553e052d147ab6611aff0',
                                      '542f1ee001f6e8210dbafd4e13ebd7796c316948'),
 'Tests/ContractChecks/test_merchant_review_draft_return.py': ('M',
                                                               'e9f31299585059f9ce7f6e23002bd815471f7ba85e83707fe9fd571934dd1968',
                                                               'aa3055d722502f962032bcf061882fed2e1bf21c',
                                                               'e5b7c6ce7d66037ed49dba6b32b59fcf213c57e24b6f8694285e7d612575d777',
                                                               'd6e31c58ae23fae4f9a1d8e2133f2628caca1933')}

DIAGNOSTIC4_PATHS = ('.github/workflows/native-targeted.yml', 'tools/targeted_native_selection.json', 'tools/run_targeted_native.py', 'tools/tests/test_targeted_native.py')

class Creator65Contract(unittest.TestCase):
    """Preserve all old coverage and authenticate the complete Creator15 layer."""

    @staticmethod
    def sha(raw):
        return runner.hashlib.sha256(raw).hexdigest()

    @staticmethod
    def blob(raw):
        return runner.hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()

    @staticmethod
    def xml(methods, skipped=None):
        return ('<testsuite tests="' + str(len(methods)) + '">' + ''.join(
            '<testcase classname="' + m.split('/')[0] + '.' + m.split('/')[1] +
            '" name="' + m.split('/')[2] + '()">' +
            ('<skipped/>' if m == skipped else '') + '</testcase>'
            for m in methods) + '</testsuite>').encode()

    def fixture_root(self):
        # Dereference source overlays only while making the fixture. Validation then
        # reads actual regular-file bytes; no read/digest/inverse function is mocked.
        temporary = tempfile.TemporaryDirectory(prefix='targeted-creator65-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        paths = {row['path'] for row in SELECTION['source_files']}
        paths.update(CREATOR15_IDENTITIES)
        paths.update(row['path'] for row in SELECTION['reviewed_repairs'])
        paths.update(runner.STATIC_REPAIR_PATHS)
        paths.update(runner.STATIC_DIAGNOSTIC_BASE_BLOBS)
        for relative in paths:
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((SOURCE / relative).read_bytes())
        return root

    def validate_repinned(self, selection, root):
        # Re-pinning just the outer document must never erase independent identities.
        pin = self.sha(runner.encode(selection).encode())
        with mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', pin):
            return runner.validate_selection(selection, root)

    def test_original_45_exact_bindings_plus_independent_20_are_exactly_65(self):
        self.assertEqual(len(LEGACY45_METHOD_SOURCES), 45)
        self.assertEqual(len(CREATOR20_METHOD_SOURCES), 20)
        self.assertFalse(set(LEGACY45_METHOD_SOURCES) & set(CREATOR20_METHOD_SOURCES))
        expected = sorted(LEGACY45_METHOD_SOURCES + CREATOR20_METHOD_SOURCES)
        self.assertEqual(len({m for m, _ in expected}), 65)
        actual = sorted((r['method'], r['source']) for g in SELECTION['groups']
                        for r in g['method_sources'])
        self.assertEqual(actual, expected)
        self.assertEqual(list(runner.FIXED_METHOD_SOURCES), expected)
        self.assertEqual([len(g['methods']) for g in SELECTION['groups']], [44, 14, 7])
        self.assertEqual([runner.GROUPS[k][2] for k in ('core', 'app-unit', 'ui')], [44, 14, 7])
        self.assertEqual(sorted(m for g in SELECTION['groups'] for m in g['methods']),
                         [m for m, _ in expected])
        self.assertEqual(sorted((m, p) for m, p in actual if (m, p) not in CREATOR20_METHOD_SOURCES),
                         list(LEGACY45_METHOD_SOURCES))
        self.assertEqual(runner.validate_selection(copy.deepcopy(SELECTION), self.fixture_root()), SELECTION)

    def test_each_of_the_65_methods_has_one_declaration_in_its_exact_source(self):
        declarations = {}
        for method, source in LEGACY45_METHOD_SOURCES + CREATOR20_METHOD_SOURCES:
            target = method.split('/')[0]
            if (target, source) not in declarations:
                declarations[target, source] = runner.declared_methods((SOURCE / source).read_text(), target)
            with self.subTest(method=method, source=source):
                self.assertEqual(declarations[target, source].get(method), 1)
        source = 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'
        self.assertEqual(self.sha((SOURCE / source).read_bytes()),
                         'b2b199d73b7045d4c3de9ce7bc0ea41b10bfc233c6b9c180438fd415d5c99b87')
        self.assertEqual(declarations['QuestifyCoreTests', source],
                         {m: 1 for m, _ in CREATOR20_METHOD_SOURCES})

    def test_each_new_method_rejects_repinned_replacement_or_wrong_source(self):
        root = self.fixture_root()
        for method, source in CREATOR20_METHOD_SOURCES:
            for mode in ('replacement', 'wrong-source', 'missing-binding'):
                changed = copy.deepcopy(SELECTION)
                group = changed['groups'][0]
                row = next(r for r in group['method_sources'] if r['method'] == method)
                if mode == 'replacement':
                    group['methods'][group['methods'].index(method)] = method + 'Other'
                    row['method'] = method + 'Other'
                    group['methods'].sort()
                    group['method_sources'].sort(key=lambda r: r['method'])
                elif mode == 'wrong-source':
                    row['source'] = 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'
                else:
                    group['method_sources'].remove(row)
                with self.subTest(method=method, mode=mode), self.assertRaises(ValueError):
                    self.validate_repinned(changed, root)

    def test_each_new_declaration_is_checked_before_creator_image_validation(self):
        root = self.fixture_root()
        source = 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'
        path = root / source
        original = path.read_bytes()
        for method, _ in CREATOR20_METHOD_SOURCES:
            name = method.rsplit('/', 1)[1]
            for mode in ('missing', 'duplicate'):
                if mode == 'missing':
                    raw = original.replace(('func ' + name + '(').encode(),
                                           ('func removed_' + name + '(').encode(), 1)
                else:
                    raw = original + ('\nfunc ' + name + '() {}\n').encode()
                path.write_bytes(raw)
                changed = copy.deepcopy(SELECTION)
                next(r for r in changed['source_files'] if r['path'] == source)['sha256'] = self.sha(raw)
                with self.subTest(method=method, mode=mode), self.assertRaisesRegex(ValueError, 'not uniquely declared'):
                    self.validate_repinned(changed, root)
                path.write_bytes(original)

    def test_new_source_binding_cannot_be_dropped_even_after_outer_repin(self):
        changed = copy.deepcopy(SELECTION)
        source = 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'
        changed['source_files'] = [r for r in changed['source_files'] if r['path'] != source]
        with self.assertRaises(ValueError):
            self.validate_repinned(changed, self.fixture_root())

    def test_core_44_requires_both_complete_independent_execution_streams(self):
        methods = SELECTION['groups'][0]['methods']
        self.assertEqual(len(methods), 44)
        good_xml, good_stdout = self.xml(methods), core_transcript(methods)
        self.assertEqual(len(runner.validate_core_evidence(good_xml, good_stdout, methods, 0)), 44)
        for method, _ in CREATOR20_METHOD_SOURCES:
            missing = [m for m in methods if m != method]
            replaced = [m if m != method else m + 'Other' for m in methods]
            duplicate = [m if m != method else missing[0] for m in methods]
            skipped_stdout = good_stdout.replace(core_transcript([method]), core_transcript([method], 'skipped'))
            cases = (
                ('xml-missing', self.xml(missing), good_stdout),
                ('stdout-missing', good_xml, core_transcript(missing)),
                ('both-missing', self.xml(missing), core_transcript(missing)),
                ('xml-skip', self.xml(methods, skipped=method), good_stdout),
                ('stdout-skip', good_xml, skipped_stdout),
                ('xml-same-count-replacement', self.xml(replaced), good_stdout),
                ('stdout-same-count-replacement', good_xml, core_transcript(replaced)),
                ('both-same-count-replacement', self.xml(replaced), core_transcript(replaced)),
                ('both-same-count-duplicate', self.xml(duplicate), core_transcript(duplicate)),
            )
            for mode, xml, stdout in cases:
                with self.subTest(method=method, mode=mode), self.assertRaises(ValueError):
                    runner.validate_core_evidence(xml, stdout, methods, 0)
        for returncode in (1, 65, 124, False):
            with self.subTest(returncode=returncode), self.assertRaises(ValueError):
                runner.validate_core_evidence(good_xml, good_stdout, methods, returncode)

    def receipt65(self):
        receipt, identity = ReceiptIdentity().receipt()
        receipt['expected_count'] = receipt['actual_count'] = 65
        return receipt, identity

    def test_old_45_receipt_cannot_be_upgraded_by_renaming_or_recounting(self):
        receipt, identity = self.receipt65()
        runner.validate_pass_receipt(receipt, identity, SELECTION)
        old_core = [m for m, _ in LEGACY45_METHOD_SOURCES if m.startswith('QuestifyCoreTests/')]
        self.assertEqual(len(old_core), 24)
        for mode in ('honest-45', 'forged-total-65', 'forged-core-44', 'forged-expected-44'):
            stale = copy.deepcopy(receipt)
            stale['expected_count'] = stale['actual_count'] = 45 if mode == 'honest-45' else 65
            core = stale['groups']['core']
            core['expected'] = old_core
            core['actual_count'] = 24
            core['actual'] = [{'method': m, 'status': 'Passed'} for m in old_core]
            if mode in ('forged-core-44', 'forged-expected-44'):
                core['actual_count'] = 44
            if mode == 'forged-expected-44':
                core['expected'] = SELECTION['groups'][0]['methods']
            # Source/run/selection identity intentionally remains the *new* identity:
            # rejection must survive relabelling an old execution as the new run.
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                runner.validate_pass_receipt(stale, identity, SELECTION)

    def test_each_new_method_is_required_in_the_65_receipt(self):
        receipt, identity = self.receipt65()
        for method, _ in CREATOR20_METHOD_SOURCES:
            for mode in ('missing', 'skipped', 'same-count-replacement'):
                changed = copy.deepcopy(receipt)
                core = changed['groups']['core']
                row = next(r for r in core['actual'] if r['method'] == method)
                if mode == 'missing':
                    core['actual'].remove(row)
                elif mode == 'skipped':
                    row['status'] = 'Skipped'
                else:
                    row['method'] = method + 'Other'
                with self.subTest(method=method, mode=mode), self.assertRaises(ValueError):
                    runner.validate_pass_receipt(changed, identity, SELECTION)

    def test_creator_15_and_diagnostic_4_have_exact_independent_statuses(self):
        self.assertEqual(runner.HISTORICAL_BASE_COMMIT, '45b728c7d48cf7969ac864e5693322d45e79394a')
        self.assertEqual(runner.HISTORICAL_BASE_TREE, '440cdc3bbd4a40369e6cb6762eec6306e4aa921d')
        self.assertEqual(tuple(runner.PATHS), DIAGNOSTIC4_PATHS)
        self.assertIsInstance(runner.CREATOR_PATHS, tuple)
        self.assertEqual(len(runner.CREATOR_PATHS), 15)
        self.assertEqual(set(runner.CREATOR_PATHS), set(CREATOR15_IDENTITIES))
        self.assertFalse(set(runner.CREATOR_PATHS) & set(DIAGNOSTIC4_PATHS))
        expected = {'M\t' + p for p in DIAGNOSTIC4_PATHS}
        expected.update(spec[0] + '\t' + p for p, spec in CREATOR15_IDENTITIES.items())
        self.assertIsInstance(runner.HISTORICAL_ALLOWED_CHANGES, tuple)
        self.assertEqual(len(runner.HISTORICAL_ALLOWED_CHANGES), 19)
        self.assertEqual(set(runner.HISTORICAL_ALLOWED_CHANGES), expected)
        self.assertEqual(SELECTION['historical_base']['allowed_changes'], list(runner.HISTORICAL_ALLOWED_CHANGES))
        self.assertEqual(sum(x.startswith('M\t') for x in runner.HISTORICAL_ALLOWED_CHANGES), 15)
        self.assertEqual(sum(x.startswith('A\t') for x in runner.HISTORICAL_ALLOWED_CHANGES), 4)

    def test_all_creator_current_bytes_sha_and_git_blobs_are_independently_bound(self):
        rows = SELECTION['creator_changes']
        self.assertEqual([r['path'] for r in rows], list(runner.CREATOR_PATHS))
        self.assertEqual(self.sha(runner.encode(rows).encode()), runner.CREATOR_CHANGES_CONTRACT_SHA256)
        root = self.fixture_root()
        published = runner.restore_creator_inputs(SELECTION, root)
        restored = runner.validate_creator_changes(SELECTION, root)
        self.assertEqual(set(restored), {p for p, spec in CREATOR15_IDENTITIES.items() if spec[0] == 'M'})
        for row in rows:
            path = row['path']
            with self.subTest(path=path):
                self.assertEqual(set(row), {'path', 'status', 'before_sha256', 'before_blob',
                                            'after_sha256', 'after_blob', 'hunks'})
                self.assertEqual(tuple(row[k] for k in ('status', 'before_sha256', 'before_blob',
                                                       'after_sha256', 'after_blob')),
                                 CREATOR15_IDENTITIES[path])
                raw = published.get(path, (root / path).read_bytes())
                self.assertEqual(self.sha(raw), row['after_sha256'])
                self.assertEqual(self.blob(raw), row['after_blob'])
                if row['status'] == 'A':
                    self.assertIsNone(row['before_sha256'])
                    self.assertIsNone(row['before_blob'])
                    self.assertEqual(row['hunks'], [])
                else:
                    self.assertTrue(row['hunks'])
                    self.assertEqual(restored[path], runner.inverse_reviewed_repair(row, raw))
                    self.assertEqual(self.sha(restored[path]), row['before_sha256'])
                    self.assertEqual(self.blob(restored[path]), row['before_blob'])

    def test_creator_missing_duplicate_reordered_and_changed_rows_reject_outer_repin(self):
        root = self.fixture_root()
        for mode in ('missing', 'duplicate', 'reordered', 'unknown-path', 'wrong-status',
                     'wrong-after-sha', 'wrong-after-blob', 'extra-key', 'missing-key'):
            changed = copy.deepcopy(SELECTION)
            rows = changed['creator_changes']
            if mode == 'missing':
                rows.pop()
            elif mode == 'duplicate':
                rows.append(copy.deepcopy(rows[0]))
            elif mode == 'reordered':
                rows.reverse()
            elif mode == 'unknown-path':
                rows[0]['path'] = 'Core/UnreviewedCreator.swift'
            elif mode == 'wrong-status':
                rows[0]['status'] = 'A' if rows[0]['status'] == 'M' else 'M'
            elif mode == 'wrong-after-sha':
                rows[0]['after_sha256'] = '0' * 64
            elif mode == 'wrong-after-blob':
                rows[0]['after_blob'] = '0' * 40
            elif mode == 'extra-key':
                rows[0]['ignored'] = True
            else:
                del rows[0]['after_blob']
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.validate_repinned(changed, root)

    def test_every_creator_path_rejects_changed_real_current_bytes(self):
        root = self.fixture_root()
        for path in CREATOR15_IDENTITIES:
            destination = root / path
            raw = destination.read_bytes()
            destination.write_bytes(raw + b'\n')
            with self.subTest(path=path), self.assertRaises(ValueError):
                runner.validate_creator_changes(SELECTION, root)
            destination.write_bytes(raw)
        # A successful final validation proves every temporary mutation was restored.
        self.assertEqual(len(runner.validate_creator_changes(SELECTION, root)), 11)

    def test_added_files_cannot_be_rehashed_or_claim_predecessors_or_hunks(self):
        root = self.fixture_root()
        for path, spec in CREATOR15_IDENTITIES.items():
            if spec[0] != 'A':
                continue
            destination = root / path
            raw = destination.read_bytes()
            for mode in ('rehashed-current', 'before-sha', 'before-blob', 'hunks'):
                changed = copy.deepcopy(SELECTION)
                row = next(r for r in changed['creator_changes'] if r['path'] == path)
                if mode == 'rehashed-current':
                    mutant = raw + b'\n'
                    destination.write_bytes(mutant)
                    row['after_sha256'], row['after_blob'] = self.sha(mutant), self.blob(mutant)
                    for source in changed['source_files']:
                        if source['path'] == path:
                            source['sha256'] = self.sha(mutant)
                elif mode == 'before-sha':
                    row['before_sha256'] = self.sha(b'')
                elif mode == 'before-blob':
                    row['before_blob'] = self.blob(b'')
                else:
                    row['hunks'] = [{'before': '', 'after': raw.decode()}]
                with self.subTest(path=path, mode=mode), self.assertRaises(ValueError):
                    self.validate_repinned(changed, root)
                destination.write_bytes(raw)

    def test_modified_creator_inverse_requires_complete_predecessor(self):
        published = runner.restore_creator_inputs(SELECTION, SOURCE)
        for row in SELECTION['creator_changes']:
            if row['status'] != 'M':
                continue
            raw = published.get(row['path'], (SOURCE / row['path']).read_bytes())
            old = runner.inverse_reviewed_repair(row, raw)
            self.assertEqual(self.sha(old), CREATOR15_IDENTITIES[row['path']][1])
            self.assertEqual(self.blob(old), CREATOR15_IDENTITIES[row['path']][2])
            hunk = row['hunks'][0]
            for mutant in (raw + b'\n', raw.replace(hunk['after'].encode(), b'', 1),
                           raw + hunk['after'].encode()):
                forged = copy.deepcopy(row)
                forged['after_sha256'], forged['after_blob'] = self.sha(mutant), self.blob(mutant)
                with self.subTest(path=row['path']), self.assertRaises(ValueError):
                    runner.inverse_reviewed_repair(forged, mutant)

    def baseline_records(self):
        return ['100644 blob ' + spec[2] + '\t' + path
                for path, spec in CREATOR15_IDENTITIES.items() if spec[0] == 'M']

    def verify_synthetic_baseline(self, records, root):
        # Only the git transport is synthetic; independent pinned blob records are
        # parsed by the real function. All current files remain real byte fixtures.
        output = '\0'.join(records) + ('\0' if records else '')
        expected_command = ['git', 'ls-tree', '-z', runner.HISTORICAL_BASE_TREE, '--', *runner.CREATOR_PATHS]
        def checked(command, actual_root, *args, **kwargs):
            self.assertEqual(command, expected_command)
            self.assertEqual(actual_root, root)
            return output
        with mock.patch.object(runner, 'checked', side_effect=checked) as invoked:
            result = runner.verify_creator_baseline(SELECTION, root)
            self.assertEqual(invoked.call_count, 1)
            return result

    def test_creator_baseline_requires_each_modified_blob_and_all_four_additions_absent(self):
        root = self.fixture_root()
        records = self.baseline_records()
        self.assertEqual(len(records), 11)
        self.verify_synthetic_baseline(records, root)
        for path, spec in CREATOR15_IDENTITIES.items():
            if spec[0] == 'A':
                bad = records + ['100644 blob ' + spec[4] + '\t' + path]
                with self.subTest(path=path, mode='addition-already-exists'), self.assertRaises(ValueError):
                    self.verify_synthetic_baseline(bad, root)
            else:
                original = '100644 blob ' + spec[2] + '\t' + path
                for mode in ('missing', 'wrong-blob', 'executable', 'symlink', 'tree', 'duplicate'):
                    bad = list(records)
                    if mode == 'missing':
                        bad.remove(original)
                    elif mode == 'duplicate':
                        bad.append(original)
                    else:
                        replacement = {
                            'wrong-blob': '100644 blob ' + '0' * 40 + '\t' + path,
                            'executable': original.replace('100644', '100755', 1),
                            'symlink': original.replace('100644', '120000', 1),
                            'tree': original.replace('100644 blob', '040000 tree', 1),
                        }[mode]
                        bad[bad.index(original)] = replacement
                    with self.subTest(path=path, mode=mode), self.assertRaises(ValueError):
                        self.verify_synthetic_baseline(bad, root)
        with self.assertRaises(ValueError):
            self.verify_synthetic_baseline(records + ['100644 blob ' + '1' * 40 + '\tCore/Unreviewed.swift'], root)

    def test_each_creator_current_sha_and_blob_check_remains_active_after_inner_repin(self):
        root = self.fixture_root()
        for path in CREATOR15_IDENTITIES:
            for field, bad in (('after_sha256', '0' * 64), ('after_blob', '0' * 40)):
                changed = copy.deepcopy(SELECTION)
                row = next(r for r in changed['creator_changes'] if r['path'] == path)
                row[field] = bad
                inner_pin = self.sha(runner.encode(changed['creator_changes']).encode())
                with self.subTest(path=path, field=field), \
                     mock.patch.object(runner, 'CREATOR_CHANGES_CONTRACT_SHA256', inner_pin), \
                     self.assertRaisesRegex(ValueError, 'current creator (bytes|blob)'):
                    runner.validate_creator_changes(changed, root)

    def test_each_creator_current_file_must_exist_as_a_regular_checkout_file(self):
        root = self.fixture_root()
        for path in CREATOR15_IDENTITIES:
            destination = root / path
            raw = destination.read_bytes()
            destination.unlink()
            with self.subTest(path=path, mode='missing'), self.assertRaises((ValueError, OSError)):
                runner.validate_creator_changes(SELECTION, root)
            sibling = destination.with_name(destination.name + '.unchanged-fixture')
            sibling.write_bytes(raw)
            destination.symlink_to(sibling)
            with self.subTest(path=path, mode='same-bytes-symlink'), self.assertRaises(ValueError):
                runner.validate_creator_changes(SELECTION, root)
            destination.unlink()
            sibling.unlink()
            destination.write_bytes(raw)

    def test_added_file_null_predecessor_and_empty_hunks_are_independently_enforced(self):
        root = self.fixture_root()
        for path, spec in CREATOR15_IDENTITIES.items():
            if spec[0] != 'A':
                continue
            for field, bad in (('before_sha256', self.sha(b'')), ('before_blob', self.blob(b'')),
                               ('hunks', [{'before': '', 'after': (root / path).read_text()}])):
                changed = copy.deepcopy(SELECTION)
                row = next(r for r in changed['creator_changes'] if r['path'] == path)
                row[field] = bad
                inner_pin = self.sha(runner.encode(changed['creator_changes']).encode())
                with self.subTest(path=path, field=field), \
                     mock.patch.object(runner, 'CREATOR_CHANGES_CONTRACT_SHA256', inner_pin), \
                     self.assertRaisesRegex(ValueError, 'fabricated predecessor'):
                    runner.validate_creator_changes(changed, root)


class ShallowCheckoutBoundaries(unittest.TestCase):
    def test_current_bytes_validate_without_history_but_real_run_scope_requires_it(self):
        root = Creator65Contract.fixture_root(self)
        with mock.patch.object(runner, 'checked', side_effect=AssertionError('Current validation must not read Git history')):
            self.assertEqual(runner.validate_selection(copy.deepcopy(SELECTION), root), SELECTION)
        transport = scope_transport
        with mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), \
             mock.patch.object(runner, 'checked', side_effect=transport), \
             mock.patch.object(runner, 'verify_creator_baseline', side_effect=ValueError('Historical baseline missing')) as baseline:
            with self.assertRaisesRegex(ValueError, 'Historical baseline missing'):
                runner.verify_scope(root, SELECTION)
            baseline.assert_called_once_with(SELECTION, root)

    def test_real_git_witness_proves_predecessors_and_addition_absence_without_parent_history(self):
        root = Creator65Contract.fixture_root(self)
        gitdir = root / 'witness.git'
        env = dict(os.environ, GIT_DIR=str(gitdir), GIT_INDEX_FILE=str(root / 'witness.index'))
        env.pop('GIT_OBJECT_DIRECTORY', None); env.pop('GIT_ALTERNATE_OBJECT_DIRECTORIES', None)
        subprocess.run(['git', 'init', '--bare', '-q', str(gitdir)], env=env, check=True)
        (root / '.git').write_text('gitdir: ' + str(gitdir) + '\n')
        def git(*args, data=None):
            return subprocess.check_output(['git', *args], input=data, env=env).decode().strip()
        git('read-tree', '--empty')
        published = runner.restore_creator_inputs(SELECTION, root)
        for row in SELECTION['creator_changes']:
            if row['status'] == 'M':
                old = runner.inverse_reviewed_repair(row, published.get(row['path'], (root / row['path']).read_bytes()))
                oid = git('hash-object', '-w', '--stdin', data=old)
                self.assertEqual(oid, row['before_blob'])
                git('update-index', '--add', '--cacheinfo', '100644', oid, row['path'])
        witness = git('write-tree')
        # This is an explicit disposable subset tree, not a claim to recreate45b.
        # The independent identity fixture still fixes the production full tree.
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(runner, 'HISTORICAL_BASE_TREE', witness):
            self.assertEqual(len(runner.verify_creator_baseline(SELECTION, root)), 11)
        for row in SELECTION['creator_changes']:
            if row['status'] != 'A': continue
            git('read-tree', witness)
            oid = git('hash-object', '-w', '--stdin', data=published.get(row['path'], (root / row['path']).read_bytes()))
            self.assertEqual(oid, row['after_blob'])
            git('update-index', '--add', '--cacheinfo', '100644', oid, row['path'])
            mutant = git('write-tree')
            with self.subTest(path=row['path']), mock.patch.dict(os.environ, env, clear=True), \
                 mock.patch.object(runner, 'HISTORICAL_BASE_TREE', mutant), self.assertRaisesRegex(ValueError, 'already exists in baseline'):
                runner.verify_creator_baseline(SELECTION, root)


class StaticRepairBinding(unittest.TestCase):
    """Current 3393 repair scope is independent of every preserved history layer."""
    BASELINES = {'App/ProjectThoughtDefinitionsEditor.swift': ('M',
                                               'dc2bcdecf846d8226db09d96df7ce7688cabc722249add64a114d48721263bd9',
                                               '01b97e6fa5bcfbda6ee476c8ec32bc17636cb27d'),
 'App/ProjectEndingConditionPicker.swift': ('M',
                                            '1b0a460cc65ee4ba69be25390940f188bbeaddbd824ee4d77d053dfdb28ba5a8',
                                            '6f9114ca362dac40dbfc1ae19c8947c133a44c3b'),
 'tools/run138_editor_readiness.py': ('M',
                                      'f39364ce7df89dc337047e825294047fa0af2f461424cd9aa1e6384c0c389d4f',
                                      'b59adab2ffde9df7d9ad3a3afc8e8e4084ee2bbb'),
 'tools/run138_editor_readiness_contract.json': ('M',
                                                 'b72d9b1024daadb5273a4de24c0175d42c04516b1f89c6c53c0f9c40dd7a77b6',
                                                 '045c337b9a9c36595192df7c46272ab487f4258b'),
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': ('M',
                                                                        'f9904bbd44d23bcaacd02be0647cf6bc4d7f0d5994371a8f05f2edac868b59ec',
                                                                        'be4ebdde8b93e24c2fb1833c16473598f8f6b9be'),
 'tools/club_customer_directory_admission.py': ('M',
                                                '80b6fb95961ef598ea66aa02e0081938b5df2ae7860a3e3fad76e5c0fa0a2297',
                                                '50e51bdc77a9373046c00c8313d3e45079cac76a'),
 'Tests/ContractChecks/test_category_roam_registration.py': ('M',
                                                             '80f4cbe6fba6df6ed1604aea7d7dfd20fd957d679a6e450401a49d2b80c5f1fa',
                                                             'b7403c238d4a70a362b86eb2a67627553c0958ef'),
 'tools/tests/test_creator_shelf_state_history.py': ('M',
                                                     'accaa341cf2803a6847c19ee675d7bb9d06b831d300c1a56d9f17d9aeddfb65e',
                                                     '53740f8ba2cf1f428f78da4309e7aeb883d06af6'),
 'tools/tests/test_club_parity_integration_budget.py': ('M',
                                                        'e2b27a07353c01261c3220596fa46376f77dd59b533a12caf9f3174fe279a248',
                                                        '48eee28519350c74cab77601b751db5de094c946'),
 'tools/tests/test_readiness_contract_parse_cache.py': ('A', None, None),
 'Tests/ContractChecks/test_global_search_category_recovery.py': ('M',
                                                                  '1cda598881ae8cd6327b8ef322337f78ca40d8f6c29f2a7d8b84b49050de591f',
                                                                  '375bee1d0b03f3d02bbe028b0a8b2ae69b984587'),
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py': ('M',
                                                                           'b1ee3e1eac62c6a670986301f1fe2713d615c7a8a82ece5dfdd8946ae08e43c1',
                                                                           'd5a1361846364539a119a558fd23459164a465cb')}

    def fixture_root(self):
        return Creator65Contract.fixture_root(self)

    def test_exact_published_base_nine_paths_and_old_domains_remain_separate(self):
        self.assertEqual(runner.BASE_COMMIT, '3393ec85076a7a4e246e94e98ddf81f6b73ede2f')
        self.assertEqual(runner.BASE_TREE, '7dd9461bafbe546e1c5ef5eaacc750267b416b2f')
        self.assertEqual(SELECTION['base_commit'], runner.BASE_COMMIT)
        self.assertEqual(SELECTION['base_tree'], runner.BASE_TREE)
        expected = {status + '\t' + path for path, (status, _, _) in self.BASELINES.items()}
        expected.update('M\t' + path for path in ('tools/targeted_native_selection.json',
                        'tools/run_targeted_native.py', 'tools/tests/test_targeted_native.py'))
        self.assertEqual(len(runner.ALLOWED_CHANGES), 15)
        self.assertEqual(set(runner.ALLOWED_CHANGES), expected)
        self.assertEqual(SELECTION['allowed_changes'], list(runner.ALLOWED_CHANGES))
        self.assertEqual([x for x in runner.ALLOWED_CHANGES if x.startswith('A\t')],
                         ['A\ttools/tests/test_readiness_contract_parse_cache.py'])
        self.assertNotIn('M\t.github/workflows/native-targeted.yml', runner.ALLOWED_CHANGES)
        self.assertEqual(tuple(runner.STATIC_REPAIR_PATHS), tuple(self.BASELINES))
        self.assertEqual(len(runner.HISTORICAL_ALLOWED_CHANGES), 19)
        self.assertEqual(SELECTION['historical_base'], {
            'base_commit': '45b728c7d48cf7969ac864e5693322d45e79394a',
            'base_tree': '440cdc3bbd4a40369e6cb6762eec6306e4aa921d',
            'allowed_changes': list(runner.HISTORICAL_ALLOWED_CHANGES)})
        self.assertEqual(runner.CREATOR_CHANGES_CONTRACT_SHA256,
                         'a0a916e50820419681f69c6e21ad048655f5b5d6db628079cc8a44a96ab7e1e9')
        for path in ('tools/tests/test_readiness_contract_parse_cache.py',
                     'tools/tests/test_club_parity_integration_budget.py'):
            self.assertNotIn(path, runner.CREATOR_PATHS)
            self.assertNotIn(path, runner.REPAIR_PATHS)
            self.assertNotIn(path, runner.BOUND_SOURCES)

    def test_complete_current_payload_inverts_to_independent_b75_bytes(self):
        root = self.fixture_root()
        restored = runner.validate_static_repair(SELECTION, root)
        self.assertEqual(set(restored), {p for p, row in self.BASELINES.items() if row[0] == 'M'})
        for row in SELECTION['static_repair_changes']:
            path = row['path']; raw = (root / path).read_bytes()
            with self.subTest(path=path):
                self.assertEqual(tuple(row[k] for k in ('status', 'before_sha256', 'before_blob')),
                                 self.BASELINES[path])
                self.assertEqual(Creator65Contract.sha(raw), row['after_sha256'])
                self.assertEqual(Creator65Contract.blob(raw), row['after_blob'])
                if row['status'] == 'M':
                    self.assertEqual(Creator65Contract.sha(restored[path]), self.BASELINES[path][1])
                    self.assertEqual(Creator65Contract.blob(restored[path]), self.BASELINES[path][2])
                    self.assertEqual(runner.inverse_reviewed_repair(row, raw), restored[path])
                else:
                    self.assertEqual(row['hunks'], [])
                    self.assertNotIn(path, restored)
        self.assertEqual(runner.validate_selection(copy.deepcopy(SELECTION), root), SELECTION)

    def test_manifest_cannot_widen_or_change_under_outer_repin(self):
        root = self.fixture_root()
        for mode in ('missing', 'duplicate', 'reordered', 'outside-path', 'wrong-status',
                     'before-sha', 'before-blob', 'after-sha', 'after-blob', 'hunk', 'extra-field'):
            changed = copy.deepcopy(SELECTION); rows = changed['static_repair_changes']
            if mode == 'missing': rows.pop()
            elif mode == 'duplicate': rows.append(copy.deepcopy(rows[0]))
            elif mode == 'reordered': rows.reverse()
            elif mode == 'outside-path': rows[0]['path'] = 'Core/Unreviewed.swift'
            elif mode == 'wrong-status': rows[0]['status'] = 'A'
            elif mode == 'extra-field': rows[0]['ignored'] = True
            elif mode == 'hunk': rows[0]['hunks'][0]['before'] += '\n'
            else: rows[0][mode.replace('-', '_') + ('256' if mode.endswith('sha') else '')] = '0' * (64 if mode.endswith('sha') else 40)
            pin = Creator65Contract.sha(runner.encode(changed).encode())
            with self.subTest(mode=mode), mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', pin), self.assertRaises(ValueError):
                runner.validate_selection(changed, root)
        for field in ('base_commit', 'base_tree', 'allowed_changes'):
            changed = copy.deepcopy(SELECTION)
            changed['historical_base'][field] = changed[field]
            pin = Creator65Contract.sha(runner.encode(changed).encode())
            with self.subTest(historical_field=field), mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', pin), self.assertRaisesRegex(ValueError, 'historical nineteen-path'):
                runner.validate_selection(changed, root)

    def test_every_payload_checks_real_bytes_sha_blob_and_regular_file(self):
        root = self.fixture_root()
        for row in SELECTION['static_repair_changes']:
            path = root / row['path']; original = path.read_bytes()
            path.write_bytes(original + b'\n')
            with self.subTest(path=row['path'], mode='changed'), self.assertRaisesRegex(ValueError, 'current static repair bytes'):
                runner.validate_static_repair(SELECTION, root)
            path.unlink()
            with self.subTest(path=row['path'], mode='missing'), self.assertRaises(ValueError):
                runner.validate_static_repair(SELECTION, root)
            other = path.with_name(path.name + '.witness'); other.write_bytes(original); path.symlink_to(other)
            with self.subTest(path=row['path'], mode='symlink'), self.assertRaises(ValueError):
                runner.validate_static_repair(SELECTION, root)
            path.unlink(); other.unlink(); path.write_bytes(original)
            for field in ('after_sha256', 'after_blob'):
                changed = copy.deepcopy(SELECTION)
                next(r for r in changed['static_repair_changes'] if r['path'] == row['path'])[field] = '0' * (64 if field.endswith('sha256') else 40)
                pin = Creator65Contract.sha(runner.encode(changed['static_repair_changes']).encode())
                with self.subTest(path=row['path'], field=field), mock.patch.object(runner, 'STATIC_REPAIR_CHANGES_SHA256', pin), self.assertRaisesRegex(ValueError, 'current static repair (bytes|blob)'):
                    runner.validate_static_repair(changed, root)
        self.assertEqual(len(runner.validate_static_repair(SELECTION, root)), 11)

    def test_inverse_rejects_rehashed_off_hunk_and_fabricated_addition_predecessors(self):
        root = self.fixture_root()
        for row in SELECTION['static_repair_changes']:
            raw = (root / row['path']).read_bytes()
            if row['status'] == 'A':
                for field, value in [('before_sha256', Creator65Contract.sha(b'')),
                                     ('before_blob', Creator65Contract.blob(b'')),
                                     ('hunks', [{'before': '', 'after': raw.decode()}])]:
                    changed = copy.deepcopy(SELECTION)
                    next(r for r in changed['static_repair_changes'] if r['path'] == row['path'])[field] = value
                    pin = Creator65Contract.sha(runner.encode(changed['static_repair_changes']).encode())
                    with self.subTest(field=field), mock.patch.object(runner, 'STATIC_REPAIR_CHANGES_SHA256', pin), self.assertRaisesRegex(ValueError, 'fabricated predecessor'):
                        runner.validate_static_repair(changed, root)
                continue
            for mode, mutant in [('off-hunk', raw + b'\n'),
                                 ('missing', raw.replace(row['hunks'][0]['after'].encode(), b'', 1)),
                                 ('duplicate', raw + row['hunks'][0]['after'].encode())]:
                forged = copy.deepcopy(row)
                forged['after_sha256'], forged['after_blob'] = Creator65Contract.sha(mutant), Creator65Contract.blob(mutant)
                with self.subTest(path=row['path'], mode=mode), self.assertRaises(ValueError):
                    runner.inverse_reviewed_repair(forged, mutant)

    def test_actual_parent_nine_path_scope_and_receipt_cannot_claim_old_scope(self):
        root = self.fixture_root()
        for mode in ('parent', 'merge', 'missing-base', 'tree', 'missing', 'extra', 'status', 'old-scope'):
            def transport(command, actual_root):
                result = scope_transport(command, actual_root)
                if command[1] == 'rev-list':
                    if mode == 'parent': return 'a' * 40 + ' ' + runner.HISTORICAL_BASE_COMMIT
                    if mode == 'merge': return result + ' ' + 'f' * 40
                if command[1:3] == ['rev-parse', runner.BASE_COMMIT + '^{tree}']:
                    if mode == 'missing-base': raise ValueError('Read command failed')
                    if mode == 'tree': return 'c' * 40
                if command[1] == 'diff' and command[3] == runner.BASE_COMMIT:
                    if mode == 'missing': return '\n'.join(result.splitlines()[:-1])
                    if mode == 'extra': return result + '\nM\tApp/AppSession.swift'
                    if mode == 'status': return result.replace('A\ttools/tests/test_readiness_contract_parse_cache.py', 'M\ttools/tests/test_readiness_contract_parse_cache.py')
                    if mode == 'old-scope': return '\n'.join(runner.HISTORICAL_ALLOWED_CHANGES)
                return result
            with self.subTest(mode=mode), mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), mock.patch.object(runner, 'checked', side_effect=transport), self.assertRaisesRegex(ValueError, '3393|fifteen exact'):
                runner.verify_scope(root, SELECTION)
        for field, value in [('base_commit', runner.HISTORICAL_BASE_COMMIT),
                             ('base_tree', runner.HISTORICAL_BASE_TREE),
                             ('historical_base_commit', runner.BASE_COMMIT),
                             ('historical_base_tree', runner.BASE_TREE)]:
            receipt, identity = ReceiptIdentity().receipt(); receipt[field] = value
            with self.subTest(receipt_field=field), self.assertRaises(ValueError):
                runner.validate_pass_receipt(receipt, identity, SELECTION)

    def test_each_baseline_and_current_tree_mode_blob_and_addition_absence(self):
        root = self.fixture_root()
        for before in (True, False):
            records = static_tree_records(root, before)
            def verify(rows):
                with mock.patch.object(runner, 'checked', return_value='\0'.join(rows) + '\0'):
                    return runner.verify_static_repair_tree(SELECTION, root, runner.BASE_TREE if before else 'a' * 40, before)
            self.assertEqual(len(verify(records)), 14 if before else 15)
            for i, record in enumerate(records):
                for mode in ('missing', 'duplicate', 'blob', 'executable', 'symlink', 'directory'):
                    changed = list(records)
                    if mode == 'missing': changed.pop(i)
                    elif mode == 'duplicate': changed.append(record)
                    elif mode == 'blob': changed[i] = '100644 blob ' + '0' * 40 + '\t' + record.split('\t')[1]
                    else: changed[i] = record.replace('100644 blob', {'executable':'100755 blob', 'symlink':'120000 blob', 'directory':'040000 tree'}[mode], 1)
                    with self.subTest(before=before, path=record.split('\t')[1], mode=mode), self.assertRaises(ValueError): verify(changed)
            extra = 'tools/tests/test_readiness_contract_parse_cache.py' if before else 'Core/Unreviewed.swift'
            with self.subTest(before=before, mode='unexpected-presence'), self.assertRaises(ValueError):
                verify(records + ['100644 blob ' + '1' * 40 + '\t' + extra])

    def test_real_git_subset_witness_binds_b75_payload_and_current_mode_blobs(self):
        root = self.fixture_root(); gitdir = root / 'static-witness.git'
        env = dict(os.environ, GIT_DIR=str(gitdir), GIT_INDEX_FILE=str(root / 'static-witness.index'))
        env.pop('GIT_OBJECT_DIRECTORY', None); env.pop('GIT_ALTERNATE_OBJECT_DIRECTORIES', None)
        subprocess.run(['git', 'init', '--bare', '-q', str(gitdir)], env=env, check=True)
        def git(*args, data=None):
            return subprocess.check_output(['git', *args], input=data, env=env).decode().strip()
        restored = runner.validate_static_repair(SELECTION, root)
        # The witness contains only real payload blobs. Diagnostic baseline objects
        # are fixed Git identities, not claimed source copies or a full 3393 tree.
        git('read-tree', '--empty')
        for path, raw in restored.items():
            oid = git('hash-object', '-w', '--stdin', data=raw)
            self.assertEqual(oid, self.BASELINES[path][2])
            git('update-index', '--add', '--cacheinfo', '100644', oid, path)
        # Existing diagnostic baseline identities need not be materialized to write
        # this explicit subset tree; allow-missing never changes production checks.
        for path, oid in runner.STATIC_DIAGNOSTIC_BASE_BLOBS.items():
            git('update-index', '--add', '--cacheinfo', '100644', oid, path)
        before = git('write-tree', '--missing-ok')
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(len(runner.verify_static_repair_tree(SELECTION, root, before, True)), 14)
        git('read-tree', '--empty')
        for change in runner.ALLOWED_CHANGES:
            path = change.split('\t', 1)[1]; raw = (root / path).read_bytes()
            oid = git('hash-object', '-w', '--stdin', data=raw)
            git('update-index', '--add', '--cacheinfo', '100644', oid, path)
        current = git('write-tree')
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(len(runner.verify_static_repair_tree(SELECTION, root, current, False)), 15)
        path = 'tools/tests/test_readiness_contract_parse_cache.py'
        oid = next(row['after_blob'] for row in SELECTION['static_repair_changes'] if row['path'] == path)
        git('update-index', '--cacheinfo', '100755', oid, path); mutant = git('write-tree')
        with mock.patch.dict(os.environ, env, clear=True), self.assertRaisesRegex(ValueError, 'mode/blob'):
            runner.verify_static_repair_tree(SELECTION, root, mutant, False)


class PublishedParentBridge(unittest.TestCase):
    def fixture_root(self):
        return Creator65Contract.fixture_root(self)

    def test_exact_eight_path_parent_bridge_preserves_old_source_domains(self):
        self.assertEqual(runner.CREATOR_COMMIT, 'b75f7549678caf51a65ec8942b6a6d0c23e887de')
        self.assertEqual(runner.CREATOR_TREE, '6d5a1e4a1486b3e97ed2f1e995ac5194e568bc20')
        expected = ('Questify.xcodeproj/project.pbxproj', 'Resources/Localizable.xcstrings',
                    'Tests/ContractChecks/test_profile_read_failure_remote_admission.py',
                    'Tests/ContractChecks/test_template_shelf_state_projection.py',
                    'tools/run138_editor_readiness.py', 'tools/run138_editor_readiness_contract.json',
                    'tools/tests/creator_shelf_state_history.py', 'tools/tests/test_creator_shelf_state_history.py')
        self.assertEqual(runner.CREATOR_PARENT_PATHS, expected)
        self.assertEqual(tuple(row['path'] for row in SELECTION['creator_parent_changes']), expected)
        self.assertEqual(Creator65Contract.sha(runner.encode(SELECTION['creator_parent_changes']).encode()),
                         runner.CREATOR_PARENT_CHANGES_SHA256)
        self.assertEqual({row['path'] for row in SELECTION['historical_source_files']}, runner.BOUND_SOURCES)
        self.assertEqual(len(SELECTION['historical_source_files']), 29)
        self.assertEqual({row['path'] for row in SELECTION['source_files']}, runner.BOUND_SOURCES)
        before = {row['path']:row['sha256'] for row in SELECTION['historical_source_files']}
        after = {row['path']:row['sha256'] for row in SELECTION['source_files']}
        self.assertEqual([p for p in before if before[p] != after[p]], ['Questify.xcodeproj/project.pbxproj'])
        self.assertEqual(len(runner.PARENT_HISTORY_CHANGES), 34)
        self.assertEqual(SELECTION['creator_base'], {'base_commit':runner.CREATOR_COMMIT,
                         'base_tree':runner.CREATOR_TREE,'parent_changes':list(runner.PARENT_HISTORY_CHANGES)})
        for row in SELECTION['creator_parent_changes']:
            self.assertEqual(row['status'], 'M')
            self.assertIn(row['path'], runner.BOUND_SOURCES | set(runner.CREATOR_PATHS) | set(runner.REPAIR_PATHS))

    def test_current_to_true_parent_to_b75_inverses_match_every_historical_source(self):
        root = self.fixture_root()
        parent = runner.validate_static_repair(SELECTION, root)
        historical = runner.restore_creator_inputs(SELECTION, root)
        self.assertEqual(set(historical), set(runner.CREATOR_PARENT_PATHS))
        for row in SELECTION['creator_parent_changes']:
            raw = parent.get(row['path'], (root / row['path']).read_bytes())
            with self.subTest(path=row['path']):
                self.assertEqual(Creator65Contract.sha(raw), row['after_sha256'])
                self.assertEqual(Creator65Contract.blob(raw), row['after_blob'])
                self.assertEqual(runner.inverse_reviewed_repair(row, raw), historical[row['path']])
                self.assertEqual(Creator65Contract.sha(historical[row['path']]), row['before_sha256'])
                self.assertEqual(Creator65Contract.blob(historical[row['path']]), row['before_blob'])
        for row in SELECTION['historical_source_files']:
            raw = historical.get(row['path'], (root / row['path']).read_bytes())
            self.assertEqual(Creator65Contract.sha(raw), row['sha256'])
        self.assertEqual(len(runner.validate_creator_changes(SELECTION, root)), 11)

    def test_parent_bridge_rejects_repinned_missing_reordered_or_expanded_inputs(self):
        root = self.fixture_root()
        for mode in ('missing','duplicate','reordered','outside','before-sha','before-blob',
                     'after-sha','after-blob','hunks','status','extra-field'):
            changed = copy.deepcopy(SELECTION); rows = changed['creator_parent_changes']
            if mode == 'missing': rows.pop()
            elif mode == 'duplicate': rows.append(copy.deepcopy(rows[0]))
            elif mode == 'reordered': rows.reverse()
            elif mode == 'outside': rows[0]['path'] = 'Core/Unreviewed.swift'
            elif mode == 'status': rows[0]['status'] = 'A'
            elif mode == 'extra-field': rows[0]['ignored'] = True
            elif mode == 'hunks': rows[0]['hunks'].pop()
            else: rows[0][mode.replace('-','_') + ('256' if mode.endswith('sha') else '')] = '0' * (64 if mode.endswith('sha') else 40)
            pin = Creator65Contract.sha(runner.encode(changed).encode())
            with self.subTest(mode=mode), mock.patch.object(runner,'SELECTION_CONTRACT_SHA256',pin), self.assertRaises(ValueError):
                runner.validate_selection(changed,root)
        changed = copy.deepcopy(SELECTION)
        next(r for r in changed['historical_source_files'] if r['path'] == 'Questify.xcodeproj/project.pbxproj')['sha256'] = next(r['sha256'] for r in changed['source_files'] if r['path'] == 'Questify.xcodeproj/project.pbxproj')
        with self.assertRaisesRegex(ValueError,'historical source bindings'):
            runner.restore_creator_inputs(changed,root)

    def test_each_parent_inverse_rejects_rehashed_off_hunk_and_changed_real_sources(self):
        root = self.fixture_root(); parent = runner.validate_static_repair(SELECTION,root)
        for row in SELECTION['creator_parent_changes']:
            path = root / row['path']; current = path.read_bytes()
            path.write_bytes(current + b'\n')
            with self.subTest(path=row['path'],mode='current'),self.assertRaises(ValueError):
                runner.restore_creator_inputs(SELECTION,root)
            path.write_bytes(current)
            raw = parent.get(row['path'], current)
            for mode,mutant in [('off-hunk',raw+b'\n'),('missing',raw.replace(row['hunks'][0]['after'].encode(),b'',1)),('duplicate',raw+row['hunks'][0]['after'].encode())]:
                forged = copy.deepcopy(row); forged['after_sha256'],forged['after_blob'] = Creator65Contract.sha(mutant),Creator65Contract.blob(mutant)
                with self.subTest(path=row['path'],mode=mode),self.assertRaises(ValueError):
                    runner.inverse_reviewed_repair(forged,mutant)
        self.assertEqual(len(runner.restore_creator_inputs(SELECTION,root)),8)

    def test_every_real_parent_bridge_tree_mode_blob_and_presence_is_exact(self):
        for before in (True,False):
            records = ['100644 blob '+r['before_blob' if before else 'after_blob']+'\t'+r['path'] for r in SELECTION['creator_parent_changes']]
            def verify(rows):
                with mock.patch.object(runner,'checked',return_value='\0'.join(rows)+'\0'):
                    return runner.verify_creator_parent_tree(SELECTION,SOURCE,runner.CREATOR_TREE if before else runner.BASE_TREE,before)
            self.assertEqual(len(verify(records)),8)
            for i,record in enumerate(records):
                for mode in ('missing','duplicate','blob','mode','symlink','tree'):
                    changed = list(records)
                    if mode == 'missing':changed.pop(i)
                    elif mode == 'duplicate':changed.append(record)
                    elif mode == 'blob':changed[i]='100644 blob '+'0'*40+'\t'+record.split('\t')[1]
                    else:changed[i]=record.replace('100644 blob',{'mode':'100755 blob','symlink':'120000 blob','tree':'040000 tree'}[mode],1)
                    with self.subTest(before=before,path=record.split('\t')[1],mode=mode),self.assertRaises(ValueError):verify(changed)
            with self.assertRaises(ValueError):verify(records+['100644 blob '+'0'*40+'\tCore/Unreviewed.swift'])

    def test_parent_history_and_receipts_cannot_relabel_b75_as_current_parent(self):
        for mode in ('missing','extra','old-nineteen'):
            def transport(command,root):
                result=scope_transport(command,root)
                if command[1]=='diff' and command[3]==runner.CREATOR_COMMIT:
                    if mode=='missing':return '\n'.join(result.splitlines()[:-1])
                    if mode=='extra':return result+'\nM\tCore/Unreviewed.swift'
                    return '\n'.join(runner.HISTORICAL_ALLOWED_CHANGES)
                return result
            with self.subTest(mode=mode),mock.patch.dict(os.environ,{'GITHUB_SHA':'a'*40}),mock.patch.object(runner,'checked',side_effect=transport),self.assertRaisesRegex(ValueError,'creator-to-3393 history'):
                runner.verify_scope(SOURCE,SELECTION)
        for field,value in [('base_commit',runner.CREATOR_COMMIT),('base_tree',runner.CREATOR_TREE),('creator_base_commit',runner.BASE_COMMIT),('creator_base_tree',runner.BASE_TREE)]:
            receipt,identity=ReceiptIdentity().receipt();receipt[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):runner.validate_pass_receipt(receipt,identity,SELECTION)


class FixedPublicCreatorRead(unittest.TestCase):
    @staticmethod
    def headers(tree=None,parent=None):
        return 'tree '+(tree or runner.CREATOR_TREE)+'\nparent '+(parent or runner.HISTORICAL_BASE_COMMIT)+'\nauthor Test <test@example.invalid> 1 +0000\n\nSynthetic commit metadata'

    def present(self,command,root):
        if command[1:3]==['cat-file','-e']:return ''
        if command==['git','cat-file','-p',runner.CREATOR_COMMIT]:return self.headers()
        raise AssertionError(command)

    def missing(self,command,root):
        if command[1:3]==['cat-file','-e']:raise ValueError('Synthetic missing object')
        return self.present(command,root)

    def test_present_exact_object_never_fetches_or_inspects_network_configuration(self):
        with mock.patch.object(runner,'checked',side_effect=self.present) as read,mock.patch.object(runner,'execute') as execute:
            runner.ensure_creator_commit(SOURCE)
            execute.assert_not_called()
            self.assertEqual(read.call_args_list,[mock.call(['git','cat-file','-e',runner.CREATOR_COMMIT+'^{commit}'],SOURCE),mock.call(['git','cat-file','-e',runner.CREATOR_COMMIT+'^{tree}'],SOURCE),mock.call(['git','cat-file','-p',runner.CREATOR_COMMIT],SOURCE)])

    def test_missing_object_uses_one_whitelisted_bounded_noninteractive_public_read(self):
        inherited={'GITHUB_TOKEN':'do-not-forward','GH_TOKEN':'do-not-forward','SECRET':'do-not-forward',
                   'HTTPS_PROXY':'https://do-not-forward.invalid','GIT_CONFIG_COUNT':'1','GIT_ASKPASS':'do-not-forward',
                   'SSH_AUTH_SOCK':'do-not-forward','HOME':'do-not-forward','GIT_OBJECT_DIRECTORY':'do-not-forward'}
        with mock.patch.object(runner,'checked',side_effect=self.missing),mock.patch.object(runner,'execute',side_effect=[(0,b'core.repositoryformatversion\ncore.bare\n'),(0,b'')]) as execute,mock.patch.dict(os.environ,inherited):
            runner.ensure_creator_commit(SOURCE)
        self.assertEqual(execute.call_count,2)
        config,fetch=execute.call_args_list
        self.assertEqual(config.args,(['git','config','--local','--includes','--name-only','--list'],SOURCE,10,True))
        command=fetch.args[0]
        self.assertEqual(fetch.args[1:],(SOURCE,60,True))
        self.assertEqual(command[-7:],['fetch','--no-tags','--no-write-fetch-head','--depth=1','--no-recurse-submodules','https://github.com/liboyang42-cpu/chengyin-ios.git','b75f7549678caf51a65ec8942b6a6d0c23e887de'])
        for value in ('credential.helper=','core.askPass=','http.extraHeader=','http.followRedirects=false','protocol.allow=never','protocol.https.allow=always'):self.assertIn(value,command)
        environment=fetch.kwargs['env']
        self.assertEqual(set(environment),{'PATH','LANG','HOME','GIT_TERMINAL_PROMPT','GIT_CONFIG_NOSYSTEM','GIT_CONFIG_GLOBAL','GIT_ASKPASS','SSH_ASKPASS'})
        self.assertNotIn('do-not-forward',environment.values())
        self.assertEqual(environment['GIT_TERMINAL_PROMPT'],'0')
        self.assertEqual(environment['GIT_CONFIG_NOSYSTEM'],'1')
        self.assertEqual(environment['GIT_CONFIG_GLOBAL'],'/dev/null')
        self.assertEqual(environment['HOME'],'/dev/null')
        self.assertEqual(config.kwargs['env'],environment)
        for action in ('checkout','reset','push','pull'):self.assertNotIn(action,command)

    def test_offline_timeout_or_unreadable_config_fail_closed_without_retry(self):
        for mode in ('offline','timeout','config'):
            outputs=[(1,b'')] if mode=='config' else [(0,b'core.bare\n'),(124 if mode=='timeout' else 1,b'')]
            with self.subTest(mode=mode),mock.patch.object(runner,'checked',side_effect=self.missing),mock.patch.object(runner,'execute',side_effect=outputs) as execute,self.assertRaises(ValueError):
                runner.ensure_creator_commit(SOURCE)
            self.assertEqual(execute.call_count,1 if mode=='config' else 2)

    def test_existing_or_fetched_wrong_tree_parent_or_duplicate_parent_is_rejected(self):
        for existing in (True,False):
            for mode in ('tree','parent','merge'):
                headers=self.headers(tree='0'*40) if mode=='tree' else self.headers(parent=runner.BASE_COMMIT) if mode=='parent' else self.headers().replace('\nauthor','\nparent '+'1'*40+'\nauthor')
                def read(command,root):
                    if command[1:3]==['cat-file','-e']:
                        if existing:return ''
                        raise ValueError('Synthetic missing object')
                    return headers
                with self.subTest(existing=existing,mode=mode),mock.patch.object(runner,'checked',side_effect=read),mock.patch.object(runner,'execute',side_effect=[(0,b'core.bare\n'),(0,b'')]) as execute,self.assertRaisesRegex(ValueError,'commit/tree/parent identity'):
                    runner.ensure_creator_commit(SOURCE)
                self.assertEqual(execute.call_count,0 if existing else 2)

    def test_credential_redirect_include_and_auth_configuration_never_reach_fetch(self):
        for key in ('credential.helper','credential.https://github.com.username','http.extraheader','http.https://github.com/.extraheader','http.proxy','url.ssh://example.invalid.insteadof','include.path','includeif.gitdir:work.path','core.askpass','extensions.worktreeconfig'):
            with self.subTest(key=key),mock.patch.object(runner,'checked',side_effect=self.missing),mock.patch.object(runner,'execute',return_value=(0,(key+'\n').encode())) as execute,self.assertRaisesRegex(ValueError,'rejects credential, redirect, or included'):
                runner.ensure_creator_commit(SOURCE)
            self.assertEqual(execute.call_count,1)

    def test_public_target_cannot_be_generalized_by_changing_fixed_identity(self):
        for key in ('CREATOR_COMMIT','CREATOR_TREE','HISTORICAL_BASE_COMMIT'):
            with self.subTest(key=key),mock.patch.object(runner,key,'f'*40),mock.patch.object(runner,'checked') as read,mock.patch.object(runner,'execute') as execute,self.assertRaisesRegex(ValueError,'fixed public creator object target'):
                runner.ensure_creator_commit(SOURCE)
            read.assert_not_called();execute.assert_not_called()


if __name__ == '__main__':
    unittest.main()

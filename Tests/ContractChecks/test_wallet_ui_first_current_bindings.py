"""Current source guards complement exact historical workspace assertions.

These checks are not Swift compilation or native XCTest execution.
"""
from pathlib import Path
import ast
import hashlib
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class WalletUIFirstCurrentBindingTests(unittest.TestCase):
    def test_project_empty_bindings_adopt_only_first_id_in_same_generation(self):
        source = (ROOT / 'App/MerchantProjectsView.swift').read_text()
        summary = source.split('    func summaryBinding()', 1)[1].split('    func workspaceBinding()', 1)[0]
        workspace = source.split('    func workspaceBinding()', 1)[1]
        for fragment, value in [(summary, 'selected'), (workspace, 'current')]:
            self.assertEqual(fragment.count('self.generation == epoch'), 2)
            self.assertIn('if captured == nil { captured = ' + value + '.id }', fragment)
            self.assertIn('return ' + value + '.id == captured ? ' + value + ' : nil', fragment)
        self.assertIn('self.closeSummary(id: captured)', summary)
        self.assertIn('let captured, self.route?.id == captured else { return }', workspace)

    def test_all_current_workspace_regressions_include_original_and_four_new_methods(self):
        source = (ROOT / 'Tests/AppUnitTests/MerchantProjectWorkspaceEntryTests.swift').read_text()
        names = re.findall(r'\bfunc (test\w+)\(', source)
        self.assertEqual(len(names), 28)
        self.assertEqual(len(set(names)), 28)
        for name in ['testOldSummaryBindingCannotDismissReopenedSummary',
                     'testOldWorkspaceBindingCannotPopReopenedWorkspace',
                     'testInitiallyEmptySummaryBindingObservesFirstSelectionAndDismissesOnlyIt',
                     'testUnreadEmptySummaryBindingCannotDismissAfterGenerationRetirement',
                     'testInitiallyEmptyWorkspaceBindingObservesOnlyFirstRoute',
                     'testUnreadEmptyWorkspaceBindingCannotDismissAfterScopeGenerationChanges']:
            self.assertIn(name, names)

    def test_brand_lease_belongs_to_stable_document_and_editor(self):
        source = (ROOT / 'App/MerchantBrandImagesView.swift').read_text()
        entry = source.split('@MainActor struct MerchantBrandImagesEntry', 1)[1].split('/// Presentation belongs', 1)[0]
        for forbidden in ['@State ', '.sheet(', '.onDisappear', 'retire()']:
            self.assertNotIn(forbidden, entry)
        self.assertIn('@Published var brandImagesPresentation: MerchantBrandImagesModel?', (ROOT / 'App/MerchantOperationsViews.swift').read_text())
        self.assertIn('.modifier(MerchantBrandImagesPresentation(document: model))', (ROOT / 'App/MerchantOperationsEditor.swift').read_text())
        for guard in ['document.brandImagesPresentation?.id == value.id',
                      '.onChange(of: document.coordinator.reader.scope)',
                      '.onChange(of: document.coordinator.draftIdentity)',
                      '.onChange(of: document.coordinator.draft)',
                      '.onChange(of: document.coordinator.confirmation)',
                      '.onChange(of: scenePhase)', '.onDisappear { model.retire() }']:
            self.assertIn(guard, source)

    def test_exact_template_input_and_original_fresh_list_assertion_remain(self):
        source = (ROOT / 'Tests/AppUITests/MerchantTemplateBrowserFlowTests.swift').read_text()
        for text in ['CGVector(dx: 0.98, dy: 0.9)',
                     'XCTAssertEqual(title.value as? String, "Synthetic template 1")',
                     'XCTAssertEqual(title.value as? String, "Synthetic template 1 refreshed")',
                     'let refreshed = app.staticTexts["Synthetic template 1 refreshed"]',
                     'XCTAssertTrue(revealFixtureElement(refreshed, in: app, requiresHittable: false))']:
            self.assertIn(text, source)

    def test_historical_workspace_loader_keeps_all_original_method_declarations(self):
        source = (ROOT / 'Tests/ContractChecks/test_merchant_project_workspace_entry.py').read_text()
        tree = ast.parse(source)
        cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'ProjectWorkspaceContracts')
        self.assertEqual(sum(isinstance(n, ast.FunctionDef) and n.name.startswith('test_') for n in cls.body), 20)
        self.assertIn("_workspace_fixed_history().load('Tests/ContractChecks/test_merchant_project_workspace_entry.py')", source)
        load = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'load_tests')
        assignment = next(n for n in load.body if isinstance(n, ast.Assign) and n.targets[0].id == 'historical_names')
        historical_names = ast.literal_eval(assignment.value.args[0])
        self.assertEqual(historical_names, {
            'test_exact_inverse_of_all_five_existing_files',
            'test_existing_transactions_grants_sensitive_routes_and_invitation_remain_exact',
            'test_hosted_lifecycle_tests_are_authored',
            'test_old_summary_and_navigation_bindings_are_id_bound',
        })
        names = {n.name for n in cls.body if isinstance(n, ast.FunctionDef) and n.name.startswith('test_')}
        self.assertEqual(len(names - historical_names), 16)
        self.assertIn('names != old_names or not historical_names <= set(names)', source)
        self.assertIn('historical.ProjectWorkspaceContracts if name in historical_names', source)
        self.assertIn('else ProjectWorkspaceContracts)(name) for name in names', source)
        self.assertNotIn('SkipTest', source)
        self.assertNotIn('@unittest.skip', source)

    def test_current_roam_lifecycle_and_read_masks_reject_missing_guards(self):
        # Current behavior remains checked independently of four old-text methods.
        import test_roam_route_replay as replay
        core = (ROOT / 'Core/RoamExperienceMath.swift').read_text()
        view = (ROOT / 'App/RoamExperienceComponents.swift').read_text()
        detail = (ROOT / 'App/RoamHistoryViews.swift').read_text().split('@MainActor struct RoamHistoryDetailView:', 1)[1]
        self.assertEqual(replay.core_contract(core), [])
        self.assertEqual(replay.replay_contract(view), [])
        markers = {
            'current_record': 'loadedOwner == readKey ? record : nil',
            'current_error': 'loadedOwner == readKey ? error : nil',
            'current_loaded': 'loadedOwner == readKey && loaded',
            'task_retirement': '.task(id: readKey) { showShare = false; selectedMedal = nil; load() }',
            'change_retirement': '.onChange(of: readKey) { _, _ in showShare = false; selectedMedal = nil }',
            'clear_before_read': 'record = nil; error = nil; loaded = false; loadedOwner = nil',
            'same_read_key': 'let captured = readKey',
        }
        def errors(source):
            result = [key for key, value in markers.items() if source.count(value) != 1]
            if source.count('guard captured == readKey else { return }') != 2:
                result.append('both_read_acceptance_guards')
            if source.count('reader.history()') != 1:
                result.append('one_local_read')
            return result
        self.assertEqual(errors(detail), [])
        for key, marker in markers.items():
            with self.subTest(guard=key):
                self.assertIn(key, errors(detail.replace(marker, '', 1)))
        guard = 'guard captured == readKey else { return }'
        for offset in [detail.index(guard), detail.rindex(guard)]:
            self.assertIn('both_read_acceptance_guards', errors(detail[:offset] + detail[offset:].replace(guard, '', 1)))

if __name__ == '__main__':
    unittest.main()

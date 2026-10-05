"""Supplementary source/fixture checks only; Apple compilation and XCUITest remain required.

This is a reconstructed successor, not verification of the unavailable historical patch.
These checks inspect wiring and corpus data. They do not execute Swift or prove UI behavior.
"""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


def fixture_rows(name):
    source = read('App/DiscoveryFixtureReader.swift')
    return json.loads(re.search(r'static let ' + name + r' = #"(.*?)"#', source).group(1))


class TemplateMetadataUIAcceptanceChecks(unittest.TestCase):
    def test_fixtures_remain_debug_only_and_offline(self):
        for path in ['App/DiscoveryFixtureReader.swift', 'App/TemplateAuthoringFixtureSupport.swift']:
            source = read(path)
            self.assertTrue(source.startswith('#if DEBUG\n'))
            self.assertTrue(source.rstrip().endswith('#endif'))
            for forbidden in ['URLSession', 'http://', 'https://', 'authorizationToken', 'APIClient(']:
                self.assertNotIn(forbidden, source)

    def test_metadata_scenario_is_opt_in_and_ordinary_reader_stays_default(self):
        source = read('App/DiscoveryFixtureReader.swift')
        self.assertIn('metadataScenario: MetadataScenario? = nil', source)
        self.assertIn('if metadataScenario != nil', source)
        self.assertIn('guard self.metadataScenario != nil else { return try await self.discoveryCategories(type: 4) }', source)
        host = read('App/TemplateAuthoringFixtureSupport.swift')
        self.assertIn('environment["--template-author-metadata-scenario"]', host)
        self.assertIn('metadataReader: context.metadataReader', host)

    def test_player_rows_decode_exact_wire_keys_and_nonlabel_value(self):
        rows = fixture_rows('metadataPlayersJSON')
        self.assertTrue(all(set(row) == {'dictValue', 'dictLabel'} for row in rows))
        self.assertEqual(rows[0]['dictValue'].encode(), b'  team:2-6  ')
        self.assertNotEqual(rows[0]['dictValue'], rows[0]['dictLabel'])
        source = read('App/DiscoveryFixtureReader.swift')
        self.assertIn('decode([TemplateMetadataOption].self,', source)
        self.assertIn('JSONDecoder().decode(type, from: Data(json.utf8))', source)
        core = read('Core/TemplateMetadata.swift')
        self.assertIn('case value = "dictValue", label = "dictLabel"', core)

    def test_duration_corpus_has_exactly_one_supported_spelling(self):
        rows = fixture_rows('metadataDurationJSON')
        self.assertEqual([row['dictValue'] for row in rows], ['45', '045', '+45', '45.0', '2147483648'])
        def exact_int32(value):
            try:
                number = int(value)
            except ValueError:
                return False
            return -(2**31) <= number < 2**31 and str(number) == value
        self.assertEqual([row['dictValue'] for row in rows if exact_int32(row['dictValue'])], ['45'])
        self.assertIn('Int32(value), String(minutes) == value', read('Core/TemplateMetadata.swift'))

    def test_category_json_preserves_order_and_known_unknown_distinction(self):
        rows = fixture_rows('metadataCategoriesJSON')
        self.assertEqual([row['id'] for row in rows], [11, 12] + list(range(101, 114)))
        self.assertTrue(all(set(row) == {'id', 'categoryName', 'type'} and row['type'] == 4 for row in rows))
        self.assertNotIn(999, [row['id'] for row in rows])
        self.assertEqual(len({row['id'] for row in rows}), len(rows))

    def test_required_read_request_overrides_reach_real_reader_methods(self):
        source = read('App/DiscoveryFixtureReader.swift')
        self.assertIn('func templateMetadataDictionaryRequest(kind: TemplateMetadataKind) -> DiscoveryReadRequest<[TemplateMetadataOption]>', source)
        self.assertIn('return try await self.templateMetadataDictionary(kind: kind)', source)
        self.assertIn('func templateMetadataCategoriesRequest() -> DiscoveryReadRequest<[DiscoveryCategory]>', source)
        self.assertIn('return try self.decode([DiscoveryCategory].self, Self.metadataCategoriesJSON)', source)
        selector = read('App/TemplateAuthoringMetadataSelectors.swift')
        self.assertIn('reader.templateMetadataDictionaryRequest(kind: kind)', selector)
        self.assertIn('reader.templateMetadataCategoriesRequest()', selector)

    def test_read_ledgers_use_dictionary_namespace_and_independent_completions(self):
        source = read('App/DiscoveryFixtureReader.swift')
        self.assertIn('metadataReadInvocations.append(kind.rawValue)', source)
        self.assertIn('defer { metadataReadCompletions.append(kind.rawValue) }', source)
        self.assertIn('metadataReadInvocations.append("categories:4")', source)
        self.assertIn('defer { self.metadataReadCompletions.append("categories:4") }', source)
        self.assertNotIn('transport.requests', source)

    def test_lifecycle_has_real_suspended_continuation_and_distinct_read_states(self):
        source = read('App/DiscoveryFixtureReader.swift')
        for text in ['case 1: throw APIError.notConfigured', 'case 2: throw APIError.httpStatus(503)',
                     'case 3: return []', 'withCheckedThrowingContinuation',
                     'heldMetadataRead = continuation', 'continuation?.resume(returning:',
                     'heldMetadataRead == nil ? 0 : 1']:
            self.assertIn(text, source)
        self.assertNotIn('Task.sleep', source)

    def test_owner_is_invalidated_before_releasing_canceled_read(self):
        host = read('App/TemplateAuthoringFixtureSupport.swift')
        switch = host.split('func switchAccount()')[1].split('func reopen()')[0]
        self.assertLess(switch.index('coordinator.synchronizeSession()'), switch.index('metadataReader.releaseHeldMetadataRead()'))
        ui = read('Tests/AppUITests/TemplateMetadataSelectorsFlowTests.swift')
        self.assertIn('reads(held, beforeHold + [playersRead], pending: 1)', ui)
        self.assertIn('XCTAssertEqual(switched.accountID, 902)', ui)
        self.assertIn('reads(switched, beforeHold + [playersRead])', ui)
        selector = read('App/TemplateAuthoringMetadataSelectors.swift')
        self.assertIn('stamp == generation && canEdit && !Task.isCancelled', selector)
        self.assertIn('active && model.canReadMetadataDraft', selector)

    def test_seed_is_initial_input_not_a_later_draft_or_lock_mutator(self):
        host = read('App/TemplateAuthoringFixtureSupport.swift')
        seed_block = host.split('switch metadataReader.metadataScenario')[1].split('c.open(seed: seed)')[0]
        self.assertIn('seed.players = nil; seed.duration = nil', seed_block)
        self.assertIn('seed.activityCategoryids = " 999, 11,12 "; seed.categoryId = 777', seed_block)
        for forbidden in ['coordinator.change(', 'coordinator.prepare(', 'coordinator.confirm(', 'savePending(', 'locked = true']:
            self.assertNotIn(forbidden, host)

    def test_probe_reads_actual_coordinator_and_last_synthetic_request(self):
        host = read('App/TemplateAuthoringFixtureSupport.swift')
        probe = host.split('func inspectLocalDraft()')[1].split('@MainActor struct')[0]
        for text in ['draft: coordinator.draft', 'requestCount: transport.requests.count',
                     'case .json(let fields) = request.body', 'lastRequestFields = fields',
                     'lastRequestPath: transport.requests.last?.path', 'locked: coordinator.locked',
                     'metadataReadInvocations: metadataReader.metadataReadInvocations',
                     'metadataReadCompletions: metadataReader.metadataReadCompletions']:
            self.assertIn(text, probe)
        for forbidden in ['seed.', 'coordinator.change(', 'saveLocal()', 'metadataPlayersJSON']:
            self.assertNotIn(forbidden, probe)

    def test_three_single_launch_journeys_have_only_unmeasured_estimates(self):
        ui = read('Tests/AppUITests/TemplateMetadataSelectorsFlowTests.swift')
        methods = re.findall(r'func (test\w+)\(', ui)
        self.assertEqual(methods, ['testExactDictionaryValuesCancelRestoreAndSyntheticRequest',
            'testCategorySaveCancelNoopCSVAndOrderedSixteenSelections',
            'testUnavailableRetryEmptyCanceledReadOwnerSwitchAndLockedValues'])
        self.assertEqual(len(re.findall(r'let app = launch\(', ui)), 3)
        self.assertIn('240 + 360 + 420 = 1,020 seconds', ui)
        self.assertEqual(ui.count('UNMEASURED estimate:'), 3)

    def test_lazy_rows_are_revealed_before_existence_checks(self):
        ui = read('Tests/AppUITests/TemplateMetadataSelectorsFlowTests.swift')
        option = ui.split('private func option(')[1].split('private func choose(')[0]
        self.assertIn('reveal(row, in: app', option)
        self.assertNotIn('waitForExistence', option)
        category = ui.split('private func category(')[1].split('private func toggle(')[0]
        self.assertIn('reveal(row, in: app', category)
        self.assertNotIn('waitForExistence', category)
        reveal = ui.split('private func reveal(')[1].split('private func tap(')[0]
        self.assertLess(reveal.index('revealFixtureElement('), reveal.index('XCTAssertTrue(element.exists'))

    def test_csv_assertions_cover_cancel_noop_order_restore_and_primary_independence(self):
        ui = read('Tests/AppUITests/TemplateMetadataSelectorsFlowTests.swift')
        final_csv = re.search(r'private let selectedCSV = "([^"]+)"', ui).group(1)
        self.assertEqual(final_csv, '999,11,12,103,101,102,104,105,106,107,108,109,110,111,112,113')
        self.assertEqual(len(set(final_csv.split(','))), 16)
        journey = ui.split('func testCategorySaveCancelNoopCSVAndOrderedSixteenSelections')[1].split('// UNMEASURED estimate: 420')[0]
        self.assertIn('toggle(101, in: app); close(app)', journey)
        self.assertIn('toggle(101, in: app); toggle(101, in: app, from: true)', journey)
        self.assertIn('Array(repeating: categoriesRead, count: 5)', journey)
        self.assertIn('try saveAndRestore(app)', journey)
        self.assertIn('XCTAssertEqual(final.draft.categoryId, 777)', journey)
        self.assertIn('Array($0.utf8)', ui)

    def test_confirmation_is_the_normal_flow_with_zero_write_cancel_and_actual_request(self):
        ui = read('Tests/AppUITests/TemplateMetadataSelectorsFlowTests.swift')
        for text in ['tap("templateAuthor.reviewDraft", in: app)',
                     'tap("templateAuthor.cancelReview", in: app)',
                     'tap("templateAuthor.confirmSimulation", in: app)',
                     'inspect(app, requests: 1, locked: true)',
                     'let request = try XCTUnwrap(locked.lastRequestFields)',
                     'bytes(request.players, exactPlayers)', 'XCTAssertEqual(request.duration, 45)']:
            self.assertIn(text, ui)
        for forbidden in ['TemplateAuthoringDraft(', 'coordinator.', 'savePending(', 'launchEnvironment["locked']:
            self.assertNotIn(forbidden, ui)

    def test_locked_readback_and_signout_cover_all_metadata_fields(self):
        ui = read('Tests/AppUITests/TemplateMetadataSelectorsFlowTests.swift')
        self.assertIn('lockedValue("players", exactPlayers', ui)
        self.assertIn('lockedValue("duration", "45"', ui)
        self.assertIn('lockedValue("categories", "12"', ui)
        helper = ui.split('private func lockedValue(')[1].split('// UNMEASURED estimate: 240')[0]
        self.assertIn('reveal(row, in: app', helper)
        self.assertIn('XCTAssertFalse(row.isEnabled)', helper)
        self.assertIn('row.label.contains(expected)', helper)
        self.assertIn('tap("templateAuthor.fixture.signOut", in: app)', ui)
        self.assertIn('XCTAssertNil(signedOut.draft.players)', ui)
        self.assertIn('XCTAssertNil(signedOut.draft.duration)', ui)
        self.assertIn('XCTAssertNil(signedOut.draft.activityCategoryids)', ui)


if __name__ == '__main__':
    unittest.main()

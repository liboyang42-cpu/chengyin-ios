"""Offline source assertions, not Swift execution or Apple UI evidence."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TopicSessionSelectionChecks(unittest.TestCase):
    def setUp(self):
        self.core = (ROOT / 'Core/TopicSessionSelection.swift').read_text()
        self.sheet = (ROOT / 'App/TopicSessionSelectionView.swift').read_text()
        self.detail = (ROOT / 'App/TopicDetailView.swift').read_text()
        self.fragment = json.loads((ROOT / 'Resources/TopicSessionSelectionLocalizations.fragment.json').read_text())

    def test_bottom_button_opens_sheet_and_return_refreshes_same_topic(self):
        for value in ['Button("topic.sessionSelection.enroll")',
                      'if !showingSessionSelection { showingSessionSelection = true }',
                      '.sheet(isPresented: $showingSessionSelection, onDismiss: { loads.start { await load() } })',
                      'TopicSessionSelectionView(detail: value, scope: key.scope, activityDestination: activityDestination)',
                      'showingSessionSelection = false']:
            self.assertIn(value, self.detail)
        # The pre-existing inline activity rows keep using the same destination.
        self.assertIn('activityDestination(activity.id)', self.detail)

    def test_selection_forwards_only_real_activity_ids(self):
        self.assertIn('flow.select(activityID: activity.id, hasDestination: activityDestination != nil)', self.sheet)
        self.assertIn('activityDestination(activityID)', self.sheet)
        self.assertIn('snapshotIDs.contains(activityID)', self.core)
        for forbidden in ['ticket.id', 'activityDestination(ticket', 'omsTicketList']:
            self.assertNotIn(forbidden, self.sheet)
            self.assertNotIn(forbidden, self.core)

    def test_distinct_results_for_missing_empty_and_uninjected_destination(self):
        for value in ['case missingData', 'case empty', 'case destinationUnavailable', 'case ready',
                      'guard let activities else { return .missingData }',
                      'guard !activities.isEmpty else { return .empty }']:
            self.assertIn(value, self.core)
        for value in ['topic.sessionSelection.missingData', 'topic.sessionSelection.empty',
                      'topic.sessionSelection.destinationUnavailable']:
            self.assertIn(value, self.sheet)

    def test_stale_duplicate_background_and_scope_guards(self):
        for value in ['guard !isPresented else { return presentation }',
                      'selectedActivityID == nil', 'public mutating func backgrounded()',
                      'public mutating func scopeChanged(to newScope: UUID) -> Bool',
                      'public mutating func returnedFromActivity()']:
            self.assertIn(value, self.core)
        for value in ['if phase != .active, flow.isPresented { flow.backgrounded(); dismiss() }',
                      'if flow.scopeChanged(to: newScope) { dismiss() }',
                      'if newPath.isEmpty { flow.returnedFromActivity() }']:
            self.assertIn(value, self.sheet)

    def test_tickets_are_display_only_with_dependency_note(self):
        self.assertIn('topic.sessionSelection.ticketDependency', self.sheet)
        self.assertIn('ForEach(Array(detail.tickets.enumerated())', self.sheet)

    def test_no_new_api_inventory_currency_or_write_path(self):
        for source in [self.core, self.sheet]:
            for forbidden in ['URLSession', 'HTTPTransport', 'APIConfiguration', '¥', '$"', 'remainingInventory',
                              'enroll(', 'signUp(', 'register(']:
                self.assertNotIn(forbidden, source)

    def test_fragment_keys_match_sheet_and_detail_usage_and_are_bilingual(self):
        strings = self.fragment['strings']
        used = {key for key in strings if key in self.sheet or key in self.detail}
        self.assertEqual(used, set(strings))
        for key, entry in strings.items():
            self.assertEqual(set(entry['localizations']), {'en', 'zh-Hans'}, key)
        self.assertIn('Sign up now', strings['topic.sessionSelection.enroll']['localizations']['en']['stringUnit']['value'])
        self.assertIn('立即报名', strings['topic.sessionSelection.enroll']['localizations']['zh-Hans']['stringUnit']['value'])
        self.assertIn('ticket-to-activity', strings['topic.sessionSelection.ticketDependency']['localizations']['en']['stringUnit']['value'])

    def test_authored_core_tests_cover_required_guards(self):
        unit = (ROOT / 'Tests/CoreTests/TopicSessionSelectionTests.swift').read_text()
        for name in ['testResolutionDistinguishesMissingEmptyUnavailableAndReady',
                     'testSelectionUsesOnlyRealActivityIDsFromTheCapturedSnapshot',
                     'testDuplicateTapAndMissingDestinationCannotSelect',
                     'testCloseReopenBackgroundAndScopeChangeRejectStaleIDs']:
            self.assertIn(name, unit)


if __name__ == '__main__':
    unittest.main()

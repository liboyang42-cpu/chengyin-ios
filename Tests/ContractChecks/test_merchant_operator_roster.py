"""Offline source contracts; not Swift compiler, XCTest, UI or live-service evidence."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = 'Core/MerchantOperatorRoster.swift'
APP = 'App/MerchantOperatorRosterSections.swift'
FRAGMENT = 'Resources/MerchantOperatorRosterLocalizations.fragment.json'


class MerchantOperatorRosterContracts(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_only_the_existing_team_query_can_supply_the_projection(self):
        source = self.read(CORE)
        self.assertIn('guard document.query == .operators else { throw MerchantBusinessFailure.malformed }', source)
        self.assertIn('for row in document.rows', source)
        self.assertIn('default: throw MerchantBusinessFailure.malformed', source)

    def test_exact_mini_statuses_define_current_rows_and_all_other_known_statuses_survive(self):
        source = self.read(CORE)
        for value in ['case (.operatorMember, "ACTIVE"): active.append(row)',
                      'case (.operatorMember, "REVOKED"): members.append(row)',
                      'case (.invite, "PENDING"): pending.append(row)',
                      'case (.invite, "ACCEPTED"), (.invite, "EXPIRED"), (.invite, "REVOKED"): invites.append(row)']:
            self.assertIn(value, source)
        for forbidden in ['Date(', 'expiresAt', '.sorted(', '.lowercased()', 'trimmingCharacters', 'roleCode']:
            self.assertNotIn(forbidden, source)

    def test_roster_is_immutable_and_retains_original_record_types(self):
        source = self.read(CORE)
        for name in ['activeMembers', 'pendingInvites', 'previousMembers', 'previousInvites']:
            self.assertIn('public let ' + name + ': [MerchantBusinessRecord]', source)
        self.assertNotIn('MerchantBusinessRecord(', source)
        self.assertNotIn('Set(', source)

    def test_page_uses_current_snapshot_and_the_same_existing_row_renderer(self):
        source = self.read('App/MerchantBusinessViews.swift')
        self.assertIn('if let snapshot = state.snapshot, state.isCurrent {', source)
        self.assertIn('if query != .operators, snapshot.document.sections.allSatisfy', source)
        self.assertIn('if query == .operators {\n                    if let roster = try? MerchantOperatorRoster(document: snapshot.document)', source)
        self.assertIn('MerchantOperatorRosterSections(roster: roster, access: snapshot.access) { row in\n                            rowView(row, access: snapshot.access)', source)
        self.assertIn('else { Text("merchant.operatorRoster.unavailable")', source)
        self.assertIn('if access.canManageOperators {', source)
        self.assertIn('row.kind == .operatorMember, row.fields.mbText("status") == "ACTIVE"', source)
        self.assertIn('row.kind == .invite, row.fields.mbText("status") == "PENDING"', source)

    def test_loaded_counts_independent_empty_states_and_history_are_reachable(self):
        source = self.read(APP)
        for value in ['if access.canManageOperators', 'String(roster.activeMembers.count)',
                      'String(roster.pendingInvites.count)', 'if roster.activeMembers.isEmpty',
                      'if roster.pendingInvites.isEmpty', 'if roster.hasHistory',
                      'DisclosureGroup("merchant.operatorRoster.previousMembers")',
                      'DisclosureGroup("merchant.operatorRoster.previousInvites")']:
            self.assertIn(value, source)
        for group in ['activeMembers', 'pendingInvites', 'previousMembers', 'previousInvites']:
            self.assertIn('ForEach(roster.' + group + ') { row in rowContent(row) }', source)

    def test_no_new_authorization_transport_persistence_or_action_dispatch(self):
        source = self.read(CORE) + self.read(APP)
        for forbidden in ['URLSession', 'URLRequest', 'UserDefaults', 'FileManager',
                          'UIPasteboard', '.execute(', '.reserve(', '.confirm(',
                          '.task(', 'api/', 'canExecute', 'token', '@State', '@AppStorage']:
            self.assertNotIn(forbidden, source)

    def test_accessibility_and_dynamic_type_preserve_content(self):
        source = self.read(APP)
        self.assertIn('.frame(minHeight: 44)', source)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', source)
        for name in ['memberCount', 'inviteCount', 'membersEmpty', 'invitesEmpty', 'previousMembers', 'previousInvites']:
            self.assertIn('.accessibilityIdentifier("merchant.operatorRoster.' + name + '")', source)
        self.assertNotIn('.lineLimit(', source)
        self.assertNotIn('.frame(height:', source)

    def test_every_display_string_is_bilingual_and_scope_is_loaded_not_global(self):
        fragment = json.loads(self.read(FRAGMENT))
        self.assertEqual(len(fragment), 12)
        app = re.sub(r'\.accessibilityIdentifier\([^\n]*', '', self.read(APP))
        page = self.read('App/MerchantBusinessViews.swift')
        keys = set(re.findall(r'"(merchant\.operatorRoster\.[A-Za-z]+)"', app + page))
        self.assertEqual(keys, set(fragment))
        for key, value in fragment.items():
            self.assertEqual(set(value['localizations']), {'en', 'zh-Hans'}, key)
            for row in value['localizations'].values():
                self.assertTrue(row['stringUnit']['value'].strip(), key)
        en = lambda name: fragment['merchant.operatorRoster.' + name]['localizations']['en']['stringUnit']['value']
        self.assertIn('latest loaded', en('loadedScope'))
        self.assertIn('server', en('historyScope'))
        self.assertIn('in this list', en('membersEmpty'))
        self.assertIn('in this list', en('invitesEmpty'))

    def test_existing_journal_and_scope_cancellation_remain_on_the_owner(self):
        page = self.read('App/MerchantBusinessViews.swift')
        for value in ['.onChange(of: reader.scope)', '.onChange(of: reader.authorizationGeneration)',
                      '.onDisappear { editor = nil; pendingMutation = nil; model.invalidate() }',
                      'if state.isLocked { Text("merchant.business.unknownResult")',
                      'if query == .operators, snapshot.access.canManageOperators']:
            self.assertIn(value, page)
        coordinator = self.read('Core/MerchantBusinessCoordinator.swift')
        confirm = coordinator.split('public func confirm')[1]
        self.assertLess(confirm.index('latest == review.baseline'), confirm.index('journal.reserve'))
        self.assertLess(confirm.index('journal.reserve'), confirm.index('reader.execute'))

    def test_behavioral_negatives_are_authored_separately(self):
        source = self.read('Tests/CoreTests/MerchantOperatorRosterTests.swift')
        self.assertEqual(len(re.findall(r'    func test\w+\(', source)), 12)
        for name in ['testProjectionKeepsOriginalRecordsVersionsAndOrderWithinEachGroup',
                     'testMatchingNumericIDsRemainSeparateMemberAndInvitationIdentities',
                     'testServerStatusIsNotInferredFromOldOrFutureExpiryDates',
                     'testRefreshedResponseReplacesPreviousStateWithoutCaching',
                     'testUnknownAndNormalizedStatusVariantsFailExistingDocumentBoundary',
                     'testProjectionDoesNotChangeExistingExactMutationPayloads']:
            self.assertIn('func ' + name, source)


if __name__ == '__main__':
    unittest.main(verbosity=2)

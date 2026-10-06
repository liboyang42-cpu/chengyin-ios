"""Coop row hit area and fixture observation boundary; no Apple execution claim."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CoopProfileEntryLifetimeChecks(unittest.TestCase):
    def test_actual_plain_button_has_a_complete_rectangular_label(self):
        s = (ROOT / 'App/CoopRelationDiscoveryView.swift').read_text()
        button = s.split('guard canOpen(choice) else { return }')[1].split('.accessibilityIdentifier("cooprelation.open.')[0]
        for text in ['selection = choice', 'card(row)', '.frame(maxWidth: .infinity, alignment: .leading)',
                     '.contentShape(Rectangle())', '.buttonStyle(.plain)']:
            self.assertIn(text, button)
        self.assertIn('selection?.id == choice.id && canOpen(choice)', s)
        self.assertIn('guard loadedKey == key', s)

    def test_read_counters_publish_only_through_the_dedicated_fixture_ledger(self):
        s = (ROOT / 'App/CoopRelationDiscoveryFixture.swift').read_text()
        reader = s.split('final class CoopRelationFixtureReader:')[1].split('struct CoopRelationFixtureHost:')[0]
        self.assertIn('@Published var session', reader); self.assertIn('@Published var scope', reader)
        for count in ['reads', 'ownerReads', 'clubReads']:
            self.assertNotIn('@Published var ' + count, reader)
            self.assertIn('ledger.' + count + ' += 1', reader)
            self.assertIn('var ' + count + ': Int { ledger.' + count + ' }', reader)
        counter = s.split('private struct CoopRelationFixtureReadCounter:')[1].split('final class CoopRelationFixtureReader:')[0]
        self.assertIn('@ObservedObject var ledger:', counter)
        self.assertIn('cooprelation.fixture.profileReads', counter)

    def test_only_harness_chrome_is_size_limited_and_original_identity_actions_remain(self):
        s = (ROOT / 'App/CoopRelationDiscoveryFixture.swift').read_text()
        host = s.split('struct CoopRelationFixtureHost:')[1]
        before, stack = host.split('NavigationStack {', 1)
        self.assertIn('CoopRelationFixtureReadCounter(ledger: reader.ledger)', before)
        self.assertIn('.dynamicTypeSize(.large)', before)
        self.assertIn('reader.session = nil; reader.scope = UUID()', before)
        self.assertIn('.environment(\\.cooperationRelationDiscovery', stack)
        self.assertIn('? .accessibility5 : .large)', stack)

    def test_true_reader_and_profile_adapter_regressions_are_authored(self):
        s = (ROOT / 'Tests/AppUnitTests/CoopRelationProfileReadTests.swift').read_text()
        for name in ['testRealReadAccountingDoesNotRepublishTheNavigationIdentityOwner',
                     'testIdentityReplacementStillPublishesAndRejectsTheOldScopedProfile',
                     'testAcceptedClubChoiceStaysCurrentDuringItsOwnLedgerPublication',
                     'testCountersRemainMonotonicAcrossSyntheticIdentityChangesAndFailures']:
            self.assertIn('func ' + name, s)


if __name__ == '__main__':
    unittest.main()

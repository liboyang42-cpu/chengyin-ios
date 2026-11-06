from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]


class PurchasedUpgradeEntryChecks(unittest.TestCase):
    def read(self, p):
        return (ROOT / p).read_text()

    def test_symbols_and_default_closed(self):
        e = self.read('App/WorkshopPurchasedUpgradeEntry.swift')
        for x in ['WorkshopPurchasedUpgradeHandlers', 'WorkshopPurchasedUpgradeFactory = () -> WorkshopPurchasedUpgradeHandlers?',
                  'WorkshopPurchasedUpgradeEntry', 'WorkshopModUpgradeSheetView(presentation: presentation)', 'saveDraft', 'showing = false',
                  'performBeginCompare', 'performFinishCompare', 'performSaveDraft', 'performDismissSheet']:
            self.assertIn(x, e)
        v = self.read('App/WorkshopPurchasedLibraryView.swift')
        self.assertEqual(v.count('makeUpgrade: @escaping WorkshopPurchasedUpgradeFactory = { nil }'), 3)
        self.assertIn('if let handlers = makeUpgrade() { WorkshopPurchasedUpgradeEntry(item: item, handlers: handlers) }', v)

    def test_no_endpoint_or_network_and_no_guessed_versions(self):
        e = '\n'.join(l for l in self.read('App/WorkshopPurchasedUpgradeEntry.swift').split('\n') if not l.strip().startswith('///'))
        for bad in ['URLSession', 'http://', 'https://', '/api/', 'CompareModVersions', 'UpgradeInstallDraft', 'WorkshopModVersionRef(', 'coverage: .covered']:
            self.assertNotIn(bad, e)
        self.assertIsNone(re.search(r'"/[a-z]+/', e))

    def test_unit_test_exists(self):
        t = self.read('Tests/AppUnitTests/StoryWalkingFogAndWorkshopUpgradeViewTests.swift')
        self.assertIn('testPurchasedUpgradeEntryHostsInjectedCompareAndStaysClosedByDefault', t)
        self.assertIn('testWorkshopModUpgradeSheetViewInstantiatesBreakingAndCompatibleDiffWithConfirmationGate', t)


if __name__ == '__main__':
    unittest.main()

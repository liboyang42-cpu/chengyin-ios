"""Source checks only: v1 workshop routes answer 409 WORKSHOP_CONTRACT_UPGRADE_REQUIRED.
These do not execute Swift or HTTP; the Swift behaviour tests live in WorkshopPaidInstallTests."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]
SERVICES = {
    'Core/WorkshopPurchasedService.swift': 'WorkshopPurchasedIssue.upgradeRequired',
    'Core/WorkshopPaidInstallService.swift': 'WorkshopPaidInstallIssue.upgradeRequired',
    'Core/WorkshopPaidInstalledTextService.swift': 'WorkshopPaidInstalledTextIssue.upgradeRequired',
    'Core/WorkshopPaidProfessionalService.swift': 'WorkshopPaidProfessionalIssue.upgradeRequired',
}


class WorkshopContractUpgradeChecks(unittest.TestCase):
    def read(self, name): return (ROOT / name).read_text()

    def test_exact_backend_envelope_is_matched(self):
        s = self.read('Core/WorkshopContractUpgrade.swift')
        self.assertIn('"WORKSHOP_CONTRACT_UPGRADE_REQUIRED"', s)
        self.assertIn('public static let code = 409', s)
        self.assertIn('envelope.msg == message', s)

    def test_every_v1_service_decodes_the_refusal_before_generic_mapping(self):
        for path, issue in SERVICES.items():
            s = self.read(path)
            self.assertIn('WorkshopContractUpgrade.isRequired(data: data, status: status)', s, path)
            self.assertIn(issue, s, path)

    def test_install_submit_refusal_is_not_reported_as_unknown(self):
        s = self.read('Core/WorkshopPaidInstallService.swift').split('public func submit(', 1)[1].split('private func read', 1)[0]
        self.assertLess(s.index('== .upgradeRequired'), s.index('throw WorkshopPaidInstallIssue.outcomeUnknown\n        }'))
        p = self.read('Core/WorkshopPaidProfessionalService.swift')
        self.assertIn('issue == .unauthorized || issue == .upgradeRequired { throw issue }', p)

    def test_library_shows_update_instead_of_empty_and_hides_retry(self):
        b = self.read('Core/WorkshopPurchasedBrowser.swift')
        self.assertIn('issue == .upgradeRequired ? .notEnabled', b)
        v = self.read('App/WorkshopPurchasedLibraryView.swift')
        self.assertIn('PurchasedUnavailableView(upgradeRequired: browser.issue == .upgradeRequired)', v)
        self.assertIn('issue != .upgradeRequired', v)

    def test_strings_exist_in_english_and_chinese(self):
        for table, keys in {
            'WorkshopPurchased': ['workshopPurchased.upgradeRequired', 'workshopPurchased.upgradeRequiredDetail'],
            'WorkshopPaidInstall': ['workshopPaidInstall.upgradeRequired'],
            'WorkshopPaidInstalledText': ['workshopPaidInstalledText.upgradeRequired'],
            'WorkshopPaidProfessional': ['workshopPaidProfessional.upgradeRequired'],
        }.items():
            catalog = json.loads((ROOT / 'Resources' / (table + '.xcstrings')).read_text())
            for key in keys:
                loc = catalog['strings'][key]['localizations']
                self.assertEqual(set(loc), {'en', 'zh-Hans'}, key)


if __name__ == '__main__':
    unittest.main()

"""Explicit-locale fixtures must not inherit a prior test's persisted app language."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['ClubCommunityUITests.swift', 'ClubEnrollmentFlowTests.swift', 'ClubGovernanceFlowTests.swift', 'CouponManagementFlowTests.swift', 'JourneyContentFlowTests.swift', 'JourneyRoleViewFlowTests.swift', 'MerchantBusinessFlowTests.swift', 'MerchantMarketingUITests.swift', 'NativeEnrollmentFlowTests.swift', 'NativePlatformFlowTests.swift', 'NativeVerificationFlowTests.swift', 'NearbyTeamUITests.swift', 'OfficialActionUITests.swift', 'OrderLifecycleUITests.swift', 'PlayCompareFlowTests.swift', 'PlayDirectorPrefabFlowTests.swift', 'PublishingModesFlowTests.swift', 'SquareGovernanceFlowTests.swift', 'WalletCommerceFlowTests.swift']
class FixtureLanguageIsolationTests(unittest.TestCase):
    def test_explicit_language_launches_reset_saved_app_preference(self):
        for name in FIXTURES:
            source = (ROOT / 'Tests/AppUITests' / name).read_text()
            launches = re.findall(r'app\.launchArguments\s*\+?=\s*(\[[^\]]*\])', source)
            explicit = [launch for launch in launches if '-AppleLanguages' in launch]
            with self.subTest(fixture=name):
                self.assertTrue(explicit)
                for launch in explicit:
                    self.assertIn('"--uitesting-reset-language"', launch)
if __name__ == '__main__': unittest.main()

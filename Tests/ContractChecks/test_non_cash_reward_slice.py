"""Supplementary source boundary checks, not Swift/UI runtime evidence."""
import json
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class NonCashRewardSliceChecks(unittest.TestCase):
    def test_normal_account_entry_uses_existing_scope(self):
        source = (ROOT / 'App/AccountCollectionFavoritesView.swift').read_text()
        self.assertIn('NonCashRewardsView(reader: reader, rewards: rewards).id(reader.scope)', source)
        self.assertIn('AccountCollectionAccountLinks(', (ROOT / 'App/AccountView.swift').read_text())
    def test_no_live_transport_or_coupon_credential_reuse(self):
        source = (ROOT / 'App/NonCashRewardViews.swift').read_text()
        for forbidden in ['URLSession', 'URLRequest', 'CouponCodeView', 'couponCodeFactory', 'UserDefaults', 'UIPasteboard']:
            self.assertNotIn(forbidden, source)
        self.assertIn('#if DEBUG', source)
        self.assertIn('return nil\n        #endif', source)
        self.assertIn('return []\n        #endif', source)
        self.assertIn('.onChange(of: scenePhase)', source)
        self.assertIn('.onChange(of: reader.scope)', source)
    def test_all_reward_keys_are_bilingual(self):
        import re
        source = (ROOT / 'App/NonCashRewardViews.swift').read_text()
        keys = set(re.findall(r'"(rewards\.[A-Za-z]+)"', source))
        catalog = json.loads((ROOT / 'Resources/Localizable.xcstrings').read_text())['strings']
        for key in keys:
            if key in ['rewards.retry', 'rewards.presentation', 'rewards.close', 'rewards.loadMore']: continue
            for lang in ['en', 'zh-Hans']:
                self.assertTrue(catalog[key]['localizations'][lang]['stringUnit']['value'])
    def test_no_api_decoding_or_reward_authority_added(self):
        source = (ROOT / 'Core/NonCashReward.swift').read_text()
        self.assertNotIn('Codable', source)
        self.assertNotIn('mutating', source)
        self.assertIn('now < validUntil', source)
        self.assertIn('state == .awarded', source)

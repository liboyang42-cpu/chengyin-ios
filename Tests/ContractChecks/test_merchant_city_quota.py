"""Focused source wiring checks; these do not execute Swift or prove runtime behavior."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MerchantCityQuotaContracts(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()

    def test_quota_parser_is_strict_and_zero_is_explicit(self):
        source = self.read('Core/MerchantCityQuota.swift')
        for token in ['case .integer(let used) = catalog["used"], used >= 0',
                      'case .integer(let maximum) = catalog["max"], maximum >= 0',
                      'state = .unknown', 'maximum == 0 ? .none', 'used >= maximum ? .full',
                      'state == .available']:
            self.assertIn(token, source)
        self.assertNotIn('Int(', source)
        self.assertNotIn('.integer ??', source)

    def test_current_snapshot_drives_visible_quota_and_placement_link(self):
        source = self.read('App/MerchantContentViews.swift')
        block = source.split('case .city:', 1)[1].split('case .registration(', 1)[0]
        self.assertIn('let quota = MerchantCityQuota(catalog: s.value)', block)
        self.assertIn('MerchantCityQuotaSummary(quota: quota', block)
        self.assertIn('.disabled(!quota.canPlace || c.busy || c.locked)', block)
        self.assertIn('rows: s.value["nodes"].array ?? []', block)
        self.assertIn('rows: s.value["applications"].array ?? []', block)

    def test_retry_rechecks_snapshot_and_read_generation_inside_task(self):
        source = self.read('App/MerchantContentViews.swift')
        block = source.split('MerchantCityQuotaSummary(quota: quota', 1)[1].split('NavigationLink(', 1)[0]
        guard = block.index('guard c.isCurrent')
        self.assertLess(block.index('Task {'), guard)
        self.assertLess(guard, block.index('await model.load()'))
        for token in ['!c.busy', '!c.locked', 'c.review == nil', 'c.snapshot == s', 'c.snapshot?.observedAt == s.observedAt']:
            self.assertIn(token, block)

    def test_editor_and_command_use_the_same_quota_contract(self):
        editor = self.read('App/MerchantContentEditor.swift')
        self.assertIn('!MerchantCityQuota(catalog: source.value["catalog"]).canPlace', editor)
        self.assertIn('MerchantCityQuotaSummary(quota: .init(catalog: s.value["catalog"]))', editor)
        self.assertIn('try result.validate(against: s)', editor)
        command = self.read('Core/MerchantContentCommands.swift').split('case .place(let draft):')[-1].split('case .saveNPC', 1)[0]
        self.assertIn('try need(MerchantCityQuota(catalog: snapshot.value["catalog"]).canPlace)', command)
        self.assertIn('snapshot.query == .cityPlacement', command)
        self.assertIn('draft.templateID', command)

    def test_existing_reload_and_confirm_preserve_frozen_review_boundaries(self):
        coordinator = self.read('Core/MerchantContentCoordinator.swift')
        load = coordinator.split('public func load()', 1)[1].split('public func prepare', 1)[0]
        self.assertIn('invalidate()', load)
        self.assertIn('review = nil', coordinator.split('public func invalidate()', 1)[1].split('public func cancelReview', 1)[0])
        perform = self.read('Core/MerchantContentService.swift').split('public func perform(', 1)[1].split('let record =', 1)[0]
        self.assertLess(perform.index('let latest = try await load(baseline.query)'), perform.index('guard latest == baseline'))
        self.assertLess(perform.index('guard latest == baseline'), perform.index('try command.validate(against: latest)'))

    def test_summary_has_no_io_and_unique_bilingual_keys(self):
        source = self.read('App/MerchantCityQuotaSummary.swift')
        for forbidden in ['URLSession', 'perform(', 'Task {', 'UserDefaults', 'UIApplication', 'request(']:
            self.assertNotIn(forbidden, source)
        fragment = json.loads(self.read('Resources/MerchantCityQuotaLocalizations.fragment.json'))
        catalog = json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        self.assertEqual(len(fragment), 5)
        self.assertTrue(set(fragment).isdisjoint(catalog))
        for entry in fragment.values():
            for language in ['en', 'zh-Hans']:
                self.assertTrue(entry['localizations'][language]['stringUnit']['value'].strip())

if __name__ == '__main__': unittest.main()

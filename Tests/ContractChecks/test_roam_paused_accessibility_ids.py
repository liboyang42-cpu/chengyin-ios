from pathlib import Path
import re, unittest
ROOT=Path(__file__).resolve().parents[2]
class PausedIdentifiers(unittest.TestCase):
    def setUp(self):
        self.checker=(ROOT/'tools/check_scaffold.py').read_text()
        self.block='var accessibilityID: String { switch self { case .history: return "roam.live.pausedHistory.open"; case .settings: return "roam.live.pausedSettings.open"; case .album: return "roam.live.pausedAlbum.open" } }'
    def test_exact_property_is_nonlocalized_and_used_as_accessibility_identifier(self):
        source=(ROOT/'App/RoamLiveSessionView.swift').read_text()
        self.assertEqual(source.count(self.block),1)
        self.assertIn('.accessibilityIdentifier(kind.accessibilityID)',source)
        self.assertIn('localizable_ui=localizable_ui.replace('+repr(self.block)+", '')",self.checker)
    def test_localized_use_of_identical_literals_remains_checked(self):
        for key in ['roam.live.pausedHistory.open','roam.live.pausedSettings.open','roam.live.pausedAlbum.open']:
            source=self.block+'\nText("'+key+'")'
            cleaned=source.replace(self.block,'')
            self.assertIn(key,re.findall(r'"(roam\.[A-Za-z0-9.]+)"',cleaned))
    def test_changed_property_is_not_exempted(self):
        changed=self.block.replace('pausedHistory.open','pausedHistory.changed')
        self.assertEqual(changed.replace(self.block,''),changed)
    def test_pause_is_still_required_on_real_host_departure(self):
        import test_roam_live_contracts as checks
        original=checks.source
        view=original('App/RoamLiveSessionView.swift')
        changed=view.replace('browse.parentHidden(); owner.pause()', 'browse.parentHidden()')
        self.assertNotEqual(view,changed)
        checks.source=lambda path: changed if path=='App/RoamLiveSessionView.swift' else original(path)
        try:
            with self.assertRaises(AssertionError):
                checks.LiveRoamContracts().test_precise_tracking_is_ephemeral_and_presence_ttl_is_honest()
        finally:
            checks.source=original

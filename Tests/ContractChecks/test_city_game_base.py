"""Source guards for the W20 CITY business section and W19 return-home UI (w2-21).

Independent of Apple tooling; the authored Swift/XCTest files still need an Apple executor.
"""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ['Core/CityGameBoardProjection.swift', 'Core/CityGameCoordinator.swift', 'Core/HomeReturnCoordinator.swift']
APP = ['App/CityGamePanel.swift', 'App/HomeReturnSection.swift']
FIXTURE = 'App/CityGameFixtureHost.swift'


def text(name):
    return (ROOT / name).read_text()


def code(name):
    return '\n'.join(line for line in text(name).splitlines() if not line.strip().startswith('///') and not line.strip().startswith('//'))


class CityGameBaseContracts(unittest.TestCase):
    def test_reviewed_allowlist_is_empty_and_capabilities_stay_off(self):
        projection = text('Core/CityGameBoardProjection.swift')
        self.assertIn('public static let reviewed: [RegionalMarket: Set<CityGameOperation>] = [:]', projection)
        capabilities = text('Core/ReformWorldCapabilities.swift')
        self.assertIn('public static let disabled = ReformWorldCapabilities(enabled: [])', capabilities)
        self.assertIn('if service == nil || !capabilities.allows(.cityActions)', text('Core/CityGameCoordinator.swift'))
        self.assertIn('if service == nil || !capabilities.allows(.homeReturnRestore)', text('Core/HomeReturnCoordinator.swift'))

    def test_core_performs_no_io_and_carries_no_location_or_client_economics(self):
        for name in CORE:
            source = code(name)
            for forbidden in ['URLRequest', 'URLSession', 'HTTPTransport', 'UserDefaults', 'CLLocationManager', 'FileManager', 'print(']:
                self.assertNotIn(forbidden, source, (name, forbidden))
        projection = code('Core/CityGameBoardProjection.swift')
        self.assertNotIn('latitude', projection)
        self.assertNotIn('longitude', projection)
        coordinator = code('Core/CityGameCoordinator.swift')
        # Bodies come only from the agent-H intent; no client cost/reward/dice is composed here.
        self.assertNotIn('JSONSerialization', coordinator)
        for forbidden in ['dice', 'reward']:
            self.assertNotIn(forbidden, coordinator.lower())

    def test_only_debug_fixtures_conform_to_the_proposed_services(self):
        pattern = re.compile(r':\s*(?:[A-Za-z]+\s*,\s*)*(CityGameServing|HomeReturnServing)\b')
        owners = set()
        for path in list(ROOT.glob('App/*.swift')) + list(ROOT.glob('Core/*.swift')):
            source = path.read_text()
            for match in pattern.finditer(source):
                line = source[source.rfind('\n', 0, match.start()) + 1:source.find('\n', match.start())]
                if 'protocol ' in line:
                    continue
                owners.add(str(path.relative_to(ROOT)))
        self.assertEqual(owners, {FIXTURE})
        self.assertTrue(text(FIXTURE).startswith('#if DEBUG\n'))
        self.assertTrue(text(FIXTURE).rstrip().endswith('#endif'))

    def test_production_entry_points_pass_no_game_or_restore_model(self):
        city = text('App/CityPlayerView.swift')
        self.assertIn('CityPlayerView(reader: session.makeCityPlayerReader()).id(session.cityPlayerReadIdentity)', city)
        self.assertIn('CityGameSlot(snapshot: context.snapshot, factory: gameFactory).id(context.readID)', city)
        self.assertIn('static let defaultValue: HomeReturnCoordinator? = nil', text('App/HomeReturnSection.swift'))
        for path in ROOT.glob('App/*.swift'):
            if path.name == 'CityGameFixtureHost.swift':
                continue
            source = path.read_text()
            self.assertNotIn('gameFactory: {', source, path.name)
            self.assertNotIn('\\.homeReturnCoordinator, ', source, path.name)

    def test_home_point_is_never_rendered_by_the_restore_section(self):
        section = code('App/HomeReturnSection.swift')
        for forbidden in ['latitude', 'longitude', 'label)', 'PrivateHomePoint']:
            self.assertNotIn(forbidden, section)

    def test_catalog_is_complete_bilingual_and_has_no_invented_numbers(self):
        catalog = json.loads(text('Resources/CityGame.xcstrings'))['strings']
        used = set()
        for name in APP + ['App/CityGamePanel.swift']:
            used |= set(re.findall(r'Text\("([A-Za-z0-9.]+)", tableName: "CityGame"\)', text(name)))
        self.assertEqual(used, set(catalog))
        for key, row in catalog.items():
            values = [row['localizations'][lang]['stringUnit']['value'] for lang in ('en', 'zh-Hans')]
            self.assertTrue(all(v.strip() for v in values), key)
            self.assertFalse(any(re.search(r'\d', v) for v in values), key)

    def test_ui_flags_exist_in_the_fixture_host(self):
        host = text(FIXTURE)
        for name in ['Tests/AppUITests/CityGameFlowTests.swift', 'Tests/AppUITests/HomeReturnFlowTests.swift']:
            for flag in set(re.findall(r'"(--(?:city-game|home-return)-[a-z-]+)"', text(name))):
                self.assertIn('"' + flag + '"', host, (name, flag))
        modules = text('App/ModuleFixtureSupport.swift')
        self.assertIn('case .cityGame: CityGameFixtureHost()', modules)
        self.assertIn('case .homeReturn: HomeReturnFixtureHost()', modules)


if __name__ == '__main__':
    unittest.main()

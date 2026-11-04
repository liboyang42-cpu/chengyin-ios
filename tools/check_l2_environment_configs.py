#!/usr/bin/env python3
"""Offline tracked-config checks. Never reads actual Local*.xcconfig or contacts a server.
This checks include precedence and safety boundaries, not xcodebuild or successful login.
"""
from pathlib import Path
import fnmatch
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MARKETS = {'China': 'CN', 'UnitedStates': 'US'}
ENVIRONMENTS = ('Development', 'Staging', 'Production')
CONFIG_FILES = ('Base.xcconfig', 'China.xcconfig', 'UnitedStates.xcconfig') + tuple(
    f'{market}.{environment}.xcconfig' for market in MARKETS for environment in ENVIRONMENTS)

def tracked_inputs(root=ROOT):
    # Deliberate allowlist: no glob, directory scan or reading a developer's local configuration.
    return {name: (root / 'Config' / name).read_text() for name in CONFIG_FILES}

def settings(entry, files):
    values = {}
    def include(name, stack):
        if name in stack:
            raise ValueError('include cycle')
        for line in files[name].splitlines():
            line = line.strip()
            match = re.fullmatch(r'#include(\?)?\s+"([^"]+)"', line)
            if match:
                child = match[2]
                if child in files:
                    include(child, stack + (name,))
                elif not match[1]:
                    raise ValueError('missing required include')
                continue
            line = line.split('//', 1)[0].strip()
            if not line or '=' not in line:
                continue
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip()
    include(entry, ())
    def expand(value, seen=()):
        def replace(match):
            key = match[1]
            if key in seen:
                raise ValueError('variable cycle')
            return expand(values.get(key, ''), seen + (key,))
        return re.sub(r'\$\(([^)]*)\)', replace, value)
    return {key: expand(value) for key, value in values.items()}

class L2EnvironmentConfigChecks(unittest.TestCase):
    def setUp(self):
        self.files = tracked_inputs()

    def test_default_remains_unconfigured(self):
        result = settings('Base.xcconfig', self.files)
        self.assertEqual(result['QUESTIFY_API_BASE_URL'], '')
        self.assertEqual(result['QUESTIFY_SESSION_REALM'], '')
        self.assertEqual(result['QUESTIFY_DEPLOYMENT_ENVIRONMENT'], 'unconfigured')

    def test_market_profiles_do_not_inherit_common_endpoint_or_realm(self):
        files = dict(self.files, **{'Local.xcconfig': 'QUESTIFY_API_BASE_URL = https:/$()/other.example.test\nQUESTIFY_SESSION_REALM = other-realm\n'})
        for market, code in MARKETS.items():
            with self.subTest(market=market):
                result = settings(market + '.xcconfig', files)
                self.assertEqual(result['QUESTIFY_API_BASE_URL'], '')
                self.assertEqual(result['QUESTIFY_SESSION_REALM'], '')
                self.assertEqual(result['QUESTIFY_MARKET'], code)

    def test_market_local_endpoint_and_realm_reach_existing_profile(self):
        for market, code in MARKETS.items():
            with self.subTest(market=market):
                files = dict(self.files)
                files[f'Local.{market}.xcconfig'] = 'QUESTIFY_API_BASE_URL = https:/$()/approved.example.test/native\nQUESTIFY_SESSION_REALM = isolated-test\nQUESTIFY_MARKET = WRONG\n'
                result = settings(market + '.xcconfig', files)
                self.assertEqual(result['QUESTIFY_API_BASE_URL'], 'https://approved.example.test/native')
                self.assertEqual(result['QUESTIFY_SESSION_REALM'], 'isolated-test')
                self.assertEqual(result['QUESTIFY_MARKET'], code)
                self.assertEqual(result['INFOPLIST_KEY_QuestifyMarket'], code)

    def test_development_defaults_only_to_loopback(self):
        for market, code in MARKETS.items():
            with self.subTest(market=market):
                result = settings(f'{market}.Development.xcconfig', self.files)
                self.assertEqual(result['QUESTIFY_API_BASE_URL'], 'http://127.0.0.1:8099')
                self.assertEqual(result['QUESTIFY_SESSION_REALM'], code.lower() + '-development')
                self.assertEqual(result['QUESTIFY_DEPLOYMENT_ENVIRONMENT'], 'development')

    def test_staging_and_production_cannot_inherit_market_deployment(self):
        for market in MARKETS:
            for environment in ('Staging', 'Production'):
                with self.subTest(market=market, environment=environment):
                    files = dict(self.files)
                    files[f'Local.{market}.xcconfig'] = 'QUESTIFY_API_BASE_URL = https:/$()/earlier.example.test\nQUESTIFY_SESSION_REALM = earlier\n'
                    result = settings(f'{market}.{environment}.xcconfig', files)
                    self.assertEqual(result['QUESTIFY_API_BASE_URL'], '')
                    self.assertEqual(result['QUESTIFY_SESSION_REALM'], '')

    def test_environment_local_overrides_are_scoped_and_identity_is_pinned(self):
        for market, code in MARKETS.items():
            for environment in ENVIRONMENTS:
                with self.subTest(market=market, environment=environment):
                    files = dict(self.files)
                    files[f'Local.{market}.{environment}.xcconfig'] = 'QUESTIFY_API_BASE_URL = https:/$()/approved.example.test/native\nQUESTIFY_SESSION_REALM = explicit\nQUESTIFY_MARKET = WRONG\nQUESTIFY_DEPLOYMENT_ENVIRONMENT = wrong\n'
                    result = settings(f'{market}.{environment}.xcconfig', files)
                    self.assertEqual(result['QUESTIFY_API_BASE_URL'], 'https://approved.example.test/native')
                    self.assertEqual(result['QUESTIFY_SESSION_REALM'], 'explicit')
                    self.assertEqual(result['QUESTIFY_MARKET'], code)
                    self.assertEqual(result['QUESTIFY_DEPLOYMENT_ENVIRONMENT'], environment.lower())
                    self.assertEqual(result['INFOPLIST_KEY_QuestifyDeploymentEnvironment'], environment.lower())

    def test_market_profile_does_not_inherit_environment_label(self):
        for market in MARKETS:
            files = dict(self.files)
            files['Local.xcconfig'] = 'QUESTIFY_DEPLOYMENT_ENVIRONMENT = production\n'
            files[f'Local.{market}.xcconfig'] = 'QUESTIFY_DEPLOYMENT_ENVIRONMENT = staging\n'
            self.assertEqual(settings(market + '.xcconfig', files)['QUESTIFY_DEPLOYMENT_ENVIRONMENT'], 'unconfigured')

    def test_other_market_and_environment_overrides_are_never_loaded(self):
        for market, code in MARKETS.items():
            other = next(name for name in MARKETS if name != market)
            for environment in ENVIRONMENTS:
                files = dict(self.files)
                files[f'Local.{other}.{environment}.xcconfig'] = 'QUESTIFY_API_BASE_URL = https:/$()/wrong.example.test\nQUESTIFY_SESSION_REALM = wrong\n'
                for earlier in ENVIRONMENTS:
                    if earlier != environment:
                        files[f'Local.{market}.{earlier}.xcconfig'] = 'QUESTIFY_API_BASE_URL = https:/$()/wrong.example.test\nQUESTIFY_SESSION_REALM = wrong\n'
                result = settings(f'{market}.{environment}.xcconfig', files)
                self.assertEqual(result['QUESTIFY_API_BASE_URL'], 'http://127.0.0.1:8099' if environment == 'Development' else '')
                self.assertEqual(result['QUESTIFY_SESSION_REALM'], code.lower() + '-development' if environment == 'Development' else '')

    def test_empty_override_clears_both_inputs_and_next_evaluation_recovers(self):
        for market in MARKETS:
            files = dict(self.files)
            local = f'Local.{market}.Development.xcconfig'
            files[local] = 'QUESTIFY_API_BASE_URL =\nQUESTIFY_SESSION_REALM =\n'
            cleared = settings(f'{market}.Development.xcconfig', files)
            self.assertEqual(cleared['QUESTIFY_API_BASE_URL'], '')
            self.assertEqual(cleared['QUESTIFY_SESSION_REALM'], '')
            files[local] = 'QUESTIFY_API_BASE_URL = https:/$()/recovered.example.test\nQUESTIFY_SESSION_REALM = recovered\n'
            recovered = settings(f'{market}.Development.xcconfig', files)
            self.assertEqual(recovered['QUESTIFY_API_BASE_URL'], 'https://recovered.example.test')
            self.assertEqual(recovered['QUESTIFY_SESSION_REALM'], 'recovered')

    def test_info_inputs_match_existing_bundle_consumers(self):
        info = plistlib.loads((ROOT / 'Config/Info.plist').read_bytes())
        consumer = (ROOT / 'App/RegionalLaunchConfiguration.swift').read_text()
        for key, setting in [('QuestifyMarket', 'QUESTIFY_MARKET'), ('QuestifyAPIBaseURL', 'QUESTIFY_API_BASE_URL'), ('QuestifySessionRealm', 'QUESTIFY_SESSION_REALM')]:
            self.assertEqual(info[key], '$(' + setting + ')')
            self.assertIn('object(forInfoDictionaryKey: "' + key + '")', consumer)
            for market in MARKETS:
                for environment in ENVIRONMENTS:
                    values = settings(f'{market}.{environment}.xcconfig', self.files)
                    self.assertEqual(values['INFOPLIST_KEY_' + key], values[setting])

    def test_invalid_include_graph_is_reported(self):
        with self.assertRaisesRegex(ValueError, 'include cycle'):
            settings('a', {'a': '#include "b"', 'b': '#include "a"'})
        with self.assertRaisesRegex(ValueError, 'missing required include'):
            settings('a', {'a': '#include "missing"'})
        self.assertEqual(settings('a', {'a': '#include? "absent"\nVALUE = retained'}), {'VALUE': 'retained'})

    def test_variable_cycle_is_reported(self):
        with self.assertRaisesRegex(ValueError, 'variable cycle'):
            settings('a', {'a': 'FIRST = $(SECOND)\nSECOND = $(FIRST)'})

    def test_local_input_files_are_gitignored(self):
        patterns = [line.strip() for line in (ROOT / '.gitignore').read_text().splitlines() if line.strip() and not line.startswith('#')]
        for market in MARKETS:
            names = [f'Config/Local.{market}.xcconfig'] + [f'Config/Local.{market}.{environment}.xcconfig' for environment in ENVIRONMENTS]
            for name in names:
                self.assertTrue(any(fnmatch.fnmatchcase(name, pattern) for pattern in patterns), name)
        self.assertFalse(any(fnmatch.fnmatchcase('Config/Local.xcconfig.example', pattern) for pattern in patterns))

    def test_metadata_declares_no_transport_exception(self):
        info = plistlib.loads((ROOT / 'Config/Info.plist').read_bytes())
        self.assertEqual(info['QuestifyDeploymentEnvironment'], '$(QUESTIFY_DEPLOYMENT_ENVIRONMENT)')
        self.assertNotIn('NSAppTransportSecurity', info)
        for value in self.files.values():
            self.assertNotIn('NSAllowsArbitraryLoads', value)
            self.assertNotIn('NSAllowsLocalNetworking', value)

    def test_profile_data_does_not_enable_runtime_authority(self):
        source = (ROOT / 'App/RegionalLaunchConfiguration.swift').read_text()
        self.assertIn('makeComposition(reviewed: nil, build: .current)', source)
        self.assertIn('verifiedCapabilities:[]', source)
        api = (ROOT / 'Core/APIConfiguration.swift').read_text()
        self.assertIn('parts.scheme == "https"', api)

if __name__ == '__main__':
    unittest.main()

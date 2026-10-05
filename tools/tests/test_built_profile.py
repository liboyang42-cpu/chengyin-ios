import importlib.util
import pathlib
import unittest
spec=importlib.util.spec_from_file_location('built_profile',pathlib.Path(__file__).resolve().parents[1]/'check_built_profile.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class BuiltProfileTests(unittest.TestCase):
    def test_explicit_empty_endpoint_is_valid_for_each_market(self):
        for market in ['CN','US']:
            module.validate({'QuestifyMarket':market,'QuestifyAPIBaseURL':'','QuestifySessionRealm':''},market)
    def test_missing_wrong_or_live_configuration_is_rejected(self):
        for value in [{},{'QuestifyMarket':'US','QuestifyAPIBaseURL':''},{'QuestifyMarket':'CN'},
                      {'QuestifyMarket':'CN','QuestifyAPIBaseURL':'https://example.invalid'}]:
            with self.assertRaises(ValueError):module.validate(value,'CN')
    def test_missing_malformed_unresolved_or_live_realm_is_rejected(self):
        for realm in [None, 123, '$(QUESTIFY_SESSION_REALM)', 'cn-pilot']:
            value = {'QuestifyMarket':'CN','QuestifyAPIBaseURL':''}
            if realm is not None:value['QuestifySessionRealm'] = realm
            with self.assertRaises(ValueError):module.validate(value,'CN')

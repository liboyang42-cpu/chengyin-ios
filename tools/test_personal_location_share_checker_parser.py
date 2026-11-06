#!/usr/bin/env python3
"""Positive/negative controls against the actual existing SourceChecks methods, without modifying assertions.
All mutations are in-memory read fixtures; original application/checker bytes never change.
"""
from pathlib import Path
import json
import unittest
import check_personal_location_share as checker
ROOT = Path(__file__).resolve().parents[1]
FILES = ['App/PersonalLocationShareHost.swift', 'App/PersonalLocationShareView.swift',
         'Core/PersonalLocationShareCoordinator.swift', 'Resources/PersonalLocationShare.xcstrings']
SOURCE = {p:(ROOT/p).read_text() for p in FILES}
HOST, VIEW, CORE, CATALOG = FILES

class CheckerParserControls(unittest.TestCase):
    def run_original(self, method, replacements=None):
        source = dict(SOURCE)
        if replacements: source.update(replacements)
        case = checker.SourceChecks(method)
        # Explicit test fixture reader, not mutation of unittest or the production checker.
        case.read = lambda relative: source.get(relative) if relative in source else (ROOT/relative).read_text()
        getattr(case, method)()
    def rejected(self, method, path, old, new):
        self.assertIn(old, SOURCE[path])
        mutated = SOURCE[path].replace(old, new, 1)
        with self.assertRaises(AssertionError): self.run_original(method, {path:mutated})
    def catalog_mutation(self, key, language, value):
        data=json.loads(SOURCE[CATALOG]); data['strings'][key]['localizations'][language]['stringUnit']['value']=value
        return {CATALOG:json.dumps(data,ensure_ascii=False)}
    def test_positive_current_source_passes_both_original_methods(self):
        self.run_original('test_real_driver_is_grant_bound_and_first_prompt_is_explicit')
        self.run_original('test_localization_resource_is_valid_and_used')
    def test_positive_equivalent_stop_whitespace_and_comments(self):
        s=SOURCE[HOST].replace('manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false',
            'manager.stopUpdatingLocation() // still stops synchronously\n        manager.allowsBackgroundLocationUpdates=false',1)
        self.run_original('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',{HOST:s})
    def test_missing_stop_cannot_be_satisfied_by_comment(self):
        self.rejected('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',HOST,
            'manager.stopUpdatingLocation();','/* manager.stopUpdatingLocation(); */')
    def test_missing_delegate_clear_rejected(self):
        self.rejected('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',HOST,'manager.delegate = nil','noop()')
    def test_delegate_before_stop_rejected(self):
        s=SOURCE[HOST].replace('manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false','manager.delegate = nil; manager.allowsBackgroundLocationUpdates = false',1).replace('manager.showsBackgroundLocationIndicator = false; manager.delegate = nil','manager.showsBackgroundLocationIndicator = false; manager.stopUpdatingLocation()',1)
        with self.assertRaises(AssertionError):self.run_original('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',{HOST:s})
    def test_deferred_stop_rejected(self):
        self.rejected('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',HOST,'manager.stopUpdatingLocation();','Task { manager.stopUpdatingLocation() };')
    def test_conditional_stop_rejected(self):
        self.rejected('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',HOST,'manager.stopUpdatingLocation();','if false { manager.stopUpdatingLocation() };')
    def test_missing_background_reset_rejected(self):
        self.rejected('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',HOST,'manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false','manager.stopUpdatingLocation()')
    def test_missing_callback_retirement_rejected(self):
        self.rejected('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',HOST,'onLocation = nil; onAuthorization = nil; onFailure = nil','onLocation = nil; onAuthorization = nil')
    def test_continuation_before_stop_rejected(self):
        self.rejected('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',HOST,
            'driver?.stop(); driver = nil // Synchronous stop before any continuation resumes.\n        reply?.resume(with: result)',
            'reply?.resume(with: result)\n        driver?.stop(); driver = nil')
    def test_original_permission_guard_still_rejected(self):
        self.rejected('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',HOST,'guard allowsFirstPermissionRequest','guard true')
    def test_original_synthetic_fix_guard_still_rejected(self):
        self.rejected('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',HOST,'value.sourceInformation?.isSimulatedBySoftware != true','true')
    def test_missing_status_mapping_not_satisfied_by_comment(self):
        self.rejected('test_localization_resource_is_valid_and_used',CORE,
            'key = "personalLocationShare.status.01"','key = nil // "personalLocationShare.status.01"')
    def test_disconnected_mapped_output_rejected(self):
        self.rejected('test_localization_resource_is_valid_and_used',CORE,
            'if let key { return [.init(key: key, arguments: [], fallback: base)] + trailing }',
            'if let key { return [.init(key: nil, arguments: [], fallback: base)] + trailing }')
    def test_missing_host_unavailable_surface_rejected(self):
        self.rejected('test_localization_resource_is_valid_and_used',HOST,
            'Text("personalLocationShare.unavailable.title", tableName: "PersonalLocationShare")','Text("Unavailable")')
    def test_wrong_resource_table_rejected(self):
        self.rejected('test_localization_resource_is_valid_and_used',VIEW,'table: "PersonalLocationShare", locale: locale','table: "Other", locale: locale')
    def test_disconnected_status_rendering_rejected(self):
        self.rejected('test_localization_resource_is_valid_and_used',VIEW,'Text(statusMessage)','Text("No status")')
    def test_missing_translation_rejected(self):
        with self.assertRaises(AssertionError): self.run_original('test_localization_resource_is_valid_and_used',self.catalog_mutation('personalLocationShare.status.01','en',''))
    def test_disclosure_not_satisfied_by_another_surface(self):
        with self.assertRaises(AssertionError): self.run_original('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',self.catalog_mutation('personalLocationShare.disclosure.summary','zh-Hans','说明已删除'))
    def test_missing_confirmation_disclosure_rejected(self):
        with self.assertRaises(AssertionError): self.run_original('test_real_driver_is_grant_bound_and_first_prompt_is_explicit',self.catalog_mutation('personalLocationShare.confirmationSummary','zh-Hans','说明已删除'))
    def test_unknown_status_must_not_be_success(self):
        self.rejected('test_localization_resource_is_valid_and_used',CORE,'default: key = nil','default: key = "personalLocationShare.status.20"')

if __name__=='__main__':
    print('Actual SourceChecks methods + in-memory mutation fixtures. Source-only; NOT Swift or UI execution.',flush=True)
    unittest.main(verbosity=2)

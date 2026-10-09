#!/usr/bin/env python3
"""Run both complete native-local Python discoveries and attest their real results.

Only the Linux static job runs the suites. Every Apple consumer and the aggregate
verify the same-run artifact before claiming a successful static prerequisite.
The artifact is an integrity receipt, not a signature or a cross-run cache.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time
import unittest

SUITES = {
    'tools': {'directory': 'tools/tests', 'pattern': 'test_*.py'},
    'contracts': {'directory': 'Tests/ContractChecks', 'pattern': 'test_*.py'},
}
# Exact observed NOT_RUN results from the 2529-test, 49-skip baseline.
# setUpClass is a single skip event covering three separately discovered methods.
# Counts alone never authorize a skip. Configured or present sources must run.
ALLOWED_SKIPS = {'merchant_template_assist_source_checks.MerchantTemplateAssistSourceTests.test_optional_flutter_contract_reference': 'Optional '
                                                                                                                      'private '
                                                                                                                      'Flutter '
                                                                                                                      'source '
                                                                                                                      'not '
                                                                                                                      'configured',
 'setUpClass (test_merchant_public_production.CurrentBackendMerchantSourceTests)': 'NOT_RUN: explicit '
                                                                                   'CURRENT backend source '
                                                                                   'root not supplied',
 'test_club_operations_contracts.ClubOperationsSourceChecks.test_catalog_external_flutter_parity': 'External '
                                                                                                   'Flutter '
                                                                                                   'parity '
                                                                                                   'NOT_RUN: '
                                                                                                   '../app-audit '
                                                                                                   'is '
                                                                                                   'unavailable; '
                                                                                                   'native-local '
                                                                                                   'assertions '
                                                                                                   'run '
                                                                                                   'separately',
 'test_club_operations_contracts.ClubOperationsSourceChecks.test_six_paths_external_flutter_parity': 'External '
                                                                                                     'Flutter '
                                                                                                     'parity '
                                                                                                     'NOT_RUN: '
                                                                                                     '../app-audit '
                                                                                                     'is '
                                                                                                     'unavailable; '
                                                                                                     'native-local '
                                                                                                     'assertions '
                                                                                                     'run '
                                                                                                     'separately',
 'test_compare_game_contract.CompareGameContracts.test_optional_private_source_matches_exact_current_contract': 'NOT_RUN: '
                                                                                                                'optional '
                                                                                                                'current '
                                                                                                                'backend '
                                                                                                                'source '
                                                                                                                'checkout '
                                                                                                                'not '
                                                                                                                'supplied',
 'test_creator_composition.CreatorCompositionSourceChecks.test_current_mini_compound_and_cross_family_contracts': 'Current '
                                                                                                                  'mini '
                                                                                                                  'checkout '
                                                                                                                  'not '
                                                                                                                  'provided; '
                                                                                                                  'native '
                                                                                                                  'assertions '
                                                                                                                  'still '
                                                                                                                  'ran',
 'test_journey_narrative_workflows.JourneyNarrativeCurrentBackendContracts.test_routes_and_exact_run_fallback_contract': 'Optional '
                                                                                                                         'current '
                                                                                                                         'backend '
                                                                                                                         'source '
                                                                                                                         'not '
                                                                                                                         'supplied; '
                                                                                                                         'native '
                                                                                                                         'checks '
                                                                                                                         'still '
                                                                                                                         'run',
 'test_merchant_customer_detail.MerchantCustomerDetailContracts.test_optional_verified_source_blobs_and_refund_semantics': 'NOT_RUN: '
                                                                                                                           'private '
                                                                                                                           'source '
                                                                                                                           'evidence '
                                                                                                                           'directory '
                                                                                                                           'not '
                                                                                                                           'supplied',
 'test_merchant_discovery_redemption_contracts.MerchantDiscoveryRedemptionContracts.test_external_flutter_source_contracts': 'NOT_RUN: '
                                                                                                                             'supply '
                                                                                                                             'CHENGYIN_FLUTTER_SOURCE_ROOT '
                                                                                                                             'for '
                                                                                                                             'external '
                                                                                                                             'source '
                                                                                                                             'evidence',
 'test_merchant_npc_access_parity.MerchantNPCAccessCe61Parity.test_pinned_source_requires_profile_write_for_character': 'NOT_RUN: '
                                                                                                                        'optional '
                                                                                                                        'pinned '
                                                                                                                        'ce61 '
                                                                                                                        'NPC '
                                                                                                                        'source '
                                                                                                                        'evidence '
                                                                                                                        'not '
                                                                                                                        'supplied',
 'test_merchant_npc_character_readback.MerchantNPCCharacterCe61Parity.test_verified_mini_and_backend_review_contracts': 'NOT_RUN: '
                                                                                                                        'optional '
                                                                                                                        'ce61 '
                                                                                                                        'source '
                                                                                                                        'checkout '
                                                                                                                        'not '
                                                                                                                        'supplied',
 'test_operation_http_adapters.OperationHTTPAdapters.test_project_routes_external_flutter_parity': 'External '
                                                                                                   'Flutter '
                                                                                                   'parity '
                                                                                                   'NOT_RUN: '
                                                                                                   '../app-audit '
                                                                                                   'is '
                                                                                                   'unavailable; '
                                                                                                   'native-local '
                                                                                                   'assertions '
                                                                                                   'run '
                                                                                                   'separately',
 'test_play_director_prefab_contracts.PlayDirectorPrefabSourceChecks.test_director_reason_codes_external_flutter_parity': 'External '
                                                                                                                          'Flutter '
                                                                                                                          'parity '
                                                                                                                          'NOT_RUN: '
                                                                                                                          '../app-audit '
                                                                                                                          'is '
                                                                                                                          'unavailable; '
                                                                                                                          'native-local '
                                                                                                                          'assertions '
                                                                                                                          'run '
                                                                                                                          'separately',
 'test_play_director_prefab_contracts.PlayDirectorPrefabSourceChecks.test_prefab_arrival_external_flutter_parity': 'External '
                                                                                                                   'Flutter '
                                                                                                                   'parity '
                                                                                                                   'NOT_RUN: '
                                                                                                                   '../app-audit '
                                                                                                                   'is '
                                                                                                                   'unavailable; '
                                                                                                                   'native-local '
                                                                                                                   'assertions '
                                                                                                                   'run '
                                                                                                                   'separately',
 'test_play_director_prefab_contracts.PlayDirectorPrefabSourceChecks.test_recap_export_external_flutter_parity': 'External '
                                                                                                                 'Flutter '
                                                                                                                 'parity '
                                                                                                                 'NOT_RUN: '
                                                                                                                 '../app-audit '
                                                                                                                 'is '
                                                                                                                 'unavailable; '
                                                                                                                 'native-local '
                                                                                                                 'assertions '
                                                                                                                 'run '
                                                                                                                 'separately',
 'test_play_director_prefab_contracts.PlayDirectorPrefabSourceChecks.test_scene_timing_external_flutter_parity': 'External '
                                                                                                                 'Flutter '
                                                                                                                 'parity '
                                                                                                                 'NOT_RUN: '
                                                                                                                 '../app-audit '
                                                                                                                 'is '
                                                                                                                 'unavailable; '
                                                                                                                 'native-local '
                                                                                                                 'assertions '
                                                                                                                 'run '
                                                                                                                 'separately',
 'test_play_director_prefab_contracts.PlayDirectorPrefabSourceChecks.test_upload_external_flutter_parity': 'External '
                                                                                                           'Flutter '
                                                                                                           'parity '
                                                                                                           'NOT_RUN: '
                                                                                                           '../app-audit '
                                                                                                           'is '
                                                                                                           'unavailable; '
                                                                                                           'native-local '
                                                                                                           'assertions '
                                                                                                           'run '
                                                                                                           'separately',
 'test_play_experience_contracts.PlayExperienceSourceChecks.test_advanced_action_catalog_matches_source': 'External '
                                                                                                          'Flutter '
                                                                                                          'parity '
                                                                                                          'NOT_RUN: '
                                                                                                          '../app-audit '
                                                                                                          'is '
                                                                                                          'unavailable; '
                                                                                                          'native-local '
                                                                                                          'assertions '
                                                                                                          'run '
                                                                                                          'separately',
 'test_play_experience_contracts.PlayExperienceSourceChecks.test_circle_paths_external_flutter_parity': 'External '
                                                                                                        'Flutter '
                                                                                                        'parity '
                                                                                                        'NOT_RUN: '
                                                                                                        '../app-audit '
                                                                                                        'is '
                                                                                                        'unavailable; '
                                                                                                        'native-local '
                                                                                                        'assertions '
                                                                                                        'run '
                                                                                                        'separately',
 'test_play_experience_contracts.PlayExperienceSourceChecks.test_classic_paths_external_flutter_parity': 'External '
                                                                                                         'Flutter '
                                                                                                         'parity '
                                                                                                         'NOT_RUN: '
                                                                                                         '../app-audit '
                                                                                                         'is '
                                                                                                         'unavailable; '
                                                                                                         'native-local '
                                                                                                         'assertions '
                                                                                                         'run '
                                                                                                         'separately',
 'test_play_experience_contracts.PlayExperienceSourceChecks.test_director_actions_match_source': 'External '
                                                                                                 'Flutter '
                                                                                                 'parity '
                                                                                                 'NOT_RUN: '
                                                                                                 '../app-audit '
                                                                                                 'is '
                                                                                                 'unavailable; '
                                                                                                 'native-local '
                                                                                                 'assertions '
                                                                                                 'run '
                                                                                                 'separately',
 'test_play_experience_contracts.PlayExperienceSourceChecks.test_player_paths_external_flutter_parity': 'External '
                                                                                                        'Flutter '
                                                                                                        'parity '
                                                                                                        'NOT_RUN: '
                                                                                                        '../app-audit '
                                                                                                        'is '
                                                                                                        'unavailable; '
                                                                                                        'native-local '
                                                                                                        'assertions '
                                                                                                        'run '
                                                                                                        'separately',
 'test_play_preference_contracts.PlayPreferenceSourceChecks.test_preference_paths_external_flutter_parity': 'External '
                                                                                                            'Flutter '
                                                                                                            'parity '
                                                                                                            'NOT_RUN: '
                                                                                                            '../app-audit '
                                                                                                            'is '
                                                                                                            'unavailable; '
                                                                                                            'native-local '
                                                                                                            'assertions '
                                                                                                            'run '
                                                                                                            'separately',
 'test_playkit_retired_components.PlayKitRetiredComponentChecks.test_current_mini_dispatch_and_components_confirm_retirement': 'External '
                                                                                                                               'mini-program '
                                                                                                                               'retirement '
                                                                                                                               'comparison '
                                                                                                                               'NOT_RUN: '
                                                                                                                               'no '
                                                                                                                               'configured '
                                                                                                                               'source '
                                                                                                                               'checkout',
 'test_project_edit_contracts.ProjectEditContracts.test_source_endpoint_and_whitelist_alignment': 'Flutter '
                                                                                                  'source '
                                                                                                  'unavailable; '
                                                                                                  'do not '
                                                                                                  'claim '
                                                                                                  'source '
                                                                                                  'verification',
 'test_project_edit_contracts.ProjectEditContracts.test_source_local_draft_envelope_and_conflict_evidence': 'Flutter '
                                                                                                            'source '
                                                                                                            'unavailable',
 'test_project_edit_contracts.ProjectEditContracts.test_source_replacement_fields_preserved': 'Flutter '
                                                                                              'source '
                                                                                              'unavailable',
 'test_project_edit_rich_story.RichStoryContracts.test_current_external_sources_if_supplied': 'Current '
                                                                                              'private '
                                                                                              'source '
                                                                                              'unavailable: '
                                                                                              'source '
                                                                                              'comparison '
                                                                                              'NOT_RUN',
 'test_project_edit_v2_contract.ProjectEditV2Contract.test_current_mini_and_backend_source_when_explicitly_supplied': 'Current '
                                                                                                                      'private '
                                                                                                                      'source '
                                                                                                                      'not '
                                                                                                                      'supplied; '
                                                                                                                      'external '
                                                                                                                      'source '
                                                                                                                      'parity '
                                                                                                                      'NOT_RUN',
 'test_search_map_contracts.SearchMapSourceChecks.test_source_backing_when_flutter_available': 'Preserved '
                                                                                               'Flutter '
                                                                                               'source not '
                                                                                               'present',
 'test_square_workspace.SquareWorkspaceSourceChecks.test_endpoints_external_flutter_parity': 'External '
                                                                                             'Flutter parity '
                                                                                             'NOT_RUN: '
                                                                                             '../app-audit '
                                                                                             'is '
                                                                                             'unavailable; '
                                                                                             'native-local '
                                                                                             'assertions run '
                                                                                             'separately',
 'test_square_workspace.SquareWorkspaceSourceChecks.test_fields_and_enums_external_flutter_parity': 'External '
                                                                                                    'Flutter '
                                                                                                    'parity '
                                                                                                    'NOT_RUN: '
                                                                                                    '../app-audit '
                                                                                                    'is '
                                                                                                    'unavailable; '
                                                                                                    'native-local '
                                                                                                    'assertions '
                                                                                                    'run '
                                                                                                    'separately',
 'test_team_contracts.TeamSourceChecks.test_creation_matches_source_eligibility_sizes_and_default': 'Preserved '
                                                                                                    'Flutter '
                                                                                                    'source '
                                                                                                    'is not '
                                                                                                    'available '
                                                                                                    'in this '
                                                                                                    'checkout',
 'test_team_contracts.TeamSourceChecks.test_five_statuses_use_expire_time_and_server_count': 'Preserved '
                                                                                             'Flutter source '
                                                                                             'is not '
                                                                                             'available in '
                                                                                             'this checkout',
 'test_team_contracts.TeamSourceChecks.test_mutation_contracts_are_not_transports': 'Preserved Flutter '
                                                                                    'source is not available '
                                                                                    'in this checkout',
 'test_team_contracts.TeamSourceChecks.test_owned_and_nearby_are_distinct': 'Preserved Flutter source is not '
                                                                            'available in this checkout',
 'test_team_contracts.TeamSourceChecks.test_provisional_join_mode_has_no_mutation_or_toggle': 'Preserved '
                                                                                              'Flutter '
                                                                                              'source is not '
                                                                                              'available in '
                                                                                              'this checkout',
 'test_team_contracts.TeamSourceChecks.test_read_contracts_are_source_backed_post_json': 'Preserved Flutter '
                                                                                         'source is not '
                                                                                         'available in this '
                                                                                         'checkout',
 'test_team_contracts.TeamSourceChecks.test_roster_role_zero_matches_source_fixture': 'Preserved Flutter '
                                                                                      'source is not '
                                                                                      'available in this '
                                                                                      'checkout',
 'test_template_authoring_contracts.TemplateAuthoringContracts.test_adopt_does_not_reconstruct_hidden_answers': 'Flutter '
                                                                                                                'source '
                                                                                                                'unavailable; '
                                                                                                                'no '
                                                                                                                'source '
                                                                                                                'verification',
 'test_template_authoring_contracts.TemplateAuthoringContracts.test_dormant_wire_builder_is_exact_and_has_no_send': 'Flutter '
                                                                                                                    'source '
                                                                                                                    'unavailable; '
                                                                                                                    'no '
                                                                                                                    'source '
                                                                                                                    'verification',
 'test_template_authoring_contracts.TemplateAuthoringContracts.test_exact_template_endpoint_set': 'Flutter '
                                                                                                  'source '
                                                                                                  'unavailable; '
                                                                                                  'no source '
                                                                                                  'verification',
 'test_template_authoring_contracts.TemplateAuthoringContracts.test_payload_field_names_match_all_source_fields': 'Flutter '
                                                                                                                  'source '
                                                                                                                  'unavailable; '
                                                                                                                  'no '
                                                                                                                  'source '
                                                                                                                  'verification',
 'test_template_authoring_contracts.TemplateAuthoringContracts.test_source_defaults_are_exact': 'Flutter '
                                                                                                'source '
                                                                                                'unavailable; '
                                                                                                'no source '
                                                                                                'verification',
 'test_template_authoring_contracts.TemplateAuthoringContracts.test_source_enabled_game_catalog': 'Flutter '
                                                                                                  'source '
                                                                                                  'unavailable; '
                                                                                                  'no source '
                                                                                                  'verification',
 'test_template_authoring_contracts.TemplateAuthoringContracts.test_source_prefab_scene_order': 'Flutter '
                                                                                                'source '
                                                                                                'unavailable; '
                                                                                                'no source '
                                                                                                'verification',
 'test_template_authoring_contracts.TemplateAuthoringContracts.test_source_verification_codes_not_conflated': 'Flutter '
                                                                                                              'source '
                                                                                                              'unavailable; '
                                                                                                              'no '
                                                                                                              'source '
                                                                                                              'verification',
 'test_template_authoring_repair.ExactOwnShelfRepair.test_generic_project_external_flutter_parity': 'External '
                                                                                                    'Flutter '
                                                                                                    'parity '
                                                                                                    'NOT_RUN: '
                                                                                                    '../app-audit '
                                                                                                    'is '
                                                                                                    'unavailable; '
                                                                                                    'native-local '
                                                                                                    'assertions '
                                                                                                    'run '
                                                                                                    'separately',
 'test_template_authoring_repair.ExactOwnShelfRepair.test_own_shelf_external_flutter_parity': 'External '
                                                                                              'Flutter '
                                                                                              'parity '
                                                                                              'NOT_RUN: '
                                                                                              '../app-audit '
                                                                                              'is '
                                                                                              'unavailable; '
                                                                                              'native-local '
                                                                                              'assertions '
                                                                                              'run '
                                                                                              'separately'}
# A setUpClass event must not silently expand to newly skipped methods.
ALLOWED_CLASS_SKIPS = {
    'setUpClass (test_merchant_public_production.CurrentBackendMerchantSourceTests)': [
        'test_merchant_public_production.CurrentBackendMerchantSourceTests.test_current_chat_request_and_server_idempotency_match',
        'test_merchant_public_production.CurrentBackendMerchantSourceTests.test_current_voice_is_single_sample_and_reset_not_legacy_five_sample_contract',
        'test_merchant_public_production.CurrentBackendMerchantSourceTests.test_public_home_is_anonymous_discriminated_identity_and_visibility_checked',
    ],
}
SOURCE_ENVIRONMENTS = (
    'CHENGYIN_FLUTTER_SOURCE_ROOT', 'FLUTTER_AUDIT_ROOT',
    'CHENGYIN_CURRENT_SOURCE_ROOT', 'CHENGYIN_MINI_SOURCE_ROOT',
    'CHENGYIN_MINIPROGRAM_SOURCE_ROOT', 'CHENGYIN_BACKEND_SOURCE_ROOT',
    'CHENGYIN_COMPARE_BACKEND_SOURCE_ROOT', 'CHENGYIN_CE61_SOURCE_ROOT',
    'CHENGYIN_NPC_ACCESS_EVIDENCE_ROOT', 'CHENGYIN_CUSTOMER_DETAIL_EVIDENCE',
)
IDENTITY_KEYS = {'commit', 'head', 'tree', 'run_id', 'run_attempt', 'source_sha256'}
OUTCOMES = ('successes', 'failures', 'errors', 'expected_failures', 'unexpected_successes')


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate JSON key: ' + key)
            result[key] = value
        return result
    try:
        return json.loads(Path(path).read_bytes(), object_pairs_hook=unique)
    except (OSError, json.JSONDecodeError, UnicodeError) as error:
        raise ValueError('Missing or malformed static artifact: ' + str(path)) from error


def atomic_json(path, data):
    path = Path(path)
    temporary = path.with_name(path.name + '.partial')
    with temporary.open('x') as output:
        output.write(encode(data) + '\n')
        output.flush()
        os.fsync(output.fileno())
    temporary.replace(path)


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def valid_identity(identity):
    if not isinstance(identity, dict) or set(identity) != IDENTITY_KEYS:
        raise ValueError('Incomplete static identity')
    for key in ['commit', 'head', 'tree']:
        if not isinstance(identity[key], str) or not re.fullmatch('[0-9a-f]{40}', identity[key]):
            raise ValueError('Invalid static Git identity: ' + key)
    if identity['commit'] != identity['head']:
        raise ValueError('Static checkout HEAD differs from GITHUB_SHA')
    for key in ['run_id', 'run_attempt']:
        if not isinstance(identity[key], str) or not re.fullmatch('[1-9][0-9]*', identity[key]):
            raise ValueError('Exact positive workflow run identity required: ' + key)
    if not isinstance(identity['source_sha256'], str) or not re.fullmatch('[0-9a-f]{64}', identity['source_sha256']):
        raise ValueError('Invalid static source digest')
    return identity


def source_identity(root, environ=None):
    environ = os.environ if environ is None else environ
    root = Path(root).resolve()
    if git(root, 'rev-parse', '--show-toplevel') != str(root):
        raise ValueError('Static source must be the checkout root')
    if git(root, 'status', '--porcelain=v1', '--untracked-files=all'):
        raise ValueError('Static source checkout is not clean')
    tracked = {}
    for entry in subprocess.check_output(['git', '-C', str(root), 'ls-tree', '-rz', 'HEAD']).split(b'\0'):
        if entry:
            metadata, relative = entry.split(b'\t', 1)
            mode, kind, blob = metadata.decode().split()
            if kind != 'blob' or mode not in {'100644', '100755'}:
                raise ValueError('Unsupported static Git source type')
            tracked[relative.decode()] = (mode, blob)
    actual = {}
    def walk_error(error):
        raise ValueError('Unreadable static source tree') from error
    for directory, directories, files in os.walk(root, onerror=walk_error):
        if Path(directory) == root:
            directories[:] = [name for name in directories if name != '.git']
            files = [name for name in files if name != '.git']
        for name in directories + files:
            path = Path(directory) / name
            if path.is_symlink():
                raise ValueError('Symlink in static source tree: ' + str(path))
        for name in files:
            path = Path(directory) / name
            mode = path.stat().st_mode
            if not stat.S_ISREG(mode):
                raise ValueError('Non-regular static source input')
            relative, raw = path.relative_to(root).as_posix(), path.read_bytes()
            executable = bool(mode & 0o111)
            blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
            if tracked.get(relative) != ('100755' if executable else '100644', blob):
                raise ValueError('Static source bytes/mode differ from exact Git tree: ' + relative)
            actual[relative] = {'sha256': digest(raw), 'executable': executable}
    if set(actual) != set(tracked):
        raise ValueError('Static source file inventory differs from Git (including ignored files)')
    value = {'commit': environ.get('GITHUB_SHA'), 'head': git(root, 'rev-parse', 'HEAD'),
             'tree': git(root, 'rev-parse', 'HEAD^{tree}'),
             'run_id': environ.get('GITHUB_RUN_ID'), 'run_attempt': environ.get('GITHUB_RUN_ATTEMPT'),
             'source_sha256': digest(encode(actual).encode())}
    return valid_identity(value)


def checked_output(path, root):
    temporary = os.environ.get('RUNNER_TEMP')
    if not temporary:
        raise ValueError('RUNNER_TEMP is required')
    temporary, path, root = Path(temporary).resolve(), Path(path).resolve(), Path(root).resolve()
    if path == temporary or temporary not in path.parents or path == root or root in path.parents:
        raise ValueError('Static artifacts must be below RUNNER_TEMP and outside source')
    return path


def check_configured_sources(environ=None):
    environ = os.environ if environ is None else environ
    for name in SOURCE_ENVIRONMENTS:
        if name in environ and (not environ[name] or not Path(environ[name]).is_dir()):
            raise ValueError('Configured external source is missing: ' + name)


def skip_allowed(identifier, reason, root, environ=None):
    environ = os.environ if environ is None else environ
    if ALLOWED_SKIPS.get(identifier) != reason:
        return False
    # Every approved reason is absence-only. A configured source cannot excuse a
    # missing file, tool (including Node), malformed source, or changed contract.
    if 'test_team_contracts.' in identifier or 'test_search_map_contracts.' in identifier:
        names, default = (), True
    elif 'test_project_edit_contracts.' in identifier or 'test_template_authoring_contracts.' in identifier:
        names, default = ('FLUTTER_AUDIT_ROOT',), True
    elif reason.startswith('External Flutter parity NOT_RUN:'):
        names, default = ('CHENGYIN_FLUTTER_SOURCE_ROOT',), True
    else:
        default = False
        names = {
            'test_compare_game_contract': ('CHENGYIN_COMPARE_BACKEND_SOURCE_ROOT',),
            'test_creator_composition': ('CHENGYIN_MINI_SOURCE_ROOT',),
            'test_journey_narrative_workflows': ('CHENGYIN_BACKEND_SOURCE_ROOT',),
            'test_merchant_customer_detail': ('CHENGYIN_CUSTOMER_DETAIL_EVIDENCE',),
            'test_merchant_discovery_redemption_contracts': ('CHENGYIN_FLUTTER_SOURCE_ROOT',),
            'test_merchant_npc_access_parity': ('CHENGYIN_NPC_ACCESS_EVIDENCE_ROOT',),
            'test_merchant_npc_character_readback': ('CHENGYIN_CE61_SOURCE_ROOT',),
            'setUpClass (test_merchant_public_production': ('CHENGYIN_BACKEND_SOURCE_ROOT',),
            'merchant_template_assist_source_checks': ('CHENGYIN_FLUTTER_SOURCE_ROOT',),
            'test_playkit_retired_components': ('CHENGYIN_MINIPROGRAM_SOURCE_ROOT',),
            'test_project_edit_rich_story': ('CHENGYIN_CURRENT_SOURCE_ROOT',),
            'test_project_edit_v2_contract': ('CHENGYIN_CURRENT_SOURCE_ROOT',),
        }.get(identifier.split('.')[0])
        if names is None:
            return False
    return not any(name in environ for name in names) and not (default and (Path(root).parent / 'app-audit').exists())


def flatten(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from flatten(test)
        else:
            yield test


class RecordingResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # unittest startTest IDs include individual skips; class setup skips
        # never start their methods and are accounted separately in affected_ids.
        self.executed_ids = []
        self.success_ids = []

    def startTest(self, test):
        self.executed_ids.append(test.id())
        super().startTest(test)

    def addSuccess(self, test):
        self.success_ids.append(test.id())
        super().addSuccess(test)


def suite_report(name, root):
    if sys.flags.optimize or os.environ.get('PYTHONOPTIMIZE'):
        raise ValueError('Optimized Python is forbidden for static assertions')
    check_configured_sources()
    specification = SUITES[name]
    sys.path.insert(0, str(root))
    loader = unittest.TestLoader()
    try:
        suite = loader.discover(str(root / specification['directory']), pattern=specification['pattern'])
        discovery_errors = list(loader.errors)
    except (ImportError, OSError) as error:
        suite = unittest.TestSuite()
        discovery_errors = [str(error)]
    discovered = [test.id() for test in flatten(suite)]
    started = time.monotonic()
    result = unittest.TextTestRunner(verbosity=2, resultclass=RecordingResult).run(suite)
    skipped = []
    for test, reason in result.skipped:
        identifier = test.id()
        affected = [identifier] if identifier in discovered else []
        match = re.fullmatch(r'setUpClass \((.+)\)', identifier)
        if match:
            affected = [item for item in discovered if item.startswith(match.group(1) + '.')]
        skipped.append({'id': identifier, 'reason': reason, 'affected_ids': affected})
    report = {'suite': name, 'discovery': specification, 'discovery_errors': discovery_errors, 'discovered_ids': discovered,
              'executed_ids': result.executed_ids, 'tests_run': result.testsRun,
              'successes': result.success_ids, 'failures': [test.id() for test, _ in result.failures],
              'errors': [test.id() for test, _ in result.errors],
              'expected_failures': [test.id() for test, _ in result.expectedFailures],
              'unexpected_successes': [test.id() for test in result.unexpectedSuccesses],
              'skipped': skipped, 'duration_seconds': time.monotonic() - started,
              'process_id': os.getpid(), 'discovered_count': len(discovered), 'executed_count': len(result.executed_ids),
              'skip_count': len(skipped),
              'outcome_counts': {key: 0 for key in OUTCOMES}}
    report['outcome_counts'] = {key: len(report[key]) for key in OUTCOMES}
    return report


def validate_report(report, name, root, environ=None):
    keys = {'suite', 'discovery', 'discovery_errors', 'discovered_ids', 'executed_ids', 'tests_run', 'skipped',
            'process_id', 'duration_seconds', 'discovered_count', 'executed_count', 'skip_count', 'outcome_counts', *OUTCOMES}
    if not isinstance(report, dict) or set(report) != keys or report['suite'] != name or report['discovery'] != SUITES[name]:
        raise ValueError('Invalid static suite report: ' + name)
    if not isinstance(report['discovery_errors'], list) or report['discovery_errors']:
        raise ValueError('Static test discovery failed')
    for key in ['discovered_ids', 'executed_ids', *OUTCOMES]:
        ids = report[key]
        if not isinstance(ids, list) or not all(isinstance(value, str) and value for value in ids) or len(set(ids)) != len(ids):
            raise ValueError('Invalid or duplicated test IDs: ' + key)
    if type(report['process_id']) is not int or report['process_id'] <= 0 or not isinstance(report['skipped'], list):
        raise ValueError('Invalid static process or skipped results')
    discovered, executed = set(report['discovered_ids']), set(report['executed_ids'])
    if not discovered or not executed.issubset(discovered):
        raise ValueError('Empty or inconsistent static discovery')
    counts = {'discovered_count': len(discovered), 'executed_count': len(executed),
              'tests_run': len(executed), 'skip_count': len(report['skipped'])}
    if any(type(report[key]) is not int or report[key] != value for key, value in counts.items()):
        raise ValueError('Static test count disagrees with actual IDs')
    if report['outcome_counts'] != {key: len(report[key]) for key in OUTCOMES} or any(type(value) is not int for value in report['outcome_counts'].values()):
        raise ValueError('Static outcome count mismatch')
    if type(report['duration_seconds']) not in (int, float) or not 0 <= report['duration_seconds'] < 86400:
        raise ValueError('Invalid static suite duration')
    if report['failures'] or report['errors'] or report['unexpected_successes']:
        raise ValueError('Static suite had failures, errors or unexpected successes')
    accounted = list(report['successes']) + list(report['expected_failures'])
    unstarted = []
    seen_skips = set()
    for row in report['skipped']:
        if not isinstance(row, dict) or set(row) != {'id', 'reason', 'affected_ids'}:
            raise ValueError('Malformed static skip')
        identifier = row['id']
        if identifier in seen_skips or name != 'contracts' or not skip_allowed(identifier, row['reason'], root, environ):
            raise ValueError('Unapproved static skip: ' + str(identifier))
        seen_skips.add(identifier)
        expected = [identifier] if identifier in discovered else []
        match = re.fullmatch(r'setUpClass \((.+)\)', identifier)
        if match:
            expected = [item for item in report['discovered_ids'] if item.startswith(match.group(1) + '.')]
            if expected != ALLOWED_CLASS_SKIPS.get(identifier):
                raise ValueError('Class skip changed its approved discovered methods')
        if not expected or row['affected_ids'] != expected:
            raise ValueError('Static skip does not cover its exact discovered methods')
        accounted.extend(expected)
        if identifier not in discovered:
            unstarted.extend(expected)
    if Counter(accounted) != Counter(report['discovered_ids']) or set(unstarted) & executed or executed | set(unstarted) != discovered:
        raise ValueError('Not every discovered test has exactly one completed outcome')


def receipt_for(manifest, raw):
    return encode({'version': 1, **manifest['identity'], 'manifest_sha256': digest(raw)})


def validated_receipt(value, commit, run_id, run_attempt):
    try:
        data = json.loads(value)
    except (TypeError, json.JSONDecodeError) as error:
        raise ValueError('Missing or malformed static receipt') from error
    if not isinstance(data, dict) or set(data) != IDENTITY_KEYS | {'version', 'manifest_sha256'} or type(data['version']) is not int or data['version'] != 1:
        raise ValueError('Invalid static receipt schema')
    identity = valid_identity({key: data[key] for key in IDENTITY_KEYS})
    if (identity['commit'], identity['run_id'], identity['run_attempt']) != (commit, run_id, run_attempt):
        raise ValueError('Static receipt belongs to another SHA, workflow run or attempt')
    if not isinstance(data['manifest_sha256'], str) or not re.fullmatch('[0-9a-f]{64}', data['manifest_sha256']):
        raise ValueError('Invalid static manifest digest')
    return encode(data)


def verify_bundle(directory, root, expected=None):
    directory = checked_output(directory, root)
    identity = source_identity(root)
    manifest_path = directory / 'manifest.json'
    if manifest_path.is_symlink():
        raise ValueError('Static manifest must not be a symlink')
    manifest = read_json(manifest_path)
    if not isinstance(manifest, dict) or set(manifest) != {'version', 'identity', 'suites'} or type(manifest['version']) is not int or manifest['version'] != 1:
        raise ValueError('Invalid static manifest schema')
    if valid_identity(manifest['identity']) != identity:
        raise ValueError('Static manifest source/SHA/tree/run identity differs from this checkout')
    if not isinstance(manifest['suites'], dict) or set(manifest['suites']) != set(SUITES):
        raise ValueError('Static manifest must contain both complete suites')
    check_configured_sources()
    processes = set()
    for name, record in manifest['suites'].items():
        if not isinstance(record, dict) or set(record) != {'report_sha256', 'log_sha256'}:
            raise ValueError('Invalid static suite binding')
        for extension, key in [('json', 'report_sha256'), ('log', 'log_sha256')]:
            path = directory / (name + '.' + extension)
            if path.is_symlink() or not path.is_file() or digest(path.read_bytes()) != record[key]:
                raise ValueError('Static suite artifact missing or digest mismatch: ' + name)
        report = read_json(directory / (name + '.json'))
        validate_report(report, name, root)
        if report['process_id'] in processes:
            raise ValueError('Static suites did not use independent processes')
        processes.add(report['process_id'])
    value = receipt_for(manifest, manifest_path.read_bytes())
    if expected is not None and validated_receipt(expected, identity['commit'], identity['run_id'], identity['run_attempt']) != value:
        raise ValueError('Static artifact differs from successful job receipt')
    return value


def run_all(root, directory):
    root = Path(root).resolve()
    if sys.flags.optimize or os.environ.get('PYTHONOPTIMIZE'):
        raise ValueError('Optimized Python is forbidden for static assertions')
    directory = checked_output(directory, root)
    before = source_identity(root)
    check_configured_sources()
    directory.mkdir(parents=True, exist_ok=False)
    completed = {}
    failed = []
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')

    def check_source_boundary(label):
        # Latch every boundary failure: the following suite restoring the source
        # cannot erase evidence that another suite ran against modified inputs.
        try:
            if source_identity(root) != before:
                raise ValueError('source identity changed')
        except (ValueError, OSError, subprocess.CalledProcessError) as error:
            failed.append('Static source boundary ' + label + ': ' + str(error))

    # Independent interpreters preserve the two original unittest discoveries.
    for name in SUITES:
        check_source_boundary('before ' + name)
        report = directory / (name + '.json')
        log = directory / (name + '.log')
        command = [sys.executable, '-B', str(root / 'tools/run_static_checks.py'), '_suite',
                   '--suite', name, '--report', str(report)]
        print('Full static discovery:', name, SUITES[name], flush=True)
        with log.open('x') as stream:
            result = subprocess.run(command, cwd=root, env=environment, stdout=stream, stderr=subprocess.STDOUT)
        check_source_boundary('after ' + name)
        print(log.read_text(), end='', flush=True)
        try:
            if result.returncode:
                raise ValueError('Suite process did not succeed: ' + name)
            validate_report(read_json(report), name, root)
            completed[name] = {'report_sha256': digest(report.read_bytes()), 'log_sha256': digest(log.read_bytes())}
        except ValueError as error:
            failed.append(str(error))
    check_source_boundary('before manifest')
    if failed or set(completed) != set(SUITES):
        raise ValueError('; '.join(failed) or 'Missing complete static suite')
    manifest = {'version': 1, 'identity': before, 'suites': completed}
    atomic_json(directory / 'manifest.json', manifest)
    return verify_bundle(directory, root)


def write_output(path, value):
    with Path(path).open('a') as output:
        output.write('static_receipt=' + value + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    run = sub.add_parser('run')
    run.add_argument('--output', type=Path, required=True)
    run.add_argument('--github-output', type=Path, required=True)
    child = sub.add_parser('_suite')
    child.add_argument('--suite', choices=SUITES, required=True)
    child.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.action == '_suite':
        report_path = checked_output(args.report, root)
        report = suite_report(args.suite, root)
        atomic_json(report_path, report)
        validate_report(report, args.suite, root)
    else:
        write_output(args.github_output, run_all(root, args.output))


if __name__ == '__main__':
    main()

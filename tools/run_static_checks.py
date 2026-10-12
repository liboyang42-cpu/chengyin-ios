#!/usr/bin/env python3
"""Run both complete native-local Python discoveries and attest their real results.

Only the Linux static job runs the suites. Every Apple consumer and the aggregate
verify the same-run artifact before claiming a successful static prerequisite.
The artifact is an integrity receipt, not a signature or a cross-run cache.
"""
import argparse
from collections import Counter
from contextlib import contextmanager
import faulthandler
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import time
import threading
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



_WORKSPACE_HISTORY_IDENTITY_PATH = 'Tests/ContractChecks/test_merchant_project_workspace_entry.py'
_WORKSPACE_HISTORY_IDENTITY_SHA256 = '8cd437913c3f7e66cd3e7de6d8bdd894c4dd22a073952e7d17278a4e4cab8eea'
_WORKSPACE_HISTORY_METHODS = frozenset({
    'test_exact_inverse_of_all_five_existing_files',
    'test_existing_transactions_grants_sensitive_routes_and_invitation_remain_exact',
    'test_hosted_lifecycle_tests_are_authored',
    'test_old_summary_and_navigation_bindings_are_id_bound',
})

def require_workspace_history_method(relative, class_name, method):
    if (relative != _WORKSPACE_HISTORY_IDENTITY_PATH or class_name != 'ProjectWorkspaceContracts'
            or method not in _WORKSPACE_HISTORY_METHODS):
        raise ValueError('Method outside the exact workspace historical quartet')


def workspace_history_identity_context(root, admission):
    """One explicit physical history, never an arbitrary namespace/provider."""
    import ast
    import marshal
    path = Path(root) / _WORKSPACE_HISTORY_IDENTITY_PATH
    modules = [module for name, module in tuple(sys.modules.items())
               if name in {'test_merchant_project_workspace_entry',
                           'Tests.ContractChecks.test_merchant_project_workspace_entry'}
               and getattr(module, '_workspace_history_context', None) is not None]
    if not modules:
        return None
    if len(modules) != 1:
        raise ValueError('Ambiguous workspace historical provider')
    module = modules[0]
    if getattr(module, '__file__', None) != str(path) or getattr(module, 'ROOT', None) != Path(root):
        raise ValueError('Workspace historical provider belongs to a foreign source')
    admission._club_authenticate_raw(root)
    raw = path.read_bytes()
    nodes = [node for node in ast.parse(raw).body
             if isinstance(node, ast.FunctionDef) and node.name == '_workspace_fixed_history']
    factory = getattr(module, '_workspace_fixed_history', None)
    if len(nodes) != 1 or not callable(factory):
        raise ValueError('Missing exact workspace history factory')
    module_code = compile(raw, str(path), 'exec', dont_inherit=True)
    code = next(value for value in module_code.co_consts
                if type(value) is type(module_code) and value.co_name == '_workspace_fixed_history')
    if not hasattr(factory, '__code__') or marshal.dumps(factory.__code__) != marshal.dumps(code):
        raise ValueError('Changed loaded workspace history factory')
    expected = getattr(module, '_WORKSPACE_HISTORY_SHA256', None)
    if (type(expected) is not dict or len(expected) != 24
            or digest(json.dumps(expected, sort_keys=True, separators=(',', ':')).encode()) != _WORKSPACE_HISTORY_IDENTITY_SHA256):
        raise ValueError('Changed complete workspace history membership')
    context = factory()
    if (context is not module._workspace_history_context
            or not getattr(context, '_club_e2b_guarded', False)
            or dict(context.file_sha256) != expected
            or admission._club_tree_sha256(context.root) != expected):
        raise ValueError('Changed exact workspace history context')
    context.verify()
    return context

def discovery_identities(tests, root, *, report_invalid_duplicates=False):
    """Stable transport keys without mutating any historical test or module.

    Random physical e2b namespaces are admitted only through the existing exact
    context. Logs retain both the original test.id() and its source-bound key.
    Ordinary methods, including every approved skip ID, remain byte-identical.
    """
    tests = list(tests)
    rows = [{'observed_id': test.id(), 'transport_id': test.id()} for test in tests]
    if any(row['observed_id'].startswith('historical_e2b_') for row in rows):
        raise ValueError('Reserved historical transport identity cannot be an observed test ID')
    historical = [(test, row) for test, row in zip(tests, rows)
                  if row['observed_id'].startswith('_club_e2b_')]
    if historical:
        from tools import club_customer_directory_admission as admission
        root = Path(root).resolve(strict=True)
        if (Path(admission.__file__).resolve(strict=True) != root / 'tools/club_customer_directory_admission.py'
                or Path(admission._CLUB_CURRENT_ROOT).resolve(strict=True) != root):
            raise ValueError('Historical identity helper belongs to another current root')
        context = admission._club_context_cache
        if (context is None or not getattr(context, '_club_e2b_guarded', False)
                or dict(context.file_sha256) != admission._CLUB_E2B_SHA256):
            raise ValueError('Historical identity lacks its exact authenticated context')
        context.verify()
        contexts = {'_club_e2b_' + digest(str(context.root).encode())[:24]: (context, None)}
        workspace = workspace_history_identity_context(root, admission)
        if workspace is not None:
            contexts['_club_e2b_' + digest(str(workspace.root).encode())[:24]] = (workspace, _WORKSPACE_HISTORY_METHODS)
        file_hashes = {}
        for test, row in historical:
            case = type(test)
            module_name = case.__module__
            namespace = module_name.split('.', 1)[0]
            if namespace not in contexts:
                raise ValueError('Historical method has an unauthenticated temporary namespace')
            context, allowed_methods = contexts[namespace]
            local = module_name[len(namespace) + 1:]
            relative = local.replace('.', '/') + '.py'
            module = sys.modules.get(module_name)
            method = getattr(test, '_testMethodName', None)
            path = Path(context.root) / relative
            if allowed_methods is not None:
                require_workspace_history_method(relative, case.__name__, method)
            if (module is None or getattr(module, '__file__', None) != str(path)
                    or relative not in context.file_sha256
                    or getattr(module, case.__name__, None) is not case
                    or case.__qualname__ != case.__name__
                    or not isinstance(method, str) or not re.fullmatch(r'test\w+', method)
                    or not callable(getattr(case, method, None))
                    or row['observed_id'] != module_name + '.' + case.__name__ + '.' + method):
                raise ValueError('Historical test class/method is not its admitted module instance')
            if relative not in file_hashes:
                file_hashes[relative] = digest(path.read_bytes())
            source_hash = file_hashes[relative]
            if source_hash != context.file_sha256[relative]:
                raise ValueError('Historical identity source changed after admission')
            row.update(transport_id='historical_e2b_' + source_hash + '.' + local + '.' + case.__name__ + '.' + method,
                       historical_source=relative, historical_source_sha256=source_hash)
        for context, _ in contexts.values():
            context.verify()
    for key in ('observed_id', 'transport_id'):
        values = [row[key] for row in rows]
        if (any(not isinstance(value, str) or not value for value in values)
                or (len(values) != len(set(values)) and not report_invalid_duplicates)):
            raise ValueError('Duplicate or malformed discovered identity mapping')
    observed_by_transport = {}
    for row in rows:
        observed_by_transport.setdefault(row['transport_id'], set()).add(row['observed_id'])
    if any(len(values) != 1 for values in observed_by_transport.values()):
        raise ValueError('Historical transport identity collision')
    # The original unsharded failure path emits duplicate-ID diagnostics before
    # validate_report rejects them. Plan and selected-shard paths stay strict.
    return rows


def emit_identity_evidence(rows):
    for row in rows:
        if row['observed_id'] != row['transport_id']:
            print('STATIC_TEST_IDENTITY ' + encode(row), file=sys.stderr, flush=True)


class RecordingResult(unittest.TextTestResult):
    def __init__(self, *args, identity=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.identity = identity or (lambda test: test.id())
        # unittest startTest IDs include individual skips; class setup skips
        # never start their methods and are accounted separately in affected_ids.
        self.executed_ids = []
        self.success_ids = []
        self.raw_executed_ids = []
        self.raw_success_ids = []
        self.test_started = {}

    def startTest(self, test):
        self.executed_ids.append(self.identity(test))
        self.raw_executed_ids.append(test.id())
        self.test_started[id(test)] = time.monotonic()
        self.stream.writeln('START ' + test.id())
        self.stream.flush()
        super().startTest(test)

    def stopTest(self, test):
        elapsed = time.monotonic() - self.test_started.pop(id(test))
        super().stopTest(test)
        self.stream.writeln('END ' + test.id() + f' duration_seconds={elapsed:.6f}')
        self.stream.flush()

    def addSuccess(self, test):
        self.success_ids.append(self.identity(test))
        self.raw_success_ids.append(test.id())
        super().addSuccess(test)


def _diagnostic_watchdog(stopped, interval, descriptor):
    # Unlike dump_traceback_later's native watchdog, this Python worker holds
    # the GIL while faulthandler reads frames, so active frame/code teardown
    # cannot race the dump. A C extension holding the GIL can delay sampling.
    while not stopped.wait(interval):
        try:
            os.write(descriptor, f'Timeout ({interval:g}-second diagnostic interval)!\n'.encode())
            faulthandler.dump_traceback(file=descriptor, all_threads=True)
        except (OSError, RuntimeError, ValueError):
            # Optional diagnostics must not replace or change suite outcomes.
            return


@contextmanager
def diagnostic_stacks():
    # Stack locations only: no source lines, frame locals, or failure messages.
    if os.environ.get('NATIVE_STATIC_DIAGNOSTIC_STACKS') != '1':
        yield
        return
    try:
        descriptor = sys.stderr.fileno()
    except (AttributeError, OSError, ValueError):
        yield
        return
    stopped = threading.Event()
    worker = threading.Thread(target=_diagnostic_watchdog,
                              args=(stopped, 60, descriptor),
                              name='static-stack-diagnostics', daemon=True)
    try:
        try:
            worker.start()
        except RuntimeError:
            # A resource failure starting optional diagnostics is non-fatal.
            pass
        yield
    finally:
        stopped.set()
        if worker.ident is not None:
            worker.join()


def discover_original_suite(loader, root, specification):
    # Keep the complete original unittest discovery, including dynamically
    # imported historical classes whose test.id is not an importable module.
    # Native repositories provide the authenticated, process-local admission
    # transaction. Generic small fixtures do not have that native layer.
    from contextlib import nullcontext
    admission = root / 'tools/club_customer_directory_admission.py'
    if (root / 'tools/run138_editor_readiness_contract.json').exists() and not admission.is_file():
        raise ValueError('Missing native authenticated admission helper')
    if admission.exists():
        from tools.club_customer_directory_admission import club_authenticated_transaction
        transaction = club_authenticated_transaction(root)
    else:
        transaction = nullcontext()
    with transaction:
        return loader.discover(str(root / specification['directory']), pattern=specification['pattern'])


def select_discovered_suite(suite, test_ids, root=None):
    if not isinstance(test_ids, list) or not test_ids or not all(isinstance(x, str) and x for x in test_ids) or len(set(test_ids)) != len(test_ids):
        raise ValueError('Invalid assigned test IDs')
    tests = list(flatten(suite))
    rows = discovery_identities(tests, Path(__file__).resolve().parents[1] if root is None else root)
    by_id = {row['transport_id']: test for test, row in zip(tests, rows)}
    if len(by_id) != len(tests) or any(identifier not in by_id for identifier in test_ids):
        raise ValueError('Assigned test missing or duplicated in full discovery')
    selected = unittest.TestSuite(by_id[identifier] for identifier in test_ids)
    # Preserve the same real instances and their authenticated one-to-one map.
    selected._static_identity_rows = {id(test): row for test, row in zip(tests, rows)
                                      if row['transport_id'] in test_ids}
    return selected


def suite_report(name, root, test_ids=None, *, evidence=None):
    if sys.flags.optimize or os.environ.get('PYTHONOPTIMIZE'):
        raise ValueError('Optimized Python is forbidden for static assertions')
    check_configured_sources()
    specification = SUITES[name]
    sys.path.insert(0, str(root))
    loader = unittest.TestLoader()
    with diagnostic_stacks():
        discovery_started = time.monotonic()
        print('DISCOVERY START ' + name, file=sys.stderr, flush=True)
        try:
            try:
                suite = discover_original_suite(loader, root, specification)
                discovery_errors = list(loader.errors)
                if test_ids is not None:
                    if discovery_errors:
                        raise ValueError('Static discovery failed: ' + str(discovery_errors))
                    suite = select_discovered_suite(suite, test_ids, root)
            except (ImportError, OSError) as error:
                suite = unittest.TestSuite()
                discovery_errors = [str(error)]
            tests = list(flatten(suite))
            if test_ids is not None and not discovery_errors:
                identity_rows = [suite._static_identity_rows[id(test)] for test in tests]
            else:
                identity_rows = discovery_identities(tests, root, report_invalid_duplicates=True)
            emit_identity_evidence(identity_rows)
            identities = {id(test): row for test, row in zip(tests, identity_rows)}
            def identifier_for(test):
                row = identities.get(id(test))
                if row is None:
                    return test.id()  # Original class/setup error and skip holders.
                if test.id() != row['observed_id']:
                    raise ValueError('Test identity changed after authenticated discovery')
                return row['transport_id']
            discovered = [identifier_for(test) for test in tests]
        finally:
            elapsed = time.monotonic() - discovery_started
            print(f'DISCOVERY END {name} duration_seconds={elapsed:.6f}', file=sys.stderr, flush=True)
        started = time.monotonic()
        result = unittest.TextTestRunner(verbosity=2, resultclass=lambda *args, **kwargs: RecordingResult(*args, identity=identifier_for, **kwargs)).run(suite)
    skipped = []
    for test, reason in result.skipped:
        identifier = identifier_for(test)
        affected = [identifier] if identifier in discovered else []
        match = re.fullmatch(r'setUpClass \((.+)\)', identifier)
        if match:
            affected = [item for item in discovered if item.startswith(match.group(1) + '.')]
        skipped.append({'id': identifier, 'reason': reason, 'affected_ids': affected})
    report = {'suite': name, 'discovery': specification, 'discovery_errors': discovery_errors, 'discovered_ids': discovered,
              'executed_ids': result.executed_ids, 'tests_run': result.testsRun,
              'successes': result.success_ids, 'failures': [identifier_for(test) for test, _ in result.failures],
              'errors': [identifier_for(test) for test, _ in result.errors],
              'expected_failures': [identifier_for(test) for test, _ in result.expectedFailures],
              'unexpected_successes': [identifier_for(test) for test in result.unexpectedSuccesses],
              'skipped': skipped, 'duration_seconds': time.monotonic() - started,
              'process_id': os.getpid(), 'discovered_count': len(discovered), 'executed_count': len(result.executed_ids),
              'skip_count': len(skipped),
              'outcome_counts': {key: 0 for key in OUTCOMES}}
    report['outcome_counts'] = {key: len(report[key]) for key in OUTCOMES}
    # Keep the actual original unittest report, not only transport identifiers.
    # Both report forms share the same events, duration, counts and process.
    raw_report = dict(report, discovered_ids=[row['observed_id'] for row in identity_rows],
                      executed_ids=result.raw_executed_ids, successes=result.raw_success_ids,
                      failures=[test.id() for test, _ in result.failures],
                      errors=[test.id() for test, _ in result.errors],
                      expected_failures=[test.id() for test, _ in result.expectedFailures],
                      unexpected_successes=[test.id() for test in result.unexpectedSuccesses])
    raw_report['skipped'] = []
    for test, reason in result.skipped:
        identifier = test.id()
        affected = [identifier] if identifier in raw_report['discovered_ids'] else []
        match = re.fullmatch(r'setUpClass \((.+)\)', identifier)
        if match:
            affected = [item for item in raw_report['discovered_ids'] if item.startswith(match.group(1) + '.')]
        raw_report['skipped'].append({'id': identifier, 'reason': reason, 'affected_ids': affected})
    payload = {'raw_report': raw_report, 'identities': identity_rows}
    if evidence is not None:
        evidence.update(payload)
    print('STATIC_RAW_REPORT ' + encode(payload), file=sys.stderr, flush=True)
    return report


def validate_identity_report(report, payload, root):
    """Require a complete one-to-one source-bound mapping of the raw report.

    The authenticated discovery proves real module/class ownership. Consumers
    independently verify the finite historical source map and exact report
    projection; the existing log digest binds the original evidence end to end.
    """
    if not isinstance(payload, dict) or set(payload) != {'raw_report', 'identities'}:
        raise ValueError('Missing exact original report and identity mapping')
    raw, rows = payload['raw_report'], payload['identities']
    name = report['suite']
    validate_report(raw, name, root)
    validate_report(report, name, root)
    if not isinstance(rows, list) or len(rows) != len(raw['discovered_ids']):
        raise ValueError('Incomplete original report identity mapping')
    mapping = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get('observed_id'), str) or not isinstance(row.get('transport_id'), str):
            raise ValueError('Malformed original report mapping')
        observed, transport = row['observed_id'], row['transport_id']
        if observed in mapping or observed.startswith('historical_e2b_'):
            raise ValueError('Duplicate or forged original identity')
        if observed.startswith('_club_e2b_'):
            if set(row) != {'observed_id', 'transport_id', 'historical_source', 'historical_source_sha256'}:
                raise ValueError('Incomplete historical source identity')
            match = re.fullmatch(r'_club_e2b_[0-9a-f]{24}\.((?:[A-Za-z_]\w*\.)+)([A-Za-z_]\w*)\.(test\w+)', observed)
            if match is None:
                raise ValueError('Malformed historical observed identity')
            local = match.group(1).rstrip('.')
            relative = local.replace('.', '/') + '.py'
            from tools import club_customer_directory_admission as admission
            if (Path(admission.__file__).resolve(strict=True) != Path(root).resolve(strict=True) / 'tools/club_customer_directory_admission.py'
                    or Path(admission._CLUB_CURRENT_ROOT).resolve(strict=True) != Path(root).resolve(strict=True)):
                raise ValueError('Historical report helper belongs to another current root')
            source_hash = admission._CLUB_E2B_SHA256.get(relative)
            if (not source_hash or row['historical_source'] != relative or row['historical_source_sha256'] != source_hash
                    or transport != 'historical_e2b_' + source_hash + '.' + local + '.' + match.group(2) + '.' + match.group(3)):
                raise ValueError('Historical raw report mapping changed its source or method')
        elif set(row) != {'observed_id', 'transport_id'} or observed != transport:
            raise ValueError('Ordinary test identity was rewritten')
        mapping[observed] = transport
    if list(mapping) != raw['discovered_ids'] or len(set(mapping.values())) != len(mapping):
        raise ValueError('Missing, reordered or colliding raw report mapping')
    projected = dict(raw)
    for key in ['discovered_ids', 'executed_ids', *OUTCOMES]:
        projected[key] = [mapping.get(identifier, identifier) for identifier in raw[key]]
    projected['skipped'] = [dict(row, id=mapping.get(row['id'], row['id']),
                               affected_ids=[mapping[identifier] for identifier in row['affected_ids']]) for row in raw['skipped']]
    if projected != report:
        raise ValueError('Transport report differs from its exact raw report projection')
    return payload


def validate_log_identity_report(log, report, root):
    records = [line[len('STATIC_RAW_REPORT '):] for line in log.decode('utf-8').splitlines()
               if line.startswith('STATIC_RAW_REPORT ')]
    if len(records) != 1:
        raise ValueError('Missing or duplicate raw report in hash-bound shard log')
    def unique(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError('Duplicate raw report JSON key')
            value[key] = item
        return value
    return validate_identity_report(report, json.loads(records[0], object_pairs_hook=unique), root)


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


def run_logged_process(command, root, environment, log):
    """Relay the exact merged child bytes as they arrive, without a pipe wait.

    A file-backed tee preserves the artifact even when CI interrupts the parent.
    Unlike a pipe reader, it cannot hang on an inherited writer after child exit.
    Read only each observed snapshot so a noisy writer cannot starve cancellation.
    """
    termination_signal = None

    def interrupted(signum, frame):
        nonlocal termination_signal
        if termination_signal is None:
            termination_signal = signum
            # Only record here: asynchronous exceptions can interrupt Popen's
            # handle transfer or even the first instruction of cleanup. The
            # protected 100 ms loop below owns propagation and child cleanup.

    previous = {signum: signal.signal(signum, interrupted)
                for signum in (signal.SIGTERM, signal.SIGINT)}
    try:
        with log.open('xb') as stream, log.open('rb') as replay:
            def relay_available():
                remaining = os.fstat(replay.fileno()).st_size - replay.tell()
                while remaining:
                    # Defer cancellation until the already-read bytes have
                    # reached stdout; otherwise a partial write loses its tail.
                    mask = signal.pthread_sigmask(signal.SIG_BLOCK, previous)
                    try:
                        chunk = replay.read(min(65536, remaining))
                        if not chunk:
                            break
                        pending = memoryview(chunk)
                        while pending:
                            written = sys.stdout.buffer.write(pending)
                            if written is None or written <= 0:
                                raise OSError('Static console output stopped accepting bytes')
                            pending = pending[written:]
                        sys.stdout.buffer.flush()
                        remaining -= len(chunk)
                    finally:
                        signal.pthread_sigmask(signal.SIG_SETMASK, mask)

            process = None
            try:
                # Defer signals in Python, without blocking their OS mask:
                # the child must not inherit TERM/INT blocked during startup.
                process = subprocess.Popen(command, cwd=root, env=environment,
                                           stdout=stream, stderr=subprocess.STDOUT,
                                           start_new_session=True)
                while True:
                    if termination_signal is not None:
                        raise SystemExit(128 + termination_signal)
                    try:
                        returncode = process.wait(timeout=0.1)
                    except subprocess.TimeoutExpired:
                        returncode = None
                    relay_available()
                    if returncode is not None:
                        return subprocess.CompletedProcess(command, returncode)
            finally:
                # Reap on interruption and kill residual inherited writers; no
                # helper thread or unbounded communicate()/pipe read can linger.
                if process is not None:
                    try:
                        try:
                            os.killpg(process.pid, signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            pass
                    finally:
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        process.wait(timeout=5)
                        relay_available()
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)
        if termination_signal is not None:
            raise SystemExit(128 + termination_signal)


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
        command = [sys.executable, '-B', '-u', str(root / 'tools/run_static_checks.py'), '_suite',
                   '--suite', name, '--report', str(report)]
        print('Full static discovery:', name, SUITES[name], flush=True)
        result = run_logged_process(command, root, environment, log)
        check_source_boundary('after ' + name)
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
    child.add_argument('--test-ids', type=Path)
    discovery = sub.add_parser('_discover')
    discovery.add_argument('--suite', choices=SUITES, required=True)
    discovery.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.action == '_discover':
        if sys.flags.optimize or os.environ.get('PYTHONOPTIMIZE'):
            raise ValueError('Optimized Python is forbidden for static assertions')
        check_configured_sources()
        sys.path.insert(0, str(root))
        loader = unittest.TestLoader()
        spec = SUITES[args.suite]
        suite = discover_original_suite(loader, root, spec)
        if loader.errors:
            raise ValueError('Static discovery failed: ' + str(loader.errors))
        rows = discovery_identities(list(flatten(suite)), root)
        emit_identity_evidence(rows)
        atomic_json(checked_output(args.report, root), [row['transport_id'] for row in rows])
        atomic_json(checked_output(args.report.with_suffix('.identities.json'), root), rows)
        atomic_json(checked_output(args.report.with_suffix('.raw.json'), root), [row['observed_id'] for row in rows])
    elif args.action == '_suite':
        report_path = checked_output(args.report, root)
        ids = read_json(checked_output(args.test_ids, root)) if args.test_ids is not None else None
        evidence = {}
        report = suite_report(args.suite, root, ids, evidence=evidence)
        atomic_json(report_path, report)
        atomic_json(report_path.with_suffix('.raw.json'), evidence['raw_report'])
        atomic_json(report_path.with_suffix('.identities.json'), evidence['identities'])
        validate_report(report, args.suite, root)
        validate_identity_report(report, evidence, root)
    else:
        write_output(args.github_output, run_all(root, args.output))


if __name__ == '__main__':
    main()

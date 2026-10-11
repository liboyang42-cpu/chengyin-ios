"""Active source-bound UI1/UI33/UI35 readiness costs with an exact prior inverse.

The active runner dispatches current sources here. Profile, workflow and historical
contracts retain their exact original values. It validates the candidate first, then asks the unchanged historical
planning chain for the original costs and adds every new operation allowance.
"""
from pathlib import Path
import argparse
import atexit
import hashlib
import json
from copy import deepcopy
from functools import lru_cache
import math
import re
import tempfile

ROOT = Path(__file__).resolve().parents[1]
# Bind the validator bytes loaded for this process, including its contract pin.
IMPLEMENTATION_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
CONTRACT_SHA256 = 'f9b759524a5def849d485bc8ede1783fab23cb7b73cd34d732cbbe8c77dbb12b'
SOURCE_CONTRACT = 'Tests/ContractChecks/fixtures/project_editor_readiness.json'
REVIEW = 'ProjectEditReviewReadinessFlowTests.testLocalEditReviewAndCancelledConfirmation'
WHITELIST = 'ProjectEditFlowTests.testWhitelistDisablesStructureAndScheduleButKeepsCopyEditable'
CHINESE = 'ApprovedTopicSelectedCoverChineseFlowTests.testChineseMaximumTextShowsAuthorOnlyBoundaryAndKeepsOriginalReceipt'
CURRENT_REVIEW = 'ApprovedTopicReviewCurrentChineseFlowTests.testChineseMaximumTextCurrentTaskReadRemainsSeparateFromSavedSubmissionAndClearsOnReopen'
RELEASE_RECOVERY = 'ApprovedReleaseRecoveryFlowTests.testChineseMaximumTextUnknownRecoveryKeepsOnlyThePersistedRequest'
COVER_RECOVERY = 'OwnedTopicCoverRecoveryFlowTests.testChineseMaximumTextUnknownSelectionReopensAndChecksOriginalRequestWithoutReupload'
_lives = []
_ui_projections = {}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return digest(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


@lru_cache(maxsize=1)
def _parsed_contract(raw):
    return json.loads(raw)


def contract(root=ROOT):
    raw = (Path(root) / 'tools/run138_editor_readiness_contract.json').read_bytes()
    if digest(raw) != CONTRACT_SHA256:
        raise ValueError('Unreviewed current readiness planning contract')
    return deepcopy(_parsed_contract(raw))


def source_contract(root=ROOT):
    raw = (Path(root) / SOURCE_CONTRACT).read_bytes()
    if digest(raw) != contract(root)['source_contract_sha256']:
        raise ValueError('Changed exact readiness source contract')
    return json.loads(raw)


def contract_member(section, member=None, root=ROOT):
    """Copy one validated member without copying unrelated contract branches."""
    raw = (Path(root) / 'tools/run138_editor_readiness_contract.json').read_bytes()
    if digest(raw) != CONTRACT_SHA256:
        raise ValueError('Unreviewed current readiness planning contract')
    value = _parsed_contract(raw)[section]
    if member is not None:
        value = value.get(member)
    return deepcopy(value)


def original_source(relative, raw, root=ROOT):
    raw = followons().source_before_followons(relative, raw)
    row = source_contract(root)['files'][relative]
    if digest(raw) != row['after_sha256']:
        raise ValueError('Unknown current readiness source: ' + relative)
    if row['before_sha256'] is None:
        return None
    source = raw.decode()
    for hunk in reversed(row['hunks']):
        if source.count(hunk['after']) != 1:
            raise ValueError('Missing or duplicated exact readiness span')
        source = source.replace(hunk['after'], hunk['before'], 1)
    restored = source.encode()
    if digest(restored) != row['before_sha256']:
        raise ValueError('Original readiness source not restored exactly')
    return restored


def followons():
    try:
        from . import ci138_followon_projection as value
    except ImportError:
        import ci138_followon_projection as value
    return value


def required_followon_files(root=ROOT):
    c = contract(root)
    return {'tools/run138_editor_readiness.py', 'Tests/ContractChecks/test_run130_topic_media_source_adapter.py'} | set(c['node_description_sources']) | set(c['feature_batch_sources']) | set(c['feature_batch_support_sha256']) | set(c['followon_support_sha256']) | set(followons().availability().contract()['scope']) | set(followons().availability().contract()['unchanged_dependencies'])


def ui52_layer():
    try:
        from . import run138_ui52_driver_inverse as driver
    except ImportError:
        import run138_ui52_driver_inverse as driver
    return driver


def entry_projection():
    try:
        from . import run138_current_source_projection as entry
    except ImportError:
        import run138_current_source_projection as entry
    return entry


def inventory(directory):
    keys = []
    classes = []
    for path in Path(directory).glob('*.swift'):
        text = path.read_text()
        methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', text)
        if not methods:
            continue
        owners = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', text)
        if len(owners) != 1 or len(methods) != len(set(methods)):
            raise ValueError('Missing, repeated or hidden readiness method owner')
        classes.append(owners[0])
        keys.extend(owners[0] + '.' + name for name in methods)
    if len(keys) != len(set(keys)) or len(classes) != len(set(classes)):
        raise ValueError('Duplicate readiness method or class')
    return sorted(keys), sorted(classes)


def validate_current(directory, profile_path, root=ROOT):
    root, directory = Path(root), Path(directory)
    c = contract(root)
    if digest((root / 'tools/run138_editor_readiness.py').read_bytes()) != IMPLEMENTATION_SHA256:
        raise ValueError('Current readiness implementation bytes changed')
    entry_projection().validate_entries(root)
    actual = {p.name: digest(p.read_bytes()) for p in directory.glob('*.swift')}
    if actual != c['current_ui_sources']:
        raise ValueError('Changed, missing or additional current UI source')
    if digest(Path(profile_path).read_bytes()) != c['unchanged_profile_sha256']:
        raise ValueError('Old profile, floors or historical observations changed')
    keys, classes = inventory(directory)
    if (len(keys) != 765 or len(classes) != 171
            or canonical(keys) != c['current_inventory_sha256']):
        raise ValueError('Current 765 complete methods are not preserved')
    for relative, expected in c['followon_support_sha256'].items():
        if digest(entry_projection().historical_entry_bytes(root, relative)) != expected:
            raise ValueError('Follow-on source or cost adapter changed: ' + relative)
    if followons().validate_owned_ui(directory, root) != c['followon_complete_method_costs']:
        raise ValueError('Follow-on complete-method costs changed')
    source = source_contract(root)
    for relative, row in source['files'].items():
        path = directory / Path(relative).name if relative.startswith('Tests/AppUITests/') else root / relative
        original_source(relative, path.read_bytes(), root)
    for relative, expected in {**source['protected_sha256'], **c['protected_planning_sha256']}.items():
        if digest(entry_projection().historical_entry_bytes(root, relative)) != expected:
            raise ValueError('Protected helper, effective environment, history or runner changed: ' + relative)
    driver = ui52_layer()
    if digest(entry_projection().historical_entry_bytes(root, 'tools/run138_ui52_driver_inverse.py')) != c['ui52_inverse_sha256']:
        raise ValueError('Owned UI52 inverse changed')
    if digest((root / driver.CONTRACT_PATH).read_bytes()) != c['ui52_contract_sha256']:
        raise ValueError('Owned UI52 source/cost contract changed')
    for relative in driver.contract(root)['files']:
        driver.original_source(relative, (directory / Path(relative).name).read_bytes(), root)
    if driver.validate_costs(root) != c['ui52_method_costs']:
        raise ValueError('UI52 complete-method waits were not fully charged')
    # Historical planning modules validate their own reviewed evolution. In
    # particular, the independent DEBUG history-fixture projection can compose.
    migrated = (directory / 'ProjectEditReviewReadinessFlowTests.swift').read_text()
    helpers = '    private var launchedApp:' + migrated.split('    private var launchedApp:', 1)[1].split('    // UNMEASURED', 1)[0]
    original = original_source('Tests/AppUITests/ProjectEditFlowTests.swift', (directory / 'ProjectEditFlowTests.swift').read_bytes(), root).decode()
    before_helpers = '    private var launchedApp:' + original.split('    private var launchedApp:', 1)[1].split('    private func revealTicketAboveEditorActions(', 1)[0]
    if helpers != before_helpers or digest(helpers.encode()) != c['helper_copy_sha256']:
        raise ValueError('Migrated launch, replacement, cancel reveal or teardown helpers changed')
    if set(c['method_costs']) != {REVIEW, WHITELIST, CHINESE, CURRENT_REVIEW, RELEASE_RECOVERY, COVER_RECOVERY}:
        raise ValueError('Unapproved current readiness cost identity')
    for key, row in c['method_costs'].items():
        text = (directory / (key.split('.')[0] + '.swift')).read_text()
        body = re.search(r'(?m)^    func ' + re.escape(key.split('.')[1]) + r'\b[\s\S]*?^    }', text)
        if body is None or digest(body.group().encode()) != row['declaration_sha256']:
            raise ValueError('Complete current method body changed')
        query_slots = row['maximum_viewport_evaluations']
        seconds = query_slots * (row['query_phase_seconds_assumption'] + row['gesture_and_settle_seconds_assumption'])
        seconds += row['initial_ax_lookups'] * row['initial_ax_lookup_seconds_assumption']
        rounded = math.ceil(seconds / 10) * 10
        if (row['measured'] is not False or query_slots != 11 or row['maximum_gestures'] != 10
                or row['unrounded_added_seconds'] != seconds or rounded != row['added_seconds']
                or rounded != 40 or row['candidate_complete_method_seconds'] != row['prior_complete_method_seconds'] + rounded):
            raise ValueError('Added query/gesture work or retained full-method floor changed')
    direction = c['direction_only_helper']
    relative = direction['path']
    current_helper = followons().source_before_followons(relative, (directory / Path(relative).name).read_bytes())
    old_helper = original_source(relative, (directory / Path(relative).name).read_bytes(), root)
    current_text = current_helper.decode()
    if (relative != 'Tests/AppUITests/ProjectStoryTemplateFlowSupport.swift'
            or direction['added_seconds'] != 0 or direction['maximum_swipes_unchanged'] != 10
            or current_text.count(direction['after_call']) != 1
            or current_text.replace(direction['after_call'], direction['before_call'], 1).encode() != old_helper):
        raise ValueError('Direction-only story helper added work or changed other semantics')
    if (c['new_over900_exceptions'] != {CHINESE: 948, CURRENT_REVIEW: 946, 'ProjectStoryImageFlowTests.testChosenStoryImageAppliesOnlyAfterUploadAndRestoresIntoExactPreparedOrder': 905, RELEASE_RECOVERY: 944, COVER_RECOVERY: 942, 'ApprovedTopicFrozenCoverPublicationFlowTests.testApprovedCoverConfirmationAndUnknownPublicationRestoreOriginalManifest': 940, 'ProjectStoryAudioRecoveryFlowTests.testChineseMaximumTextUnknownUploadChecksSameRequestWithoutSecondUpload': 980}
            or c['preserved_historical_exceptions'] != {CHINESE: 908, CURRENT_REVIEW: 906, RELEASE_RECOVERY: 904, COVER_RECOVERY: 902}
            or c['added_total_seconds'] != 9713.948 or c['deadline_seconds'] != 1800
            or c['startup_reserve_seconds'] != 300 or c['shard_count'] != 79):
        raise ValueError('Exception scope, added work, reserve or deadline changed')
    validate_club_leaderboard_budget(c, directory, root)
    validate_product_ui_budget(c, directory, root)
    return c


def previous_directory(directory, profile_path, root=ROOT):
    c = validate_current(directory, profile_path, root)
    key = (str(Path(directory).resolve()), str(Path(root).resolve()), canonical(c['current_ui_sources']))
    cached = _ui_projections.get(key)
    if cached is not None and cached.exists():
        # Admission above still hashes all current inputs on every call. Cached
        # prior bytes are separately revalidated, never trusted by path alone.
        actual = {p.name: digest(p.read_bytes()) for p in cached.glob('*.swift')}
        if actual != c['previous_ui_sources']:
            raise ValueError('Cached exact historical UI was changed')
        return cached
    life = tempfile.TemporaryDirectory(prefix='run138-readiness-original-')
    _lives.append(life)
    target = Path(life.name) / 'AppUITests'
    target.mkdir()
    changed = source_contract(root)['files']
    for name, expected in c['previous_ui_sources'].items():
        raw = (Path(directory) / name).read_bytes()
        relative = 'Tests/AppUITests/' + name
        if relative in c['feature_batch_sources']:
            raw = entry_projection().original_feature_batch_bytes(relative, raw, root)
        if relative in changed:
            raw = original_source(relative, raw, root)
        elif relative in ui52_layer().contract(root)['files']:
            raw = ui52_layer().original_source(relative, raw, root)
        elif relative in followons().owned_ui_paths():
            raw = followons().source_before_followons(relative, raw)
        if raw is None or digest(raw) != expected:
            raise ValueError('Original complete UI inventory not restored exactly')
        (target / name).write_bytes(raw)
    keys, classes = inventory(target)
    if len(keys) != 736 or len(classes) != 162 or canonical(keys) != c['previous_inventory_sha256']:
        raise ValueError('Historical complete-method identity is not restored exactly')
    _ui_projections[key] = target
    return target


def weights(directory=ROOT / 'Tests/AppUITests', profile_path=ROOT / 'tools/ui_duration_weights.json', root=ROOT):
    c = validate_current(directory, profile_path, root)
    old = previous_directory(directory, profile_path, root)
    try:
        from .run_ui_shard import measured_weights
    except ImportError:
        from run_ui_shard import measured_weights
    before = measured_weights(old, profile_path)
    for name, expected in c['prior_class_seconds'].items():
        if not math.isclose(before.get(name, -1), expected, abs_tol=1e-9):
            raise ValueError('Historical class cost changed before readiness accounting')
    if not math.isclose(before.get('ClubGovernanceFlowTests', -1), 626.149, abs_tol=1e-9):
        raise ValueError('Original whole club class floor changed')
    result = dict(before)
    result['ProjectEditFlowTests'] = before['ProjectEditFlowTests'] - 150 + 40
    result['ProjectEditReviewReadinessFlowTests'] = 150 + 40
    result['ApprovedTopicSelectedCoverChineseFlowTests'] = before['ApprovedTopicSelectedCoverChineseFlowTests'] + 40
    result['ApprovedTopicReviewCurrentChineseFlowTests'] = before['ApprovedTopicReviewCurrentChineseFlowTests'] + 40
    result['MerchantMarketingUITests'] = before['MerchantMarketingUITests'] + 30
    result['ProjectStoryImageFlowTests'] = before['ProjectStoryImageFlowTests'] + 5
    result['ApprovedReleaseRecoveryFlowTests'] = before['ApprovedReleaseRecoveryFlowTests'] + 40
    result['OwnedTopicCoverRecoveryFlowTests'] = before['OwnedTopicCoverRecoveryFlowTests'] + 40
    result['ProjectStoryAudioRecoveryFlowTests'] = before['ProjectStoryAudioRecoveryFlowTests'] + 80
    result['OwnedCouponCodeJourneyUITests'] = before['OwnedCouponCodeJourneyUITests'] + 20
    result['ApprovedTopicFrozenCoverPublicationFlowTests'] = before['ApprovedTopicFrozenCoverPublicationFlowTests'] + 32
    result['SquareWorkspaceFlowTests'] = 19.197 + 110 + 120
    result['ClubLeaderboardMemberFlowTests'] = validate_club_leaderboard_budget(c, directory, root)
    increments=validate_product_ui_budget(c, directory, root)
    if not math.isclose(before.get('ProfileEditFlowTests',-1),c['product_ui_budget']['prior_profile_class_seconds'],abs_tol=1e-9):
        raise ValueError('Prior profile whole-class floor changed')
    for name,seconds in increments.items():result[name]=result.get(name,0)+seconds
    if ({name: result[name] for name in c['candidate_class_seconds']} != c['candidate_class_seconds']
            or not math.isclose(sum(result.values()) - sum(before.values()), 9713.948, abs_tol=1e-7)):
        raise ValueError('New full-method work was omitted or an old cost decreased')
    return result


def report(root=ROOT):
    root = Path(root)
    c = contract(root)
    costs = weights(root / 'Tests/AppUITests', root / 'tools/ui_duration_weights.json', root)
    try:
        from .run_ui_shard import partition
    except ImportError:
        from run_ui_shard import partition
    groups = partition(costs, 79)
    loads = [sum(costs[name] for name in group) for group in groups]
    if max(loads) + 300 > 1800:
        raise ValueError('A complete class/shard exceeds the unchanged deadline and reserve')
    return {'status': c['status'], 'active_ci_runner_modified': True, 'apple_executed': False,
            'method_count': 765, 'class_count': len(costs), 'shard_count': 79,
            'candidate_class_seconds': c['candidate_class_seconds'],
            'added_total_seconds': 9713.948, 'total_seconds': sum(costs.values()),
            'maximum_shard_seconds': max(loads), 'maximum_with_startup_reserve_seconds': max(loads) + 300,
            'deadline_seconds': 1800, 'startup_reserve_seconds': 300,
            'shards': [{'index': index, 'classes': group, 'seconds': loads[index]} for index, group in enumerate(groups)]}

# P045 complete-method budgets. These source-bound allowances are UNMEASURED.
_CLUB_BUDGET = {'status': 'UNMEASURED_RECONSTRUCTED_SOURCE_BOUND_PROPOSAL', 'measured': False, 'complete_class_seconds': 1190, 'explicit_wait_seconds': 177, 'held_response_counter_wait_calls': 8, 'maximum_swipes_per_reveal': 10, 'maximum_viewport_evaluations_per_reveal': 11, 'source_sha256': {'App/ClubGovernanceFixtureHost.swift': '77e6f477469531673b73f6317bbb2a7504662642bbb4e4067cf99bfe3d0c993d', 'Tests/AppUITests/ClubLeaderboardMemberFlowTests.swift': '742da04056398fb638cc53eae154497c332b9c647390a7762665d4db77156b6d', 'Tests/AppUITests/ClubGovernanceFlowTests.swift': '4d41464ed772a0c371669e5dd55c8a06700b5980e2cb6f17e6ece58a7d1ce7ee', 'Tests/AppUITests/FailureScreenshot.swift': '705ba7fa14128cfd9e81f181fd2b5f5edd0cb464b2ececd26119510d98ed6e49'}, 'methods': {'testLeaderboardMemberPublicProfileBackAndReopen': {'declaration_sha256': '78b021023aaba4bf2506416fbd86eb728dd6846953d79e430030323ccdf81ead', 'measured': False, 'explicit_wait_seconds': 40, 'reveal_calls_with_loop_expansion': 3, 'lifecycle_and_failure_seconds': 90, 'per_reveal_seconds': 40, 'direct_ax_allowance_seconds': 10, 'unrounded_complete_seconds': 260, 'complete_seconds': 260}, 'testLeaderboardAccountSwitchRetiresVisiblePublicProfile': {'declaration_sha256': '6fa4c2645c06bb0971749d1f42548aa93c22742f47f50a3f03930c58ecbafa56', 'measured': False, 'explicit_wait_seconds': 30, 'reveal_calls_with_loop_expansion': 2, 'lifecycle_and_failure_seconds': 90, 'per_reveal_seconds': 40, 'direct_ax_allowance_seconds': 10, 'unrounded_complete_seconds': 210, 'complete_seconds': 210}, 'testLeaderboardSwitchDuringProfileLoadRejectsLatePresentation': {'declaration_sha256': 'abe2d9f80518c935f1e032e7a6874878981ccca61a97a6a4a902dc9d8059f569', 'measured': False, 'explicit_wait_seconds': 62, 'reveal_calls_with_loop_expansion': 2, 'lifecycle_and_failure_seconds': 90, 'per_reveal_seconds': 40, 'direct_ax_allowance_seconds': 20, 'unrounded_complete_seconds': 252, 'complete_seconds': 260}, 'testLeaderboardMissingProfileReaderKeepsReadOnlyFacts': {'declaration_sha256': 'fb19942e35e3eb799ac3f88cc5b833201f5cf298d96ecf189937e55e91e06f12', 'measured': False, 'explicit_wait_seconds': 15, 'reveal_calls_with_loop_expansion': 1, 'lifecycle_and_failure_seconds': 90, 'per_reveal_seconds': 40, 'direct_ax_allowance_seconds': 10, 'unrounded_complete_seconds': 155, 'complete_seconds': 160}, 'testLeaderboardMismatchedProfileAccountCannotOpenMember': {'declaration_sha256': '87a0023eb5865cd1f94c8cbca0b097cfeee4b6379961ad47a9be4ff9c180322b', 'measured': False, 'explicit_wait_seconds': 15, 'reveal_calls_with_loop_expansion': 1, 'lifecycle_and_failure_seconds': 90, 'per_reveal_seconds': 40, 'direct_ax_allowance_seconds': 5, 'unrounded_complete_seconds': 150, 'complete_seconds': 150}, 'testLeaderboardMissingMemberIDCannotCreateDestination': {'declaration_sha256': '5da76474f68766c8a27acba8ab14af319ee12551d1acfccc746d93cf471d3b1b', 'measured': False, 'explicit_wait_seconds': 15, 'reveal_calls_with_loop_expansion': 1, 'lifecycle_and_failure_seconds': 90, 'per_reveal_seconds': 40, 'direct_ax_allowance_seconds': 5, 'unrounded_complete_seconds': 150, 'complete_seconds': 150}}}


def validate_club_leaderboard_budget(c, directory, root):
    budget = c.get('club_leaderboard_member_budget')
    if budget != _CLUB_BUDGET:
        raise ValueError('Unreviewed complete club leaderboard budget')
    root, directory = Path(root), Path(directory)
    if directory.absolute() != (root / 'Tests/AppUITests').absolute():
        raise ValueError('Club budget must read the supplied actual current UI directory')
    for relative, expected in budget['source_sha256'].items():
        path = directory / Path(relative).name if relative.startswith('Tests/AppUITests/') else root / relative
        if digest(path.read_bytes()) != expected:
            raise ValueError('Changed club whole-method budget source: ' + relative)
    text = (directory / 'ClubLeaderboardMemberFlowTests.swift').read_text()
    if len(re.findall(r'(?m)^    func testLeaderboard\w+\(', text)) != 6:
        raise ValueError('Changed complete club UI method inventory')
    expected_waits = [40, 30, 62, 15, 15, 15]
    expected_reveals = [3, 2, 2, 1, 1, 1]
    expected_ax = [10, 10, 20, 10, 5, 5]
    expected_caps = [260, 210, 260, 160, 150, 150]
    costs = []
    for i, (name, row) in enumerate(budget['methods'].items()):
        match = re.search(r'(?m)^    func ' + re.escape(name) + r'\b[\s\S]*?^    }', text)
        if match is None or digest(match.group().encode()) != row['declaration_sha256']:
            raise ValueError('Changed complete club method declaration: ' + name)
        wait, reveals, ax = expected_waits[i], expected_reveals[i], expected_ax[i]
        # 90 covers launch/reset/termination and failure capture; each reveal
        # charges all eleven viewport evaluations and up to ten gestures.
        unrounded = 90 + wait + reveals * 40 + ax
        complete = math.ceil(unrounded / 10) * 10
        if (row['measured'] is not False or row['explicit_wait_seconds'] != wait
                or row['reveal_calls_with_loop_expansion'] != reveals
                or row['lifecycle_and_failure_seconds'] != 90
                or row['per_reveal_seconds'] != 40 or row['direct_ax_allowance_seconds'] != ax
                or row['unrounded_complete_seconds'] != unrounded
                or row['complete_seconds'] != complete or complete != expected_caps[i]
                or complete > 900):
            raise ValueError('Club full-method work was undercharged')
        costs.append(complete)
    if (sum(costs) != 1190 or sum(expected_waits) != 177
            or text.count('        waitLeaderboardCounter(') != 8
            or budget['complete_class_seconds'] != 1190
            or budget['measured'] is not False):
        raise ValueError('Club full-class allowance or held-request waits changed')
    return 1190


_PRODUCT_UI_BUDGET = {'status': 'UNMEASURED_SOURCE_BOUND_PRODUCT_UI_INCREMENT',
 'measured': False,
 'new_methods': 23,
 'changed_existing_methods': 3,
 'method_count_after': 765,
 'class_count_after': 171,
 'assumptions': {'per_reveal_seconds': 40,
                 'per_reveal_maximum_swipes': 10,
                 'per_reveal_maximum_viewports': 11,
                 'lifecycle_and_failure_seconds': 90,
                 'per_direct_action_seconds': 5,
                 'per_direct_ax_assertion_seconds': 2,
                 'per_typed_character_seconds': 0.25,
                 'round_up_seconds': 10},
 'source_sha256': {'App/MerchantOperationsEditor.swift': '2728a1253e261b4e7712ed3fc799832668880a53d59300b211ec50b1e843e8be',
                   'App/ProfileEditView.swift': '45879a75ed1ea5c2fbe3403df07cae9aa7bcda40d03f974954f84c60a4adf427',
                   'Tests/AppUITests/FailureScreenshot.swift': '705ba7fa14128cfd9e81f181fd2b5f5edd0cb464b2ececd26119510d98ed6e49',
                   'Tests/AppUITests/MerchantTemplateExitPlanFlowTests.swift': '23bd4804a9a9de93deeef8e33975f619aa9bb244ecff7aa712fad05063f14d5c',
                   'Tests/AppUITests/MerchantTemplateMetadataFlowTests.swift': '4212ff99e168ef270480c497ab9d1fb1f95bcf79bc803e161a256e0f857c3074',
                   'Tests/AppUITests/MerchantTemplateParticipationPlanFlowTests.swift': 'b4e8c60794037f8e8fb151c3ba11516099482d63cf2784b3085bc9d38a6a7e7f',
                   'Tests/AppUITests/MerchantTemplatePreparationFlowTests.swift': '1b5e909777f95a10c36b46631b7f7c8f9091c413ac0fe3a0a5f890b5fe86a673',
                   'Tests/AppUITests/MerchantTemplateRuleStepsFlowTests.swift': '48e614784818da1dfdb1a542742da2c7d9db44ad1c6e61efcea050961b005016',
                   'Tests/AppUITests/ProfileCasePortfolioFlowTests.swift': '171eb446703ca5240139d43fa1acbe3c764b848116e8f97c6b603dd2059d4455',
                   'Tests/AppUITests/ProfileContactQRRemovalFlowTests.swift': 'b2e650c4b6733546dc24ca36cce3538f487f476a122ea8e17c50597fd53d02d6',
                   'Tests/AppUITests/ProfileEditFlowTests.swift': 'e7f852988ffed57f81015d0e9eb9f0db17dc17f6500ef1522959e008ff417067'},
 'methods': {'ProfileEditFlowTests.testNicknameCancelReopenAndApply': {'source': 'Tests/AppUITests/ProfileEditFlowTests.swift',
                                                                       'declaration_sha256': '2a159139c56d4319a10df9295a2ddb0bb96f7921661382dc34a555a7cf67a3bc',
                                                                       'measured': False,
                                                                       'existing_method_increment': False,
                                                                       'lifecycle_seconds': 90,
                                                                       'explicit_wait_seconds': 47,
                                                                       'bounded_reveal_calls': 0,
                                                                       'direct_action_count': 8,
                                                                       'direct_ax_assertion_count': 4,
                                                                       'typed_characters': 17,
                                                                       'unrounded_seconds': 189.25,
                                                                       'seconds': 190},
             'ProfileEditFlowTests.testIntroductionCancelDoesNotRevertPreviouslyStagedNickname': {'source': 'Tests/AppUITests/ProfileEditFlowTests.swift',
                                                                                                  'declaration_sha256': '8dbc1df29a0f7dcc9b13926476932126f2647437787dd401c4b6a18a340d7f0b',
                                                                                                  'measured': False,
                                                                                                  'existing_method_increment': False,
                                                                                                  'lifecycle_seconds': 90,
                                                                                                  'explicit_wait_seconds': 68,
                                                                                                  'bounded_reveal_calls': 0,
                                                                                                  'direct_action_count': 12,
                                                                                                  'direct_ax_assertion_count': 5,
                                                                                                  'typed_characters': 25,
                                                                                                  'unrounded_seconds': 234.25,
                                                                                                  'seconds': 240},
             'ProfileEditFlowTests.testSwipeDismissDiscardsOnlyLocalFieldScratch': {'source': 'Tests/AppUITests/ProfileEditFlowTests.swift',
                                                                                    'declaration_sha256': 'ad04bd32e5b7c3ec6394428d7da1ba36b52c76c5afd93334e3c432c34c970b6f',
                                                                                    'measured': False,
                                                                                    'existing_method_increment': False,
                                                                                    'lifecycle_seconds': 90,
                                                                                    'explicit_wait_seconds': 47,
                                                                                    'bounded_reveal_calls': 0,
                                                                                    'direct_action_count': 5,
                                                                                    'direct_ax_assertion_count': 3,
                                                                                    'typed_characters': 10,
                                                                                    'unrounded_seconds': 170.5,
                                                                                    'seconds': 180},
             'ProfileEditFlowTests.testBackgroundKeepsFieldScratchUntilExplicitCancel': {'source': 'Tests/AppUITests/ProfileEditFlowTests.swift',
                                                                                         'declaration_sha256': '37e3d99153a5d3635ea2cea0ab41b99b24fb51bb9185d2d31701633d5a704f13',
                                                                                         'measured': False,
                                                                                         'existing_method_increment': False,
                                                                                         'lifecycle_seconds': 90,
                                                                                         'explicit_wait_seconds': 47,
                                                                                         'bounded_reveal_calls': 0,
                                                                                         'direct_action_count': 7,
                                                                                         'direct_ax_assertion_count': 3,
                                                                                         'typed_characters': 9,
                                                                                         'unrounded_seconds': 180.25,
                                                                                         'seconds': 190},
             'MerchantTemplateParticipationPlanFlowTests.testIncompletePlanBlocksReviewAndRemovingItRestoresUnchangedTemplate': {'source': 'Tests/AppUITests/MerchantTemplateParticipationPlanFlowTests.swift',
                                                                                                                                 'declaration_sha256': 'aade52d00a8fba15356483e95d512e2a3cd6a616c2ee495e8f8a30a3899e2673',
                                                                                                                                 'measured': False,
                                                                                                                                 'existing_method_increment': False,
                                                                                                                                 'lifecycle_seconds': 90,
                                                                                                                                 'explicit_wait_seconds': 4,
                                                                                                                                 'bounded_reveal_calls': 5,
                                                                                                                                 'direct_action_count': 4,
                                                                                                                                 'direct_ax_assertion_count': 4,
                                                                                                                                 'typed_characters': 0,
                                                                                                                                 'unrounded_seconds': 322.0,
                                                                                                                                 'seconds': 330},
             'MerchantTemplateParticipationPlanFlowTests.testCompletePlanReviewCannotSubmitAndCancelRetainsLocalFields': {'source': 'Tests/AppUITests/MerchantTemplateParticipationPlanFlowTests.swift',
                                                                                                                          'declaration_sha256': '9413b591e0cab9096f42346d9b21a84722f14581fa2b29baa2aedec6c14290ff',
                                                                                                                          'measured': False,
                                                                                                                          'existing_method_increment': False,
                                                                                                                          'lifecycle_seconds': 90,
                                                                                                                          'explicit_wait_seconds': 4,
                                                                                                                          'bounded_reveal_calls': 11,
                                                                                                                          'direct_action_count': 13,
                                                                                                                          'direct_ax_assertion_count': 6,
                                                                                                                          'typed_characters': 3,
                                                                                                                          'unrounded_seconds': 611.75,
                                                                                                                          'seconds': 620},
             'MerchantTemplateExitPlanFlowTests.testEmptyExitPlanBlocksReviewAndExplicitRemovalLeavesOriginalTemplate': {'source': 'Tests/AppUITests/MerchantTemplateExitPlanFlowTests.swift',
                                                                                                                         'declaration_sha256': '2ef4229746d838c0603da3fc6f804b908cb5d268894ebf72863b83fcb1bca7f2',
                                                                                                                         'measured': False,
                                                                                                                         'existing_method_increment': False,
                                                                                                                         'lifecycle_seconds': 90,
                                                                                                                         'explicit_wait_seconds': 0,
                                                                                                                         'bounded_reveal_calls': 5,
                                                                                                                         'direct_action_count': 4,
                                                                                                                         'direct_ax_assertion_count': 4,
                                                                                                                         'typed_characters': 0,
                                                                                                                         'unrounded_seconds': 318.0,
                                                                                                                         'seconds': 320},
             'MerchantTemplateExitPlanFlowTests.testExitInstructionsReviewRemainsLocalAndCancelKeepsExactText': {'source': 'Tests/AppUITests/MerchantTemplateExitPlanFlowTests.swift',
                                                                                                                 'declaration_sha256': '3e18d10659b7183fe3742acccd32e009e341961df59a58e1eed85c0b74d36015',
                                                                                                                 'measured': False,
                                                                                                                 'existing_method_increment': False,
                                                                                                                 'lifecycle_seconds': 90,
                                                                                                                 'explicit_wait_seconds': 0,
                                                                                                                 'bounded_reveal_calls': 9,
                                                                                                                 'direct_action_count': 9,
                                                                                                                 'direct_ax_assertion_count': 5,
                                                                                                                 'typed_characters': 75,
                                                                                                                 'unrounded_seconds': 523.75,
                                                                                                                 'seconds': 530},
             'ProfileEditFlowTests.testFailedReloadKeepsDraftAndAllowsReviewedSave': {'source': 'Tests/AppUITests/ProfileEditFlowTests.swift',
                                                                                      'declaration_sha256': '4c5c16cafb45e2950d7a133d6469d01710b17e581d24c3851bbf6042cfdae4fb',
                                                                                      'measured': False,
                                                                                      'existing_method_increment': True,
                                                                                      'lifecycle_seconds': 0,
                                                                                      'explicit_wait_seconds': 11,
                                                                                      'bounded_reveal_calls': 0,
                                                                                      'direct_action_count': 2,
                                                                                      'direct_ax_assertion_count': 0,
                                                                                      'typed_characters': 0,
                                                                                      'unrounded_seconds': 21.0,
                                                                                      'seconds': 30},
             'ProfileEditFlowTests.testConfirmedProfileSaveIsReadBack': {'source': 'Tests/AppUITests/ProfileEditFlowTests.swift',
                                                                         'declaration_sha256': '16907fcf1e98d39835ea3c91148523936c39ab3b2b4544d7c6f6049223f972e3',
                                                                         'measured': False,
                                                                         'existing_method_increment': True,
                                                                         'lifecycle_seconds': 0,
                                                                         'explicit_wait_seconds': 11,
                                                                         'bounded_reveal_calls': 0,
                                                                         'direct_action_count': 2,
                                                                         'direct_ax_assertion_count': 0,
                                                                         'typed_characters': 0,
                                                                         'unrounded_seconds': 21.0,
                                                                         'seconds': 30},
             'ProfileEditFlowTests.testUnknownWriteLocksReviewAndOffersReadOnlyCheck': {'source': 'Tests/AppUITests/ProfileEditFlowTests.swift',
                                                                                        'declaration_sha256': 'e77675c888284be6947f798aa4bcfd60a35515f9ef86b67372b461f560142ca6',
                                                                                        'measured': False,
                                                                                        'existing_method_increment': True,
                                                                                        'lifecycle_seconds': 0,
                                                                                        'explicit_wait_seconds': 11,
                                                                                        'bounded_reveal_calls': 0,
                                                                                        'direct_action_count': 2,
                                                                                        'direct_ax_assertion_count': 0,
                                                                                        'typed_characters': 0,
                                                                                        'unrounded_seconds': 21.0,
                                                                                        'seconds': 30},
             'MerchantTemplateMetadataFlowTests.testExistingMetadataReviewAndSyntheticSaveReadsCanonicalFields': {'source': 'Tests/AppUITests/MerchantTemplateMetadataFlowTests.swift',
                                                                                                                  'declaration_sha256': '921c600bd18495a4950f1899e5eaabb6fc786484003ad42e6d022b828323d842',
                                                                                                                  'measured': False,
                                                                                                                  'existing_method_increment': False,
                                                                                                                  'lifecycle_seconds': 90,
                                                                                                                  'explicit_wait_seconds': 0,
                                                                                                                  'bounded_reveal_calls': 10,
                                                                                                                  'direct_action_count': 9,
                                                                                                                  'direct_ax_assertion_count': 4,
                                                                                                                  'typed_characters': 7,
                                                                                                                  'unrounded_seconds': 544.75,
                                                                                                                  'seconds': 550},
             'MerchantTemplateMetadataFlowTests.testOverflowCannotReviewOrSilentlyClampDuration': {'source': 'Tests/AppUITests/MerchantTemplateMetadataFlowTests.swift',
                                                                                                   'declaration_sha256': '384cf934be55a018b6ea090ec3180922b5a65f590a29649e967e3b886ea855cf',
                                                                                                   'measured': False,
                                                                                                   'existing_method_increment': False,
                                                                                                   'lifecycle_seconds': 90,
                                                                                                   'explicit_wait_seconds': 0,
                                                                                                   'bounded_reveal_calls': 5,
                                                                                                   'direct_action_count': 4,
                                                                                                   'direct_ax_assertion_count': 3,
                                                                                                   'typed_characters': 10,
                                                                                                   'unrounded_seconds': 318.5,
                                                                                                   'seconds': 320},
             'MerchantTemplatePreparationFlowTests.testVenueSelectionMaterialsReviewCancelAndSourceReadback': {'source': 'Tests/AppUITests/MerchantTemplatePreparationFlowTests.swift',
                                                                                                               'declaration_sha256': 'ef423818d39757818a7ef755212dd74c19b4b461ed3b01023d3adb93ed1cb7f4',
                                                                                                               'measured': False,
                                                                                                               'existing_method_increment': False,
                                                                                                               'lifecycle_seconds': 90,
                                                                                                               'explicit_wait_seconds': 0,
                                                                                                               'bounded_reveal_calls': 12,
                                                                                                               'direct_action_count': 11,
                                                                                                               'direct_ax_assertion_count': 6,
                                                                                                               'typed_characters': 15,
                                                                                                               'unrounded_seconds': 640.75,
                                                                                                               'seconds': 650},
             'MerchantTemplatePreparationFlowTests.testReloadRequiresExplicitDiscardAndDoesNotSavePreparationEdits': {'source': 'Tests/AppUITests/MerchantTemplatePreparationFlowTests.swift',
                                                                                                                      'declaration_sha256': 'b0e7802bbbba1b8992093bdf23f8d490db41dfc69d803c7895beb1cfcd4438a1',
                                                                                                                      'measured': False,
                                                                                                                      'existing_method_increment': False,
                                                                                                                      'lifecycle_seconds': 90,
                                                                                                                      'explicit_wait_seconds': 0,
                                                                                                                      'bounded_reveal_calls': 6,
                                                                                                                      'direct_action_count': 10,
                                                                                                                      'direct_ax_assertion_count': 4,
                                                                                                                      'typed_characters': 15,
                                                                                                                      'unrounded_seconds': 391.75,
                                                                                                                      'seconds': 400},
             'MerchantTemplateRuleStepsFlowTests.testAddRemoveReviewCancelAndAuthoritativeFixtureReadback': {'source': 'Tests/AppUITests/MerchantTemplateRuleStepsFlowTests.swift',
                                                                                                             'declaration_sha256': '5dfa36d22a27ff0f8c29355143c86f29c08a6380ec55afce169c76d7c2a873a8',
                                                                                                             'measured': False,
                                                                                                             'existing_method_increment': False,
                                                                                                             'lifecycle_seconds': 90,
                                                                                                             'explicit_wait_seconds': 0,
                                                                                                             'bounded_reveal_calls': 18,
                                                                                                             'direct_action_count': 16,
                                                                                                             'direct_ax_assertion_count': 5,
                                                                                                             'typed_characters': 40,
                                                                                                             'unrounded_seconds': 910.0,
                                                                                                             'seconds': 910},
             'MerchantTemplateRuleStepsFlowTests.testClearExistingRulesRequiresReviewAndDiscardRestoresSavedText': {'source': 'Tests/AppUITests/MerchantTemplateRuleStepsFlowTests.swift',
                                                                                                                    'declaration_sha256': '4d5445ca9d6f89bfb0491e5524e0c7d91254ed5362aadce8d741b719265a851a',
                                                                                                                    'measured': False,
                                                                                                                    'existing_method_increment': False,
                                                                                                                    'lifecycle_seconds': 90,
                                                                                                                    'explicit_wait_seconds': 0,
                                                                                                                    'bounded_reveal_calls': 19,
                                                                                                                    'direct_action_count': 18,
                                                                                                                    'direct_ax_assertion_count': 6,
                                                                                                                    'typed_characters': 39,
                                                                                                                    'unrounded_seconds': 961.75,
                                                                                                                    'seconds': 970},
             'ProfileCasePortfolioFlowTests.testCancelReopenThenStageDescriptionWithoutLosingOtherFields': {'source': 'Tests/AppUITests/ProfileCasePortfolioFlowTests.swift',
                                                                                                            'declaration_sha256': '7e1f7457e36c4704bd8e176b8735021a3fa58b39bdb37b518b272f35b1fa9e3c',
                                                                                                            'measured': False,
                                                                                                            'existing_method_increment': False,
                                                                                                            'lifecycle_seconds': 90,
                                                                                                            'explicit_wait_seconds': 30,
                                                                                                            'bounded_reveal_calls': 0,
                                                                                                            'direct_action_count': 8,
                                                                                                            'direct_ax_assertion_count': 3,
                                                                                                            'typed_characters': 17,
                                                                                                            'unrounded_seconds': 170.25,
                                                                                                            'seconds': 180},
             'ProfileCasePortfolioFlowTests.testCaseOnlyEditAppearsInWholeProfileReviewAndVerifiedReadback': {'source': 'Tests/AppUITests/ProfileCasePortfolioFlowTests.swift',
                                                                                                              'declaration_sha256': 'ffb5eb1e682b08a9c5fa6c251e03cc3b13139662ec91572630f7463986084207',
                                                                                                              'measured': False,
                                                                                                              'existing_method_increment': False,
                                                                                                              'lifecycle_seconds': 90,
                                                                                                              'explicit_wait_seconds': 35,
                                                                                                              'bounded_reveal_calls': 0,
                                                                                                              'direct_action_count': 7,
                                                                                                              'direct_ax_assertion_count': 2,
                                                                                                              'typed_characters': 8,
                                                                                                              'unrounded_seconds': 166.0,
                                                                                                              'seconds': 170},
             'ProfileCasePortfolioFlowTests.testEmptyPortfolioShowsExplicitEmptyStateWithoutUploadAction': {'source': 'Tests/AppUITests/ProfileCasePortfolioFlowTests.swift',
                                                                                                            'declaration_sha256': '4affed7b739b7cd5d73d126aa43c555bdae6edbc34c4b18343ccd5f2cc325f3d',
                                                                                                            'measured': False,
                                                                                                            'existing_method_increment': False,
                                                                                                            'lifecycle_seconds': 90,
                                                                                                            'explicit_wait_seconds': 20,
                                                                                                            'bounded_reveal_calls': 0,
                                                                                                            'direct_action_count': 1,
                                                                                                            'direct_ax_assertion_count': 2,
                                                                                                            'typed_characters': 0,
                                                                                                            'unrounded_seconds': 119.0,
                                                                                                            'seconds': 120},
             'ProfileCasePortfolioFlowTests.testExistingImageGalleryClosesBackToRetainedCaseScratch': {'source': 'Tests/AppUITests/ProfileCasePortfolioFlowTests.swift',
                                                                                                       'declaration_sha256': '9a0f028db381b740348bc331cd3580a15de531af80b61249b9c825770a523f70',
                                                                                                       'measured': False,
                                                                                                       'existing_method_increment': False,
                                                                                                       'lifecycle_seconds': 90,
                                                                                                       'explicit_wait_seconds': 45,
                                                                                                       'bounded_reveal_calls': 0,
                                                                                                       'direct_action_count': 9,
                                                                                                       'direct_ax_assertion_count': 4,
                                                                                                       'typed_characters': 9,
                                                                                                       'unrounded_seconds': 190.25,
                                                                                                       'seconds': 200},
             'ProfileContactQRRemovalFlowTests.testLocalRemovalCancelLeavesExistingQRCode': {'source': 'Tests/AppUITests/ProfileContactQRRemovalFlowTests.swift',
                                                                                             'declaration_sha256': 'ebc10c228c12a3c1741aa49c0432dccb7e02d5445dae10a86fc1919aeb1593cc',
                                                                                             'measured': False,
                                                                                             'existing_method_increment': False,
                                                                                             'lifecycle_seconds': 90,
                                                                                             'explicit_wait_seconds': 30,
                                                                                             'bounded_reveal_calls': 0,
                                                                                             'direct_action_count': 6,
                                                                                             'direct_ax_assertion_count': 3,
                                                                                             'typed_characters': 0,
                                                                                             'unrounded_seconds': 156.0,
                                                                                             'seconds': 160},
             'ProfileContactQRRemovalFlowTests.testStageReopenAndRestoreRemovalBeforeSaving': {'source': 'Tests/AppUITests/ProfileContactQRRemovalFlowTests.swift',
                                                                                               'declaration_sha256': 'e783e071fddb68f5561b0da1d49c65f69dc1ee16d47e2a3459a746f0eb3c2930',
                                                                                               'measured': False,
                                                                                               'existing_method_increment': False,
                                                                                               'lifecycle_seconds': 90,
                                                                                               'explicit_wait_seconds': 30,
                                                                                               'bounded_reveal_calls': 0,
                                                                                               'direct_action_count': 8,
                                                                                               'direct_ax_assertion_count': 3,
                                                                                               'typed_characters': 0,
                                                                                               'unrounded_seconds': 166.0,
                                                                                               'seconds': 170},
             'ProfileContactQRRemovalFlowTests.testRemovalIsReviewedAndSavedThroughExistingProfileFlow': {'source': 'Tests/AppUITests/ProfileContactQRRemovalFlowTests.swift',
                                                                                                          'declaration_sha256': 'e68651db6204bba8700af71e7e20e8cfd42767007c21cdbfe6597fd5b92547fd',
                                                                                                          'measured': False,
                                                                                                          'existing_method_increment': False,
                                                                                                          'lifecycle_seconds': 90,
                                                                                                          'explicit_wait_seconds': 45,
                                                                                                          'bounded_reveal_calls': 0,
                                                                                                          'direct_action_count': 9,
                                                                                                          'direct_ax_assertion_count': 3,
                                                                                                          'typed_characters': 0,
                                                                                                          'unrounded_seconds': 186.0,
                                                                                                          'seconds': 190},
             'ProfileContactQRRemovalFlowTests.testViewerEntryClosesWithoutChangingRemovalIntent': {'source': 'Tests/AppUITests/ProfileContactQRRemovalFlowTests.swift',
                                                                                                    'declaration_sha256': '9d6ab71a6d66fce54b1b1e707614aecdd6199403c5bdcbf5b116bba240fc0e8f',
                                                                                                    'measured': False,
                                                                                                    'existing_method_increment': False,
                                                                                                    'lifecycle_seconds': 90,
                                                                                                    'explicit_wait_seconds': 30,
                                                                                                    'bounded_reveal_calls': 0,
                                                                                                    'direct_action_count': 5,
                                                                                                    'direct_ax_assertion_count': 3,
                                                                                                    'typed_characters': 0,
                                                                                                    'unrounded_seconds': 151.0,
                                                                                                    'seconds': 160},
             'ProfileContactQRRemovalFlowTests.testSwipeDismissDoesNotStageLocalRemoval': {'source': 'Tests/AppUITests/ProfileContactQRRemovalFlowTests.swift',
                                                                                           'declaration_sha256': '3b37b2d4852dd060384685ef6d4abde6b58a8f4d224bd97c7252ae416735ac98',
                                                                                           'measured': False,
                                                                                           'existing_method_increment': False,
                                                                                           'lifecycle_seconds': 90,
                                                                                           'explicit_wait_seconds': 35,
                                                                                           'bounded_reveal_calls': 0,
                                                                                           'direct_action_count': 6,
                                                                                           'direct_ax_assertion_count': 1,
                                                                                           'typed_characters': 0,
                                                                                           'unrounded_seconds': 157.0,
                                                                                           'seconds': 160}},
 'class_increment_seconds': {'ProfileEditFlowTests': 890,
                             'MerchantTemplateParticipationPlanFlowTests': 950,
                             'MerchantTemplateExitPlanFlowTests': 850,
                             'MerchantTemplateMetadataFlowTests': 870,
                             'MerchantTemplatePreparationFlowTests': 1050,
                             'MerchantTemplateRuleStepsFlowTests': 1880,
                             'ProfileCasePortfolioFlowTests': 670,
                             'ProfileContactQRRemovalFlowTests': 840},
 'added_seconds': 8000,
 'prior_profile_class_seconds': 81.645}

def validate_product_ui_budget(c, directory, root):
    budget=c.get('product_ui_budget')
    if budget!=_PRODUCT_UI_BUDGET or budget['measured'] is not False:
        raise ValueError('Changed source-bound unmeasured product UI budget')
    for path,expected in budget['source_sha256'].items():
        if digest((Path(root)/path).read_bytes())!=expected:
            raise ValueError('Product UI budget source changed: '+path)
    totals={}
    for identity,row in budget['methods'].items():
        text=(Path(root)/row['source']).read_text();name=identity.split('.')[1]
        match=re.search(r'(?m)^    func '+re.escape(name)+r'\b[\s\S]*?^    }',text)
        if match is None or digest(match.group().encode())!=row['declaration_sha256']:
            raise ValueError('Product complete UI method changed: '+identity)
        seconds=row['lifecycle_seconds']+row['explicit_wait_seconds']+40*row['bounded_reveal_calls']+5*row['direct_action_count']+2*row['direct_ax_assertion_count']+0.25*row['typed_characters']
        if row['measured'] is not False or seconds!=row['unrounded_seconds'] or math.ceil(seconds/10)*10!=row['seconds'] or not 0<row['seconds']<=900:
            raise ValueError('Product UI action/wait allowance changed')
        cls=identity.split('.')[0];totals[cls]=totals.get(cls,0)+row['seconds']
    if totals!=budget['class_increment_seconds'] or sum(totals.values())!=budget['added_seconds']:
        raise ValueError('Product UI full-class/increment accounting differs')
    return totals

atexit.register(lambda: [life.cleanup() for life in _lives])

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    payload = json.dumps(report(), indent=2) + '\n'
    if args.output:
        args.output.write_text(payload)
    else:
        print(payload, end='')

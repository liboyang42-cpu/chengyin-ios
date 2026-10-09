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
import math
import re
import tempfile

ROOT = Path(__file__).resolve().parents[1]
# Bind the validator bytes loaded for this process, including its contract pin.
IMPLEMENTATION_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
CONTRACT_SHA256 = 'b1c9624ab9e9d9e654c38e7a7e54c2a4128a5843b9c95bb2e978bbc90a2a3486'
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


def contract(root=ROOT):
    raw = (Path(root) / 'tools/run138_editor_readiness_contract.json').read_bytes()
    if digest(raw) != CONTRACT_SHA256:
        raise ValueError('Unreviewed current readiness planning contract')
    return json.loads(raw)


def source_contract(root=ROOT):
    raw = (Path(root) / SOURCE_CONTRACT).read_bytes()
    if digest(raw) != contract(root)['source_contract_sha256']:
        raise ValueError('Changed exact readiness source contract')
    return json.loads(raw)


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
    return {'tools/run138_editor_readiness.py'} | set(c['followon_support_sha256']) | set(followons().availability().contract()['scope']) | set(followons().availability().contract()['unchanged_dependencies'])


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
    if (len(keys) != 736 or len(classes) != 163
            or canonical(keys) != c['current_inventory_sha256']):
        raise ValueError('Current 736 complete methods are not preserved')
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
            or c['added_total_seconds'] != 523.948 or c['deadline_seconds'] != 1800
            or c['startup_reserve_seconds'] != 300 or c['shard_count'] != 79):
        raise ValueError('Exception scope, added work, reserve or deadline changed')
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
    if ({name: result[name] for name in c['candidate_class_seconds']} != c['candidate_class_seconds']
            or not math.isclose(sum(result.values()) - sum(before.values()), 523.948, abs_tol=1e-7)):
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
            'method_count': 736, 'class_count': len(costs), 'shard_count': 79,
            'candidate_class_seconds': c['candidate_class_seconds'],
            'added_total_seconds': 523.948, 'total_seconds': sum(costs.values()),
            'maximum_shard_seconds': max(loads), 'maximum_with_startup_reserve_seconds': max(loads) + 300,
            'deadline_seconds': 1800, 'startup_reserve_seconds': 300,
            'shards': [{'index': index, 'classes': group, 'seconds': loads[index]} for index, group in enumerate(groups)]}


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

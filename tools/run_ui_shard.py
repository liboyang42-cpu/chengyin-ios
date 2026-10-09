#!/usr/bin/env python3
"""Run every discovered XCTestCase exactly once across deterministic class-level shards."""
import argparse
import pathlib
import re
import subprocess
import os
import signal
import json
import math
import hashlib
try:
    from ui_failure_evidence import EvidenceStream
except ModuleNotFoundError:
    from tools.ui_failure_evidence import EvidenceStream

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_SHARD_COUNT = 79
PLAYER_MAP_HISTORY_CONTRACT_PATH = ROOT / 'tools/player_map_history_planning_contract.json'
PLAYER_MAP_HISTORY_CONTRACT_SHA256 = '233f2dad8e06d49e10fcb9af868221979c3ead3b7a2bf987d9a567bdfe7faa67'
STORY_TEMPLATE_CONTRACT_PATH = ROOT / 'tools/story_template_planning_contract.json'
STORY_TEMPLATE_CONTRACT_SHA256 = '2c41a3053421739836bf545888444741146f4f2f91e589b6a8469e6d46311d74'
CLUB_PARITY_CONTRACT_PATH = ROOT / 'tools/club_parity_planning_contract.json'
CLUB_PARITY_CONTRACT_SHA256 = 'fc3334bb2f98ae1668cb7cd2a0e6dbb5a74bfa189f9c9d887cc509f8859617a7'

def discover(directory):
    weights = {}
    for path in sorted(pathlib.Path(directory).glob('*.swift')):
        source = path.read_text()
        methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
        if not methods:
            continue
        cases = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)
        if len(cases) != 1:
            raise ValueError(f'{path.name}: keep one XCTestCase per test file; refusing incomplete inventory')
        name = cases[0]
        if name in weights or len(methods) != len(set(methods)):
            raise ValueError(f'{path.name}: duplicate class or test method')
        weights[name] = len(methods)
    if not weights:
        raise ValueError('No UI tests discovered')
    return weights

def measured_weights(directory, profile):
    """Observed/declared estimated costs affect grouping only; source defines every case."""
    try:
        from run138_current_source_projection import current_weights
    except ModuleNotFoundError:
        from tools.run138_current_source_projection import current_weights
    current = current_weights(directory, profile)
    if current is not None:
        return current
    try:
        from branch_history_handshake_planning import weights as handshake_weights
    except ModuleNotFoundError:
        from tools.branch_history_handshake_planning import weights as handshake_weights
    handshake = handshake_weights(directory, profile)
    if handshake is not None:
        return handshake
    try:
        from run130_receipt_planning import weights as receipt_weights
    except ModuleNotFoundError:
        from tools.run130_receipt_planning import weights as receipt_weights
    receipt = receipt_weights(directory, profile)
    if receipt is not None:
        return receipt
    try:
        from run130_prepared_readiness import weights as prepared_readiness_weights
    except ModuleNotFoundError:
        from tools.run130_prepared_readiness import weights as prepared_readiness_weights
    prepared = prepared_readiness_weights(directory, profile)
    if prepared is not None:
        return prepared
    try:
        from run129_late_readiness import weights as late_readiness_weights
    except ModuleNotFoundError:
        from tools.run129_late_readiness import weights as late_readiness_weights
    late = late_readiness_weights(directory, profile)
    if late is not None:
        return late
    try:
        from run129_repair_planning import repair_weights
    except ModuleNotFoundError:
        from tools.run129_repair_planning import repair_weights
    repair = repair_weights(directory, profile)
    if repair is not None:
        return repair
    counts = discover(directory)
    data = json.loads(pathlib.Path(profile).read_text())
    if data.get('version') != 1 or not isinstance(data.get('method_seconds'), dict):
        raise ValueError('Invalid UI duration profile')
    default = data.get('unobserved_method_seconds')
    timings = data['method_seconds']
    estimates = data.get('estimated_method_seconds', {})
    floors = data.get('method_planning_floors', {})
    if not isinstance(floors, dict):
        raise ValueError('Invalid source-bound method planning floors')
    if not isinstance(estimates, dict):
        raise ValueError('Invalid estimated UI duration profile')
    def valid(value):
        return type(value) in (int, float) and math.isfinite(value) and 0 < value <= 900
    if not valid(default) or any(not re.fullmatch(r'[A-Za-z_]\w*\.test\w+', name) or not valid(seconds)
                                 for name, seconds in list(timings.items()) + list(estimates.items())):
        raise ValueError('Invalid UI duration or method identity')
    result = {}
    current_sources = {}
    for path in sorted(pathlib.Path(directory).glob('*.swift')):
        source = path.read_text()
        methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', source)
        if not methods:
            continue
        name = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', source)[0]
        for method in methods:
            current_sources[name + '.' + method] = (path, source)
        result[name] = sum(timings.get(name + '.' + method, estimates.get(name + '.' + method, default)) for method in methods)
    club_floors = _source_required_club_floors(directory, counts, current_sources)
    story_floors = _source_required_story_floors(directory, counts, current_sources)
    player_floors = _source_required_player_map_history_floors(directory, counts, current_sources)
    trusted_floors = {**club_floors, **story_floors, **player_floors}
    for key, row in floors.items():
        if (key not in current_sources or not isinstance(row, dict)
                or row.get('measured') is not False or not valid(row.get('seconds'))):
            raise ValueError('Invalid or undiscovered source-bound planning floor')
        _validate_current_method_source(key, row, current_sources)
    # Both custom floors and immutable source-required floors can only raise
    # effective planning. Keep every observation/estimate in the supplied data.
    # Apply each method exactly once, including future observations below a floor.
    for key in set(floors) | set(trusted_floors):
        prior = timings.get(key, estimates.get(key, default))
        required = trusted_floors.get(key, {}).get('seconds', 0)
        declared = floors.get(key, {}).get('seconds', 0)
        result[key.split('.')[0]] += max(prior, required, declared) - prior
    plan = data.get('planning_budget', {}).get('reviewed_club_parity_replan')
    marker = 'parentApprovedClubParityWholeMethodPlanning20261006'
    provenance = data.get('estimate_provenance', {}).get('methods', [])
    if plan is None and (any(row.get('source') == marker for row in provenance)
                         or any(row.get('source') == marker for row in floors.values())):
        raise ValueError('Missing current club whole-method plan')
    if plan is not None:
        # A claimed current plan must retain every independently required floor;
        # deleting its self-reported list cannot erase the source requirement.
        if any(plan.get('whole_method_estimates', {}).get(key) != row['seconds']
               for key, row in club_floors.items()):
            raise ValueError('Current plan omits or changes a source-required floor')
        if set(plan['current_inventory']) != set(current_sources) - set(story_floors) - set(player_floors):
            raise ValueError('Current club plan does not cover exact live inventory')
        records = {row['method']: row for row in provenance}
        for key, seconds in plan['whole_method_estimates'].items():
            row = floors.get(key, records.get(key))
            if row is None or row.get('seconds') != seconds:
                raise ValueError('Missing or changed complete-method planning allowance')
            _validate_current_method_source(key, row, current_sources)
            if key not in timings and estimates.get(key, 0) < seconds:
                raise ValueError('Claimed current plan lacks its declared method estimate')
            effective = max(timings.get(key, estimates.get(key, default)),
                            floors.get(key, {}).get('seconds', 0),
                            trusted_floors.get(key, {}).get('seconds', 0))
            if effective < seconds:
                raise ValueError('Whole-method planning allowance cannot fall back or be shadowed')
    story_plan = data.get('planning_budget', {}).get('reviewed_story_template_replan')
    story_marker = 'storyTemplateWholeMethodCandidate20261007'
    if story_plan is None and any(row.get('source') == story_marker for row in provenance):
        raise ValueError('Missing current story-template whole-method plan')
    if story_plan is not None:
        inventory = story_plan.get('current_inventory')
        story_inventory = sorted(set(current_sources) - set(player_floors))
        if not story_floors or inventory != story_inventory:
            raise ValueError('Current story-template plan does not cover exact live inventory')
        expected_inventory_hash = hashlib.sha256('\n'.join(inventory).encode()).hexdigest()
        if (story_plan.get('current_inventory_sha256') != expected_inventory_hash
                or story_plan.get('method_count') != len(story_inventory)
                or story_plan.get('class_count') != len({key.split('.')[0] for key in story_inventory})
                or story_plan.get('new_methods') != sorted(story_floors)):
            raise ValueError('Current story-template inventory identity is inconsistent')
        if story_plan.get('whole_method_estimates') != {key: row['seconds'] for key, row in story_floors.items()}:
            raise ValueError('Current story-template plan omits or changes source-required floors')
        records = {row['method']: row for row in provenance}
        for key, floor in story_floors.items():
            row = records.get(key)
            if (row is None or row.get('seconds') != floor['seconds'] or row.get('measured') is not False
                    or row.get('shared_helper_source_sha256') != floor['shared_helper_source_sha256']):
                raise ValueError('Missing complete story-template method provenance')
            _validate_current_method_source(key, row, current_sources)
            if estimates.get(key) != floor['seconds']:
                raise ValueError('Claimed current story-template plan lacks exact method estimate')
    player_plan = data.get('planning_budget', {}).get('reviewed_player_map_history_replan')
    marker = 'playerRouteHistoryWholeMethodReview20261007'
    if player_plan is None and any(row.get('source') == marker for row in provenance):
        raise ValueError('Missing current player map/history whole-method plan')
    if player_plan is not None:
        inventory = sorted(current_sources)
        if (not player_floors or player_plan.get('current_inventory') != inventory
                or player_plan.get('current_inventory_sha256') != hashlib.sha256('\n'.join(inventory).encode()).hexdigest()
                or player_plan.get('method_count') != len(inventory)
                or player_plan.get('class_count') != len(counts)
                or player_plan.get('new_methods') != sorted(player_floors)
                or player_plan.get('whole_method_estimates') != {key: row['seconds'] for key, row in player_floors.items()}
                or player_plan.get('complete_method_derivations') != list(player_floors.values())
                or player_plan.get('source') != marker
                or player_plan.get('deadline_seconds') != 1800
                or player_plan.get('startup_reserve_seconds') != 300
                or player_plan.get('complete_method_limit_seconds') != 900):
            raise ValueError('Current player map/history inventory or costs are inconsistent')
        records = {row['method']: row for row in provenance}
        for key, required in player_floors.items():
            row = records.get(key)
            if (row != required or row.get('seconds') != required['seconds'] or row.get('measured') is not False
                    or row.get('shared_helper_source_sha256') != required['shared_helper_source_sha256']
                    or estimates.get(key) != required['seconds']):
                raise ValueError('Missing complete player map/history provenance or estimate')
            _validate_current_method_source(key, row, current_sources)
    assert set(result) == set(counts)
    return result




def _source_required_player_map_history_floors(directory, counts, sources):
    directory = pathlib.Path(directory)
    relevant = (directory.resolve() == (ROOT / 'Tests/AppUITests').resolve()
                or any(name.startswith(('PlayRouteMap', 'PlayBranchHistory')) for name in counts)
                or any(directory.glob('PlayRouteMap*.swift')) or any(directory.glob('PlayBranchHistory*.swift')))
    relevant = relevant or any(any(marker in path.read_text() for marker in ('playRoute.', 'playRouteCamera.', 'branchHistory.', '--branch-history-scenario')) for path in directory.glob('*.swift'))
    try:
        encoded = PLAYER_MAP_HISTORY_CONTRACT_PATH.read_bytes()
    except OSError as error:
        raise ValueError('Required player map/history planning contract is missing') from error
    if hashlib.sha256(encoded).hexdigest() != PLAYER_MAP_HISTORY_CONTRACT_SHA256:
        raise ValueError('Player map/history planning contract hash mismatch')
    contract = json.loads(encoded)
    historical = set(contract['historical_inventory'])
    relevant = relevant or historical < set(sources)
    if not relevant:
        if set(sources) == historical:
            for row in contract['historical_ui_sources']:
                path = directory / pathlib.Path(row['path']).name
                if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != row['sha256']:
                    raise ValueError('Claimed historical player-map absence does not match exact old UI bytes')
        return {}
    for key, row in contract['required_floors'].items():
        _validate_current_method_source(key, row, sources)
    return contract['required_floors']


def _source_required_story_floors(directory, counts, sources):
    """A protected class, method, helper or the live directory requires every floor."""
    directory = pathlib.Path(directory)
    has_source = (directory.resolve() == (ROOT / 'Tests/AppUITests').resolve()
                  or any(name.startswith('ProjectStoryTemplate') for name in counts)
                  or any(key.split('.')[1].endswith('GapPreviewCancelApplySaveAndRestore') for key in sources)
                  or any(directory.glob('ProjectStoryTemplate*.swift')))
    # Semantic markers also protect copied/renamed wrappers. A complete known
    # historical inventory plus any extra methods is a current extension, not
    # a historical-source exemption, even when all six identities are renamed.
    has_source = has_source or any(
        'projectStoryTemplate.' in path.read_text() or '--project-story-template' in path.read_text()
        for path in directory.glob('*.swift'))
    try:
        encoded = STORY_TEMPLATE_CONTRACT_PATH.read_bytes()
    except OSError as error:
        raise ValueError('Required trusted story-template planning contract is missing') from error
    if hashlib.sha256(encoded).hexdigest() != STORY_TEMPLATE_CONTRACT_SHA256:
        raise ValueError('Trusted story-template planning contract hash mismatch')
    contract = json.loads(encoded)
    historical = set(contract['historical_inventory'])
    has_source = has_source or (historical < set(sources))
    if not has_source:
        return {}
    for key, row in contract['required_floors'].items():
        _validate_current_method_source(key, row, sources)
    return contract['required_floors']


def _source_required_club_floors(directory, counts, sources):
    """Source identity, never profile-provided keys, selects mandatory floors."""
    protected_names = {
        'testAdminProfileHasNoOwnerSettingsOrRoleActions',
        'testAdminDisplayOnlyReviewCancelsThenSavesOnce',
        'testOwnerProfileReviewRetainsOperatingFields',
    }
    relevant = (pathlib.Path(directory).resolve() == (ROOT / 'Tests/AppUITests').resolve()
                or bool({'ClubOperationsFlowTests', 'ClubProfileScopeFlowTests'} & set(counts))
                or any(key.split('.')[1] in protected_names for key in sources))
    if not relevant:
        return {}
    try:
        encoded = CLUB_PARITY_CONTRACT_PATH.read_bytes()
    except OSError as error:
        raise ValueError('Required trusted club planning contract is missing') from error
    if hashlib.sha256(encoded).hexdigest() != CLUB_PARITY_CONTRACT_SHA256:
        raise ValueError('Trusted club planning contract hash mismatch')
    contract = json.loads(encoded)
    historical = contract['historical_source']
    old_source = sources.get(historical['method'])
    new_names = protected_names - {historical['method'].split('.')[1]}
    has_new = (contract['current_class'] in counts
               or any(key.split('.')[1] in new_names for key in sources))
    if (not has_new and old_source is not None
            and hashlib.sha256(old_source[0].read_bytes()).hexdigest() == historical['file_sha256']):
        # Historical projections retain exact old source, not merely fewer tests.
        return {}
    required = contract['required_floors']
    for key, row in required.items():
        _validate_current_method_source(key, row, sources)
    return required


def _validate_current_method_source(key, row, sources):
    """Bind a changed-source allowance to its complete declaration and helpers."""
    if key not in sources:
        raise ValueError('Planning allowance has no current source method')
    path, source = sources[key]
    declaration = re.findall(r'(?m)^    (func ' + re.escape(key.split('.')[1]) + r'\b[\s\S]*?^    })', source)
    non_test = re.sub(r'(?m)^    (func (test\w+)\b[\s\S]*?^    })', '', source)
    non_test = non_test.replace('final class ClubProfileScopeFlowTests: XCTestCase',
                                'final class ClubOperationsFlowTests: XCTestCase')
    non_test = re.sub(r'(?m)^[ \t]*\n', '', non_test)
    expected = {'test_file_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'declaration_sha256': hashlib.sha256(declaration[0].encode()).hexdigest() if len(declaration) == 1 else None,
                'all_non_test_source_sha256': hashlib.sha256(non_test.encode()).hexdigest()}
    if any(row.get(field) != value or value is None for field, value in expected.items()):
        raise ValueError('Planning allowance does not bind exact current method and helpers')
    for relative, expected_hash in row.get('shared_helper_source_sha256', {}).items():
        helper = path.parent / pathlib.Path(relative).name
        try:
            encoded = helper.read_bytes()
        except OSError as error:
            raise ValueError('Planning allowance shared helper is missing') from error
        if hashlib.sha256(encoded).hexdigest() != expected_hash:
            raise ValueError('Planning allowance does not bind exact shared helper source')


def partition(weights, count):
    if count < 1 or count > len(weights):
        raise ValueError('Shard count must be between one and the number of test classes')
    groups = [[] for _ in range(count)]
    totals = [0] * count
    for name, weight in sorted(weights.items(), key=lambda item: (-item[1], item[0])):
        target = min(range(count), key=lambda index: (totals[index], index))
        groups[target].append(name)
        totals[target] += weight
    flat = [name for group in groups for name in group]
    assert len(flat) == len(set(flat)) and set(flat) == set(weights)
    return groups

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--shard', type=int, required=True)
    parser.add_argument('--count', type=int, default=DEFAULT_SHARD_COUNT)
    parser.add_argument('--simulator')
    parser.add_argument('--derived-data')
    parser.add_argument('--result-bundle')
    parser.add_argument('--xctestrun')
    parser.add_argument('--deadline-seconds', type=int)
    parser.add_argument('--evidence-directory', type=pathlib.Path)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--duration-profile', type=pathlib.Path, default=ROOT/'tools/ui_duration_weights.json')
    args = parser.parse_args()
    weights = discover(ROOT / 'Tests/AppUITests')
    costs = measured_weights(ROOT / 'Tests/AppUITests', args.duration_profile)
    groups = partition(costs, args.count)
    if not 0 <= args.shard < args.count:
        parser.error('shard index out of range')
    selected = groups[args.shard]
    print(f'Inventory: {sum(weights.values())} tests in {len(weights)} classes; shard {args.shard}: '
          f'{sum(weights[name] for name in selected)} tests, estimated {sum(costs[name] for name in selected):.1f}s in {selected}', flush=True)
    if args.dry_run:
        return 0
    if not all([args.simulator, args.result_bundle]) or not (args.xctestrun or args.derived_data):
        parser.error('simulator, result-bundle and xctestrun or derived-data are required')
    if args.deadline_seconds is not None and args.deadline_seconds < 1:
        parser.error('deadline-seconds must be positive')
    if args.xctestrun:
        if not pathlib.Path(args.xctestrun).is_file():
            parser.error('Verified xctestrun is missing; refusing an implicit rebuild')
        command = ['xcodebuild', '-xctestrun', args.xctestrun]
        action = 'test-without-building'
    else:
        command = ['xcodebuild', '-project', 'Questify.xcodeproj', '-scheme', 'Questify',
                   '-configuration', 'Debug', '-derivedDataPath', args.derived_data]
        action = 'test'
    command += ['-destination', f'platform=iOS Simulator,id={args.simulator}',
               '-resultBundlePath', args.result_bundle,
               '-parallel-testing-enabled', 'NO']
    command += [f'-only-testing:QuestifyUITests/{name}' for name in selected]
    command += ['CODE_SIGNING_ALLOWED=NO', action]
    try:
        evidence = EvidenceStream(args.evidence_directory) if args.evidence_directory else None
    except (OSError, ValueError):
        print('UI evidence directory unavailable; continuing authoritative test execution', flush=True)
        evidence = None
    process = subprocess.Popen(command, cwd=ROOT, start_new_session=True,
                               **({'stdout': subprocess.PIPE, 'stderr': subprocess.STDOUT} if evidence else {}))
    if evidence:
        evidence.start(process.stdout)
    try:
        code = process.wait(timeout=args.deadline_seconds)
        if evidence:
            evidence.finish(code)
        return code
    except subprocess.TimeoutExpired:
        # Give xcodebuild time to finalize partial results before the job limit.
        # A partial run always fails, even if its graceful interrupt returns zero.
        print('UI shard deadline reached: incomplete, never passed; requesting result finalization', flush=True)
        process.send_signal(signal.SIGINT)
        try:
            process.wait(timeout=60)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        if evidence:
            evidence.finish(124)
        return 124

if __name__ == '__main__':
    raise SystemExit(main())

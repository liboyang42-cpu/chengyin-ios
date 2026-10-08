"""Three reviewed late run129 helper changes over exact, retained 30cd evidence.

Current bytes are validated before any historical projection. No historical floor
is lowered. Successful method timing observations are not consumed by this layer.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re
import tempfile
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'tools/tests/fixtures/run129_late_readiness'
PLAN = 'reviewed_run129_late_readiness'
CONTRACT_SHA256 = '4028598b554aa20d4a57a60320533eb53497edabf27e7df789ed1dd368363bd8'
PATTERN = r'(?m)^    (func (test\w+)\b[\s\S]*?^    })'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return digest(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def contract():
    raw = (ROOT / 'tools/run129_late_readiness_contract.json').read_bytes()
    if digest(raw) != CONTRACT_SHA256:
        raise ValueError('Unreviewed late readiness contract')
    return json.loads(raw)


def previous_profile(profile):
    try:
        from run130_prepared_readiness import previous_profile as before_prepared
    except ModuleNotFoundError:
        from tools.run130_prepared_readiness import previous_profile as before_prepared
    result = before_prepared(profile)
    if PLAN not in result.get('planning_budget', {}):
        return result
    c = contract()
    if canonical(result) != c['current_profile_canonical_sha256']:
        raise ValueError('Changed late readiness profile')
    result['planning_budget'].pop(PLAN)
    if canonical(result) != c['previous_profile_canonical_sha256']:
        raise ValueError('Previous repair evidence did not restore exactly')
    return result


def previous_source(path):
    """Accept only the exact before/after bytes of the three reviewed files."""
    try:
        from run130_prepared_readiness import previous_source as before_prepared_source
    except ModuleNotFoundError:
        from tools.run130_prepared_readiness import previous_source as before_prepared_source
    path = before_prepared_source(path)
    if path.parent.name != 'AppUITests':
        return path
    for row in contract()['required_floors'].values():
        if path.name != Path(row['path']).name:
            continue
        actual = digest(path.read_bytes())
        if actual == row['before_file_sha256']:
            return path
        if actual != row['file_sha256']:
            raise ValueError('Unknown late UI source cannot project to history')
        before = FIXTURES / path.name
        if digest(before.read_bytes()) != row['before_file_sha256']:
            raise ValueError('Changed late readiness preimage')
        return before
    return path


def validate_current(directory):
    directory = Path(directory)
    c = contract()
    actual = {'Tests/AppUITests/' + p.name: {'sha256': digest(p.read_bytes())}
              for p in directory.glob('*.swift')}
    if actual != c['current_ui_sources']:
        raise ValueError('Incomplete or changed current late readiness UI inventory')
    for key, row in c['required_floors'].items():
        text = (directory / Path(row['path']).name).read_text()
        methods = {name: body for body, name in re.findall(PATTERN, text)}
        non = re.sub(r'(?m)^[ \t]*\n', '', re.sub(PATTERN, '', text))
        if (digest(methods[key.split('.')[1]].encode()) != row['declaration_sha256']
                or digest(non.encode()) != row['all_non_test_source_sha256']):
            raise ValueError('Unbound late method or helper')
        if not row['historical_seconds'] <= row['seconds'] <= 900 or row['measured'] is not False:
            raise ValueError('Invalid late whole-method allowance')
    return c


def materialize_previous_ui(directory, current_directory):
    try:
        from run130_prepared_readiness import previous_directory as before_prepared_directory
    except ModuleNotFoundError:
        from tools.run130_prepared_readiness import previous_directory as before_prepared_directory
    current_directory = before_prepared_directory(current_directory)
    validate_current(current_directory)
    target = Path(directory); target.mkdir(parents=True, exist_ok=True)
    for p in current_directory.glob('*.swift'):
        (target / p.name).write_bytes(previous_source(p).read_bytes())
    return target


def weights(directory, profile_path):
    directory = Path(directory)
    profile = json.loads(Path(profile_path).read_text())
    c = contract()
    current = directory.resolve() == (ROOT / 'Tests/AppUITests').resolve()
    if PLAN not in profile.get('planning_budget', {}):
        # Exact old inventories and small synthetic fixtures still use their old
        # runner. Missing a plan may never hide current changed source bytes.
        for row in c['required_floors'].values():
            p = directory / Path(row['path']).name
            if p.exists() and digest(p.read_bytes()) != row['before_file_sha256']:
                raise ValueError('Changed late readiness sources require their plan')
        if current:
            raise ValueError('Current late readiness source requires its plan')
        return None
    validate_current(directory)
    prior = previous_profile(profile)
    try:
        from run129_repair_planning import repair_weights
    except ModuleNotFoundError:
        from tools.run129_repair_planning import repair_weights
    with tempfile.TemporaryDirectory(prefix='late-readiness-cost-') as d:
        root = Path(d)
        ui = materialize_previous_ui(root/'Tests/AppUITests', directory)
        p = root/'profile.json'; p.write_text(json.dumps(prior))
        retained = repair_weights(ui, p)
    result = dict(retained)
    for key, row in c['required_floors'].items():
        name = key.split('.')[0]
        # These exact files contain one complete test each, checked by source hash.
        if result[name] != row['historical_seconds']:
            raise ValueError('Previous whole-method cost changed')
        result[name] = row['seconds']
    return result


def frozen_repair_context():
    """Existing 15 repair-budget tests retain exact assertions and old inputs."""
    lifetime = tempfile.TemporaryDirectory(prefix='frozen-30cd-repair-')
    root = Path(lifetime.name)
    materialize_previous_ui(root/'Tests/AppUITests', ROOT/'Tests/AppUITests')
    profile = previous_profile(json.loads((ROOT/'tools/ui_duration_weights.json').read_text()))
    for rel in ['tools/run129_repair_planning_contract.json', 'docs/run129-repair-integration-budget.json']:
        p = root/rel; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes((ROOT/rel).read_bytes())
    (root/'tools/ui_duration_weights.json').write_text(json.dumps(profile))
    raw = (FIXTURES/'ui-shard-inventory.json').read_bytes()
    if digest(raw) != contract()['previous_ui_inventory_sha256']:
        raise ValueError('Changed previous shard inventory')
    (root/'docs/ui-shard-inventory.json').write_bytes(raw)
    return SimpleNamespace(root=root, lifetime=lifetime)

"""Exact reviewed presentation-handshake layer over the passing receipt budget.

Historical projections validate complete current bytes and remove only the five
reviewed UI lines. No failed run is converted into a timing observation or floor.
"""
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace
import atexit
import hashlib
import json
import re
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PLAN = 'reviewed_branch_history_presentation_handshake'
CONTRACT_SHA256 = '5f3e5d8bcddb6c84ec64dd7d4b3e8d1ed2fa1946c60906eb7c5e74aed355b586'
NAME = 'PlayBranchHistoryLifetimeFlowTests.swift'
METHOD = 'PlayBranchHistoryLifetimeFlowTests.testRefreshAndAccountSwitchWhilePresentedRemoveOldSheetAndRows'
LINEAR = 'PlayBranchHistoryLifetimeFlowTests.testLinearSummaryHasNoHistoryEntryBeforeOrAfterRefresh'
PATTERN = r'(?m)^    (func (test\w+)\b[\s\S]*?^    })'
_lives = []


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return digest(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def contract():
    raw = (ROOT / 'tools/branch_history_handshake_planning_contract.json').read_bytes()
    if digest(raw) != CONTRACT_SHA256:
        raise ValueError('Unreviewed handshake planning contract')
    return json.loads(raw)


def previous_profile(profile):
    result = deepcopy(profile)
    if PLAN not in result.get('planning_budget', {}):
        return result
    c = contract()
    if canonical(result) != c['current_profile_canonical_sha256']:
        raise ValueError('Changed current handshake profile')
    result['planning_budget'].pop(PLAN)
    if canonical(result) != c['previous_profile_canonical_sha256']:
        raise ValueError('Original receipt profile was not restored exactly')
    return result


def original_source(raw):
    c = contract()
    if digest(raw) != c['after_file_sha256']:
        raise ValueError('Unknown current handshake source')
    current = raw.decode()
    if current.count(c['added_exact_lines']) != 1:
        raise ValueError('Missing or duplicated exact handshake inverse')
    old = current.replace(c['added_exact_lines'], '', 1).encode()
    if digest(old) != c['before_file_sha256']:
        raise ValueError('Original handshake source was not restored exactly')
    return old


def _temporary(prefix):
    lifetime = tempfile.TemporaryDirectory(prefix=prefix)
    _lives.append(lifetime)
    return lifetime, Path(lifetime.name)


def previous_source(path):
    try:
        from run138_current_source_projection import previous_source as before_current
    except ModuleNotFoundError:
        from tools.run138_current_source_projection import previous_source as before_current
    p = before_current(Path(path))
    if p.parent.name != 'AppUITests' or p.name != NAME:
        return p
    raw = p.read_bytes()
    if digest(raw) == contract()['before_file_sha256']:
        return p
    old = original_source(raw)
    _, root = _temporary('handshake-prior-source-')
    destination = root / 'AppUITests' / NAME
    destination.parent.mkdir()
    destination.write_bytes(old)
    return destination


def critical_source_bytes(path):
    """Keep old critical comparisons; admit only the exact reviewed byte inverse."""
    raw = (ROOT / path).read_bytes()
    adapter = ROOT / 'tools/branch_history_fixture_lifetime_projection.py'
    if not adapter.is_file():
        # A genuine historical checkout has no lifetime-adapter artifacts. Its
        # raw bytes still have to pass every original critical_sources hash.
        if any((ROOT / marker).exists() for marker in [
            'tools/branch_history_fixture_lifetime_projection_contract.json',
            'tools/tests/test_branch_history_fixture_lifetime_projection.py',
            'tools/tests/fixtures/branch_history_fixture_lifetime',
            'Tests/ContractChecks/test_branch_history_fixture_lifetime.py',
            'docs/branch-history-fixture-lifetime.md',
        ]):
            raise ValueError('Incomplete branch-history lifetime projection')
        return raw
    if digest(adapter.read_bytes()) != 'c2d62e292abf65bc7189b52d3937c4b67fa11710edecd852b4b302d92d636ed9':
        raise ValueError('Changed branch-history lifetime projection adapter')
    try:
        from branch_history_fixture_lifetime_projection import historical_source
    except ModuleNotFoundError:
        from tools.branch_history_fixture_lifetime_projection import historical_source
    return historical_source(ROOT, path)


def validate_current(directory):
    try:
        from run138_current_source_projection import previous_directory as before_current
    except ModuleNotFoundError:
        from tools.run138_current_source_projection import previous_directory as before_current
    directory = before_current(Path(directory))
    c = contract()
    actual = {p.name: {'sha256': digest(p.read_bytes())} for p in directory.glob('*.swift')}
    if actual != c['current_ui_sources']:
        raise ValueError('Changed or incomplete current handshake UI sources')
    keys = []
    for p in directory.glob('*.swift'):
        text = p.read_text()
        methods = re.findall(r'\bfunc\s+(test\w+)\s*\(', text)
        if not methods:
            continue
        classes = re.findall(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b', text)
        if len(classes) != 1 or len(methods) != len(set(methods)):
            raise ValueError('Repeated or hidden handshake method identity')
        keys.extend(classes[0] + '.' + method for method in methods)
    if sorted(keys) != c['current_inventory'] or len(set(keys)) != 736:
        raise ValueError('Current whole-method inventory changed')
    raw = (directory / NAME).read_bytes()
    old = original_source(raw)
    declarations = {name: body for body, name in re.findall(PATTERN, raw.decode())}
    old_declarations = {name: body for body, name in re.findall(PATTERN, old.decode())}
    if set(declarations) != {METHOD.split('.')[1], LINEAR.split('.')[1]}:
        raise ValueError('Handshake complete method inventory changed')
    if (digest(declarations[METHOD.split('.')[1]].encode()) != c['after_declaration_sha256']
            or digest(old_declarations[METHOD.split('.')[1]].encode()) != c['before_declaration_sha256']
            or declarations[LINEAR.split('.')[1]] != old_declarations[LINEAR.split('.')[1]]
            or re.sub(PATTERN, '', raw.decode()) != re.sub(PATTERN, '', old.decode())):
        raise ValueError('Handshake method or unchanged helper source changed')
    for path, expected in c['critical_sources'].items():
        if digest(critical_source_bytes(path)) != expected:
            raise ValueError('Critical handshake implementation or P2 cleanup changed')
    d = c['derivation']
    subtotal = d['launch_count'] * 90 + d['explicit_wait_caps_seconds'] + d['reveal_count'] * 11 * 2 + 60 + 20
    if (subtotal != 488 or ((subtotal + 9) // 10) * 10 != 490
            or c['method_seconds'] != 490 or c['linear_seconds'] != 160
            or c['previous_method_seconds'] != 410 or c['additional_seconds'] != 80
            or c['measured'] is not False):
        raise ValueError('Handshake source-derived floor changed')
    return c


def previous_directory(directory):
    try:
        from run138_current_source_projection import previous_directory as before_current
    except ModuleNotFoundError:
        from tools.run138_current_source_projection import previous_directory as before_current
    directory = before_current(Path(directory))
    p = directory / NAME
    if not p.exists():
        if directory.resolve() == (ROOT / 'Tests/AppUITests').resolve():
            raise ValueError('Current handshake source is missing')
        return directory
    if digest(p.read_bytes()) == contract()['before_file_sha256']:
        return directory
    c = validate_current(directory)
    _, root = _temporary('handshake-prior-ui-')
    destination = root / 'AppUITests'
    destination.mkdir()
    for p in directory.glob('*.swift'):
        raw = original_source(p.read_bytes()) if p.name == NAME else p.read_bytes()
        if digest(raw) != c['previous_ui_sources'][p.name]['sha256']:
            raise ValueError('Previous receipt UI source not restored exactly')
        (destination / p.name).write_bytes(raw)
    return destination


def weights(directory, profile_path):
    try:
        from run138_current_source_projection import previous_directory as before_current
    except ModuleNotFoundError:
        from tools.run138_current_source_projection import previous_directory as before_current
    directory = before_current(Path(directory))
    profile = json.loads(Path(profile_path).read_text())
    if PLAN not in profile.get('planning_budget', {}):
        p = directory / NAME
        if (directory.resolve() == (ROOT / 'Tests/AppUITests').resolve()
                or (p.exists() and digest(p.read_bytes()) != contract()['before_file_sha256'])):
            raise ValueError('Current handshake source requires its exact plan')
        return None
    c = validate_current(directory)
    prior = previous_profile(profile)
    old_ui = previous_directory(directory)
    try:
        from run130_receipt_planning import weights as receipt_weights
    except ModuleNotFoundError:
        from tools.run130_receipt_planning import weights as receipt_weights
    with tempfile.TemporaryDirectory(prefix='handshake-prior-cost-') as temporary:
        path = Path(temporary) / 'profile.json'
        path.write_text(json.dumps(prior))
        result = receipt_weights(old_ui, path)
    if result is None or abs(sum(result.values()) - c['budget_total_before']) > 1e-7:
        raise ValueError('Previous receipt class costs changed')
    result = dict(result)
    cls = METHOD.split('.')[0]
    if result[cls] != c['previous_method_seconds'] + c['linear_seconds']:
        raise ValueError('Original branch-history method floors changed')
    result[cls] = c['method_seconds'] + c['linear_seconds']
    if abs(sum(result.values()) - c['budget_total_after']) > 1e-7:
        raise ValueError('Handshake cost total drift')
    return result


def retained_protected_source(path):
    """Keep original 30cd protected assertions through an exact current-byte inverse."""
    path = Path(path)
    relative = path.relative_to(ROOT).as_posix()
    try:
        from run138_current_source_projection import historical_entry_bytes
    except ModuleNotFoundError:
        from tools.run138_current_source_projection import historical_entry_bytes
    raw = historical_entry_bytes(ROOT, relative)
    row = contract()['protected_central_inverse'].get(relative)
    if row is None:
        return raw
    if digest(raw) != row['current_sha256']:
        raise ValueError('Unreviewed protected central source')
    for hunk in reversed(row['inverse_spans']):
        start, end = hunk['current_byte_start'], hunk['current_byte_end']
        if raw[start:end] != hunk['current_text'].encode():
            raise ValueError('Protected central inverse span changed')
        raw = raw[:start] + hunk['original_text'].encode() + raw[end:]
    if digest(raw) != row['original_sha256']:
        raise ValueError('Original protected central bytes not restored exactly')
    return raw


def frozen_receipt_context():
    """Replay the known passing receipt input; retain all original test bodies.

    This is the exact inverse of the five-line handshake, not a new historical
    snapshot. Existing receipt fixtures/contracts remain byte-identical.
    """
    c = validate_current(ROOT / 'Tests/AppUITests')
    old_ui = previous_directory(ROOT / 'Tests/AppUITests')
    lifetime, root = _temporary('retained-passing-receipt-')
    target = root / 'Tests/AppUITests'
    target.mkdir(parents=True)
    for p in old_ui.glob('*.swift'):
        (target / p.name).write_bytes(p.read_bytes())
    profile = previous_profile(json.loads((ROOT / 'tools/ui_duration_weights.json').read_text()))
    target = root / 'tools/ui_duration_weights.json'
    target.parent.mkdir(parents=True)
    target.write_text(json.dumps(profile))
    for path, expected in c['retained_receipt_audit_files'].items():
        try:
            from run138_current_source_projection import historical_entry_bytes
        except ModuleNotFoundError:
            from tools.run138_current_source_projection import historical_entry_bytes
        raw = historical_entry_bytes(ROOT, path)
        if digest(raw) != expected:
            raise ValueError('Retained passing receipt audit bytes changed')
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
    return SimpleNamespace(root=root, lifetime=lifetime)


atexit.register(lambda: [life.cleanup() for life in _lives])

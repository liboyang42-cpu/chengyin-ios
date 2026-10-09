"""Current CI dispatch and explicit, byte-exact historical review contexts.

Current UI admission and current costs always run before any historical view is
created. Historical contexts preserve old assertions; they do not test new work.
"""
from pathlib import Path
from types import SimpleNamespace
import atexit
import hashlib
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ENTRY_CONTRACT = 'tools/run138_ci_entry_contract.json'
_lives = []
_contexts = {}


def planning():
    try:
        from . import run138_editor_readiness as current
    except ImportError:
        import run138_editor_readiness as current
    return current


def entry_contract(root=ROOT):
    current = planning()
    raw = (Path(root) / ENTRY_CONTRACT).read_bytes()
    if current.digest(raw) != current.contract(root)['entry_contract_sha256']:
        raise ValueError('Unreviewed current CI entry inverse')
    return json.loads(raw)


def original_entry_bytes(relative, raw, root=ROOT):
    row = entry_contract(root)['files'].get(relative)
    if row is None:
        return raw
    if hashlib.sha256(raw).hexdigest() == row['before_sha256']:
        return raw
    if hashlib.sha256(raw).hexdigest() != row['after_sha256']:
        raise ValueError('Changed current CI entry: ' + relative)
    source = raw.decode()
    for hunk in reversed(row['hunks']):
        if source.count(hunk['after']) != 1:
            raise ValueError('Missing or repeated current CI entry span')
        source = source.replace(hunk['after'], hunk['before'], 1)
    restored = source.encode()
    if hashlib.sha256(restored).hexdigest() != row['before_sha256']:
        raise ValueError('Original CI entry not restored exactly')
    return restored


def historical_entry_bytes(root, relative):
    return original_entry_bytes(relative, (Path(root) / relative).read_bytes(), root)


def validate_entries(root=ROOT):
    root = Path(root)
    c = entry_contract(root)
    for relative, row in c['files'].items():
        raw = (root / relative).read_bytes()
        if hashlib.sha256(raw).hexdigest() != row['after_sha256']:
            raise ValueError('Missing or changed active CI entry: ' + relative)
        original_entry_bytes(relative, raw, root)
    expected = planning().contract(root)['entry_projection_module_sha256']
    if hashlib.sha256((root / 'tools/run138_current_source_projection.py').read_bytes()).hexdigest() != expected:
        raise ValueError('Current CI projection implementation changed')
    validate_feature_batch_sources(root)
    validate_description_sources(root)


def original_feature_batch_bytes(relative, raw, root=ROOT):
    """Restore the pinned input of an existing gate for this product batch only."""
    row = planning().contract(root)['feature_batch_sources'].get(relative)
    if row is None:
        return raw
    text_input = isinstance(raw, str)
    value = raw.encode('utf-8') if text_input else raw
    if hashlib.sha256(value).hexdigest() != row['after_sha256']:
        raise ValueError('Unknown current feature-batch source: ' + relative)
    source = value.decode('utf-8')
    for hunk in reversed(row['hunks']):
        if source.count(hunk['after']) != 1:
            raise ValueError('Missing or repeated feature-batch span: ' + relative)
        source = source.replace(hunk['after'], hunk['before'], 1)
    restored = source.encode('utf-8')
    if hashlib.sha256(restored).hexdigest() != row['before_sha256']:
        raise ValueError('Feature-batch predecessor not restored exactly: ' + relative)
    return restored.decode('utf-8') if text_input else restored


def validate_feature_batch_sources(root=ROOT):
    root = Path(root)
    c = planning().contract(root)
    for relative in c['feature_batch_sources']:
        original_feature_batch_bytes(relative, (root / relative).read_bytes(), root)
    for relative, expected in c['feature_batch_support_sha256'].items():
        if hashlib.sha256((root / relative).read_bytes()).hexdigest() != expected:
            raise ValueError('Current feature-batch input changed: ' + relative)


def original_description_bytes(relative, raw, root=ROOT):
    """Reverse only this exact product increment, before unchanged old assertions."""
    raw = original_feature_batch_bytes(relative, raw, root)
    row = planning().contract(root)['node_description_sources'].get(relative)
    if row is None:
        return raw
    if hashlib.sha256(raw).hexdigest() != row['after_sha256']:
        raise ValueError('Unknown current node-description source: ' + relative)
    if row['before_sha256'] is None:
        return None
    source = raw.decode('utf-8')
    for hunk in reversed(row['hunks']):
        if source.count(hunk['after']) != 1:
            raise ValueError('Missing or repeated node-description span: ' + relative)
        source = source.replace(hunk['after'], hunk['before'], 1)
    restored = source.encode('utf-8')
    if hashlib.sha256(restored).hexdigest() != row['before_sha256']:
        raise ValueError('Original node-description source not restored exactly: ' + relative)
    return restored


def validate_description_sources(root=ROOT):
    root = Path(root)
    c = planning().contract(root)
    for relative in c['node_description_sources']:
        original_description_bytes(relative, (root / relative).read_bytes(), root)
    adapter = root / 'Tests/ContractChecks/test_run130_topic_media_source_adapter.py'
    if hashlib.sha256(adapter.read_bytes()).hexdigest() != c['node_description_adapter_sha256']:
        raise ValueError('Node-description historical entry changed')


def description_sources_before_buffer(sources, root=ROOT):
    validate_description_sources(root)
    restored = {}
    for relative, source in sources.items():
        value = original_description_bytes(relative, source.encode('utf-8'), root)
        if value is None:
            raise ValueError('New node-description source has no historical preimage')
        restored[relative] = value.decode('utf-8')
    return restored


def is_current_ui(directory):
    directory = Path(directory)
    return (directory.resolve() == (ROOT / 'Tests/AppUITests').resolve()
            or (directory / 'ProjectEditReviewReadinessFlowTests.swift').exists())


def current_weights(directory, profile):
    if not is_current_ui(directory):
        return None
    return planning().weights(directory, profile)


def previous_directory(directory):
    if not is_current_ui(directory):
        return Path(directory)
    return planning().previous_directory(directory, ROOT / 'tools/ui_duration_weights.json')


def previous_source(path):
    path = Path(path)
    if path.parent.name != 'AppUITests' or not is_current_ui(path.parent):
        return path
    old = previous_directory(path.parent)
    result = old / path.name
    if not result.is_file():
        raise ValueError('A new complete class has no single old-file preimage')
    return result


def previous_text(relative, source):
    current = planning()
    if not relative.startswith('Tests/AppUITests/'):
        return source
    owned = set(current.source_contract()['files']) | set(current.ui52_layer().contract()['files']) | current.followons().owned_ui_paths() | {p for p in current.contract()['feature_batch_sources'] if p.startswith('Tests/AppUITests/')}
    if relative not in owned:
        return source
    name = Path(relative).name
    # Unknown or already historical input must continue through the original
    # strict verifier, never be replaced with convenient current disk bytes.
    expected = current.contract()['current_ui_sources'].get(name)
    if current.digest(source.encode()) != expected:
        return source
    path = ROOT / relative
    return previous_source(path).read_text()


# Exclusions are source-root-relative generated paths, not broad directory
# basenames or source extensions. A fixture's nested DerivedData/.build/.git
# folder remains a real input. Python __pycache__ is the generated cache name
# wherever Python imports a source module. All other paths remain in scope.
CONTEXT_GENERATED_ROOTS = frozenset({'.git', '.build', 'DerivedData'})
CONTEXT_GENERATED_PATHS = (
    'Questify.xcodeproj/xcuserdata',
    'Questify.xcodeproj/project.xcworkspace/xcuserdata',
)


def context_generated_path(relative):
    relative = Path(relative)
    if '__pycache__' in relative.parts:
        return True
    if relative.parts and relative.parts[0] in CONTEXT_GENERATED_ROOTS:
        return True
    text = relative.as_posix()
    return text == '.DS_Store' or any(text == prefix or text.startswith(prefix + '/')
                                    for prefix in CONTEXT_GENERATED_PATHS)


def ignore_context_names(root, directory, names):
    directory = Path(directory).relative_to(root)
    return {name for name in names if context_generated_path(directory / name)}


def context_walk_error(error):
    raise ValueError('Unreadable historical-context input tree') from error


def tree_sha256(root):
    root = Path(root)
    hashes = {}
    for directory, directories, files in os.walk(root, onerror=context_walk_error):
        ignored = ignore_context_names(root, directory, directories + files)
        for name in directories + files:
            if name not in ignored and (Path(directory) / name).is_symlink():
                raise ValueError('Unreviewed symlink in historical-context input tree')
        directories[:] = [name for name in directories if name not in ignored]
        for name in files:
            if name not in ignored:
                path = Path(directory) / name
                hashes[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def frozen_context(stage='all', root=ROOT):
    """Actual current source is validated first; only then build a prior context."""
    root = Path(root)
    current = planning()
    c = current.validate_current(root / 'Tests/AppUITests', root / 'tools/ui_duration_weights.json', root)
    if stage not in {'all', 'ui52', 'coupon', 'review'}:
        raise ValueError('Unknown reviewed historical context')
    key = (str(root.resolve()), current.canonical(c), stage)
    cached = _contexts.get(key)
    if cached is not None and cached.root.exists():
        if tree_sha256(root) != cached.current_file_sha256:
            raise ValueError('Current historical-context input tree was changed')
        actual = tree_sha256(cached.root)
        if actual != cached.file_sha256:
            raise ValueError('Cached historical review context was changed')
        return cached
    current_file_sha256 = tree_sha256(root)
    life = tempfile.TemporaryDirectory(prefix='run138-historical-' + stage + '-')
    _lives.append(life)
    target = Path(life.name) / 'source'
    shutil.copytree(root, target, ignore=lambda directory, names: ignore_context_names(root, directory, names))
    for relative in c['feature_batch_sources']:
        if relative.startswith('Tests/AppUITests/') or (stage == 'review' and relative == 'App/ProjectEditView.swift'):
            (target / relative).write_bytes(original_feature_batch_bytes(relative, (root / relative).read_bytes(), root))
    for relative in current.source_contract(root)['files']:
        raw = current.original_source(relative, (root / relative).read_bytes(), root)
        destination = target / relative
        if raw is None:
            destination.unlink()
        else:
            destination.write_bytes(raw)
    if stage != 'ui52':
        driver = current.ui52_layer()
        for relative in driver.contract(root)['files']:
            (target / relative).write_bytes(driver.original_source(relative, (root / relative).read_bytes(), root))
    for relative in current.followons().owned_ui_paths() - set(current.source_contract(root)['files']):
        if stage == 'coupon' and relative in current.followons().coupon_paths():
            continue
        (target / relative).write_bytes(current.followons().source_before_followons(relative, (root / relative).read_bytes()))
    for relative, row in current.followons().availability().contract()['scope'].items():
        if stage != 'review' and row['before_sha256'] is not None:
            (target / relative).write_bytes(current.followons().historical_app_source(relative, (root / relative).read_bytes(), root))
    for relative in entry_contract(root)['files']:
        (target / relative).write_bytes(historical_entry_bytes(root, relative))
    if stage == 'coupon':
        (target / 'tools/branch_history_handshake_planning.py').write_bytes(oldest_handshake_bytes(root))
    def load(relative, name):
        loader = SourceFileLoader(name, str(target / relative))
        module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
        # Existing tools use both direct and package imports; leave their own
        # historical validation boundaries intact rather than patching globals.
        old_path = list(sys.path)
        try:
            sys.path.insert(0, str(target / 'tools'))
            loader.exec_module(module)
        finally:
            sys.path[:] = old_path
        return module
    file_sha256 = tree_sha256(target)
    if tree_sha256(root) != current_file_sha256:
        raise ValueError('Current historical-context inputs changed during construction')
    context = SimpleNamespace(root=target, lifetime=life, load=load, file_sha256=file_sha256,
                              current_file_sha256=current_file_sha256)
    _contexts[key] = context
    return context


def validate_ui52_component(root=ROOT):
    context = frozen_context('ui52', root)
    # No migrated class remains in this explicit component context, so the
    # original isolated admission executes unchanged after the current gate.
    historical_driver = context.load('tools/run138_ui52_driver_inverse.py', 'run138_retained_ui52')
    return historical_driver.validate_current(context.root)


def oldest_handshake_bytes(root=ROOT):
    path = Path(root) / 'tools/ci138_followon_handshake_contract.json'
    raw = path.read_bytes()
    if planning().digest(raw) != planning().contract(root)['followon_handshake_contract_sha256']:
        raise ValueError('Changed exact prior handshake bridge')
    c = json.loads(raw)
    value = historical_entry_bytes(root, 'tools/branch_history_handshake_planning.py').decode()
    if planning().digest(value.encode()) != c['after_sha256']:
        raise ValueError('Unknown intermediate handshake implementation')
    for hunk in reversed(c['hunks']):
        if value.count(hunk['after']) != 1:
            raise ValueError('Changed or repeated fixture-lifetime handshake entry')
        value = value.replace(hunk['after'], hunk['before'], 1)
    if planning().digest(value.encode()) != c['before_sha256']:
        raise ValueError('Original published handshake was not restored exactly')
    return value.encode()


def validate_coupon_component(root=ROOT):
    context = frozen_context('coupon', root)
    return planning().followons().coupon().validate_current(context.root)


atexit.register(lambda: [life.cleanup() for life in _lives])

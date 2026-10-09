"""Strict owned inverse for the isolated CI138 Review-availability candidate.

No caller is wired here. Integrators must invoke this before the unchanged
version-row / topic-media historical adapters, never replace their hashes.
"""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
CONTRACT_SHA256 = '33d7db9ad0af3fc610cfabcdcfa4a3949491b9ecdc24f6f75d522e5494bbc151'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def contract():
    raw = (HERE / 'review_availability_contract.json').read_bytes()
    if digest(raw) != CONTRACT_SHA256:
        raise ValueError('Review availability contract bytes changed')
    return json.loads(raw)


def verify_current(root):
    root = Path(root)
    plan = contract()
    for relative, expected in plan['scope'].items():
        if digest((root / relative).read_bytes()) != expected['after_sha256']:
            raise ValueError('Current review candidate changed: ' + relative)
    for relative, expected in plan['unchanged_dependencies'].items():
        if digest((root / relative).read_bytes()) != expected:
            raise ValueError('Existing review authority changed: ' + relative)


def _transform(relative, raw, inverse):
    plan = contract()['scope']
    if relative not in plan:
        return raw
    was_text = isinstance(raw, str)
    value = raw.encode('utf-8') if was_text else raw
    item = plan[relative]
    source_key, target_key = ('after', 'before') if inverse else ('before', 'after')
    expected = item[source_key + '_sha256']
    if expected is None:
        if value != b'':
            raise ValueError('New source already existed: ' + relative)
    elif digest(value) != expected:
        raise ValueError('Complete source postimage/preimage changed: ' + relative)
    if inverse and item['before_sha256'] is None:
        raise ValueError('New source has no historical predecessor: ' + relative)
    lines = value.decode('utf-8').splitlines(keepends=True)
    for hunk in sorted(item['hunks'], key=lambda h: h[source_key + '_line'], reverse=True):
        start = hunk[source_key + '_line']
        old = hunk[source_key].splitlines(keepends=True)
        new = hunk[target_key].splitlines(keepends=True)
        if lines[start:start + len(old)] != old:
            raise ValueError('Exact review hunk changed: ' + relative)
        lines[start:start + len(old)] = new
    result = ''.join(lines).encode('utf-8')
    if digest(result) != item[target_key + '_sha256']:
        raise ValueError('Exact previous/current source was not restored: ' + relative)
    return result.decode('utf-8') if was_text else result


def original_source(relative, raw, root):
    """Validate the owned current package, then restore a targeted full preimage.

Unowned paths are returned unchanged. Added current checks intentionally have
no historical projection. Raw bytes and UTF-8 strings preserve their input type.
"""
    if relative not in contract()['scope']:
        return raw
    verify_current(root)
    return _transform(relative, raw, inverse=True)


def candidate_source(relative, raw):
    return _transform(relative, raw, inverse=False)

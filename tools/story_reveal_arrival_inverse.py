"""Exact, fail-closed inverse for the two isolated story harness repairs.

This module does not alter any repository or active planning layer. The editor
must explicitly integrate the candidates and extend the current projection.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_SHA256 = '468a348b5ec509d12180fc74b4c8387da98680a94a92e8f8b0ac2494d5b1a211'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def contract():
    raw = (ROOT / 'tools/story_reveal_arrival_contract.json').read_bytes()
    if digest(raw) != CONTRACT_SHA256:
        raise ValueError('Changed story repair contract')
    return json.loads(raw)


def row_for(path):
    key = str(path)
    matches = [row for row in contract()['changes'] if row['path'] == key]
    if len(matches) != 1:
        raise ValueError('Unknown story helper path')
    return matches[0]


def inverse(path, raw):
    row = row_for(path)
    if digest(raw) != row['after_sha256']:
        raise ValueError('Unknown candidate story helper bytes')
    after = row['replace_after'].encode()
    before = row['replace_before'].encode()
    if raw.count(after) != 1:
        raise ValueError('Missing or repeated exact story repair')
    restored = raw.replace(after, before, 1)
    if digest(restored) != row['before_sha256']:
        raise ValueError('Story inverse did not restore current275 exactly')
    return restored


def forward(path, raw):
    row = row_for(path)
    if digest(raw) != row['before_sha256']:
        raise ValueError('Unknown baseline story helper bytes')
    before = row['replace_before'].encode()
    after = row['replace_after'].encode()
    if raw.count(before) != 1:
        raise ValueError('Missing or repeated original story statement')
    changed = raw.replace(before, after, 1)
    if digest(changed) != row['after_sha256']:
        raise ValueError('Story forward transform differs from candidate')
    return changed

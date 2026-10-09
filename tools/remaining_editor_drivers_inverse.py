"""Source-bound two-file candidate. Restore exact current275 before old planning.

This package does not modify the runner or reinterpret historical evidence.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_SHA256 = '36ebb3104a1f4fb0f5bb513163e2714e1b59c9933e604da75019a4a213f98733'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def contract():
    raw = (ROOT / 'tools/remaining_editor_drivers_contract.json').read_bytes()
    if digest(raw) != CONTRACT_SHA256:
        raise ValueError('Unknown remaining-editor contract')
    return json.loads(raw)


def row_for(path):
    rows = [row for row in contract()['changes'] if row['path'] == str(path)]
    if len(rows) != 1:
        raise ValueError('Unowned remaining-editor source')
    return rows[0]


def transform(path, raw, reverse=False):
    row = row_for(path)
    start, end = ('after', 'before') if reverse else ('before', 'after')
    if digest(raw) != row[start + '_sha256']:
        raise ValueError('Unknown input bytes for ' + str(path))
    hunks = reversed(row['hunks']) if reverse else row['hunks']
    for hunk in hunks:
        old, new = hunk[start].encode(), hunk[end].encode()
        if raw.count(old) != 1:
            raise ValueError('Missing or repeated exact remaining-editor hunk')
        raw = raw.replace(old, new, 1)
    if digest(raw) != row[end + '_sha256']:
        raise ValueError('Remaining-editor projection is not exact')
    return raw


def inverse(path, raw):
    return transform(path, raw, reverse=True)


def forward(path, raw):
    return transform(path, raw)

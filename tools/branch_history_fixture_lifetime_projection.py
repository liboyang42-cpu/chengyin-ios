"""Strict byte inverse for the reviewed DEBUG fixture-lifetime evolution.

Validate complete current sources and full historical preimages before returning
any projection. The original caller still compares all historical critical hashes.
"""
from pathlib import Path
import hashlib
import json

CONTRACT = 'tools/branch_history_fixture_lifetime_projection_contract.json'
CONTRACT_SHA256 = 'abb3b29dc745424c61e9d268dd5fa7e904631656a720f8abaeeb6a5c29dc7936'
SOURCE_PREIMAGES = {
    'App/PlayBranchHistoryFixtureSupport.swift': (
        '56b35ee882ee9095d6c1364356d991c5ddbad552110fbfc3990187da068be0d5',
        'tools/tests/fixtures/branch_history_fixture_lifetime/App__PlayBranchHistoryFixtureSupport.swift.txt'),
    'Tests/AppUnitTests/PlayBranchHistoryFixtureHandshakeTests.swift': (
        'e377ce367af0afef0a960fc2437ccc1ea14f3a81e5611d7885339192a55512a8',
        'tools/tests/fixtures/branch_history_fixture_lifetime/Tests__AppUnitTests__PlayBranchHistoryFixtureHandshakeTests.swift.txt'),
}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def historical_source(root, relative):
    root = Path(root)
    raw = (root / relative).read_bytes()
    if relative not in SOURCE_PREIMAGES:
        return raw
    contract_path = root / CONTRACT
    if not contract_path.is_file():
        raise ValueError('Missing branch-history lifetime projection contract')
    contract_bytes = contract_path.read_bytes()
    if digest(contract_bytes) != CONTRACT_SHA256:
        raise ValueError('Changed branch-history lifetime projection contract')
    contract = json.loads(contract_bytes)
    rows = contract['sources']
    if contract['schema_version'] != 1 or set(rows) != set(SOURCE_PREIMAGES):
        raise ValueError('Changed branch-history lifetime projection inventory')
    expected_support = {'Tests/ContractChecks/test_branch_history_fixture_lifetime.py',
                        'tools/tests/test_branch_history_fixture_lifetime_projection.py'}
    if set(contract['support_sources']) != expected_support:
        raise ValueError('Changed branch-history lifetime proof inventory')
    for path, expected in contract['support_sources'].items():
        file = root / path
        if not file.is_file() or digest(file.read_bytes()) != expected:
            raise ValueError('Missing or changed branch-history lifetime proof: ' + path)
    current = {}
    # Validate the complete pair before any historical bytes are returned.
    for path, row in rows.items():
        data = (root / path).read_bytes()
        if digest(data) != row['current_sha256']:
            raise ValueError('Unreviewed current branch-history lifetime source: ' + path)
        current[path] = data
    projected = {}
    for path, row in rows.items():
        expected, preimage_path = SOURCE_PREIMAGES[path]
        if row['original_sha256'] != expected or row['preimage'] != preimage_path:
            raise ValueError('Changed historical branch-history source identity')
        preimage = root / preimage_path
        if not preimage.is_file():
            raise ValueError('Missing complete branch-history historical preimage')
        original = preimage.read_bytes()
        if digest(original) != expected:
            raise ValueError('Changed complete branch-history historical preimage')
        data = current[path]
        spans = row['inverse_spans']
        end = 0
        for span in spans:
            start, stop = span['current_byte_start'], span['current_byte_end']
            if not (0 <= end <= start <= stop <= len(data)):
                raise ValueError('Moved or overlapping branch-history inverse range')
            if data[start:stop] != span['current_text'].encode('utf-8'):
                raise ValueError('Changed exact branch-history inverse span')
            end = stop
        for span in reversed(spans):
            start, stop = span['current_byte_start'], span['current_byte_end']
            data = data[:start] + span['original_text'].encode('utf-8') + data[stop:]
        if digest(data) != expected or data != original:
            raise ValueError('Original branch-history bytes not restored exactly')
        projected[path] = data
    return projected[relative]

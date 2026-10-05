#!/usr/bin/env python3
"""Supplementary source/structure checks; NOT Swift/XCTest or backend acceptance."""
from pathlib import Path
import re, json, hashlib
root = Path(__file__).resolve().parents[1]
sibling = root.parent
core = (root / 'Core/PublisherAuthoritySource.swift').read_text()
reader = (root / 'Core/PublisherSourceAuthorityReader.swift').read_text()
host = (root / 'App/AppSession.swift').read_text()
tests = (root / 'Tests/CoreTests/PublisherSourceAuthorityTests.swift').read_text()
source = '\n'.join((sibling / 'app-audit/lib/data/models' / name).read_text() for name in ['topic.dart', 'activity.dart'])
# Every raw scalar field in the projection must occur in the audited source model.
for match in re.finditer(r'fields\(\[([^\]]*)\]', core, re.S):
    for field in re.findall(r'"([A-Za-z_][A-Za-z_0-9]*)"', match.group(1)):
        assert f"'{field}'" in source, f'Unaudited projection field {field}'
assert 'clubs.clubOwned()' in reader and 'clubs.clubDetail(id: candidate.id)' in reader
assert 'if fresh.isOwner' in reader and 'if fresh.viewerIsAdmin' not in reader
assert 'clubDirectory(' not in reader and 'clubMembers(' not in reader
assert 'currentSession() == session' in reader
assert 'source.resourceID == resource.value' in reader
assert 'topics.scope == topicScope, clubs.clubIdentity == clubIdentity' in reader
assert 'ownerAccountID: session.accountID' in reader
assert 'encoder.outputFormatting = [.sortedKeys]' in reader
assert 'sorted { $0.id < $1.id }' in reader
assert 'publisherAuthoritySource = try?' in (root / 'docs/remaining-native-clients/publisher-authority/reader-projections.patch').read_text()
for text in [core, reader]:
    assert 'URLSession' not in text and 'OperationEndpointApproval(' not in text
    assert 'PublisherLifecycleGrants(' not in text
assert 'freshPublisherAuthority' in host
for path in ['Core/TopicContracts.swift','Core/ActivityDetail.swift']:
    assert 'publisherAuthoritySource = try?' in (root/path).read_text()
assert len(re.findall(r'func test\w+', tests)) == 10
print('PASS audited source keys, same-response projection, exact identity/owner/session fences, source /my plus fresh leadership, canonical fingerprint, no new grants/transport, 10 authored XCTest methods, integrated main projections')
print('NOT_RUN Swift typechecking, XCTest execution, Apple SDK build, simulator/device, live backend acceptance')

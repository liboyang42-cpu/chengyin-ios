#!/usr/bin/env python3
"""Supplementary source/packet checks; not Swift compiler or XCTest execution."""
from pathlib import Path
import json, hashlib
root=Path(__file__).resolve().parents[1]
source=root.parent/'app-audit/lib/data/api'
packet=json.loads((root/'docs/remaining-native-clients/publisher/packet-manifest.json').read_text())
files={entry['path']:(root/entry['path']).read_text() for entry in packet['files'] if entry['path'].endswith('.swift')}
allcode='\n'.join(files.values())
sourcecode='\n'.join((source/name).read_text() for name in ['topic_api.dart','activity_api.dart','creator_api.dart','club_api.dart','roam_api.dart'])
paths=['api/topic/pricing/preview','api/topic/pricing/confirm','api/topic/cancel','api/topic/cancel_preview','api/activity/cancel','api/activity/cancel_preview','api/topic/transfer-to-club','api/topic/beta/graduate','api/topic/xp-budget','api/creator/apply','api/club/detail','api/merchant/public-detail']
for p in paths: assert p in sourcecode and p in allcode,p
assert 'grants: .dormant' in files['App/PublisherLifecycleHostHooks.swift']
assert 'case .number' in files['Core/PublisherLifecycleContracts.swift']
assert 'center.status == .notApplied' in files['Core/CreatorApplication.swift']
assert 'paidPlayers' in files['Core/PublisherLifecycleCoordinator.swift']
assert 'fresh == review.authority' in files['Core/PublisherLifecycleCoordinator.swift']
assert 'generation == stamp' in files['Core/CreatorApplication.swift']
assert '.shared' not in '\n'.join(v for k,v in files.items() if k.startswith('Core/'))
assert all('URLSession' not in v for v in files.values())
# Packet hashes are archived source evidence. Integrated hashes are recorded by the batch manifest.
for entry in packet['files']:
 if entry['path'].endswith('.swift'): assert (root/entry['path']).is_file()
assert 'PublisherSourceAuthorityReader' in (root/'App/AppSession.swift').read_text()
assert 'PublisherLifecycleNavigationLink' in (root/'App/PlatformConsumerSessionOwner.swift').read_text()
print(f'PASS {len(paths)} source-backed endpoints; dormant production factory, integrated source boundary checks')
print('Apple compilation/typechecking/XCTest/simulator/device: NOT_RUN')

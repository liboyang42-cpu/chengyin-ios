#!/usr/bin/env python3
"""Static contract assertions, not Swift/runtime or live service acceptance."""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
source=(r/'Core/ChapterThoughtSync.swift').read_text()
assert '"api/play/journey/thought/sync"' in source and 'capability: .thoughtClaims' in source
assert '"claim": .array(claims.map(PlayWireValue.string))' in source
for forbidden in ['"steps":','"encryptedData":','"code":','"iv":','"expectedVersion":']:
 assert forbidden not in source,forbidden
assert 'route.sessionID == sessionID' in source and 'version > previousVersion' in source
assert '!snapshot.isLocked(node), snapshot.isDone(node) else { break }' in source
coordinator=(r/'Core/PlayExperienceCoordinator.swift').read_text()
assert 'guard canWrite, hasCurrentMediaSnapshot' in coordinator
assert 'service.enabled.contains(.thoughtClaims)' in coordinator
assert 'pendingThoughtKeys.subtract(storyThoughts.compactMap' in coordinator
assert 'No implicit retry after a possibly committed claim' in coordinator
ui=(r/'App/ChapterStoryView.swift').read_text()
assert 'await model.claimVisibleThoughts(chapterID: chapterID)' in ui
assert '.task(id: thoughtClaimKey)' not in ui
assert 'Button("playx.refresh") { Task { await model.load() } }' in ui
print('PASS: visible-block claim barrier, separate default-off grant, exact claim-only JSON, session/version validation, authoritative readback and stable UI task identity')
print('Swift, Apple UI/device, provider and live backend execution: NOT_RUN')

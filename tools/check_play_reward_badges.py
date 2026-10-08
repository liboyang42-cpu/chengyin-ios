#!/usr/bin/env python3
"""Focused source contracts only. Not Swift typechecking, UI execution or live reward proof."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
def read(path):
    return (ROOT / path).read_text()

core = read('Core/PlayRewardBadgePresentation.swift')
view = read('App/PlayRewardBadgeViews.swift')
host = read('App/SessionPlayRuntimeView.swift')
play = read('App/PlayExperienceView.swift')
free = read('App/FreeExplorationViews.swift')
fragment = json.loads(read('Resources/PlayRewardBadgeLocalizations.fragment.json'))
strings = fragment['strings']
checks = {
    'receipt exact source key': 'receipt["newBadges"].array' in core and 'row["code"].text' in core,
    'stable unique identities': 'seen.insert(code).inserted' in core,
    'no name-based confirmation': '$0.badgeCode == target.code' in core and '$0.badgeName ==' not in core,
    'achievement separation': '$0.isAchievement && $0.badgeCode == target.code' in core,
    'missing vs partial': 'wall.isPartial ? .incompleteWall : .missingFromWall' in core,
    'conflicting matches fail closed': 'identities.count + achievements.count > 1' in core,
    'captured owner and approval': 'owner == expectedOwner && owner == reader.identity' in core,
    'fresh owner cannot read old target': 'owner = identity' in core and 'reader.identity == expectedOwner ? reader.identity : nil' in core,
    'revoked config hidden': 'reader.isConfigured' in core and 'current ? storedFocus : nil' in core,
    'queued retry cannot revive': 'guard active, !Task.isCancelled else { return }' in core,
    'underlying read cancellation': 'onCancel: { task.cancel() }' in core and 'readTask?.cancel()' in core,
    'generation rejection': 'generation == revision' in core,
    'queued dispatch revalidates captured context': core.index('guard accepts(captured, revision) else { throw CancellationError() }') < core.index('return try await reader.profileBadges()'),
    'cancelled view task cannot reactivate': 'guard !Task.isCancelled else { return }\n            reads.activate(); model.activate()' in view,
    'view owns retries and disappearance': 'reads.start { await model.load() }' in view and 'reads.deactivate(); model.deactivate()' in view,
    'source code routes from host': 'rewardCollectionDestination:' in host and 'reader: session.profileReader' in host,
    'current play authorization injected': 'isCurrent: { model.identity != nil }' in host and 'reader.isConfigured && isCurrent()' in core,
    'existing growth reader only': 'growthReader: session.growthCenterReader' in host and 'GrowthCenterView(reader: growthReader)' in view,
    'classic and free exploration mounted': 'collectionDestination: rewardCollectionDestination' in play and 'destination: rewardCollectionDestination' in free,
    'old reward fields preserved': all(f'reward["{key}"]' in play for key in ['xp', 'score', 'puzzleScore', 'completionMode', 'medalName']),
    'explicit continue and empty suppression': '!targets.isEmpty && !continued' in view and 'continued = true' in view,
    'only existing reader dispatched': core.count('reader.profileBadges()') == 1 and 'api/' not in core + view,
    'no award or wallet client': all(term not in core + view for term in ['URLSession', 'claimReward(', 'redeem(', 'submit(', 'grant(', 'couponId']),
}
keys = set(re.findall(r'"(playBadge\.[A-Za-z]+)"', core + view))
# Accessibility identifiers are not display copy.
keys -= {'playBadge.growth', 'playBadge.refresh'}
checks['bilingual coverage'] = keys <= set(strings) and all(
    all(item.get('localizations', {}).get(lang, {}).get('stringUnit', {}).get('value') for lang in ['en', 'zh-Hans'])
    for item in strings.values())
for name, passed in checks.items():
    print(('PASS' if passed else 'FAIL') + ': ' + name)
assert all(checks.values()), 'Focused source contract failed'
print(f'PASS: {len(checks)} focused source checks; {len(strings)} bilingual keys')
print('NOT_RUN: Swift XCTest, Apple compilation, simulator, VoiceOver, screenshots, real backend rewards')

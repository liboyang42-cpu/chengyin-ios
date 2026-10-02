#!/usr/bin/env python3
"""Offline source/contract audit; no Swift runtime or network evidence."""
import json, pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[1]
source = pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else root.parent/'app-audit'
api = (source/'lib/data/api/club_api.dart').read_text()
contracts = (root/'Core/ClubCommunityContracts.swift').read_text()
service = (root/'Core/ClubCommunityService.swift').read_text()
views = (root/'App/ClubCommunityViews.swift').read_text()
for suffix in ['list','feed','like','create','update','pin','history','delete','report','comment/list','comment/create','comment/delete','comment/report']:
    assert '/api/club/post/'+suffix in api, suffix
for needle in ['images.join(\';\')', "'requestId': requestId", "'version': version", "'postId': postId", "'id': commentId"]:
    assert needle in api, needle
for needle in ['images.joined(separator: ";")', '"requestId": key', '"version": evidence.post!.version', 'case .delete, .report: return ["id": postID]', 'case .toggleLike: return ["postId": postID]']:
    assert needle in contracts, needle
for needle in ['allowsInjectedWrites = false', 'guard allowsInjectedWrites', 'locks.insert(candidate.lockKey)', 'consumed.contains(candidate.id)', 'fresh.post == candidate.evidence.post', 'fresh.identity == candidate.evidence.identity', 'case .report, .reportComment: outcome = .moderationQueued']:
    assert needle in service, needle
assert 'URLSession' not in service
assert 'editorMemberId' not in contracts
catalog = {k:v for k,v in json.loads((root/'Resources/Localizable.xcstrings').read_text())['strings'].items() if k.startswith('club.community.')}
keys = set(re.findall(r'"(club\.community\.[A-Za-z]+)"',views)) - {'club.community.entry','club.community.notice','club.community.reviewDraft'}
for key in keys:
    assert key in catalog, key
for key,entry in catalog.items():
    assert set(entry['localizations']) == {'en','zh-Hans'}, key
print(f'PASS: 13 source routes, exact mutation keys, dormant adapter/locks, {len(catalog)} bilingual labels')
print('Swift typecheck/XCTest/Apple UI runtime: NOT_RUN')

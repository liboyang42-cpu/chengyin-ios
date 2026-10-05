#!/usr/bin/env python3
"""Current contextual contract structure; no service, Swift or Apple execution."""
from pathlib import Path
import json
r=Path(__file__).resolve().parents[1]
def read(p):return (r/p).read_text()
coop=read('Core/CooperationContextual.swift')
assert 'kind == .merchant ? "memberId" : "id"' in coop
assert '["merchant", "talent"].contains(fromType ?? "")' in coop
service=read('Core/CooperationFlowService.swift')
for field in ['"api/club/merchants"','"invite_target"','"is_my"','case .nearby, .ownedTopics: isForm = true']:
 assert field in service,field
ui=read('App/CooperationContextualViews.swift')
for field in ['topic?.inviteWindowOpen != true','CoopFlowBatchInviteEditor','async let a: Void','async let b: Void','session == reader.session']:
 assert field in ui,field
assert 'peerReader:session.cooperationFlowReader' in read('App/AccountView.swift')
ops=read('Core/ClubContextualOperations.swift')
for field in ['api/club/lead/edit-ops','api/activity/info','enabled: Bool = false','Asia/Shanghai','states[account] = .unknown']:
 assert field in ops,field
rules=read('App/ClubContextualViews.swift')
for section in ['leaveClub','leaveTeam','refund','pause','cancel']: assert '"'+section+'"' in rules
assert 'ClubOpsTimeView' in read('App/ClubGovernanceViews.swift')
assert 'ClubOperatingRulesView' in read('App/ClubGovernanceViews.swift')
ai=read('Core/ClubAIDesignFlow.swift')
for field in ['error != .null','ClubAIDesignFailure.parse','ClubAIDesignFailure.empty','resultSession','current() == session','node.longitude = ""; node.latitude = ""']:
 assert field in ai,field
assert 'makePublishingAuxiliaryService(feature: .publishingAIClub)' in read('App/ClubAIDesignView.swift')
assert 'club.isOwner, let session = reader as? AppSession' in read('App/ClubDetailView.swift')
strings=json.loads(read('Resources/Localizable.xcstrings'))['strings']
for key,value in strings.items():
 if key.startswith('context.'):
  assert all(value['localizations'][l]['stringUnit']['value'] for l in ['en','zh-Hans']),key
print('PASS scoped cooperation recipient domains, peer partial reads, five rule sections, exact dormant edit-ops and club-AI adoption')
print('Swift tests, Apple builds, simulator visual/accessibility and live services NOT_RUN')

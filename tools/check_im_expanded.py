#!/usr/bin/env python3
"""Source/structural evidence only. Does not execute Swift or prove UI behavior."""
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT.parent/'app-audit/lib'
api=(SOURCE/'data/api/im_api.dart').read_text()
service=(ROOT/'Core/IMExpandedService.swift').read_text()
contracts=(ROOT/'Core/IMExpandedContracts.swift').read_text()
coordinator=(ROOT/'Core/IMExpandedCoordinator.swift').read_text()
media=(ROOT/'Core/IMMediaSelection.swift').read_text()
ui=(ROOT/'App/IMExpandedViews.swift').read_text()
for endpoint in ['/api/im/start','/api/im/read','/api/im/mute','/api/im/send','/api/common/uploadOSS']:
    assert endpoint in api, endpoint
for field in ['target_member_id','conversation_id','muted','client_message_id','extra_json','msg_type','content']:
    assert field in api and field in service+contracts, field
assert 'WebSocket' in (SOURCE/'feature/im/im_chat_page.dart').read_text()
assert "不做 WebSocket" in (SOURCE/'feature/im/im_chat_page.dart').read_text()
assert 'message.senderID == 0' in contracts
assert 'httpShouldHandleCookies = false' in service
assert 'approvedMediaOrigins.contains(origin)' in service
assert 'consent.selectionID == selection.id' in service
assert 'case .submitting, .outcomeUnknown, .closed: return false' in coordinator
assert 'case .uploading, .outcomeUnknown: state = .outcomeUnknown' in media
assert 'self.scope == scope' in coordinator
for bad in ['URLSession(', 'AVAudioRecorder', 'requestAuthorization(', 'URLSessionWebSocketTask', 'UIApplication.shared.open']:
    assert bad not in service+contracts+media+ui+coordinator, bad
catalog=json.loads((ROOT/'docs/im-expanded-localizations.json').read_text())
for key in set(re.findall(r'"(im\.full\.[A-Za-z]+)"',ui+contracts)):
    assert key in catalog or key in {'im.full.cardActions','im.full.controls','im.full.imageCompose'},key
for key,row in catalog.items(): assert row['en'] and row['zh-Hans'],key
assert (ROOT/'Tests/AppUITests/IMExpandedUITests.swift').exists()
print('PASS 24 source/structural invariant groups; Swift/Xcode/device runtime NOT_RUN')

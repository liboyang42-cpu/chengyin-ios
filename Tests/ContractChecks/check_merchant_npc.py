#!/usr/bin/env python3
"""Static source checks only. No Swift execution, network or provider calls."""
from pathlib import Path
import json,re
root=Path(__file__).resolve().parents[2]
source=(root.parent/'app-audit/lib/data/api/merchant_npc_api.dart').read_text()
http=(root/'Core/MerchantNPCHTTP.swift').read_text()
core=(root/'Core/MerchantNPCCoordinators.swift').read_text()
contracts=(root/'Core/MerchantNPCContracts.swift').read_text()
ui=(root/'App/MerchantNPCViews.swift').read_text()
count=0
def check(ok,msg):
 global count
 assert ok,msg
 count+=1
for path in ['/api/ai/npc/merchant-chat','/api/merchant/npc/voice/script','/api/merchant/npc/voice/enroll','/api/merchant/npc/voice/revoke','/api/merchant/npc/avatar/generate']:
 check(path in http and path in source,path)
for key in ['requestId','bizId','message','sampleUrls','imageUrl','style']:
 check('"'+key+'"' in http and "'"+key+"'" in source,key)
check('shop-chat' not in http and 'nodeId' not in http,'merchant identity isolation')
check('merchantRowID.rawValue' in http,'exact row identity')
check('code == 200' in http,'business gate')
check('response.status >= 500' in http,'ambiguous server failures')
check('URLSession' not in http,'no bare live transport')
check('requestID: requestID' in core and 'attempts < 3' in core,'bounded same-ID retries')
check('retryAfterSeconds' in core,'retry delay')
for key in ['server','provider','legal','resourceOwnership','voiceCloning','mediaTransmission']:
 check('var '+key+' = false' in contracts,'default off '+key)
for token in ['consentIndex == 0','script.count == 5','approvedHosts.contains(host)']:
 check(token in contracts,token)
for token in ['reader.document(.assets)','reader.access()','reader.scope == captured','generation == stamp','samples.count == 5','sample.kind == .voiceSample(index: index)','ownsVoice','explicitConsent','outcome != .unknown','value.script == script','voiceStatus == 1','== "PENDING"']:
 check(token in core,token)
check('voice/status' not in http and 'avatar/status' not in http,'reuse existing reads')
for token in ['installMerchantNPC','scope.merchantRowID == row','npcDestination','onDisappear','scenePhase','.privacySensitive()','authorizationFirst','reviewWarning','for: .seconds(5)','task(id: model.coordinator.shouldPoll)']:
 check(token in ui,token)
for token in ['AVAudioRecorder','PhotosPicker','URLSession','uploadOSS']:
 check(token not in ui+http, 'no new capture/upload '+token)
strings=json.loads((root/'Resources/MerchantNPCLocalizations.fragment.json').read_text())['strings']
for key in set(re.findall(r'"(merchantNPC\.[A-Za-z]+)"',ui)) - {'merchantNPC.input','merchantNPC.reply','merchantNPC.error'}:
 check(key in strings,'localized '+key)
 for lang in ['en','zh-Hans']: check(lang in strings[key]['localizations'], key+' '+lang)
for token in ['revokeWriteAuthority()', 'try journal.write(record)', 'try journal.clear(record)', 'OperationDefaultsJournal(defaults: .standard)', 'hasUnresolvedWrite', 'scope.namespace.utf8.count', 'resources:merchant-row:', 'failure == .malformed { failure = .unknownOutcome }']:
 check(token in core,token)
confirm=core.split('public func confirm(_ id: UUID) async')[1]
check(confirm.index('await refresh()') < confirm.index('try journal.write(record)') < confirm.index('client.perform('),'fresh reads and journal before mutation')
refresh=core.split('public func refresh() async')[1].split('public func prepare')[0]
check(refresh.index('revokeWriteAuthority()') < refresh.index('reader.access()'),'refresh revokes before awaiting')
check('revokeWriteAuthority()' in refresh.split('} catch {')[1],'failure revokes authority')
check('namespace: String' in contracts,'required namespace identity')
check('confirmationGeneration == confirmationStamp' in confirm,'consent cancellation during confirmation reads')
print(f'PASS: {count} static source/contract assertions. Apple build and runtime NOT_RUN.')

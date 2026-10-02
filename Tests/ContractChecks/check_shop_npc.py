#!/usr/bin/env python3
"""Static source checks, not execution of Swift or proof of runtime behavior."""
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[2]
WORKSPACE=ROOT.parent
checks=0
def check(value, message):
 global checks
 assert value, message
 checks+=1
http=(ROOT/'Core/ShopNPCHTTP.swift').read_text()
model=(ROOT/'Core/ShopNPCContracts.swift').read_text()
state=(ROOT/'Core/ShopNPCCoordinator.swift').read_text()
ui=(ROOT/'App/ShopNPCView.swift').read_text()
voice=(ROOT/'App/ShopNPCVoiceProvider.swift').read_text()
source=(WORKSPACE/'app-audit/lib/data/api/ai_npc_api.dart').read_text()
for path in ['/api/ai/npc/shop-chat','/api/ai/npc/voice-chat']:
 check(path in http and path in source,path)
for field in ['requestId','nodeId','message']:
 check(field in http and "'"+field+"'" in source,field)
check('body[\'asr\'] as String?' in source,'top-level source ASR')
check('asr: voice ? body.asr : nil' in model,'top-level native ASR')
check('safe.isEmpty ? body.data?.text' in model,'safe text fallback')
check('code == 200' in model,'business envelope gate')
for value in ['sessionID','accountID','roleID','accessRevision','nodeID']:
 check('let '+value in model,'scope '+value)
for value in ['server','provider','legal','access','voiceTransmission','voiceFormatVerified','microphone','playback']:
 check('var '+value+' = false' in model,'default off '+value)
for token in ['epoch == stamp','scope == review.scope','guard active','pending = nil','messages = []','case .voice','replacing','lastSend','review.id']:
 check(token in state,'coordinator '+token)
check('uploadOSS' not in http,'no OSS route')
check('URLSession' not in http,'no bare transport')
check('voice.m4a' in http,'truthful filename')
for token in ['AVAudioRecorder','16000','32000','AVNumberOfChannelsKey: 1','record(forDuration: 60)','removeItem','recordPermission == .granted','grants.voiceAllowed, grants.microphone']:
 check(token in voice,'voice '+token)
check('requestRecordPermission' not in voice,'no implicit permission request')
for token in ['onDisappear','scenePhase','privacySensitive','shopNPC.confirmSend','shopNPC.reviewText','shopNPC.record','textSelection','Text(verbatim: message)']:
 check(token in ui,'UI '+token)
check('merchantId' not in http,'no merchant identity conversion')
check('unavailableInSource' in model,'no invented audio')
strings=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())['strings']
for key in set(re.findall(r'"(shopNPC\.[A-Za-z]+)"',ui+model)) - {'shopNPC.error','shopNPC.input'}:
 check(key in strings,'localized '+key)
 for lang in ['en','zh-Hans']:check(lang in strings[key]['localizations'],key+' '+lang)
check(len(re.findall(r'func test', (ROOT/'Tests/CoreTests/ShopNPCTests.swift').read_text()))==23,'core test count')
check(len(re.findall(r'func test', (ROOT/'Tests/AppUITests/ShopNPCFlowTests.swift').read_text()))==4,'UI test count')
print(f'PASS: {checks} static source/contract assertions; Swift execution and Apple runtime NOT_RUN')

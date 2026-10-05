#!/usr/bin/env python3
"""Structural evidence only; not Swift typechecking or Apple runtime."""
from pathlib import Path
import json,re,sys
root=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
core=(root/'Core/MerchantNPCVoiceSamples.swift').read_text()
upload=(root/'Core/MerchantNPCVoiceUpload.swift').read_text()
device=(root/'App/MerchantNPCVoiceDevice.swift').read_text()
view=(root/'App/MerchantNPCVoiceSamplesView.swift').read_text()
host=(root/'App/MerchantNPCViews.swift').read_text()
assert 'journal.write(record)' in core and core.index('journal.write(record)')<core.index('uploader.upload(clip')
assert 'resources.prepare(.enroll' in core and 'resources.refresh()' in core
assert 'resources:merchant-row:' in core and 'merchant-npc:' in core
assert 'index == 0 || clips[0] != nil' in core
assert 'if let clip = try device.finish()' in core
assert 'configuration: MerchantNPCVoiceConfiguration? = nil' in core
assert 'enabled: Bool = false' in upload and 'enabled: @escaping () -> Bool = { false }' in device
assert 'api/common/uploadOSS' in upload and 'json["url"] as? String' in upload
assert 'sampleUrls' not in upload and 'shop-chat' not in upload
assert 'requestRecordPermission' in device and 'AVAudioSession.interruptionNotification' in device
assert '.protectionKey: FileProtectionType.complete' in device
assert 'voiceSamples?.invalidate()' in host and 'imageContext?.picker.cancel()' in host
assert 'currentScope' in upload and 'grants() == policy' in upload
assert 'scenePhase' in view and '.privacySensitive()' in view
catalog=json.loads((root/'Resources/MerchantNPCVoiceSamples.fragment.json').read_text())['strings']
for key in set(re.findall(r'(?:Text|Button|Toggle|Section|ProgressView)\("(merchantVoice\.[A-Za-z]+)"',view)):
    assert key in catalog,key
for entry in catalog.values():
    assert set(entry['localizations'])=={'en','zh-Hans'}


assert "transport: any HTTPTransport = ResponseLimitedHTTPTransport()" in upload
assert "URLSessionTransport()" not in upload

print('PASS MerchantNPC voice samples source checks (structural only)')

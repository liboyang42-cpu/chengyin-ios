#!/usr/bin/env python3
"""Source-contract checks only, not execution of Swift/OS adapters."""
import json
from pathlib import Path
r=Path(__file__).resolve().parents[1]
a=(r/'Core/PlatformAudioPlayback.swift').read_text()
m=(r/'Core/PlatformExternalMaps.swift').read_text()
n=(r/'App/NativePlatformAdapters.swift').read_text()
v=(r/'App/PlatformConsumerViews.swift').read_text()
checks = {
    'default-off audio': 'enabled: Bool = false' in a,
    'default-off maps': 'enabled: Bool = false' in m,
    'stale callbacks fenced': 'self.generation == token' in a and 'token == generation' in m,
    'HTTPS origins explicit': 'approvedOrigins.contains(origin)' in a and 'url.user == nil' in a,
    'redirect checked': 'willPerformHTTPRedirection' in n and 'policy.allows($0)' in n,
    'bounded media': '20 * 1024 * 1024' in n and 'bytes.count + data.count <= limit' in n,
    'ephemeral media': 'URLSessionConfiguration.ephemeral' in n and 'urlCredentialStorage = nil' in n,
    'lifecycle hooks': all(x in v for x in ['.onDisappear', '.onChange(of: scenePhase)', '.onChange(of: source)', '.onChange(of: scope)']),
    'no permission request': all(x not in n for x in ['requestRecordPermission','requestWhenInUseAuthorization','CLLocationManager(']),
    'no gameplay mutations': all(x not in a+n+v for x in ['completeTask(', 'submitProof(', 'claimReward(']),
    'map branches distinct': all(x in m for x in ['noCoordinates','launchFailed','copyFailed','copied']),
    'finite coordinate validation': 'latitude.isFinite' in m and 'abs(latitude) <= 90' in m,
    'adapters concrete': 'AVAudioPlayer(data: data)' in n and 'item.openInMaps' in n,
}
chapter=(r/'Core/PlatformChapterAudioBridge.swift').read_text()
patch=(r/'docs/community-media-templates/chapter-audio-reader.patch').read_text()
checks.update({
    'chapter same-response decoder': 'audioURL = try c.decodeIfPresent(String.self, forKey: .audioUrl)' in patch,
    'chapter authoritative visibility': 'snapshot.visibleNodes.first' in chapter and '!snapshot.isLocked(node)' in chapter,
    'chapter exact identity': 'node.chapterID' in chapter and '$0.id == chapterID' in chapter,
    'chapter current session': 'currentRead' in chapter and 'loadedSession == currentSession()' in patch,
})
catalog=json.loads((r/'Resources/Localizable.xcstrings').read_text())
checks['bilingual catalog']=all(set(x['localizations']) == {'en','zh-Hans'} for x in catalog['strings'].values())
for k,passed in checks.items(): print(('PASS' if passed else 'FAIL')+' '+k)
assert all(checks.values())
print(f'{len(checks)} source-contract checks passed; Swift tests and OS runtime NOT_RUN')

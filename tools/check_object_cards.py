#!/usr/bin/env python3
"""Supplementary source contracts, NOT Swift typechecking or runtime evidence."""
import json,re,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=root.parent/'app-audit'
def read(p): return p.read_text()
checks=[]
def check(name, truth):
    checks.append(bool(truth)); print(('PASS ' if truth else 'FAIL ')+name)
contracts=read(root/'Core/ObjectCardContracts.swift')
service=read(root/'Core/ObjectCardReading.swift')
media=read(root/'Core/ObjectCardMedia.swift')
views=read(root/'App/ObjectCardViews.swift')
model=read(root/'Core/ObjectCardCollectionModel.swift')
source_api=read(source/'lib/data/api/object_card_api.dart')
check('source route + fixed latest-40 form contract', all(v in source_api for v in ['/api/object-card/list', "'pageNum': 1", "'pageSize': 40", 'formUrlEncodedContentType']) and all(v in service for v in ['api/object-card/list','pageNum=1&pageSize=40&category=','application/x-www-form-urlencoded']))
check('owner from JWT; no owner parameter', 'userId' not in service and 'token: session.token' in service)
check('account epoch + full credential snapshots', all(v in service for v in ['let epoch: UInt64','currentSession() == session','scope == captured','throw CancellationError()']))
check('failed filter retains last success', 'collection = result; category = next; loadedScope = scope' in model and 'failed = true; loadedScope = scope' in model)
check('frame cycling; no 3D imports', 'frames.count > 1' in contracts and '.accessibilityAdjustableAction' in views and 'objects.frame.previous' in views and not any(v in ''.join(read(p) for p in root.rglob('*.swift')) for v in ['import SceneKit','import RealityKit','WKWebView']))
check('media default dormant and no AsyncImage', 'var media: (any ObjectCardImageLoading)? = nil' in views and 'AsyncImage(' not in views)
check('streaming byte bound and redirects denied', 'ObjectCardMediaPolicy.maximumBytes - bytes.count' in media and 'completionHandler(nil)' in media and 'config.httpCookieStorage = nil' in media and 'config.urlCredentialStorage = nil' in media)
check('decode pixel bound and stale pixel guard', '32_000_000' in views and 'loadedKey == key' in views and 'run == generation' in views and 'currentScope() == expectedScope' in views)
check('source contains no bundled 3D asset', not any(p.suffix.lower() in ['.glb','.gltf','.usdz','.scn','.obj'] for p in source.rglob('*') if p.is_file()))
catalog=json.loads(read(root/'Resources/ObjectCardLocalizations.fragment.json'))['strings']
keys=set(re.findall(r'"(objects\.[A-Za-z][A-Za-z0-9.]*)"', ''.join(read(p) for p in (root/'App').glob('*.swift'))))
# Dynamic keys and accessibility identifiers are not localization strings.
keys={k for k in keys if not any(k.startswith(prefix) for prefix in ['objects.card.','objects.fixture.','objects.frame.','objects.badge.']) and k not in ['objects.filter','objects.detail','objects.collection','objects.rarity.','objects.track.']}
check('literal UI keys bilingual', all(k in catalog and set(catalog[k]['localizations']) == {'en','zh-Hans'} for k in keys))
check('dynamic categories, tracks, rarity bilingual', all(f'objects.{family}.{i}' in catalog for family,n in [('category',9),('track',5),('rarity',5)] for i in range(n)))
check('Swift + UI test cases authored', 'testStaleUnauthorizedCannotExpireNewSession' in read(root/'Tests/CoreTests/ObjectCardTests.swift') and 'testCollectionCapAndAccessibleFrames' in read(root/'Tests/AppUITests/ObjectCardFlowTests.swift'))
print(f'{sum(checks)}/{len(checks)} source checks passed; Swift/Xcode/device: NOT_RUN')
sys.exit(0 if all(checks) else 1)

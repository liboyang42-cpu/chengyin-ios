#!/usr/bin/env python3
"""Source assertions only; do not substitute for Swift/Apple runtime tests."""
from pathlib import Path
import json
root = Path(__file__).resolve().parents[1]
def source(path): return (root / path).read_text()
host = source('App/SessionPlayRuntimeView.swift')
session = source('App/AppSession.swift')
for factory in ['deviceModel:', 'playerModel:', 'circleModel:']: assert factory in host, factory
for cache in ['retainedPlayPlayers', 'retainedPlayCircles', 'retainedPlayDevices']: assert cache in session
assert 'PlayNativeDeviceProvider(grants: [])' in session
assert 'api?.enabled.contains(.mediaUpload) == true' in session
assert '\\(gate.currentStamp)' in session
photo = source('Core/PlayPhotoEvidence.swift')
for contract in ['api/common/uploadOSS', 'name=\\"file\\"', 'envelope?["url"].text', 'enabled.contains(.mediaUpload)', 'transport.send(request)']: assert contract in photo, contract
assert photo.count('transport.send(request)') == 1
assert 'URLSession' not in photo
provider = source('App/PlayNativeDeviceProvider.swift')
for adapter in ['UIImagePickerController', 'VNDetectBarcodesRequest', 'CLLocationManager', 'CMMotionManager', 'CIColorMatrix']: assert adapter in provider
assert 'coordinateSystem: "WGS84"' in provider
assert 'coordinateSystem: "GCJ02"' not in provider
assert 'case .ar:' not in provider
coordinator = source('Core/PlayDeviceTasks.swift')
assert 'current() == context' in coordinator and 'self.generation == generation' in coordinator
assert 'public func reviewedPhoto()' in coordinator
ui = source('App/PlayDeviceTaskViews.swift')
for key in ['playhost.photo.upload', 'playhost.photo.review', 'model.reviewedPhoto()', 'model.cancel()']: assert key in ui
strings = json.loads(source('docs/play-runtime-hosts/localizations.json'))
for key, values in strings.items(): assert values.get('en') and values.get('zh-Hans'), key
print('PASS: normal host, retained identity scope, upload source shape, concrete dormant adapters, separate review, bilingual strings')
print('Apple compile/device/UI and Swift XCTest: NOT_RUN')

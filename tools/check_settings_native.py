#!/usr/bin/env python3
"""Source/static checks only. Never a Swift/Xcode/runtime claim."""
import argparse, json, pathlib, re, subprocess, sys
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1])
parser.add_argument('--flutter-root', type=pathlib.Path, required=True)
args = parser.parse_args()
root = args.root.resolve()
subprocess.run([sys.executable, str(root/'tools/extract_settings_legal.py'), '--source', str(args.flutter_root/'lib/feature/legal/legal_docs.dart'), '--output', str(root/'Core/SettingsSourceLegalCatalog.swift'), '--check'], check=True)
entries = json.loads((root/'docs/settings-native-localizations.json').read_text())
keys = {r['key'] for r in entries}
assert len(keys) == len(entries), 'duplicate localization key'
assert all(r.get('en') and r.get('zh-Hans') for r in entries), 'incomplete localization'
app = '\n'.join((root/'App'/name).read_text() for name in ['SettingsAboutView.swift','SettingsFixtureSupport.swift','SettingsLegalDocumentView.swift','SettingsSupportSections.swift'])
core = '\n'.join(p.read_text() for p in (root/'Core').glob('Settings*.swift'))
# Interpolated accessibility IDs are intentionally excluded; dynamic label keys are expanded below.
literal = set(re.findall(r'(?:Text|Label|Button|ProgressView|Section|LabeledContent|appNavigationTitle)\("(settingsNative\.[^"\\]+)"', app))
dynamic = {f'settingsNative.sound.{k}' for k in ['sound','haptics','airplane','ocean','raindrop','forest']}
dynamic |= {f'settingsNative.legal.{k}' for k in ['user_agreement','privacy_policy','cancellation_notice','pendingSourceText','regionalTextNotProvided','missingMarket']}
dynamic |= {f'settingsNative.blocked.{feature}.{part}' for feature in ['locationConsent','marketingConsent','accountDeletion'] for part in ['title','message']}
dynamic |= {'settingsNative.sound.loadFailed','settingsNative.sound.saveFailed'}
assert not (literal|dynamic)-keys, f'missing labels: {(literal|dynamic)-keys}'
for forbidden in ['URLSession', 'openURL', 'UIApplication.shared', 'CLLocationManager', 'AVAudioSession', 'UIImpactFeedbackGenerator', 'URLRequest', 'AuthRequestBuilder', 'revokeRoamLocationConsent', 'setMarketingConsent']:
    assert forbidden not in app+core, f'Unexpected live side-effect surface: {forbidden}'
assert '@AppStorage' not in app, 'module must not duplicate language storage'
assert '.accept(' not in app+core and 'func accept' not in app+core
assert '1.0.0' not in (root/'App/SettingsAboutView.swift').read_text(), 'hardcoded Flutter version'
source = (args.flutter_root/'lib/feature/settings/settings_page.dart').read_text()
for literal in re.findall(r'(?:title|detail|sourceURL): "([^"\n]+)"', (root/'Core/SettingsAboutContracts.swift').read_text()):
    assert literal in source, f'attribution differs from source: {literal}'
unit = (root/'Tests/CoreTests/SettingsNativeTests.swift').read_text()
ui = (root/'Tests/AppUITests/SettingsNativeFlowTests.swift').read_text()
unit_count=len(re.findall(r'func test\w+\(', unit)); ui_count=len(re.findall(r'func test\w+\(', ui))
print(f'PASS module static boundaries, {len(keys)} EN/ZH labels, exact source attribution')
print(f'AUTHORED ONLY: {unit_count} XCTest cases and {ui_count} XCUITest cases')
print('NOT_RUN: Swift typecheck/build, XCTest execution, simulator UI, device, network, legal acceptance')

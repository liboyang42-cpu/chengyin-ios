#!/usr/bin/env python3
"""Apple CI: require the actual source-built GLTFKit2 framework in the app.

Offline symbol/load-command inspection, never executes app code or opens a device.
The app-hosted synthetic decoder XCTest remains the runtime counterpart.
"""
import argparse,pathlib,plistlib,re,subprocess
parser=argparse.ArgumentParser();parser.add_argument('--app',type=pathlib.Path,required=True);args=parser.parse_args()
app=args.app
with (app/'Info.plist').open('rb') as stream:info=plistlib.load(stream)
executable=app/info['CFBundleExecutable']
framework=app/'Frameworks/GLTFKit2.framework'
binary=framework/'GLTFKit2'
assert binary.is_file(),f'Actual embedded GLTFKit2 framework missing: {binary}'
assert (app/'GLTFKit2Notices.txt').is_file(),'Required MIT third-party notice missing'
assert (framework/'PrivacyInfo.xcprivacy').is_file(),'Framework privacy manifest missing'
def run(*args):return subprocess.run(['xcrun',*args],check=True,text=True,capture_output=True).stdout
symbols=run('nm','-g',str(binary))
for symbol in ['_OBJC_CLASS_$_GLTFAsset','_OBJC_CLASS_$_GLTFSCNSceneSource']:
    assert symbol in symbols,f'Real decoder symbol missing: {symbol}'
assert not re.search(r'(_ktx[A-Za-z_]|[0-9]basis[ut]|_ZSTD_|[0-9]draco)',symbols),'Optional codec symbols found; stop and review provenance/licenses'
linked=run('otool','-L',str(executable))
assert '@rpath/GLTFKit2.framework/GLTFKit2' in linked,'App does not link GLTFKit2'
print('PASS: app links and embeds actual GLTFKit2 framework, required notices/privacy manifest; no optional codec symbols')

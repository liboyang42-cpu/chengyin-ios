#!/usr/bin/env python3
"""Offline audit of pinned GLTFKit2 source; does not fetch or execute dependencies."""
import hashlib,json,pathlib,re,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
VENDOR=ROOT/'Vendor/GLTFKit2'
pin=json.loads((VENDOR/'PROVENANCE.json').read_text())
assert pin['revision']=='e69e354c4f31ea07b7816b8cbe2ddb28e897d073'
assert pin['sourceOnly'] is True
for row in pin['files']:
    raw=(VENDOR/row['path']).read_bytes()
    assert hashlib.sha256(raw).hexdigest()==row['sha256'],row['path']
    assert hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()==row['gitBlob'],row['path']
project=(VENDOR/'GLTFKit2.xcodeproj/project.pbxproj').read_text()
for forbidden in ['PBXShellScriptBuildPhase','XCRemoteSwiftPackageReference','ktx.xcframework','GLTF_BUILD_WITH_KTX2']:
    assert forbidden not in project,forbidden
for path in VENDOR.rglob('*'):
    assert path.suffix not in ['.a','.dylib','.zip','.xcframework'],path
notices=(ROOT/'Resources/GLTFKit2Notices.txt').read_text()
for author in ['Warren Moore','Johannes Kuhlmann','Serge A. Zaitsev']:assert author in notices
app=(ROOT/'App/PlayKitGLBAssets.swift').read_text()
assert 'import GLTFKit2' in app and 'canImport(GLTFKit2)' not in app
assert 'GLTFAsset.load(with: data' in app
print(f'PASS: {len(pin["files"])} official source files match immutable Git blobs and SHA256; MIT notices present; no optional binary codecs/scripts')

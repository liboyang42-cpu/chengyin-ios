#!/usr/bin/env python3
"""Apple CI: require the actual source-built GLTFKit2 framework in the app.

Offline symbol/load-command inspection, never executes app code or opens a device.
The app-hosted synthetic decoder XCTest remains the runtime counterpart.
Apple's Debug layout puts application code in <executable>.debug.dylib:
https://developer.apple.com/documentation/xcode/understanding-build-product-layout-changes
"""
import argparse,pathlib,plistlib,re,subprocess

GLTF_INSTALL_NAME='@rpath/GLTFKit2.framework/GLTFKit2'
DECODER_SYMBOLS=('_OBJC_CLASS_$_GLTFAsset','_OBJC_CLASS_$_GLTFSCNSceneSource')
OPTIONAL_CODECS=r'(_ktx[A-Za-z_]|[0-9]basis[ut]|_ZSTD_|[0-9]draco)'

def run(*args):
    return subprocess.run(['xcrun',*args],check=True,text=True,capture_output=True).stdout

def architectures(binary,command):
    result=command('lipo','-archs',str(binary)).split()
    assert result and all(re.fullmatch(r'[A-Za-z0-9_]+',arch) for arch in result),f'Invalid architecture inventory: {binary}'
    return set(result)

def libraries(binary,arch,command):
    output=command('otool','-arch',arch,'-L',str(binary))
    # Match actual dependency entries, not a substring in a heading/file name.
    return set(re.findall(r'^\s+(\S+)\s+\(compatibility version ',output,re.M))

def verify(app,command=run):
    with (app/'Info.plist').open('rb') as stream:info=plistlib.load(stream)
    name=info['CFBundleExecutable']
    assert isinstance(name,str) and name not in ('','.','..') and pathlib.Path(name).name==name,'Invalid app executable name'
    executable=app/name
    assert executable.is_file(),f'App executable missing: {executable}'
    framework=app/'Frameworks/GLTFKit2.framework'
    binary=framework/'GLTFKit2'
    assert binary.is_file(),f'Actual embedded GLTFKit2 framework missing: {binary}'
    assert (app/'GLTFKit2Notices.txt').is_file(),'Required MIT third-party notice missing'
    assert (framework/'PrivacyInfo.xcprivacy').is_file(),'Framework privacy manifest missing'
    app_archs=architectures(executable,command)
    assert app_archs <= architectures(binary,command),'Embedded GLTFKit2 is missing an app architecture'
    verified=[]
    for arch in sorted(app_archs):
        symbols=command('nm','-arch',arch,'-g',str(binary))
        for symbol in DECODER_SYMBOLS:
            assert re.search(r'^\s*[0-9a-fA-F]+\s+[A-Za-z]\s+'+re.escape(symbol)+r'\s*$',symbols,re.M),f'Real decoder definition missing ({arch}): {symbol}'
        assert not re.search(OPTIONAL_CODECS,symbols),'Optional codec symbols found; stop and review provenance/licenses'
        main_links=libraries(executable,arch,command)
        if GLTF_INSTALL_NAME in main_links:
            verified.append(f'{arch}: {name} -> GLTFKit2')
            continue
        # Only the exact adjacent dylib actually linked by the launcher qualifies.
        # Merely finding a debug/preview dylib or an embedded framework cannot pass.
        debug_name=name+'.debug.dylib'
        debug=app/debug_name
        expected={'@rpath/'+debug_name,'@executable_path/'+debug_name}
        assert main_links & expected,f'App does not link GLTFKit2 or its exact debug dylib ({arch})'
        assert debug.is_file() and debug.resolve().parent==app.resolve(),f'Linked app debug dylib missing or outside bundle: {debug}'
        assert arch in architectures(debug,command),f'Linked debug dylib is missing app architecture: {arch}'
        assert GLTF_INSTALL_NAME in libraries(debug,arch,command),f'App debug dylib does not link GLTFKit2 ({arch})'
        verified.append(f'{arch}: {name} -> {debug_name} -> GLTFKit2')
    print('PASS: actual GLTFKit2 link/embed, decoder definitions, notices/privacy and no optional codecs; '+'; '.join(verified))
    return verified

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--app',type=pathlib.Path,required=True)
    verify(parser.parse_args().app)

if __name__=='__main__':main()

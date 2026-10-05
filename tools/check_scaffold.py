#!/usr/bin/env python3
"""Offline structural checks, NOT a Swift compiler or runtime test."""
import hashlib, json, pathlib, re, subprocess, xml.etree.ElementTree as ET
ROOT=pathlib.Path(__file__).resolve().parents[1]
# Independent parser for the generated OpenStep subset (quoted keys/values, integers).
def parse_project(text):
    text=re.sub(r'^//.*$', '', text, flags=re.M)
    tokens=re.findall(r'"(?:\\.|[^"\\])*"|\d+|[{}()=;,]', text)
    index=0
    def take(expected=None):
        nonlocal index
        value=tokens[index]; index+=1
        if expected is not None: assert value==expected, (value,expected)
        return value
    def value():
        token=take()
        if token=='{':
            result={}
            while tokens[index]!='}':
                key=json.loads(take()); take('='); result[key]=value(); take(';')
            take('}'); return result
        if token=='(':
            result=[]
            while tokens[index]!=')': result.append(value()); take(',')
            take(')'); return result
        return json.loads(token)
    result=value(); assert index==len(tokens); return result
project_path=ROOT/'Questify.xcodeproj/project.pbxproj'
project=parse_project(project_path.read_text())
objects=project['objects']; project_obj=objects[project['rootObject']]
assert project_obj['isa']=='PBXProject'
refs={'baseConfigurationReference','buildConfigurationList','fileRef','mainGroup','productRefGroup','productReference','target','targetProxy','containerPortal','remoteGlobalIDString','remoteRef'}
list_refs={'buildConfigurations','buildPhases','children','dependencies','files','targets'}
for key,obj in objects.items():
    for k,v in obj.items():
        if k=='remoteGlobalIDString' and objects[obj['containerPortal']]['isa']=='PBXFileReference':
            reference=objects[obj['containerPortal']]
            assert reference.get('lastKnownFileType')=='wrapper.pb-project',reference
            upstream=(ROOT/reference['path']/'project.pbxproj').read_text()
            assert re.search(r'\b'+re.escape(v)+r'\s*/\*[^*]+\*/\s*=\s*\{',upstream),(key,k,v)
        elif k in refs: assert v in objects,(key,k,v)
        if k in list_refs:
            for ref in v: assert ref in objects,(key,k,ref)
    if obj['isa']=='PBXFileReference' and obj['sourceTree']=='<group>':
        if obj.get('lastKnownFileType')=='wrapper.pb-project':
            assert (ROOT/obj['path']/'project.pbxproj').is_file(),obj['path']
        else: assert (ROOT/obj['path']).is_file(),obj['path']
source_paths={o['path'] for o in objects.values() if o['isa']=='PBXFileReference' and o.get('lastKnownFileType')=='sourcecode.swift'}
assert source_paths=={str(p.relative_to(ROOT)) for folder in ['App','Core','Tests/AppUITests','Tests/AppUnitTests'] for p in (ROOT/folder).rglob('*.swift')}
catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())
assert catalog['sourceLanguage']=='en'
for key,entry in catalog['strings'].items():
    assert set(entry['localizations'])=={'en','zh-Hans'},key
    for lang in ['en','zh-Hans']:
        unit=entry['localizations'][lang]['stringUnit']
        assert unit['state']=='translated' and unit['value'].strip(),(key,lang)
ui='\n'.join(p.read_text() for p in (ROOT/'App').glob('*.swift'))
# Every dot-separated UI string is a localized key except explicit accessibility/storage IDs.
localizable_ui=re.sub(r'\.accessibilityIdentifier\("(?:\\.|[^"\\])*"\)', '', ui)
localizable_ui=re.sub(r'(?:accessibilityPrefix|identifier):\s*"(?:\\.|[^"\\])*"','',localizable_ui)
localizable_ui=re.sub(r'\.accessibilityIdentifier\s*=\s*"(?:\\.|[^"\\])*"', '', localizable_ui)
localizable_ui=re.sub(r'(?:systemImage|systemName):\s*"(?:\\.|[^"\\])*"', '', localizable_ui)
keys=set(re.findall(r'"((?:welcome|role|registration|settings|language|action|auth|account|activity|scanner|discovery|profile|merchant|club|roam|messaging|participant|play|message|topic|region|homeFeed|usApple|ticketWallet|square|cooperation|accountCollection|creatorContent|growth|official|officialAction|projectEdit|nearby|team|orderLifecycle|templateAuthor|publishModes|wallet|couponManagement|im)\.[A-Za-z0-9.]+)"',localizable_ui))
keys={key for key in keys if not key.endswith('.')}  # Prefixes concatenate a separately validated dynamic key.
assert not keys-set(catalog['strings']),keys-set(catalog['strings'])
# SwiftUI environment locale does not implicitly change Foundation String(localized:).
# Production computed labels must use LocalizedStringResource/appLocalized for lookup.
for source in (ROOT/'App').glob('*.swift'):
    if 'Fixture' in source.name: continue  # Synthetic server messages are verbatim test data.
    assert not re.search(r'LocalizedStringKey\("[^"\n]*\\\(',source.read_text()), source.name
    missing_locale=re.findall(r'String\(localized:\s*"[^"\n]*"',source.read_text())
    assert not missing_locale,(source.name,missing_locale)
assert 'preferences.language' in ui
assert not any(p.suffix in {'.p8','.p12','.mobileprovision'} for p in ROOT.rglob('*'))
config=(ROOT/'Config/Base.xcconfig').read_text()
assert 'invalid.example.questify.ios' in config
assert 'NSAllowsArbitraryLoads' not in config
scheme=ET.parse(ROOT/'Questify.xcodeproj/xcshareddata/xcschemes/Questify.xcscheme')
for ref in scheme.iter('BuildableReference'): assert ref.attrib['BlueprintIdentifier'] in objects
before=hashlib.sha256(project_path.read_bytes()).hexdigest()
subprocess.run(['python3',str(ROOT/'tools/generate_project.py')],check=True,capture_output=True)
assert hashlib.sha256(project_path.read_bytes()).hexdigest()==before
print(f'PASS structural checks: {len(source_paths)} Swift source files, {len(catalog["strings"])} bilingual keys, references, scheme, deterministic regeneration')
print('SCOPE: this script does not run Swift/Xcode, previews, simulator/device, accessibility or live backend checks; see separate evidence')

#!/usr/bin/env python3
"""Offline structural checks, NOT a Swift compiler or runtime test."""
import hashlib, json, pathlib, re, shutil, subprocess, tempfile, xml.etree.ElementTree as ET
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
def validate_bilingual_catalog(catalog, table, allowed_source_languages=('en',)):
    """Keep the same complete, translated English/Simplified-Chinese contract."""
    assert catalog['sourceLanguage'] in allowed_source_languages, table
    for key,entry in catalog['strings'].items():
        assert set(entry['localizations'])=={'en','zh-Hans'}, (table,key)
        for lang in ['en','zh-Hans']:
            unit=entry['localizations'][lang]['stringUnit']
            assert unit['state']=='translated' and unit['value'].strip(), (table,key,lang)
    return set(catalog['strings'])

def validate_literal_text_tables(source, root, objects, project_obj):
    """Validate this narrow literal Text overload, never union tables globally.

    Dynamic keys/tables, interpolation and explicit bundles are not exemptions:
    they remain in the original default-table scan. A table must be a unique
    catalog in the app's actual resource build phase, not just a file reference.
    """
    pattern=re.compile(r'(?<![\w.])Text\s*\(\s*"([A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+)"\s*,\s*tableName\s*:\s*"([A-Za-z0-9_]+)"\s*\)')
    matches=list(pattern.finditer(source))
    if not matches: return source
    applications=[objects[t] for t in project_obj['targets']
                  if objects[t].get('productType')=='com.apple.product-type.application']
    assert len(applications)==1, 'Explicit Text table requires one known application target'
    registered={}
    for phase_id in applications[0]['buildPhases']:
        phase=objects[phase_id]
        if phase['isa']!='PBXResourcesBuildPhase': continue
        for build_id in phase['files']:
            ref=objects[objects[build_id]['fileRef']]
            path=pathlib.PurePosixPath(ref.get('path',''))
            if path.suffix!='.xcstrings': continue
            assert ref.get('sourceTree')=='<group>' and not path.is_absolute() and '..' not in path.parts, ('Invalid catalog resource path',str(path))
            registered.setdefault(path.stem,[]).append(path)
    tables={}
    def checked(match):
        key,table=match.groups()
        if table not in tables:
            paths=registered.get(table,[])
            assert len(paths)==1, ('Explicit Text table is absent or ambiguous in app resources',table)
            path=root/paths[0]
            assert path.is_file() and path.resolve().is_relative_to(root.resolve()), ('Catalog is outside source root',table)
            tables[table]=validate_bilingual_catalog(json.loads(path.read_text()),table,('en','zh-Hans'))
        assert key in tables[table], ('Missing key in explicit Text table',table,key)
        # Mask only this validated key occurrence; an identical default Text
        # elsewhere still has to pass the original Localizable-key assertion.
        start,end=match.span(1)
        return match.group(0)[:start-match.start()]+match.group(0)[end-match.start():]
    return pattern.sub(checked,source)

def validate_literal_resource_tables(source, root, objects, project_obj):
    """Prove only a literal, locale-bound Foundation String resource lookup.

    Keep unsupported call shapes in the original default-key scan: no dynamic
    table/key, interpolation, extra bundle, qualified call or locale expression.
    All table/key/resource/bilingual checks belong to the unchanged Text helper.
    """
    pattern=re.compile(r'(?<![\w.])String\s*\(\s*localized\s*:\s*LocalizedStringResource\s*\(\s*"([A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+)"\s*,\s*table\s*:\s*"([A-Za-z0-9_]+)"\s*,\s*locale\s*:\s*[A-Za-z_][A-Za-z0-9_]*\s*\)\s*\)')
    def checked(match):
        key,table=match.groups()
        literal='Text('+json.dumps(key)+', tableName: '+json.dumps(table)+')'
        assert validate_literal_text_tables(literal,root,objects,project_obj)!=literal
        # Mask this key occurrence alone. Default Text or any unproven lookup
        # using the same key must still pass the original Localizable gate.
        start,end=match.span(1)
        return match.group(0)[:start-match.start()]+match.group(0)[end-match.start():]
    return pattern.sub(checked,source)

def validate_bound_participant_issue_tables(source, root, objects, project_obj):
    """Prove one closed dynamic lookup shape; never exempt arbitrary dynamic tables.

    An immutable ParticipantScreenIssue.key is bound to a literal table in the
    same single-line switch case. Its renderer must forward those exact fields.
    Unsupported mutations/renderers fail closed. Only the proven assignment
    occurrence is masked; default Text using the same key is still checked.
    """
    declarations=list(re.finditer(r'^struct ParticipantScreenIssue\s*\{\n(?P<body>.*?)^\}', source, re.M | re.S))
    if not declarations: return source
    assert len(declarations)==1, 'Ambiguous ParticipantScreenIssue binding'
    declaration=declarations[0]; body=declaration.group('body')
    pairs=list(re.finditer(r'^\s*case\s+\.[A-Za-z0-9_]+:\s*key\s*=\s*"(?P<key>[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+)";\s*tableName\s*=\s*"(?P<table>[A-Za-z0-9_]+)"[ \t]*$', body, re.M))
    if not pairs: return source
    assert '/*' not in body and '//' not in body, 'Unsupported comments in dynamic issue binding'
    assert re.search(r'^\s*let key:\s*String\s*$',body,re.M), 'Issue key must remain immutable'
    assert re.search(r'^\s*private\(set\) var tableName:\s*String\?\s*=\s*nil\s*$',body,re.M), 'Issue table must start nil and have a private setter'
    assert len(re.findall(r'\btableName\b',body))==len(pairs)+1, 'Unproven issue table mutation or use'
    switches=list(re.finditer(r'\bswitch block\s*\{(?P<cases>[^{}]*)\}',body))
    assert len(switches)==1, 'Expected one closed issue-reason switch'
    switch=switches[0]
    case_pattern=re.compile(r'case\s+\.[A-Za-z0-9_]+:\s*key\s*=\s*"[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+"(?:;\s*tableName\s*=\s*"[A-Za-z0-9_]+")?')
    for line in switch.group('cases').splitlines():
        if line.strip(): assert case_pattern.fullmatch(line.strip()), 'Unsupported issue switch case body'
    assert all(switch.start('cases')<=pair.start('key')<switch.end('cases') for pair in pairs), 'Binding is outside the closed switch'
    renderers=list(re.finditer(r'^struct ParticipantIssueText:\s*View\s*\{\n(?P<body>.*?)^\}',source,re.M | re.S))
    assert len(renderers)==1, 'Expected one ParticipantIssueText renderer'
    renderer=renderers[0].group('body')
    assert '/*' not in renderer and '//' not in renderer, 'Unsupported comments in dynamic issue renderer'
    assert re.search(r'^\s*let issue:\s*ParticipantScreenIssue\s*$',renderer,re.M), 'Renderer must consume the bound issue type'
    call=r'(?<![\w.])Text\s*\(\s*LocalizedStringKey\s*\(\s*issue\.key\s*\)\s*,\s*tableName:\s*issue\.tableName\s*\)'
    assert len(re.findall(call,renderer))==1, 'Renderer must forward the exact key and table without another bundle'
    assert len(re.findall(r'issue\.key\b',renderer))==1 and len(re.findall(r'issue\.tableName\b',renderer))==1, 'Ambiguous dynamic issue lookup'
    spans=[]
    for pair in pairs:
        key,table=pair.group('key','table')
        # Reuse all original resource-membership, unique-table, key and complete
        # bilingual checks, without changing that validator or unioning catalogs.
        literal='Text('+json.dumps(key)+', tableName: '+json.dumps(table)+')'
        assert validate_literal_text_tables(literal,root,objects,project_obj)!=literal
        spans.append((declaration.start('body')+pair.start('key'), declaration.start('body')+pair.end('key')))
    for start,end in reversed(spans): source=source[:start]+source[end:]
    return source

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
# Inspect actual target membership independently of the generator. Swift files
# sharing a basename collide in per-target localization extraction outputs.
for target_id in project_obj['targets']:
    target=objects[target_id]
    by_stem={}
    for phase_id in target['buildPhases']:
        phase=objects[phase_id]
        if phase['isa']!='PBXSourcesBuildPhase': continue
        for build_id in phase['files']:
            ref=objects[objects[build_id]['fileRef']]
            if ref.get('lastKnownFileType')!='sourcecode.swift': continue
            by_stem.setdefault(pathlib.Path(ref['path']).stem.casefold(),[]).append(ref['path'])
    duplicates=[paths for paths in by_stem.values() if len(paths)>1]
    assert not duplicates, ('Duplicate Swift basenames in target',target['name'],duplicates)
catalog=json.loads((ROOT/'Resources/Localizable.xcstrings').read_text())
validate_bilingual_catalog(catalog,'Localizable')
ui='\n'.join(p.read_text() for p in (ROOT/'App').glob('*.swift'))
# Every dot-separated UI string is a localized key except explicit accessibility/storage IDs.
localizable_ui=re.sub(r'\.accessibilityIdentifier\("(?:\\.|[^"\\])*"\)', '', ui)
localizable_ui=re.sub(r'(?:accessibilityPrefix|identifier):\s*"(?:\\.|[^"\\])*"','',localizable_ui)
localizable_ui=re.sub(r'\.accessibilityIdentifier\s*=\s*"(?:\\.|[^"\\])*"', '', localizable_ui)
localizable_ui=re.sub(r'(?:systemImage|systemName):\s*"(?:\\.|[^"\\])*"', '', localizable_ui)
# These four values are explicit nonlocalized identifiers at these exact calls.
# Do not exclude the same strings when used by Text or localization lookup.
localizable_ui=localizable_ui.replace('.accessibilityIdentifier(effectiveReduceMotion ? "roam.motion.status.reduced" : "roam.motion.status.system")', '')
localizable_ui=localizable_ui.replace('.accessibilityIdentifier(snapshot.alwaysAuthorized ? "roam.locationSettings.always.granted" : "roam.locationSettings.always.notGranted")', '')
localizable_ui=localizable_ui.replace('.accessibilityIdentifier(snapshot.servicesEnabled ? "roam.locationSettings.services.enabled" : "roam.locationSettings.services.disabled")', '')
localizable_ui=localizable_ui.replace('.accessibilityIdentifier(result == .copied ? "profile.orderNumberCopy.copied" : "profile.orderNumberCopy.failed")', '')
localizable_ui=localizable_ui.replace('.accessibilityIdentifier(openedOrderID == Int64(id) ? "profile.order.readback.opened.\\(id)" : "profile.order.readback.closed")', '')
localizable_ui=localizable_ui.replace('OfficialReadScreen(reader: reader, isPrivate: true, requestID: "merchant.officialRecruitment",', 'OfficialReadScreen(reader: reader, isPrivate: true,')
localizable_ui=localizable_ui.replace('MerchantTemplateStoryTimelineContent(timeline: timeline, prefix: "merchant.storyTimeline.review")', 'MerchantTemplateStoryTimelineContent(timeline: timeline)')
# Exact computed accessibility IDs only; identical literals in Text still require translations.
localizable_ui=localizable_ui.replace('var accessibilityID: String { switch self { case .history: return "roam.live.pausedHistory.open"; case .settings: return "roam.live.pausedSettings.open"; case .album: return "roam.live.pausedAlbum.open" } }', '')
localizable_ui=validate_bound_participant_issue_tables(localizable_ui,ROOT,objects,project_obj)
localizable_ui=validate_literal_text_tables(localizable_ui,ROOT,objects,project_obj)
localizable_ui=validate_literal_resource_tables(localizable_ui,ROOT,objects,project_obj)
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
def semantic_project(document):
    """Preserve every setting/member while ignoring opaque file IDs/list order."""
    objects=document['objects']; aliases={}
    for key,obj in objects.items():
        if obj['isa']=='PBXFileReference':
            aliases[key]='file:'+json.dumps(obj,sort_keys=True,separators=(',',':'))
    for key,obj in objects.items():
        if obj['isa']=='PBXBuildFile':
            stable={k:(aliases.get(v,v) if k=='fileRef' else v) for k,v in obj.items()}
            aliases[key]='build:'+json.dumps(stable,sort_keys=True,separators=(',',':'))
    assert len(set(aliases.values()))==len(aliases),'Duplicate file/build registration'
    def replace(value):
        if isinstance(value,str): return aliases.get(value,value)
        if isinstance(value,list): return [replace(v) for v in value]
        if isinstance(value,dict): return {aliases.get(k,k):replace(v) for k,v in value.items()}
        return value
    result=replace(document)
    for obj in result['objects'].values():
        field='children' if obj['isa']=='PBXGroup' else 'files' if obj['isa'] in {'PBXSourcesBuildPhase','PBXResourcesBuildPhase'} else None
        if field:
            values=obj[field];assert len(values)==len(set(values)),'Duplicate target/group member';obj[field]=sorted(values)
    return result

# Generate the expected project only in an isolated temporary directory. The
# checkout remains read-only; compare all configs, phases, references and schemes.
before=hashlib.sha256(project_path.read_bytes()).hexdigest()
with tempfile.TemporaryDirectory(prefix='questify-current-scaffold-') as directory:
    scratch=pathlib.Path(directory)
    for name in ('App','Core','Tests','Resources'):(scratch/name).symlink_to(ROOT/name,target_is_directory=True)
    (scratch/'tools').mkdir();shutil.copyfile(ROOT/'tools/generate_project.py',scratch/'tools/generate_project.py')
    subprocess.run(['python3','-B',str(scratch/'tools/generate_project.py')],check=True,capture_output=True)
    expected=parse_project((scratch/'Questify.xcodeproj/project.pbxproj').read_text())
    assert semantic_project(project)==semantic_project(expected),'Current project settings/targets/membership differ from generator'
    for name in ('Questify.xcscheme','QuestifyAppUnitTests.xcscheme'):
        relative='Questify.xcodeproj/xcshareddata/xcschemes/'+name
        assert ET.canonicalize((ROOT/relative).read_text())==ET.canonicalize((scratch/relative).read_text()),('Current scheme differs',name)
assert hashlib.sha256(project_path.read_bytes()).hexdigest()==before
print(f'PASS structural checks: {len(source_paths)} Swift source files, {len(catalog["strings"])} bilingual keys, references, scheme, read-only expected project equivalence')
print('SCOPE: this script does not run Swift/Xcode, previews, simulator/device, accessibility or live backend checks; see separate evidence')

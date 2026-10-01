#!/usr/bin/env python3
"""Generate a dependency-free Xcode project. Does not install tools or invoke Xcode."""
import hashlib, json, pathlib, xml.etree.ElementTree as ET
ROOT = pathlib.Path(__file__).resolve().parents[1]
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
objects = {}
def obj(object_key, **fields):
    key = ident(object_key); objects[key] = fields; return key
sources = sorted([*ROOT.glob('App/*.swift'), *ROOT.glob('Core/*.swift')])
resources = sorted(ROOT.glob('Resources/*.xcstrings'))
refs, source_builds, resource_builds = [], [], []
for path in sources + resources:
    relative = str(path.relative_to(ROOT))
    ref = obj(relative, isa='PBXFileReference', lastKnownFileType='sourcecode.swift' if path.suffix == '.swift' else 'text.json.xcstrings', path=relative, sourceTree='<group>')
    refs.append(ref)
    build = obj('build:'+relative, isa='PBXBuildFile', fileRef=ref)
    (source_builds if path in sources else resource_builds).append(build)
config_ref = obj('base', isa='PBXFileReference', lastKnownFileType='text.xcconfig', path='Config/Base.xcconfig', sourceTree='<group>')
product = obj('product', isa='PBXFileReference', explicitFileType='wrapper.application', includeInIndex=0, path='Questify.app', sourceTree='BUILT_PRODUCTS_DIR')
products = obj('products', isa='PBXGroup', children=[product], name='Products', sourceTree='<group>')
group = obj('main-group', isa='PBXGroup', children=refs+[config_ref,products], sourceTree='<group>')
src_phase=obj('sources',isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=source_builds,runOnlyForDeploymentPostprocessing=0)
res_phase=obj('resources',isa='PBXResourcesBuildPhase',buildActionMask=2147483647,files=resource_builds,runOnlyForDeploymentPostprocessing=0)
framework_phase=obj('frameworks',isa='PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
def configurations(scope):
    configs=[]
    for name in ['Debug','Release']:
        settings = {'SDKROOT':'iphoneos','CLANG_ENABLE_MODULES':'YES'} if scope=='project' else {'PRODUCT_NAME':'$(TARGET_NAME)','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SWIFT_EMIT_LOC_STRINGS':'YES'}
        if scope=='target': settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if name=='Debug' else 'dwarf-with-dsym'})
        if scope=='target' and name=='Debug': settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG $(inherited)'
        extra={'baseConfigurationReference':config_ref} if scope=='target' else {}
        configs.append(obj(scope+name,isa='XCBuildConfiguration',name=name,buildSettings=settings,**extra))
    return obj(scope+'configs',isa='XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
target=obj('target',isa='PBXNativeTarget',buildConfigurationList=configurations('target'),buildPhases=[src_phase,framework_phase,res_phase],buildRules=[],dependencies=[],name='Questify',productName='Questify',productReference=product,productType='com.apple.product-type.application')
ui_files=[]
for path in sorted(ROOT.glob('Tests/AppUITests/*.swift')):
    relative=str(path.relative_to(ROOT))
    ref=obj(relative,isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path=relative,sourceTree='<group>')
    objects[group]['children'].append(ref)
    ui_files.append(obj('build:'+relative,isa='PBXBuildFile',fileRef=ref))
ui_product=obj('ui-product',isa='PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex=0,path='QuestifyUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
objects[products]['children'].append(ui_product)
ui_configs=[]
for name in ['Debug','Release']:
    ui_configs.append(obj('ui'+name,isa='XCBuildConfiguration',name=name,baseConfigurationReference=config_ref,buildSettings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'invalid.example.questify.ios.uitests','TEST_TARGET_NAME':'Questify','SWIFT_OPTIMIZATION_LEVEL':'-Onone','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @loader_path/Frameworks'}))
ui_config_list=obj('uiconfigs',isa='XCConfigurationList',buildConfigurations=ui_configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
ui_sources=obj('ui-sources',isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=ui_files,runOnlyForDeploymentPostprocessing=0)
proxy=obj('ui-proxy',isa='PBXContainerItemProxy',containerPortal=ident('project'),proxyType=1,remoteGlobalIDString=target,remoteInfo='Questify')
dependency=obj('ui-dependency',isa='PBXTargetDependency',target=target,targetProxy=proxy)
ui_target=obj('ui-target',isa='PBXNativeTarget',buildConfigurationList=ui_config_list,buildPhases=[ui_sources],buildRules=[],dependencies=[dependency],name='QuestifyUITests',productName='QuestifyUITests',productReference=ui_product,productType='com.apple.product-type.bundle.ui-testing')
project=obj('project',isa='PBXProject',attributes={'LastUpgradeCheck':'1500','TargetAttributes':{ui_target:{'TestTargetID':target}}},buildConfigurationList=configurations('project'),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','zh-Hans','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target,ui_target])
# OpenStep property list, all strings quoted for deterministic escaping.
def serialize(value, level=0):
    if isinstance(value,dict): return '{\n'+''.join('\t'*(level+1)+json.dumps(k)+' = '+serialize(v,level+1)+';\n' for k,v in value.items())+'\t'*level+'}'
    if isinstance(value,list): return '(\n'+''.join('\t'*(level+1)+serialize(v,level+1)+',\n' for v in value)+'\t'*level+')'
    return str(value) if isinstance(value,int) else json.dumps(value,ensure_ascii=False)
folder=ROOT/'Questify.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
scheme=ET.Element('Scheme',LastUpgradeVersion='1500',version='1.3')
entry={'BuildableIdentifier':'primary','BlueprintIdentifier':target,'BuildableName':'Questify.app','BlueprintName':'Questify','ReferencedContainer':'container:Questify.xcodeproj'}
b=ET.SubElement(scheme,'BuildAction',parallelizeBuildables='YES',buildImplicitDependencies='YES')
e=ET.SubElement(ET.SubElement(b,'BuildActionEntries'),'BuildActionEntry',buildForTesting='YES',buildForRunning='YES',buildForProfiling='YES',buildForArchiving='YES',buildForAnalyzing='YES')
ET.SubElement(e,'BuildableReference',**entry)
ui_entry={'BuildableIdentifier':'primary','BlueprintIdentifier':ui_target,'BuildableName':'QuestifyUITests.xctest','BlueprintName':'QuestifyUITests','ReferencedContainer':'container:Questify.xcodeproj'}
ui_build=ET.SubElement(b.find('BuildActionEntries'),'BuildActionEntry',buildForTesting='YES',buildForRunning='NO',buildForProfiling='NO',buildForArchiving='NO',buildForAnalyzing='NO')
ET.SubElement(ui_build,'BuildableReference',**ui_entry)
test_action=ET.SubElement(scheme,'TestAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',shouldUseLaunchSchemeArgsEnv='YES')
testable=ET.SubElement(ET.SubElement(test_action,'Testables'),'TestableReference',skipped='NO',parallelizable='NO')
ET.SubElement(testable,'BuildableReference',**ui_entry)
l=ET.SubElement(scheme,'LaunchAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',launchStyle='0',useCustomWorkingDirectory='NO',ignoresPersistentStateOnLaunch='NO',debugDocumentVersioning='YES',debugServiceExtension='internal',allowLocationSimulation='YES')
ET.SubElement(ET.SubElement(l,'BuildableProductRunnable',runnableDebuggingMode='0'),'BuildableReference',**entry)
ET.SubElement(scheme,'AnalyzeAction',buildConfiguration='Debug')
ET.SubElement(scheme,'ArchiveAction',buildConfiguration='Release',revealArchiveInOrganizer='YES')
scheme_dir=folder/'xcshareddata/xcschemes';scheme_dir.mkdir(parents=True,exist_ok=True)
ET.indent(scheme)
ET.ElementTree(scheme).write(scheme_dir/'Questify.xcscheme',encoding='utf-8',xml_declaration=True)
print(f'Generated Questify.xcodeproj: {len(sources)} Swift sources, {len(resources)} catalogs')

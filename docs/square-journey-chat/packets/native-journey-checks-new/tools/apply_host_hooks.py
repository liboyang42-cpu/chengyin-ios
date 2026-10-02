#!/usr/bin/env python3
"""Explicit target integration; no implicit shared-checkout mutation. Fails on anchor drift."""
import pathlib,sys,json
packet=pathlib.Path(__file__).resolve().parents[1]
if len(sys.argv)!=2: raise SystemExit('Usage: apply_host_hooks.py /explicit/native/root')
root=pathlib.Path(sys.argv[1]).resolve()
def patch(path, pairs):
 p=root/path;s=p.read_text()
 for old,new in pairs:
  if new in s: continue
  if s.count(old)!=1: raise SystemExit(f'{path}: expected one anchor: {old[:80]}')
  s=s.replace(old,new,1)
 p.write_text(s)
patch('Core/PlayContracts.swift',[
 ('public struct PlayNodesResult: Decodable, Equatable {','public struct PlayNodesResult: Decodable, Equatable {\n    public let eggs: [JourneyEgg]'),
 ('case timeNote, expiresAt, nodes, chapters, routeState','case timeNote, expiresAt, nodes, chapters, routeState, eggs'),
 ('topicID = try c.playInt(.topicId); topicName', 'eggs = JourneyEgg.project((try? c.decode(PlayWireValue.self, forKey: .eggs)) ?? .null)\n        topicID = try c.playInt(.topicId); topicName')])
patch('App/AppSession.swift',[('    private var retainedPlayAdvanced:', (packet/'docs/app-session.snippet.swift.txt').read_text()+'\n    private var retainedPlayAdvanced:')])
patch('App/PlayExperienceView.swift',[
 ('    var prefabModel: PlayPrefabRuntimeCoordinator? = nil','    var prefabModel: PlayPrefabRuntimeCoordinator? = nil\n    var journeyModel: ((Int) -> JourneyCheckCoordinator?)? = nil\n    var ambientModel: JourneyAmbientCoordinator? = nil'),
 ('            if model.snapshot != nil {','            if let ambientModel { PlayAmbientView(model: ambientModel) }\n            if model.snapshot != nil {'),
 ('preference: preferenceModel.flatMap { $0(id) })','preference: preferenceModel.flatMap { $0(id) }, journey: journeyModel.flatMap { $0(id) })'),
 ('    let preference: PlayPreferenceCoordinator?','    let preference: PlayPreferenceCoordinator?\n    let journey: JourneyCheckCoordinator?'),
 ('            if let node {','            if let node {\n                if let journey { PlayJourneyCheckView(model: journey, nodeDone: node.done == true) }'),
 ('.task(id: model.identity) { selectedNode = nil; await model.load(); await model.restoreRun() }', '.task(id: model.identity) { selectedNode = nil; await model.load(); await model.restoreRun(); projectAmbient() }\n        .onChange(of: model.snapshot?.result) { _, _ in projectAmbient() }')])
patch('App/PlayExperienceView.swift',[
 ('    private static var milliseconds:', '    private func projectAmbient() {\n        guard let result = model.snapshot?.result else { return }\n        ambientModel?.project(eggs: result.eggs, topicID: result.topicID)\n    }\n    private static var milliseconds:')])
# Works before/after device host owner adds other named arguments; append at prefab anchor.
patch('App/SessionPlayRuntimeView.swift',[
 ('prefabModel: session.playPrefab(scope: scope))','prefabModel: session.playPrefab(scope: scope),\n                        journeyModel: { session.journeyCheck(scope: scope, topicID: model.snapshot?.result.topicID, nodeID: $0) },\n                        ambientModel: session.journeyAmbient(scope: scope))')])
patch('App/ModuleFixtureSupport.swift',[
 ('    case playExperience\n', '    case playExperience\n    case journeyContent\n'),
 ('            case .playExperience: PlayExperienceFixtureHostView()', '            case .playExperience: PlayExperienceFixtureHostView()\n            case .journeyContent: JourneyContentFixtureHostView()')])
# Merge into the actual default catalog; .strings samples alone are not the app resource.
p=root/'Resources/Localizable.xcstrings';catalog=json.loads(p.read_text())
for key,values in json.loads((packet/'docs/localizations.json').read_text()).items():
 entry={'localizations':{lang:{'stringUnit':{'state':'translated','value':text}} for lang,text in values.items()}}
 if key in catalog['strings'] and catalog['strings'][key]!=entry: raise SystemExit('Catalog key conflict: '+key)
 catalog['strings'][key]=entry
p.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
print('Journey host hooks applied; live capabilities remain default false. Regenerate project and run checks.')

#!/usr/bin/env python3
"""Source contracts for roam passport private tools (时光胶囊 / 探索目标 / 导出探索记录).

Lexical checks only: no Swift compilation, XCTest, simulator, accessibility or live backend run.
"""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--base', type=Path, help='Read-only source root for paths omitted by a sparse review overlay')
args = parser.parse_args()
checks = []


def read(path):
    source = args.root / path
    if not source.exists() and args.base is not None:
        source = args.base / path
    return source.read_text()


def check(name, value):
    assert value, name
    checks.append(name)


core = read('Core/RoamPassportPrivateTools.swift')
goals = read('Core/RoamExplorationGoals.swift')
export = read('Core/RoamExplorationExport.swift')
reading = read('Core/RoamPassportPrivateToolsReading.swift')
fixture = read('Core/RoamPassportPrivateToolsFixture.swift')
coordinators = read('Core/RoamPassportPrivateCoordinators.swift')
views = read('App/RoamPassportPrivateToolsViews.swift')
export_view = read('App/RoamExplorationExportView.swift')
copy = views + export_view
session = read('App/AppSession.swift')
composition = read('App/AppCompositionRoot.swift')
hub = read('App/RoamExperienceHubView.swift')
tools_section = read('App/RoamPassportToolsViews.swift')
fixture_host = read('App/RoamExperienceFixtureSupport.swift')
catalog = json.loads(read('Resources/Localizable.xcstrings'))['strings']
private_sources = [core, goals, export, reading, fixture, coordinators]

archive_paths = ['api/capsules/list', 'api/capsules/detail', 'api/capsules/receipt', 'api/capsules/create', 'api/capsules/delete',
                 'api/exploration-goals/list', 'api/exploration-goals/detail', 'api/exploration-goals/receipt',
                 'api/exploration-goals/create', 'api/exploration-goals/cancel',
                 'api/personal-exploration-export/prepare', 'api/personal-exploration-export/page']
check('Every archive endpoint is named exactly once as a route constant', all(reading.count('"' + p + '"') == 1 for p in archive_paths))
check('Reads and writes are separate reviewed sets',
      'public static let reads: Set<String> = [capsuleList, capsuleDetail, capsuleReceipt, goalList, goalDetail, goalReceipt, exportPrepare, exportPage]' in reading
      and 'public static let writes: Set<String> = [capsuleCreate, capsuleDelete, goalCreate, goalCancel]' in reading)
check('The service refuses any path outside the reviewed sets',
      'RoamPrivateToolsRoute.reads.contains(path) || RoamPrivateToolsRoute.writes.contains(path) else { throw APIError.invalidRequest }' in reading)
check('Capsule refusals are 400 only; 409 stays unconfirmed',
      'body: .json(draft.json), rejectedCodes: [400], token: token)' in reading and 'body: .form(["id": id]), rejectedCodes: [400], token: token)' in reading)
check('Goal refusals are 400 and 409', 'rejectedCodes: [400, 409], token: token)' in reading)
check('Post-dispatch failures are unconfirmed, never refusals', 'catch { throw RoamPrivateWriteError.outcomeUnknown }' in reading)
check('Writes need their own approval', 'if write { guard access.allowsWrites else { throw RoamPrivateWriteError.writesDisabled } }' in reading
      and 'public var allowsWrites: Bool { allows(RoamPrivateToolsRoute.writes) }' in reading)
check('Approval is bound to market, player role, deployment, namespace and account',
      all(x in reading for x in ['context.market == .china, context.role == "player"', 'approval.namespace.utf8.elementsEqual(context.session.namespace.utf8)',
                                 'approval.accountID == context.session.accountID', 'approval.paths.isSubset(of: Self.universe)']))
check('Identity change clears pending requests and confirmed cancellations',
      'if !same { bound = context; storedCapsule = nil; storedGoal = nil; storedCancelled = [] }' in reading)
check('Production composition supplies no approval',
      'roamPrivateToolsReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamPrivateToolsAccess? = { _ in nil },' in composition
      and 'let access = self.composition.roamPrivateToolsReadAccess(context),' in session
      and 'access.matches(context), !access.allowsWrites else { return nil }' in session
      and session.count('access: roamPrivateToolsAccess') == 2)
check('Private content is never persisted by Core',
      not any(x in src for src in private_sources for x in ['UserDefaults', 'Keychain', 'FileManager', 'write(to:', 'AppStorage']))
check('Views persist nothing except the temporary share copy',
      not any(x in v for v in [views, export_view] for x in ['AppStorage', 'UserDefaults']) and '.write(to:' not in views and export_view.count('.write(to:') == 1
      and 'removeTemporaryFile()' in export_view and '[.atomic, .completeFileProtection]' in export_view)
check('Share and save stay in the dedicated export file', 'ShareLink(' not in views and export_view.count('ShareLink(') == 1 and '.fileExporter(' in export_view)
check('Capsule bodies only survive for OPEN capsules', 'body: open ? raw.body : nil, photoURL: open ?' in core)
check('Capsule list strips content even in the fixture', 'var out = row; out["body"] = nil; out["photoUrl"] = nil; return out' in fixture)
check('Create dispatches only from the confirmation dialog',
      views.count('model.confirmCreate()') == 2 and views.count('.confirmationDialog(') == 4
      and 'Button("roam.capsule.seal") { model.prepareCreate(' in views and 'Button("roam.goals.create") { model.prepareCreate(' in views)
check('Destructive writes are confirmed first',
      'Button("roam.capsule.delete", role: .destructive) { Task { await model.confirmDelete() } }' in views
      and 'Button("roam.goals.cancelGoal", role: .destructive) { Task { await model.confirmCancel() } }' in views)
check('Reviewed draft becomes pending before dispatch',
      'tools.pendingCapsule = review; self.review = nil' in coordinators and 'tools.pendingGoal = review; self.review = nil' in coordinators)
check('Retry resends the pending draft, never a new one',
      'guard let pending, canWrite, !isBusy else { return false }\n        return await dispatch(pending)' in coordinators)
check('Only a refusal of a never-uncertain attempt releases the pending slot',
      coordinators.count('case .rejected where !uncertain.contains(draft.requestID), .writesDisabled, .invalidDraft:') == 2)
check('Export file only after the final chunk and never for zero rows',
      'guard live(), phase == .complete, let file, file.rows > 0, !file.isExpired(now: tools.now) else { return nil }' in coordinators)
check('Source change discards every part', 'parts = []; file = nil; checkpoint = nil; sourceChanged = true; phase = .choosing' in coordinators)
check('Chunk rows must strictly descend', 'if let last, RoamExportContract.compare(record.recordID, last) >= 0 { throw APIError.malformedResponse }' in export)
check('Goal projection pins the counting contract',
      'raw.timeZone == "Asia/Shanghai", raw.countingVersion == "COMPLETED_SESSION_AGGREGATE_V1"' in goals
      and 'raw.privateCommemoration == (state == .achieved)' in goals)
check('Photo attach stays unavailable on iOS', 'roam.capsule.photoUnavailable' in views and 'PhotosPicker' not in views)
check('Roam hub exposes goals and capsule beside the badge wall',
      '.accessibilityIdentifier("roam.badgeWall.open")\n                RoamPassportPrivateLinks(tools: privateToolsReader)' in hub)
check('Roam tools expose export after monthly recap',
      tools_section.index('roam.tools.recap.open') < tools_section.index('RoamExplorationExportView(tools: privateTools)'))
check('Offline fixture is DEBUG-only in the App', fixture_host.startswith('#if DEBUG') and 'RoamPrivateToolsFixture(scenario:' in fixture_host
      and not any('RoamPrivateToolsFixture(' in read(p) for p in ['App/AppSession.swift', 'App/QuestifyApp.swift', 'App/RoamBrowserView.swift']))
interpolated = ['roam.capsule.openedMeta %@ %@', 'roam.capsule.count %lld', 'roam.capsule.confirmMessage %@', 'roam.capsule.openReady %@',
                'roam.capsule.writtenOn %@', 'roam.capsule.daysLeft %lld', 'roam.capsule.unlocksOn %@', 'roam.capsule.count.items %lld',
                'roam.goals.unit.routes %lld', 'roam.goals.unit.days %lld', 'roam.goals.range %@ %@', 'roam.goals.count %lld',
                'roam.export.readCount %lld %lld', 'roam.export.rows %lld']
check('Every interpolated key is used and exists in both languages',
      all(('Text("' + k.split(' ')[0] + ' \\(') in copy and set(catalog[k]['localizations']) == {'en', 'zh-Hans'} for k in interpolated))
plain = set(re.findall(r'(?:Text|Button|Label|Section|LabeledContent|ProgressView|TextField|DatePicker|Picker|confirmationDialog|alert|LocalizedStringKey)\(\s*"(roam\.(?:capsule|goals|export|private)\.[A-Za-z0-9.]+)"', copy))
plain |= set(re.findall(r'return "(roam\.(?:capsule|goals|export|private)\.[A-Za-z0-9.]+)"', copy))
plain |= set(re.findall(r'\? "(roam\.(?:capsule|goals|export|private)\.[A-Za-z0-9.]+)" : "(roam\.[A-Za-z0-9.]+)"', copy) and sum(re.findall(r'\? "(roam\.(?:capsule|goals|export|private)\.[A-Za-z0-9.]+)" : "(roam\.[A-Za-z0-9.]+)"', copy), ()))
missing = sorted(k for k in plain if k not in catalog)
check('Every literal copy key exists in the catalog: ' + ', '.join(missing), not missing and len(plain) > 60)
print(f'PASS: {len(checks)} roam private tools source contracts')

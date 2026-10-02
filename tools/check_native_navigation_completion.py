#!/usr/bin/env python3
"""Bounded static/source checks only; NOT Swift compilation, UI or live acceptance."""
import argparse, hashlib, json, re
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--flutter-source',type=Path);a=p.parse_args()
r=Path(__file__).resolve().parents[1]
def read(path):return (r/path).read_text()
checks=[]
def check(label,value):
 checks.append(bool(value));print(('PASS ' if value else 'FAIL ')+label)
route=read('Core/NativeNavigationCompletion.swift');entry=read('Core/NativeEntryRouting.swift');landing=read('App/NativeEntryLandingView.swift')
check('source team and badge route parsing',all(v in route for v in ['"/team/join"','"/badge"','"fromTeamId"','Set(items.map(\\.name)).count == items.count','c.scheme == nil','c.host == nil']))
check('empty external allowlist and HTTPS identity validation',all(v in entry for v in ['verifiedHTTPSOrigins: Set<String> = []','c.scheme == "https"','c.user == nil','c.password == nil','c.port == nil','c.fragment == nil','origins.contains']))
check('guest login continuation outside account tabs',all(v in landing for v in ['case .teamInvitation(let route)','SessionTeamDetailView(lookup: .invitation(route.code))','LoginView(intent: .player)']) and '.sheet(item: Binding(get: { session.nativeEntry }' in read('App/QuestifyApp.swift'))
check('normal manual team and badge routes', 'TeamInvitationEntryView(' in read('App/TeamHomeView.swift') and 'BadgeRouteEntryView(' in read('App/ObjectBadgeViews.swift') and 'onOpenInvitation: { session.receiveNativeIntent(.teamInvitation($0)) }' in read('App/SessionTeamViews.swift'))
check('global safe fallback has home and dismiss actions','receiveNativeIntent(.routeError(.unsupported))' in read('App/AppSession.swift') and 'NativeRouteErrorView(failure:' in landing and 'Button("homeFeed.title", action: goHome)' in read('App/NativeNavigationCompletionViews.swift'))
evidence=read('Core/PlayerTaskEvidence.swift');ui=read('App/PlayerTaskEvidenceView.swift');player=read('App/PlayPlayerAndCircleViews.swift')
check('PLAYER evidence reaches owned source command review',all(v in evidence for v in ['expectedRevision: revision, action: .submit','"taskCode": .string(taskCode)','"evidenceUrls"','hasCurrentProjection','currentSession() == target.owner','projection.sessionID == target.sessionID','projection.revision == target.revision','projection?.allows(command) == true']))
check('PLAYER normal entry and scoped native capture/upload',all(v in player for v in ['model.evidenceTarget(nodeID: node.id)','PlayerTaskEvidenceView(target: target','navigationDestination(item: $evidenceTarget)']) and all(v in ui for v in ['device?.capture(.scan)','device?.capture(.photo)','device?.capture(.photo, usePhotoLibrary: true)','device?.uploadPhoto()','device?.reviewedPhoto()','player.reviewEvidence(','device?.cancel()','scenePhase','playerEvidence.scan.manualDetail']))
coupon=read('Core/CouponCodePresentation.swift');couponui=read('App/CouponCodeView.swift')
check('coupon history ID and existing exact source adapters',all(v in coupon for v in ['OrderLifecycleRequestContract.issueCoupon(historyID: historyID','couponStatus(historyID: historyID','enabled: Bool = false','approvedImageHosts: Set<String> = []','if code == 410','(1...90).contains(expiresIn)']))
check('coupon lifecycle independent from metadata and redemption',all(v in coupon for v in ['currentSession()','ownerIsCurrent','requestedAt.addingTimeInterval','date.addingTimeInterval(5)','if value.useStatus != 0','acceptTerminal(status)','generation &+= 1','public func pause()','public func invalidate()']) and 'verifyCoupon' not in coupon)
check('verified receipt QR with no generated entitlement',all(v in couponui for v in ['model.displayToken','CIFilter.qrCodeGenerator()','Data(token.utf8)','interpolation(.none)','background(.white)','privacySensitive()','model.invalidate()']) and 'OrderPassMetadata' not in couponui and 'AsyncImage' not in couponui)
check('normal coupon detail entry and hard-off factory', 'CouponCodeView(model: makeCode(coupon.id))' in read('App/AccountCollectionCouponDetailView.swift') and 'enabled: false, approvedImageHosts: []' in read('App/AppSession.swift') and '.environment(\\.couponCodeFactory' in read('App/QuestifyApp.swift'))
fragment=json.loads(read('Resources/NativeNavigationLocalizations.fragment.json'))['strings']
check('54 bilingual keys merged into default catalog',len(fragment)==54 and all(all(lang in row['localizations'] for lang in ['en','zh-Hans']) for row in fragment.values()) and all(k in json.loads(read('Resources/Localizable.xcstrings'))['strings'] for k in fragment))
core_tests=sum(len(re.findall(r'func test\w+',read(path))) for path in ['Tests/CoreTests/NativeNavigationCompletionTests.swift','Tests/CoreTests/PlayerTaskEvidenceTests.swift','Tests/CoreTests/CouponCodePresentationTests.swift'])
ui_tests=len(re.findall(r'func test\w+',read('Tests/AppUITests/NativeNavigationCompletionUITests.swift')))
check('28 core and 4 UI tests authored, not execution evidence',core_tests==28 and ui_tests==4)
source_hashes={}
if a.flutter_source:
 expected={
  'lib/feature/play/player_game_module_views.dart':['_ScanEvidencePage','evidenceUrls','_ScanEvidencePageState'],
  'lib/core/router/route_error_page.dart':['class RouteErrorPage','routeNotFound','routeCannotOpen'],
  'lib/core/router/app_router.dart':["path: '/team/join'","path: '/badge'","path: '/coupon/:id/code'"],
  'lib/feature/coupon/coupon_code_page.dart':['_startPolling','_clearTimers','Image.network'],
  'lib/data/api/coupon_api.dart':['/api/coupon/qr-token','/api/coupon/status',"'couponHistoryId'"],
  'lib/data/models/coupon.dart':['final String? token','final int expiresIn','final int useStatus'],
 }
 for path,needles in expected.items():
  file=a.flutter_source/path;data=file.read_bytes();source_hashes[path]=hashlib.sha256(data).hexdigest()
  check('Flutter source evidence: '+path,all(v in data.decode() for v in needles))
else:print('NOT_RUN: Flutter source parity was not requested with --flutter-source')
print(json.dumps({'static_checks_passed':sum(checks),'static_checks_total':len(checks),'core_tests_authored':core_tests,'ui_tests_authored':ui_tests,'Swift_Apple_runtime_visual_live':'NOT_RUN','source_hashes':source_hashes},indent=2))
raise SystemExit(0 if all(checks) else 1)

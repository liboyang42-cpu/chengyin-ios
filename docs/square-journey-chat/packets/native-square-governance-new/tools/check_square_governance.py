#!/usr/bin/env python3
"""Static source contract assertions only, never Swift runtime evidence."""
from pathlib import Path
import re,json,hashlib,argparse
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--flutter',type=Path,default=Path(__file__).resolve().parents[2]/'app-audit');a=p.parse_args();root=a.root
source=a.flutter/'lib/data/api/square_api.dart';dart=source.read_text()
service=(root/'Core/SquareGovernanceService.swift').read_text();contracts=(root/'Core/SquareGovernanceContracts.swift').read_text();coordinator=(root/'Core/SquareGovernanceCoordinator.swift').read_text();ui=(root/'App/SquareGovernanceViews.swift').read_text()
checks=[]
def check(name,condition):
 assert condition,name
 checks.append(name)
for method,path,verb in [('myEnforcements','api/v1/community/me/enforcements','get'),('appealEnforcement','api/v1/community/appeals','post'),('notifications','api/v1/community/notifications','get'),('readNotification','api/v1/community/notifications/$notificationId/read','post'),('notificationPreferences','api/v1/community/notification-preferences','get'),('updateNotificationPreferences','api/v1/community/notification-preferences','patch'),('approveComment','api/v1/community/posts/$postId/comments/$commentId/approve','post'),('deleteComment','api/comment/delete','post')]:
 segment=dart[dart.index(' '+method+'('):];segment=segment[:segment.index('_ensureOk')]
 check(method+' source verb/path', '/'+path in segment and '.dio.'+verb in segment)
 nativepath=path.replace('$notificationId',r'\(id)').replace('$postId',r'\(postID)').replace('$commentId',r'\(commentID)')
 check(method+' native path',nativepath in service)
for field in ['enforcementId','reason','evidenceAssetIds','requestId','expectedVersion','interactionEnabled','mentionEnabled','socialEnabled']:
 check('field '+field,field in dart and field in service+contracts)
check('read limits', 'limit: 30' in service and 'limit: 50' in service)
check('production reads off','readsEnabled: Bool = false' in service)
check('production mutations off','mutationCapabilities = []' in service and 'guard allows(review.action) else' in service)
check('dormant any-transport grant defaults off','transport: any HTTPTransport, readsEnabled: Bool = false, grant: SquareGovernanceMutationGrant = .disabled' in service)
check('per-operation capability gate','mutationCapabilities.contains(SquareGovernanceCapability(action))' in service)
check('no network fixture','URLSession' not in (root/'Core/SquareGovernanceSyntheticFixtures.swift').read_text())
check('immutable review', all('public let '+k in contracts for k in ['snapshot','action','requestID','createdAt']))
check('fresh snapshot equality','guard fresh == review.snapshot' in coordinator)
check('identity check','identity == access.identity' in coordinator)
check('journal before send',coordinator.index('journal.insert') < coordinator.index('return try await service.dispatch'))
check('durable account lock','UserDefaults' in coordinator and 'identity.namespace' in coordinator and 'identity.accountID' in coordinator)
check('source author distinctions','identity.accountID == postAuthorID' in contracts and 'identity.accountID == commentAuthorID' in contracts)
check('pending exact','approvalState == "PENDING"' in contracts)
check('missing version locked','(version ?? -1) >= 0' in contracts)
check('multipart delete','multipart/form-data' in service and 'form: true' in service)
check('not approved receipt','acknowledgedNeedsRefresh' in service)
check('native host entry','SquareGovernanceEntryView' in ui and 'NavigationLink' in ui)
check('generation stale suppress','guard ticket == generation' in ui and '.onChange(of: context.access.identity)' in ui)
check('Chinese and English catalog',all(set(row['localizations'])=={'en','zh-Hans'} for row in json.loads((root/'Resources/SquareGovernanceLocalizations.fragment.json').read_text())['strings'].values()))
check('no fixture import core module in App',all('import QuestifyCore' not in p.read_text() for p in (root/'App').glob('*.swift')))
for file in [source,a.flutter/'lib/feature/square/square_governance_page.dart',a.flutter/'lib/feature/square/square_detail_page.dart',a.flutter/'lib/data/models/square_post.dart']:
 check('source present '+file.name,file.is_file())
projection=(root/'verification/SquareContracts.swift').read_text()
check('optional source version projection','public let version: Int?' in projection and 'version = value["version"].number' in projection)
check('no fabricated projection version','version = value["version"].number ??' not in projection)
check('source model version numeric', "version: (json['version'] as num?)?.toInt() ?? 0" in (a.flutter/'lib/data/models/square_post.dart').read_text())
check('raw authorization convention','request.setValue(token, forHTTPHeaderField: "Authorization")' in service)
report={'static_checks' :'PASS','assertions':len(checks),'checks':checks,'authored_core_tests':sum(len(re.findall(r'func test\w+', p.read_text())) for p in (root/'Tests/CoreTests').glob('SquareGovernance*.swift')),'authored_ui_tests':len(re.findall(r'func test\w+',(root/'Tests/AppUITests/SquareGovernanceFlowTests.swift').read_text())),'bilingual_keys':len(json.loads((root/'Resources/SquareGovernanceLocalizations.fragment.json').read_text())['strings']),'swift_typecheck':'NOT_RUN: Swift unavailable','core_runtime':'NOT_RUN: Swift unavailable','apple_ui_runtime':'NOT_RUN: Xcode/simulator unavailable','source_sha256':{str(file.relative_to(a.flutter)):hashlib.sha256(file.read_bytes()).hexdigest() for file in [source,a.flutter/'lib/feature/square/square_governance_page.dart',a.flutter/'lib/feature/square/square_detail_page.dart',a.flutter/'lib/data/models/square_post.dart']}}
(root/'docs/static-evidence.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k not in ['checks','source_sha256']},indent=2))

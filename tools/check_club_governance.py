#!/usr/bin/env python3
"""Static source-backed contract checks only; not a Swift compiler or runtime test."""
from pathlib import Path
import argparse,json,re,hashlib
parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);parser.add_argument('--flutter',type=Path,default=Path(__file__).resolve().parents[2]/'app-audit');args=parser.parse_args()
root=args.root; flutter=args.flutter
source_files=[flutter/'lib/data/api'/name for name in ['club_ops_api.dart','club_crm_api.dart','club_compensation_api.dart','club_topic_ops_api.dart','club_api.dart','group_code_api.dart','publisher_identity_api.dart']]
source='\n'.join(p.read_text() for p in source_files)
core='\n'.join(p.read_text() for p in (root/'Core').glob('ClubGovernance*.swift'))
app='\n'.join(p.read_text() for p in (root/'App').glob('ClubGovernance*.swift'))
reads=(root/'Core/ClubGovernanceContracts.swift').read_text();writes=(root/'Core/ClubGovernanceCommands.swift').read_text()
read_paths=re.findall(r'case \.\w+: return "(api/[^\"]+)"',reads)
write_paths=re.findall(r'case \.\w+: return "(api/[^\"]+)"',writes)
assert len(read_paths)==34,(len(read_paths),read_paths)
assert len(write_paths)==23,(len(write_paths),write_paths)
for path in read_paths+write_paths:assert '/'+path in source,path
assert len(set(write_paths))==23
assert not any('withdraw' in p or 'reconcile' in p for p in read_paths+write_paths)
service=(root/'Core/ClubGovernanceService.swift').read_text()
assert 'offlineRisks = []' in service
assert 'guard offlineRisks.contains(command.operation.risk.rawValue)' in service
assert 'try await transport.send(request)' in service
assert 'guard snapshot == review.snapshot' in service
assert 'session.storageNamespace == review.storageNamespace' in service
for fragment in ['phoneIncluded','expectedVersion','canManageRoles','eventAccesses','CLUB_CO_OWNER','CLUB_OPERATOR','EVENT_LEAD','EVENT_CHECKIN','outcomeLocked','failedSessions','unverifiedSettledCount']:
    assert fragment in core,fragment
assert 'viewerIsAdmin' not in (root/'Core/ClubGovernanceValidation.swift').read_text()
assert 'TopicDetailView(' not in app
assert 'cmsMemberTemplate' in app
assert 'ForEach' in app and 'accessibilityIdentifier' in app and '.onChange(of: identity)' in app
catalog=json.loads((root/'Resources/ClubGovernanceLocalizations.fragment.json').read_text())['strings']
for key,value in catalog.items():
    for language in ['en','zh-Hans']:assert value['localizations'][language]['stringUnit']['value'],(key,language)
for key in re.findall(r'"(club\.gov\.[A-Za-z][A-Za-z0-9.]+)"',app):
    if key.endswith('.') or any(key.startswith('club.gov.'+s) for s in ['input.','fixture.','route.','fact.']):continue
    if key in ['club.gov.loading','club.gov.error','club.gov.open','club.gov.openHost','club.gov.openFeed','club.gov.openStory','club.gov.formError','club.gov.confirm','club.gov.prepare','club.gov.groupCode']:continue
    assert key in catalog,key
# Check every dynamic fact/form/choice label against the bilingual catalog.
form=(root/'Core/ClubGovernanceFormDraft.swift').read_text()
for key in ['targetMemberId','banId','assignmentId','version','expectedVersion','requestId','channel','evidence','hasExperience']:
    if 'club.gov.field.'+key not in catalog:
        assert key in ['channel','evidence'] # hidden implementation constants are omitted from review UI
core_tests=sum(len(re.findall(r'func test\w+',p.read_text())) for p in (root/'Tests/CoreTests').glob('ClubGovernance*.swift'))
ui_tests=sum(len(re.findall(r'func test\w+',p.read_text())) for p in (root/'Tests/AppUITests').glob('ClubGovernance*.swift'))
summary={'read_adapters':len(read_paths),'dormant_mutation_adapters':len(write_paths),'bilingual_keys':len(catalog),'authored_core_tests':core_tests,'authored_ui_tests':ui_tests,'swift_test':'NOT_RUN: Swift toolchain absent','xcode_ui':'NOT_RUN: Xcode/simulator absent','checks':'static-source checks PASS','source_hashes':{str(p.relative_to(flutter)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files}}
(root/'docs/club-governance-static-evidence.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k!='source_hashes'},ensure_ascii=False,indent=2))

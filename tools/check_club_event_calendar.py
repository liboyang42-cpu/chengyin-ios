#!/usr/bin/env python3
"""Focused static P045 calendar contracts. This does not compile or run Swift."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mini-detail', type=Path)
parser.add_argument('--mini-view', type=Path)
parser.add_argument('--mini-helper', type=Path)
args = parser.parse_args()
core = (ROOT / 'Core/ClubEventCalendar.swift').read_text()
app = (ROOT / 'App/ClubEventCalendarView.swift').read_text()
entry = (ROOT / 'App/ClubDetailView.swift').read_text()
contracts = (ROOT / 'Core/ClubGovernanceContracts.swift').read_text()
service = (ROOT / 'Core/ClubGovernanceService.swift').read_text()
checks = []

def check(label, condition):
    if not condition:
        raise AssertionError(label)
    checks.append(label)

check('normal club-detail entry', entry.count('ClubEventCalendarView(clubID: id, identity: reader.clubIdentity, governance: governance)') == 1)
check('same snapshot for list and calendar', 'if let snapshot = accepted' in app and 'calendar(snapshot)' in app and 'ForEach(snapshot.events)' in app)
check('existing read adapter only', 'access.read(.topics, scope: expected.scope, options: [:], check: check)' in app and 'case .topics: return "api/club/topics"' in contracts)
check('existing access/me preflight preserved', 'let raw = try await post(.access' in service and 'guard permitted else' in service)
check('no new mutations or transports', not re.search(r'\b(send|dispatch|prepare|confirm|URLRequest|URLSession)\s*\(', core + app))
check('Monday-first exact six-week grid', '(0..<42)' in core and '(calendar.component(.weekday, from: first) + 5) % 7' in core)
check('source start-date prefix only, no interval invention', 'String(source.prefix(10))' in core and 'row["startDate"].string' in core and 'row["endDate"]' not in core)
check('undated remains reachable', 'snapshot.undated' in app and 'club.calendar.dateUnknown' in app)
check('scope and duplicate protection', 'ids.insert(id).inserted' in core and 'positiveID(row["clubId"]) == clubID' in core)
for token in ['revision == generation', 'expected.identity == access.identity', 'expected.authorizationGeneration == access.authorizationGeneration', 'expected.accessIdentity == ObjectIdentifier(access)', 'active && !loading', '!Task.isCancelled', 'defer { if revision == generation { loading = false } }']:
    check('read fence: ' + token, token in app)
check('refresh clears before read', 'invalidate(); let revision = generation' in app)
check('navigation exact topic and context', 'detail(target.topicID).id(target.id)' in app and 'route.isCurrent(snapshot: accepted' in app)
check('invalid destination dismissed', 'if destination?.id == target.id { destination = nil }' in app)
check('covered source cannot select', '.onDisappear { model.suspend() }' in app and 'model.canSelect(readContext' in app)
check('large text has untruncated activity rows', 'dynamicTypeSize.isAccessibilitySize' in app and 'cells.filter { !$0.events.isEmpty }' in app and '.lineLimit(' not in app)
check('bounded month paging', '(1970...9999).contains(year)' in core and 'guard (-120_000...120_000).contains(delta)' in core)
strings = json.loads((ROOT / 'Resources/ClubEventCalendarLocalizations.fragment.json').read_text())['strings']
for key, value in strings.items():
    for language in ['en', 'zh-Hans']:
        check('localized: ' + key + ':' + language, bool(value['localizations'][language]['stringUnit']['value']))
check('localized weekday series', all('club.calendar.weekday.' + str(day) in strings for day in range(1, 8)))
check('formatted day accessibility label', 'club.calendar.day %@ %lld' in strings)
core_test = (ROOT / 'Tests/CoreTests/ClubEventCalendarTests.swift').read_text()
app_test = (ROOT / 'Tests/AppUnitTests/ClubEventCalendarReadTests.swift').read_text()
check('authored model tests', len(re.findall(r'func test\w+', core_test)) >= 10)
check('authored read lifecycle tests', len(re.findall(r'func test\w+', app_test)) >= 9)
# New source basenames must not collide within their target.
for filename in ['ClubEventCalendar.swift', 'ClubEventCalendarView.swift']:
    check('unique app target basename: ' + filename, sum(p.name.casefold() == filename.casefold() for folder in ['App', 'Core'] for p in (ROOT / folder).glob('*.swift')) == 1)

sources = {}
if any([args.mini_detail, args.mini_view, args.mini_helper]):
    if not all([args.mini_detail, args.mini_view, args.mini_helper]):
        parser.error('Supply all three exact source paths together')
    js, view, helper = [p.read_text() for p in [args.mini_detail, args.mini_view, args.mini_helper]]
    check('source calendar actions', 'onEventViewChange(e)' in js and 'onShiftEventMonth(e)' in js)
    check('source exact read body', "url: '/api/club/topics', method: 'POST', data: jsonBody({ id: this.data.clubId })" in js)
    check('source month cells and topic target', 'eventCalendarCells' in view and 'data-id="{{event.id}}"' in view)
    data = args.mini_helper.read_bytes()
    blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    check('exact f859 helper Git blob', blob == 'de54048b5285a492a3ca9411e899d75d4671c0ff')
    check('source Monday six-week shape', 'index < 42' in helper and '(first.getDay() + 6) % 7' in helper)
    for path in [args.mini_detail, args.mini_view, args.mini_helper]:
        sources[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
print(json.dumps({'scope': 'focused static contracts only, not Swift runtime or native acceptance', 'checks_passed': len(checks), 'authored_core_tests': len(re.findall(r'func test\w+', core_test)), 'authored_app_unit_tests': len(re.findall(r'func test\w+', app_test)), 'swift_core_tests': 'NOT_RUN: no Swift toolchain', 'apple_build_and_ui': 'NOT_RUN: no Xcode or simulator', 'exact_mini_source_check': 'PASS' if sources else 'NOT_RUN: source paths omitted', 'sources_sha256': sources}, ensure_ascii=False, indent=2))

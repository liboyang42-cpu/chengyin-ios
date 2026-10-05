#!/usr/bin/env python3
"""Native source assertions only. Never substitutes for Swift, Apple UI or live acceptance."""
from pathlib import Path
import json
r=Path(__file__).resolve().parents[1]
def read(path):return (r/path).read_text()
service=read('Core/PlayerJourneyService.swift')
assert 'readsEnabled: Bool = false' in service
for path in ['api/registration/my-joined','api/registration/info','api/play/my-completed']: assert path in service
assert 'includesBody: fields != nil' in service
assert 'currentSession() == session, captured == scope' in service
assert 'if code == 401' in service and 'isConfigured: Bool { service?.readsEnabled == true }' in service
ui=read('App/PlayerJourneyViews.swift')
assert 'PlayerJourneyAccountLinks()' in read('App/AccountView.swift')
for source in ['rows = values','rows == nil ? PlayerJourneyIssue.key(error)', 'onDismiss:', 'OrderLifecycleView(id: id', 'CompletedPlayHistoryView', 'ParticipationHistoryView']: assert source in ui,source
projection=read('Core/ChapterStoryContracts.swift')
for source in ['raw["imgArr"]','activeInlineNodeID', '!snapshot.isLocked(node) else { return result }', 'if !snapshot.isDone(node)', 'thoughts.first(where:', 'substitute']:
 assert source in projection,source
chapter=read('App/ChapterStoryView.swift')
for source in ['PlayKitInlineHost(', 'if state.inline', 'advanced.isCurrent', 'model.hasCurrentMediaSnapshot', 'confirmationDialog(', 'scrollDismissesKeyboard', 'nodeDestination(id)', 'variables(state.storyVariables)', 'reader.image(url: source)']:
 assert source in chapter,source
assert 'ChapterStoryView(chapterID:' in read('App/PlayExperienceView.swift')
assert 'storyThoughts = snapshot.route?.thoughts' in read('Core/PlayExperienceCoordinator.swift')
assert 'private let transport: any HTTPTransport' in service and 'URLSession' not in service
strings=json.loads(read('Resources/Localizable.xcstrings'))['strings']
for prefix in ['playerJourney.', 'chapterStory.']:
 keys=[k for k in strings if k.startswith(prefix)];assert keys
 assert all(all(language in strings[k]['localizations'] for language in ['en','zh-Hans']) for k in keys)
print('PASS: history normal entries and exact gated read adapter; chapter runtime/variable/spoiler/inline boundaries; bilingual catalogs')
print('Swift, simulator, visual, accessibility, devices and live services: NOT_RUN')

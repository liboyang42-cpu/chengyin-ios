#!/usr/bin/env python3
"""Offline structural contracts; no Swift/Apple/runtime or service-readiness claim."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
def read(p):return (root/p).read_text()
review=read('Core/ContextualReviews.swift')
for s in ['case topic(Int), activity(Int)', '"api/comment/add"', '"owner_type"', '"owner_id"', 'enabled: Bool = false', 'states[key] = .submitting', '.unknown, .acknowledged', 'session.realm == configuration.baseURL.absoluteString']:
 assert s in review,s
for p,s in [('App/ActivityDetailView.swift','activity.openReview'),('App/TopicDetailView.swift','topic.openReview'),('App/SessionRegistrationSheet.swift','participantCoordinator:session.participantCoordinator'),('App/RegistrationSheetView.swift','registration.form.addParticipant'),('App/AccountView.swift','categoryReader:session'),('App/MessagingHistoryView.swift','topicReader: expanded?.topicReader')]: assert s in read(p),(p,s)
participant=read('Core/ParticipantService.swift')
assert 'fields["requestId"] = requestID.uuidString.lowercased()' in participant
assert 'requestID != nil, case .save' in participant
assert 'selectCreatedParticipant' in read('Core/RegistrationUIFlow.swift')
assert 'row.id == receipt.id' in read('Core/RegistrationUIFlow.swift')
profile=read('Core/ProfileEditContracts.swift')
assert 'routePreferenceIDs.map' in profile and '?? snapshot.tagIds' in profile
assert 'latest.tagIds == original.tagIds' in read('Core/ProfileEditCoordinator.swift')
ui=read('App/IMExpandedViews.swift')
assert 'TextField("im.full.topicID"' not in ui
assert 'ContextualTopicPicker' in ui and 'payload: .route(topicID: row.id)' in ui
picker=read('App/ContextualPickers.swift')
assert 'scope == reader.scope' in picker and 'currentIdentity() == captured' in picker
assert 'try rows.accept(page)' in picker and 'discoveryCategories(type: 1)' in picker
catalog=json.loads(read('Resources/Localizable.xcstrings'))['strings']
keys=[k for k in catalog if k.startswith('context.')]
assert len(keys)>=20
for k in keys:
 assert all(catalog[k]['localizations'][l]['stringUnit']['value'] for l in ('en','zh-Hans')),k
print('PASS contextual-flow offline structure: scoped review clients, acknowledged participant ID readback, preference replacement, no manual IM topic ID, bilingual UI')
print('Swift tests, Apple compile, simulator, visual/accessibility and live backend: NOT_RUN')

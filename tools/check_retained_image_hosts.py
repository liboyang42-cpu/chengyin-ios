#!/usr/bin/env python3
"""Structural assertions only; no Swift runtime, OS selection or network is exercised."""
from pathlib import Path
import json, re, hashlib
root=Path(__file__).resolve().parents[1]
def read(p): return (root/p).read_text()
cache=read('App/RetainedImageContextCache.swift'); merchant=read('App/MerchantRetainedImageHost.swift')
review=read('App/RetainedPublicMerchantReviewHost.swift'); gate=read('Core/PublicMerchantReviewHostGate.swift')
assert 'enabled: false, approvedOrigins: []' in cache
assert 'enabled: false, origins: []' in review
assert review.count('enabled: false')==3
assert 'self.credentials == captured' in cache and 'self.generation == ticket' in cache
assert 'guard !existing.context.uploads.locked else { return nil }' in cache
assert 'entries.removeAll { !$0.context.uploads.locked }' in cache
lock=cache.split('if let unresolved = entries.first(where: {',1)[1].split('}) {',1)[0]
assert all(x in lock for x in ['uploads.locked','accountID == key.accountID','realm == key.realm','namespace == key.namespace','sameUnresolvedTarget'])
assert '.epoch' not in lock and 'newDraftID' not in lock
logical=cache.split('private func sameUnresolvedTarget',1)[1].split('func invalidate',1)[0]
assert 'templateID == otherTemplateID' in logical and 'registrationID == otherRegistrationID' in logical
assert 'newDraftID' not in logical and 'epoch' not in logical
assert 'value.identity.merchantID.flatMap(PublicMerchantRowID.init)' in merchant
assert 'value.allows(destination)' in merchant and 'try await reader.access()' in merchant
assert 'accessRevision: draftTicket, resourceID: resourceID, namespace: credentials.namespace' in merchant
for fence in ['self.accessRevision == accessTicket','self.draftRevision == draftTicket','self.reader.scope == loadedScope','coordinator.draft == draft','coordinator.confirmation == nil']:
    assert fence in merchant, fence
assert 'value.id == id' in merchant and 'value.id == access?.identity.merchantID' in merchant
assert 'PublicMerchantReviewHTTPWriter(' in review and 'PublicMerchantReviewGatedWriter(base: concrete, enabled: false' in review
assert 'self.currentSession() == session && self.writer.session == session' in review
assert 'self.activeTarget == target' in review and 'registrationID: registrationID, session: session) == revision' in review
assert 'currentSession() == session, !Task.isCancelled' in review
assert gate.count('guard isConfigured else { throw PublicMerchantReviewWriteFailure.notConfigured }')==2
assert 'eligibility.reasonCode == "ELIGIBLE"' in gate and 'value.eligibility.registrationId == registrationID' in gate
assert 'suspended.contains(target)' in gate
views=read('App/MerchantOperationsViews.swift')
assert 'imageContext: model.imageContext' in views
assert 'imageHost: imageHost' in views and 'destination: .template(nil), imageHost: imageHost' in views
assert 'destination: .template(row.id), imageHost: imageHost' in views
assert 'imageOwner?.draftChanged(coordinator.draft)' in views
assert '.onDisappear { model.leaveImages() }' in views
assert '.id(context.scope.accessRevision)' in read('App/MerchantOperationsEditor.swift')
editor=read('App/PublicMerchantReviewEditor.swift')
assert '.onChange(of: state.writer.session)' in editor and 'invalidateImages?(target)' in editor
assert 'imageContext.currentScope() == imageContext.scope, image.scope == imageContext.scope' in editor
snippet=read('App/AppSession.swift')
for text in ['publicMerchantReviewEpoch = UUID()', 'retainedPublicMerchantReviews?.invalidate()', 'retainedImageContextCache?.invalidate()', 'imageHost: retainedMerchantImages']:
    assert text in snippet
assert 'IMExpanded' not in cache+merchant+review+gate
assert 'URLSessionTransport' not in cache+merchant+review+gate
assert 'saveReviewed(' not in cache+merchant+review+gate
assert not re.search(r'enabled:\s*true',cache+merchant+review)
assert len(re.findall(r'func test',read('Tests/CoreTests/PublicMerchantReviewHostGateTests.swift')))==8
assert len(re.findall(r'func test',read('Tests/AppUnitTests/RetainedImageNormalHostTests.swift')))==6
print('PASS retained normal image host source assertions; 8 core + 6 app-unit tests AUTHORED, NOT_RUN')

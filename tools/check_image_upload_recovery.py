#!/usr/bin/env python3
"""Source checks only. Swift/XCTest/Keychain/URLSession runtime NOT_RUN."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
def read(p): return (root/p).read_text()
journal = read('Core/ImageUploadJournal.swift')
key = journal.split('fileprivate var key:', 1)[1].split('public struct ImageUploadJournalEntry',1)[0]
for part in ['namespace', 'realm', 'accountID', 'kind', 'entityID', 'field', 'resourceID']:
    assert part in key
for forbidden in ['epoch', 'newDraftID', 'token', 'url', 'jpeg', 'accessRevision']:
    assert forbidden not in key
entry = journal.split('public struct ImageUploadJournalEntry',1)[1].split('@MainActor public protocol',1)[0]
assert 'pending, acknowledged, locallyApplied, rejected' in entry
assert 'value.version == 1, value.target == target' in journal
assert 'guard try read(value.target.key) == bytes' in journal
assert 'value.attemptID == attemptID' in journal
assert 'value.phase == .acknowledged && phase == .locallyApplied' in journal
assert 'self == .locallyApplied || self == .rejected' in journal
assert '.remove(' not in journal
retained = read('Core/RetainedImageContracts.swift')
im = read('Core/IMMediaSelection.swift')
for source, call in [(retained, 'try await uploader.upload(review)'), (im, 'try await writer.upload(selection')]:
    assert source.index('try journal.begin(') < source.index(call)
    assert 'phase: .acknowledged' in source
    assert 'UnavailableImageUploadJournal()' in source
assert retained.index('try journal.record(target: target, attemptID: review.id, phase: .acknowledged)') < retained.index('state = .uploaded(image)')
assert 'image.scope == review.scope' in retained
assert 'token() == auth' in retained
storage = read('App/ImageUploadSecureStorage.swift')
for safety in ['kSecAttrSynchronizable as String: false', 'kSecAttrAccessibleWhenUnlockedThisDeviceOnly', 'errSecSuccess', 'ImageUploadJournalFailure.unavailable']:
    assert safety in storage
assert 'SecItemDelete' not in storage
app = read('App/AppSession.swift')
assert 'transport: ResponseLimitedHTTPTransport()' in app
assert 'journal: imageUploadJournal' in app
assert 'journal: imageUploadJournal, target: target' in app
assert 'service: nil' in app
cache = read('App/RetainedImageContextCache.swift')
assert 'enabled: false, approvedOrigins: []' in cache
assert 'RetainedImageUploadCoordinator(uploader: uploader, journal: journal)' in cache
assert 'func testUploadJournalSurvivesNewIMOwnerAndEpoch' in read('Tests/CoreTests/IMExpandedTests.swift')
tests = read('Tests/CoreTests/ImageUploadJournalTests.swift')
for name in ['PartialSendRecreatedOwnerNewEpochNewDraftRemainsLocked', 'WriteAheadExistsBeforeTransportAndAcknowledgementIsNotDraftApplication', 'CorruptionReadErrorAndFailedWriteNeverDispatch', 'AcknowledgementPersistenceFailureRetainsUnknown', 'AccountNamespaceAndSavedTemplateRemainIndependent', 'WrongAttemptAndCorruptVersionCannotUnlock']:
    assert 'func test'+name in tests
print('PASS image upload durable metadata/host/source checks; Apple/runtime tests NOT_RUN')

transport = read('Core/ResponseLimitedHTTPTransport.swift')
for text in ['enabled: Bool = false', 'URLSessionConfiguration.ephemeral', 'configuration.urlCredentialStorage = nil', 'configuration.httpCookieStorage = nil', 'configuration.urlCache = nil', 'completionHandler(nil)', 'maximumResponseBytes - bytes.count', 'case outcomeUnknown(Reason)']:
    assert text in transport
assert transport.index('chunk.count > maximumResponseBytes - bytes.count') < transport.index('bytes.append(chunk)')
assert 'session.data(for:' not in transport
print('PASS bounded streaming adapter source checks; network/runtime NOT_RUN')

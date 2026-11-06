#!/usr/bin/env python3
"""Static restoration checks only. This does not compile Swift or execute XCTest."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'Core'
TESTS = ROOT / 'Tests/CoreTests'
LEAVES = ['Authority', 'Contracts', 'Coordinator', 'Presentation', 'PrivacyJournal', 'Service']
source = {name: (CORE / f'NativeChannelProgress{name}.swift').read_text() for name in LEAVES}

def require(condition, message):
    if not condition:
        raise AssertionError(message)

def method(text, name):
    match = re.search(r'func ' + re.escape(name) + r'\b', text)
    require(match is not None, f'Missing method {name}')
    start = text.index('{', match.end())
    depth = 1
    cursor = start + 1
    while depth:
        require(cursor < len(text), f'Unterminated method {name}')
        depth += (text[cursor] == '{') - (text[cursor] == '}')
        cursor += 1
    return text[start:cursor]

# The three pre-existing donor tests are immutable, including assertions and fixtures.
ORIGINAL_TEST_HASHES = {
    'NativeChannelProgressAuthorityTests.swift': '446606b2ba9cf0144b2be6546b6ea174cd6f736294bd0fe2b01fa8fe8dda4c39',
    'NativeChannelProgressCoordinatorTests.swift': 'b456a558f84690df2ae263d60fdbe987b380df444860a1ce52ccb4fdeb390b64',
    'NativeChannelProgressTests.swift': '18d7cc5e1d83cb73a08491dc8a489f9444a1954d657185d6db144e9701393eb2',
}
for name, digest in ORIGINAL_TEST_HASHES.items():
    require(hashlib.sha256((TESTS / name).read_bytes()).hexdigest() == digest, f'Original XCTest bytes changed: {name}')

joined = '\n'.join(source.values())
progress_types = re.findall(r'\b(?:struct|class|enum|protocol)\s+(NativeChannelProgress\w+)', joined)
all_core = '\n'.join(path.read_text() for path in CORE.glob('*.swift'))
for name in progress_types:
    require(len(re.findall(r'\b(?:struct|class|enum|protocol)\s+' + name + r'\b', all_core)) == 1, f'Duplicate Core declaration: {name}')
for name in set(re.findall(r'\bNativeChannelProgress\w+', joined)):
    require(name in progress_types, f'Unresolved Progress type: {name}')
for name in ['APIConfiguration', 'AuthRequestBuilder', 'HTTPTransport', 'NativeChannelManagementIntegrationContext', 'NativeChannelManagementIntegrationContextProviding']:
    require(re.search(r'\b(?:struct|class|enum|protocol)\s+' + name + r'\b', all_core) is not None, f'Missing existing dependency: {name}')

authority = source['Authority']
require('lhs.authorizationVersion.utf8.elementsEqual(rhs.authorizationVersion.utf8)' in authority, 'Opaque authority version is not byte-bound')
require('capturedCredential.utf8.elementsEqual(credential.utf8)' in authority, 'Credential is not byte-bound')
require('self.token() ==' not in authority and 'token() == credential' not in authority, 'Unicode token equality reintroduced')
require('guard !authorityRetired else { return nil }' in authority, 'Observed authority loss can revive')
require(authority.count('authorityRetired = false') == 1, 'Authority retirement is reset')
require('operationRevision == revision' in authority and 'captured.operations.contains(operation)' in authority, 'Visit or independent operation approval missing')
checked = method(authority, 'checked')
error_path = checked[checked.index('} catch {'):]
require(error_path.index('guard isCurrent(operation, revision: revision, credential: credential)') < error_path.index('onUnauthorized()'), 'Stale 401 can act before current-visit validation')
require('status == 401 || status == 403' in error_path, 'Current denial does not retire the client')
for operation in ['definitions', 'overview', 'best', 'recent', 'version', 'meter', 'privacy', 'savePrivacy', 'receipt']:
    require(f'checked(.{operation})' in authority, f'Missing independent operation: {operation}')
require('checked(detail ? .detail : .top)' in authority, 'Top/detail approval was conflated')
require(authority.count('guard fence.isCurrent else') >= 3, 'Missing pre/post/error forward fence')
binding = method(authority, 'make')
for field in ['context.ownerType == "CLUB"', 'provider.contextIsCurrent(context)', 'selectedAuthority()',
              'authority.identity.actorID', 'authority.identity.namespace.utf8', 'authority.identity.origin.absoluteString.utf8',
              'authority.identity.sessionEpoch', 'authority.viewerRevision', 'authority.metadataVersion', 'authority.permissionVersion']:
    require(field in binding, f'Missing real-context binding: {field}')

coordinator = source['Coordinator']
require(coordinator.count('authorityRetired = false') == 1, 'Coordinator observed authority retirement can reset')
for name in ['loadDirectory', 'select', 'readBoard', 'readOwnHistory', 'refreshOwnHistory', 'loadMore', 'checkVersion']:
    body = method(coordinator, name)
    require('access.save(' not in body and 'journal.saveBeforeDispatch' not in body and 'savePrivacy(' not in body, f'Read path became a writer: {name}')
require('requestID: UUID().uuidString' in method(coordinator, 'savePrivacy'), 'Original UUID creation missing')
require('journal.saveBeforeDispatch(command)' in method(coordinator, 'savePrivacy'), 'Privacy command is not persisted before dispatch')
require('access.receipt(command)' in method(coordinator, 'recover'), 'Original receipt recovery missing')
require('await dispatch(command, stamp: stamp)' in method(coordinator, 'recover'), 'Retry does not reuse original command')
require('version.revision.utf8.elementsEqual($0.revision.utf8)' in coordinator, 'Version probe uses normalized string comparison')

service = source['Service']
require(service.count('method: "POST"') == 1, 'Unexpected Progress write route added')
require('execute("api/privacy/progress", method: "POST", body: command.wireBody()' in service, 'Privacy write contract changed')
require('api/progress/requests/\\(command.requestId)' in service, 'Original receipt route changed')
require('"OUTCOME_UNKNOWN"' in service and 'header?.outcomeKnown == false' in service and 'header?.outcomeConfirmed == false' in service, 'Unknown outer outcomes can become applied')
require('request.httpShouldHandleCookies = false' in service, 'Ambient cookie dispatch enabled')
require('URLSession(' not in joined and '.shared.data' not in joined, 'Generic live HTTP dispatch introduced')

journal = source['PrivacyJournal']
require('@MainActor public protocol NativeChannelProgressJournalStorage' in journal, 'Secure actor-isolated storage adapter cannot conform safely')
require('try requireKnownFields(data)' in method(journal, 'restore'), 'Unknown journal bindings can be silently discarded')
require('try command.wireBody() == record.wireBody' in journal, 'Original journal body can be normalized/replaced')
require('record.owner == owner' in journal and 'record.version == 1' in journal, 'Journal owner/version binding missing')
require('previous.revision.utf8.elementsEqual(page.revision.utf8)' in source['Presentation'], 'Opaque page revision is not byte-bound')
require('Set<Data>' in source['Presentation'], 'Cursor replay keys are not byte-bound')

regression = (TESTS / 'NativeChannelProgressRestorationBoundaryTests.swift').read_text()
expected = ['testAuthorityUsesByteExactPolicyAndEveryIndependentBinding', 'testObservedAuthorityDriftCannotReturnThroughABA',
    'testTokenChangesAndMissingTokenRetireClientWithoutABA', 'testEveryQueuedRetirementIsCheckedAtActualForward',
    'testStaleResponseAndThrown401DoNotExpireNewVisit', 'testCurrent401ExpiresExactlyOnceAnd403NeverCallsLogout',
    'testDefinitionApprovalDoesNotGrantPrivacyWriteOrReceipt', 'testRetiredCoordinatorDoesNotReviveObservedAuthorityButFreshVisitCanReload',
    'testReadJourneyNeverSavesPrivacyOrCreatesACommand', 'testLateAppliedResponsePreservesOriginalUUIDAndJournal',
    'testUnknownJournalFieldsNeverLoseTheirOriginalBytes', 'testJournalUnknownOutcomeRetainsOriginalAndOwnerSeparatesNamespaceAndOrigin',
    'testOpaqueRevisionAndCursorCompareBytesNotUnicodeEquivalence', 'testRealContextDoesNotMintProgressGrantAndRejectsBothVersionMismatches']
for test in expected:
    require(f'func {test}(' in regression, f'Missing independent regression: {test}')
print(f'PASS: 6 restored Core leaves, {len(progress_types)} unique Progress declarations, 3 byte-identical donor test files, {len(expected)} authored boundary regressions.')
print('PASS: Static authority/context/operation/fence/privacy/journal/read-only route checks. Swift/XCTest execution is not implied.')

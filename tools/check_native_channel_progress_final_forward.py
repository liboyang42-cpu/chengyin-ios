#!/usr/bin/env python3
"""Static final-forward integration checks; no Swift compilation or network execution."""
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
core = (ROOT / 'Core/NativeChannelProgressFinalForward.swift').read_text()
tests = (ROOT / 'Tests/CoreTests/NativeChannelProgressFinalForwardTests.swift').read_text()
app = (ROOT / 'App/AppCompositionRoot.swift').read_text()
session = (ROOT / 'App/AppSession.swift').read_text()

def require(value, why):
    if not value:
        raise AssertionError(why)

def function(text, name):
    start = re.search(r'func ' + re.escape(name) + r'\b', text)
    require(start, f'Missing function {name}')
    start = text.index('{', start.end())
    pos, depth = start + 1, 1
    while depth:
        depth += (text[pos] == '{') - (text[pos] == '}')
        pos += 1
    return text[start:pos]

require('private let underlying: any NativeChannelProgressDispatching' in core, 'The operation fence can be erased by a generic transport')
require('underlying: any HTTPTransport' not in core, 'Generic fallback was reintroduced')
require('underlying.send(request, fence: finalFence)' in core, 'The queued dispatcher does not receive the composed fence')
require('underlying.send(request)' not in core, 'A forward bypasses its fence')
require(core.count('try await underlying.send(') == 1, 'The wrapper retries or forwards more than once')
require('self.isCurrent, fence.isCurrent' in core, 'Parent/current/operation fence not composed')
require('restored = try? self.journal.restore(), restored == original' in core and '(try? restored.wireBody()) == originalBody' in core, 'Original command and wire bytes are not rechecked at actual forward')
require('self.approvesReceipt(latest, command: original), Self.sameApproval(receiptLease, latest)' in core, 'Independent receipt approval is not rechecked after queue')
send = function(core, 'send')
require(send.count('guard finalFence.isCurrent else') == 3, 'Missing pre/success/error fence check')
require('(operation == .savePrivacy || operation == .receipt) ? try journal.restore() : nil' in send, 'Read-only directory can be blocked by unknown write journal')
require('issued.authority.operations.contains(operation)' in send, 'Endpoint path became operation authority')
require('receiptApproval: @escaping (NativeChannelProgressPrivacyCommand) -> OperationEndpointApproval? = { _ in nil }' in core, 'Missing independent receipt selector defaults to grant')
require('OperationEndpointApproval(' not in core and 'OperationEndpointApproval.init' not in core, 'A UUID or URL is manufacturing an endpoint grant')
for binding in ['identity.actorID == Int64(context.session.accountID)', 'identity.sessionEpoch == String(context.session.epoch)',
                'identity.namespace.utf8.elementsEqual', 'identity.origin.absoluteString.utf8.elementsEqual', 'journal.owner == NativeChannelProgressJournalOwner(identity)',
                'runtime.session == captured.session', 'selected() == issued', 'retired = true']:
    require(binding in core, f'Missing live owner binding: {binding}')
for policy in ['request.httpBodyStream == nil', '!request.httpShouldHandleCookies', 'request.cachePolicy == .reloadIgnoringLocalCacheData',
               '"Authorization")?.utf8.elementsEqual(captured.session.token.utf8)', '"Accept") == "application/json"',
               'Set(items.map(\\.name)).count == items.count', 'request.httpBody == (try original.wireBody())',
               'query["subject_id"] == String(issued.authority.identity.actorID)', 'query["channel_id"] == String(channel)']:
    require(policy in core, f'Missing exact request policy: {policy}')
require('.absoluteString.utf8.elementsEqual(noQuery.absoluteString.utf8)' in core, 'Origin/deployment prefix is not exact')
require('approvesReceipt(lease, command: original)' in function(core, 'operation'), 'Receipt bypasses independently issued owner/path grant')
require('guard url.absoluteString.hasPrefix(prefix) else { return nil }' in function(core, 'receiptCommand'), 'Non-recovery read touches journal')
factory = function(app, 'makeNativeChannelProgressFinalForward')
require('as? any NativeChannelProgressDispatching' in factory, 'Normal factory can erase the final-forward protocol')
typed = re.search(r'let (\w+) = underlying as\? any NativeChannelProgressDispatching', factory)
require(typed and 'underlying: ' + typed.group(1) in factory, 'Factory does not use its typed private delegate')
require('stillCurrent()' in factory and 'currentRuntime' in factory and 'selected: selected' in factory, 'Normal factory drops current route/session/selection')
require('nativeChannelProgressSelection:' in app and 'nativeChannelProgressReceiptApproval:' in app, 'Normal selectors are absent')
for name in ['nativeChannelProgressSelection', 'nativeChannelProgressReceiptApproval']:
    line = next(line for line in app.splitlines() if 'var ' + name + ':' in line)
    require('in nil }' in line, f'{name} no longer defaults closed')
normal = function(session, 'makeNativeChannelProgressFlow')
require('sourceCurrent()' in normal and 'channels.contextIsCurrent(captured)' in normal, 'Normal flow does not bind real parent route/context')
require('NativeChannelProgressSecureJournalStorage(storage: ProjectEditSecureStorage' in normal, 'Normal flow uses unprotected or replacement journal storage')
require('nativeChannelProgressReceiptApproval(context, captured, command)' in normal, 'Original command is not passed to independent receipt selector')
require('NativeChannelProgressBinding.make(context: captured, provider: channels' in normal, 'Real channel binding was bypassed')
require('URLSessionTransport(' not in normal and 'NativeChannelProgressFileStorage(' not in normal, 'Normal flow opens a generic dispatch/storage fallback')
# Read-only integration checks for the parent's narrow native resume adapter.
auth = (ROOT / 'Core/AuthService.swift').read_text()
network = (ROOT / 'Core/NativeChannelProgressNetworkForward.swift').read_text()
require('extension URLSessionTransport: NativeChannelProgressDispatching' not in auth, 'Same-file conformance can infer global actor isolation on the old transport')
require('extension URLSessionTransport: NativeChannelProgressDispatching' in network, 'Typed native dispatcher conformance is absent')
inert = function(auth, 'makeNativeChannelProgressTask')
require('session.dataTask(with: request, completionHandler: completion)' in inert and '.resume(' not in inert, 'Shared helper performs a network send rather than returning an inert task')
require('guard terminal == nil, fence.isCurrent else' in network and 'task.resume()' in network, 'Physical resume does not consume the composed fence')
resume_start = network.index('@MainActor func resume(')
resume_body = network[resume_start:network.index('\n    }', resume_start)]
require('await ' not in resume_body and 'DispatchQueue' not in resume_body, 'A suspension/queue appears inside the final resume boundary')
# Select the exchange implementation, not the task protocol declaration.
cancel_start = network.index('    func cancel() {')
cancel = network[cancel_start:network.index('\n    }', cancel_start)]
require(cancel.index('active?.cancel()') < cancel.index('waiting?.resume(with: result)'), 'Cancellation publishes completion before cancelling the native task')
require('completionHandler(nil)' in auth and 'configuration.httpCookieStorage = nil' in auth and 'configuration.urlCache = nil' in auth, 'Existing redirect/cookie/cache suppression was lost')
expected = ['testRealServiceWireBytesPassUnchangedForEveryApprovedOperation', 'testReceiptNeedsOriginalAndSeparateExactApprovalEvenWhenGeneralPathIsListed',
    'testIndependentOperationAndEndpointCannotGrantEachOther', 'testExtraHeadersBodyQueriesCookiesAndOriginPrefixAreRejected',
    'testFilterAndSubjectQueriesCannotCrossReadKindsOrOwners', 'testPrivacyPOSTRequiresOriginalScopesCASAndExactSerializedBytes',
    'testQueuedDelegateConsumesComposedFenceBeforePhysicalForward', 'testQueuedOriginalJournalMustPreserveWireBytesNotUnicodeEquality', 'testLate401ResponseOrErrorCannotLogOutNewVisit',
    'testObservedOwnerOrAncestorRetirementDoesNotReviveByABA', 'testUnknownJournalDoesNotBlockNonRecoveryReadsOrRewriteBytes',
    'testReceiptApprovalRevokedBetweenValidationAndForwardIsNotSent']
for name in expected:
    require('func ' + name + '(' in tests, f'Missing regression: {name}')
require('await queued?()' in tests and 'guard fence.isCurrent else' in tests, 'Queued test does not consume the actual composed fence')
print(f'PASS: typed composed final-forward fence, independent operation/path/receipt approval, exact request policy, normal App factory, and {len(expected)} authored regressions.')
print('Static verification only. Swift/XCTest and Apple runtime execution remain NOT_RUN when no compiler is available.')

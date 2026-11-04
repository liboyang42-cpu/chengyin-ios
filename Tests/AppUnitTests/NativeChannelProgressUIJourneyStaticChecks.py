#!/usr/bin/env python3
"""Offline source assertions only. No Swift compilation, XCTest or device execution."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'App'
entry = (APP / 'NativeChannelProgressEntry.swift').read_text()
board = (APP / 'NativeChannelProgressBoardView.swift').read_text()
privacy = (APP / 'NativeChannelProgressPrivacyView.swift').read_text()
history = (APP / 'NativeChannelProgressOwnHistoryView.swift').read_text()
tests = Path(__file__).with_name('NativeChannelProgressUIJourneyTests.swift').read_text()

def require(condition, message):
    if not condition:
        raise AssertionError(message)

def between(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]

# Real path and per-input identity, not SwiftUI child visibility, own the authority.
require('let routeIsPresented: Binding<Bool>' in entry, 'Missing real parent path binding')
require('.constant(true)' not in entry, 'Constant path can revive a detached visit')
require('.task(id: inputIdentity)' in entry, 'Channel/provider input reuse is not fenced')
require('owner.entryIdentity == inputIdentity, let model = owner.model' in entry, 'Old-input data can flash before the next task')
require('ObjectIdentifier(provider)' in entry and 'entryIdentity != identity' in entry, 'Input owner identity missing')
require('.onDisappear { if !routeIsPresented.wrappedValue { owner.retire() } }' in entry, 'Child push incorrectly retires root')
require('if phase == .active { reopen() } else { owner.retire() }' in entry, 'Scene return must use a new owner')
require('guard sourceCurrent(), !Task.isCancelled, context.channelID == channelID' in entry, 'Late context is not fenced')
require('provider.contextIsCurrent(context)' in entry and 'try makeFlow(context, sourceCurrent)' in entry, 'Real context/source fence not propagated')
require('guard sourceCurrent(), !Task.isCancelled else { next?.invalidate(); return }' in entry, 'Late factory can install old owner')
require('self.acceptsOperations, self.visitID == visit' in entry and '[weak self]' in entry, 'Old source can retain/revive owner')
loaded = between(entry, '@MainActor private struct NativeChannelProgressLoadedView', '@MainActor struct NativeChannelProgressIssueView')
require('model.invalidate()' not in loaded and 'model.activate()' not in loaded, 'Loaded child owns the parent lifetime')
require('routeIsPresented.wrappedValue = false' in entry, 'Done does not close actual route')

# Complete v2 read-only journey and honest absence are still present.
for token in ['model.overview', 'overview.members', 'overview.teams', 'model.definitions', 'NativeChannelProgressPrivacyView', 'NativeChannelProgressBoardView', 'loadDirectory()']:
    require(token in loaded, 'Overview/directory feature lost: ' + token)
for token in ['"top"', '"detail"', '"ALL","TOPIC","WEEK","MONTH"', '"completed"', '"team_id"', 'teamIndexUnavailable', 'page.me', 'model.meter', 'NativeChannelProgressOwnHistoryView', 'model.checkVersion()', 'model.loadMore(detail: detail)']:
    require(token in board, 'Board feature lost: ' + token)
for token in ['model.best', 'model.recent', 'page.nextCursor', 'model.loadMore(history: true)', 'model.refreshOwnHistory()']:
    require(token in history, 'Own-history feature lost: ' + token)
require('let teamOptions: [NativeChannelProgressTeamOption]?' in board, 'Unavailable team source was fabricated')
require('.disabled(!model.isCurrent)' in board, 'Filters cannot record new intent while previous read is busy')
require('pending = query' in board and 'self.resume(isCurrent:' in board, 'Latest intent does not drain serially')
require('guard !isBusy(), let query = self.pending' in board, 'Busy must be checked at actual task execution')
require('.onChange(of: model.busy)' in board, 'Externally busy work cannot resume pending intent')
require('if !selections.hasPendingSelection, let page' in board, 'Old period rows can appear under new filter')
require('Task.sleep' not in board and 'while ' not in re.sub(r'//[^\n]*', '', board), 'Unbounded retry/polling introduced')
for text in [loaded, board, history]:
    require('savePrivacy(' not in text and 'recoverOriginal(' not in text, 'Read-only journey became a writer')

# Privacy review is immutable and checked both at click and dispatch.
for token in ['originalPending', 'command.requestId', 'model.recoverOriginal()', 'model.recoverOriginal(retryOriginal: true)', 'receipt.status == "APPLIED"', 'model.privacyPhase == .unresolved', 'model.privacyPhase == .conflict', 'model.privacyPhase == .persistenceFailed']:
    require(token in privacy, 'Original write recovery feature lost: ' + token)
require('let current: NativeChannelProgressPrivacy' in privacy and 'let values: NativeChannelProgressPrivacyValues' in privacy, 'Review does not capture exact current settings and draft')
require('current == review.current && draft == review.values' in privacy, 'Review validation ignores a changed revision/current/draft')
require('generation == review.generation' in privacy, 'ABA draft/appearance can revive confirmation')
require('confirmation.consume(current: model.privacy, draft: draft, canSave: model.canSavePrivacy)' in privacy, 'Click-time confirmation missing')
require('confirmation.validates(review, current: model.privacy, draft: draft, canSave: model.canSavePrivacy)' in privacy, 'Dispatch-time confirmation missing')
require('.onChange(of: model.privacy)' in privacy and '.onChange(of: draft)' in privacy, 'New settings/edit do not retire dialog')
require('owner.open(parentCurrent: { visibility.wrappedValue }, privacyOnly: true)' in privacy, 'Standalone privacy has no own visible visit')
require('model.activatePrivacy()' not in privacy, 'Privacy view attempts to reactivate retired coordinator')
require('UUID().uuidString' not in privacy, 'UI minted its own replacement write UUID')
for name, text in [('board', board), ('privacy', privacy), ('history', history)]:
    require('actions.retire()' in text, f'{name} does not cancel queued clicks on exit')
    require('Task {' not in text.split('@MainActor struct NativeChannelProgress' + {'board':'BoardView','privacy':'PrivacyView','history':'OwnHistoryView'}[name], 1)[1], f'{name} leaves unowned async click tasks')

expected_tests = [
 'testLateFactoryAfterExitCannotInstallOrActivateCoordinator',
 'testForegroundCreatesNewOwnerAndOldSourceNeverRevives',
 'testChildPushDoesNotRetireParentButClosedBindingBlocksReopen',
 'testDroppedEntryOwnerIsNotRetainedByItsCapturedSource',
 'testStandalonePrivacyVisitUsesNewFactoryAfterRetirement',
 'testChannelAndProviderInputChangesRetireLateFactory',
 'testRunningOldSelectionCannotOverwriteFreshVisitQueue',
 'testBusySelectionKeepsOnlyNewestPeriodAndFilterIntent',
 'testRunningSelectionFinishesThenDispatchesLatestWithoutRetryingIntermediate',
 'testSelectionChecksBusyAgainAtTaskExecution',
 'testRetiredSelectionCannotDrainIntoNewVisit',
 'testQueuedChildActionDoesNotRunAfterExitOrReappearance',
 'testPrivacyReviewRejectsChangedRevisionAndChangedDraft',
 'testPrivacyReviewRejectsSameRevisionDifferentCurrentSettings',
 'testConsumedPrivacyReviewRechecksAtActualDispatch',
 'testPrivacyEditABAAndRefreshCannotReuseOriginalConfirmation',
 'testCurrentPrivacyReviewRetainsExactValuesAndIsConsumedOnlyOnce',
 'testTeamOptionsCannotInventInvalidIdentifiersOrNames',
]
for name in expected_tests:
    require(f'func {name}(' in tests, 'Missing authored regression: ' + name)
require('@testable import Questify' in tests and 'NativeChannelProgressVisitOwner()' in tests, 'Tests do not exercise app implementation')
print(f'PASS: 4 restored UI leaves; route/input/late-context/lifecycle, latest intent, privacy confirmation and retained-feature source assertions; {len(expected_tests)} authored Swift regressions.')
print('NOT RUN: Swift compilation, XCTest and simulator/device UI. Python assertions do not establish Apple execution or release readiness.')

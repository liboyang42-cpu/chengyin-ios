"""Static repair boundaries, not a substitute for Apple fixture/runtime execution."""
from pathlib import Path
from tools.branch_history_handshake_planning import retained_protected_source
import hashlib
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs/branch-history-handshake'
UI = ROOT / 'Tests/AppUITests/PlayBranchHistoryLifetimeFlowTests.swift'
HOST = ROOT / 'App/PlayBranchHistoryFixtureSupport.swift'
VIEW = ROOT / 'App/PlayBranchHistoryView.swift'
APP_UNIT = ROOT / 'Tests/AppUnitTests/PlayBranchHistoryFixtureHandshakeTests.swift'
ADDED = '''            let oldRow = element("branchHistory.row.0", in: app)
            XCTAssertTrue(oldRow.waitForExistence(timeout: 5)); XCTAssertTrue(revealFixtureElement(oldRow, in: app))
            XCTAssertTrue(oldRow.isHittable); XCTAssertTrue(oldRow.label.contains("Synthetic courtyard"))
            let apply = app.buttons["branchHistory.fixture.applyPresented"]
            XCTAssertTrue(apply.waitForExistence(timeout: 5)); XCTAssertTrue(apply.isHittable); apply.tap()
'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify_handshake(source):
    assert source.startswith('#if DEBUG\n') and source.rstrip().endswith('#endif')
    assert not re.search(r'Task\.sleep|asyncAfter|Timer\(|scheduleChange', source)
    for token in ['static let defaultValue: PlayBranchHistoryFixtureHandshake? = nil',
                  'armed != nil && !applying && history?.state == .recorded && history?.rows.isEmpty == false',
                  'guard canApply(history), let action = armed else { return false }',
                  'armed = nil; applying = true; consumedCount += 1',
                  'func disarm() { armed = nil }', 'guard !Task.isCancelled, generation == current else { return }']:
        assert token in source, token
    arm = re.search(r'func arm\([^\n]+', source).group(0)
    assert 'perform(' not in arm and 'Task' not in arm
    assert source.index('armed = nil; applying = true; consumedCount += 1') < source.index('await perform(action)')



def verify_readiness_cleanup(source):
    """Source regression only: Apple must execute the asynchronous timeout/cancel cases."""
    def block(declaration):
        match = re.search(r'(?m)^    ' + re.escape(declaration) + r'[^\n]*\n[\s\S]*?^    }', source)
        assert match is not None, declaration
        return match.group(0)

    def ordered(text, *tokens):
        cursor = 0
        for token in tokens:
            assert token in text[cursor:], token
            cursor = text.index(token, cursor) + len(token)

    main = block('func testDismissalDuringRefreshDoesNotCancelTheNormalReadOrAllowSecondAction()')
    assert 'Task.yield()' not in main
    ordered(main, 'let pause = SuspendedRead()', 'await pause.wait()',
            'defer { pause.release(); handshake.cancel() }', 'handshake.apply(history)',
            'let ready = await pause.waitUntilReady(timeout: 2)',
            'let continuation = pause.continuation', 'XCTAssertNotNil(continuation)',
            'guard ready, continuation != nil else {',
            'XCTFail("Synthetic history read did not suspend before the readiness deadline")',
            'return\n        }', 'handshake.disarm(); handshake.arm(.switchOwner)',
            'XCTAssertNil(handshake.armed); XCTAssertFalse(handshake.apply(history))',
            'pause.release(); await handshake.waitForChange()',
            'XCTAssertFalse(handshake.applying); XCTAssertEqual(actions, [.refresh])')
    gate = block('@MainActor private final class SuspendedRead')
    ordered(gate, 'private var released = false', 'await withCheckedContinuation { continuation in',
            'guard !released else { continuation.resume(); return }',
            'self.continuation = continuation', 'started.fulfill()')
    ordered(gate, 'func waitUntilReady(timeout: TimeInterval)',
            'await XCTWaiter.fulfillment(of: [started], timeout: timeout)',
            'return result == .completed && continuation != nil')
    ordered(gate, 'func release()', 'released = true',
            'let pending = continuation; continuation = nil', 'pending?.resume()')
    cancellation = block('func testLeavingFixtureCancelsQueuedChangeBeforeAnyRead()')
    ordered(cancellation, 'handshake.cancel()',
            'XCTAssertEqual(calls, 0); XCTAssertNil(handshake.armed); XCTAssertFalse(handshake.applying)',
            'await assertReadinessTimeoutReleasesLateContinuation()',
            'try await assertCancellationReleasesRegisteredContinuation()')
    timeout = block('private func assertReadinessTimeoutReleasesLateContinuation()')
    ordered(timeout, 'defer { pause.release() }', 'await pause.waitUntilReady(timeout: 0.01)',
            'XCTAssertFalse(ready); XCTAssertNil(pause.continuation)',
            'pause.release(); pause.release()', 'let task = Task { await pause.wait(); finished.fulfill() }',
            'defer { pause.release(); task.cancel() }',
            'await fulfillment(of: [finished], timeout: 2)', 'XCTAssertNil(pause.continuation)')
    cancelled = block('private func assertCancellationReleasesRegisteredContinuation()')
    ordered(cancelled, 'await pause.wait(); finished.fulfill()',
            'defer { pause.release(); handshake.cancel() }', 'handshake.apply(try recorded())',
            'await pause.waitUntilReady(timeout: 2)',
            'guard ready else { XCTFail("Synthetic cancellation read did not start"); return }',
            'handshake.cancel()', 'XCTAssertNotNil(pause.continuation)',
            'pause.release(); pause.release()', 'await fulfillment(of: [finished], timeout: 2)',
            'XCTAssertNil(pause.continuation); XCTAssertNil(handshake.armed); XCTAssertFalse(handshake.applying)')


def verify_budget(budget):
    expected = {'previousRequiredFloorSeconds': 410, 'launchCount': 2,
                'launchAssumptionSeconds': 90, 'explicitWaitCapsSeconds': 96,
                'revealCount': 6, 'iterationsPerReveal': 11, 'secondsPerRevealIteration': 2,
                'existingMiscellaneousSeconds': 60, 'addedActionAndQueryAllowanceSeconds': 20,
                'subtotalSeconds': 488, 'changedMethodSeconds': 490,
                'unchangedLinearMethodSeconds': 160, 'classSeconds': 650,
                'startupSeconds': 300, 'headroomSeconds': 30, 'plannedShardSeconds': 980}
    for key, value in expected.items(): assert budget[key] == value, key
    assert budget['centralProfilesModified'] is False
    assert budget['changedMethodSeconds'] >= budget['previousRequiredFloorSeconds']
    assert budget['changedMethodSeconds'] <= 900 and budget['plannedShardSeconds'] <= 1800


class BranchHistoryFixtureHandshakeTests(unittest.TestCase):
    def test_frozen_production_and_central_contracts_unchanged(self):
        for path, expected in json.loads((DOCS / 'protected-baseline.json').read_text())['protected'].items():
            self.assertEqual(digest(retained_protected_source(ROOT / path)), expected, path)

    def test_release_view_exactly_reconstructs_original_bytes(self):
        source = VIEW.read_text()
        # All additions in this production-path file are strictly within DEBUG blocks.
        # Keep the preceding production newline; only the exact DEBUG blocks disappear.
        projected = re.sub(r'(?m)^[ \t]*#if DEBUG\n[\s\S]*?^[ \t]*#endif\n', '', source)
        expected = json.loads((DOCS / 'protected-baseline.json').read_text())['releaseViewSHA256']
        self.assertEqual(digest(projected.encode()), expected)

    def test_debug_handshake_default_nil_no_timer_and_once_only(self):
        verify_handshake(HOST.read_text())

    def test_restoring_a_timer_is_rejected(self):
        with self.assertRaises(AssertionError):
            verify_handshake(HOST.read_text().replace('await perform(action)', 'try? await Task.sleep(for: .seconds(3)); await perform(action)'))

    def test_removing_armed_recorded_or_nonempty_guard_is_rejected(self):
        for guard in ['armed != nil && ', 'history?.state == .recorded && ', ' && history?.rows.isEmpty == false']:
            with self.subTest(guard=guard), self.assertRaises(AssertionError):
                verify_handshake(HOST.read_text().replace(guard, '', 1))

    def test_default_fixture_injection_and_release_leak_are_rejected(self):
        with self.assertRaises(AssertionError):
            verify_handshake(HOST.read_text().replace('defaultValue: PlayBranchHistoryFixtureHandshake? = nil', 'defaultValue: PlayBranchHistoryFixtureHandshake? = .init { _ in }'))
        with self.assertRaises(AssertionError): verify_handshake(HOST.read_text().removeprefix('#if DEBUG\n'))

    def test_sheet_control_requires_injected_current_recorded_history(self):
        source = VIEW.read_text()
        self.assertIn('if let fixtureHandshake, fixtureHandshake.canApply(history)', source)
        self.assertIn('Button("Apply armed fixture change") { fixtureHandshake.apply(history) }', source)
        self.assertIn('.onDisappear { fixtureHandshake?.disarm() }', source)
        self.assertNotIn('dismiss()', HOST.read_text())

    def test_release_button_count_rejects_extra_production_action(self):
        from Tests.ContractChecks.test_play_branch_history import branch_history_release_source
        source = VIEW.read_text().replace('}.privacySensitive()', 'Button("Unexpected") {}\n        }.privacySensitive()')
        self.assertNotEqual(branch_history_release_source(source).count('Button('), 1)

    def test_release_count_rejects_changed_or_unguarded_fixture_button(self):
        from Tests.ContractChecks.test_play_branch_history import branch_history_release_source
        source = VIEW.read_text()
        for changed in [source.replace('Button("Apply armed fixture change")', 'Button("Another action")'),
                        source.replace('                #if DEBUG\n', '', 1),
                        source.replace('fixtureHandshake.canApply(history)', 'true'),
                        source.replace('                    ToolbarItem(placement: .bottomBar)', '                    Button("Extra debug action") {}\n                    ToolbarItem(placement: .bottomBar)')]:
            with self.subTest(source=changed), self.assertRaises(AssertionError):
                branch_history_release_source(changed)

    def test_original_ui_file_reconstructs_by_removing_only_added_handshake(self):
        source = UI.read_text(); self.assertEqual(source.count(ADDED), 1)
        original = source.replace(ADDED, '', 1)
        expected = json.loads((DOCS / 'protected-baseline.json').read_text())['oldLifetimeSHA256']
        self.assertEqual(digest(original.encode()), expected)

    def test_ui_observes_old_rows_before_explicit_action_and_keeps_withdrawal(self):
        source = UI.read_text()
        positions = [source.index(token) for token in [
            'app.buttons[action].tap(); open(app)', 'oldRow.waitForExistence(timeout: 5)',
            'revealFixtureElement(oldRow, in: app)', 'oldRow.isHittable',
            'oldRow.label.contains("Synthetic courtyard")', 'apply.waitForExistence(timeout: 5)',
            'apply.tap()', 'waitForExpectations(timeout: 8)',
            'XCTAssertFalse(element("branchHistory.row.0", in: app).exists)',
            'open(app); XCTAssertTrue(element("branchHistory.empty", in: app).waitForExistence(timeout: 5))']]
        self.assertEqual(positions, sorted(positions))
        self.assertIn('for action in ["branchHistory.fixture.delayedRefresh", "branchHistory.fixture.delayedSwitch"]', source)

    def test_budget_includes_both_complete_loops_and_preserves_floor(self):
        budget = json.loads((DOCS / 'ui-budget-assumptions.json').read_text())
        verify_budget(budget)
        subtotal = budget['launchCount'] * budget['launchAssumptionSeconds'] + budget['explicitWaitCapsSeconds']
        subtotal += budget['revealCount'] * budget['iterationsPerReveal'] * budget['secondsPerRevealIteration']
        subtotal += budget['existingMiscellaneousSeconds'] + budget['addedActionAndQueryAllowanceSeconds']
        self.assertEqual(subtotal, 488); self.assertEqual(budget['subtotalSeconds'], subtotal)
        self.assertEqual(budget['changedMethodSeconds'], 490)
        self.assertGreaterEqual(budget['changedMethodSeconds'], budget['previousRequiredFloorSeconds'])
        self.assertLessEqual(budget['changedMethodSeconds'], 900)
        self.assertEqual(budget['classSeconds'] + budget['startupSeconds'] + budget['headroomSeconds'], 980)
        self.assertLessEqual(budget['plannedShardSeconds'], 1800)
        self.assertFalse(budget['centralProfilesModified'])
        self.assertEqual(digest(UI.read_bytes()), budget['newFileSHA256'])

    def test_reduced_floor_missing_loop_or_extra_action_cost_is_rejected(self):
        budget = json.loads((DOCS / 'ui-budget-assumptions.json').read_text())
        for key in ['previousRequiredFloorSeconds', 'launchCount', 'explicitWaitCapsSeconds',
                    'revealCount', 'addedActionAndQueryAllowanceSeconds', 'changedMethodSeconds',
                    'unchangedLinearMethodSeconds', 'startupSeconds', 'headroomSeconds']:
            changed = dict(budget); changed[key] -= 1
            with self.subTest(key=key), self.assertRaises(AssertionError): verify_budget(changed)

    def test_method_hash_uses_the_central_declaration_convention(self):
        budget = json.loads((DOCS / 'ui-budget-assumptions.json').read_text())
        pattern = r'(?m)^    (func (test\w+)\b[\s\S]*?^    })'
        current = dict((name, body) for body, name in re.findall(pattern, UI.read_text()))
        old = dict((name, body) for body, name in re.findall(pattern, UI.read_text().replace(ADDED, '', 1)))
        self.assertEqual(len(current), 2); self.assertEqual(set(current), set(old))
        target = budget['changedMethod']
        self.assertEqual(digest(current[target].encode()), budget['newMethodSHA256'])
        self.assertEqual(digest(old[target].encode()), budget['oldMethodSHA256'])
        self.assertEqual(digest(('    ' + current[target]).encode()), budget['newIndentedMethodSHA256'])
        linear = 'testLinearSummaryHasNoHistoryEntryBeforeOrAfterRefresh'
        self.assertEqual(current[linear], old[linear])

    def test_app_unit_scenarios_are_authored_and_not_advertised_as_executed(self):
        source = (ROOT / 'Tests/AppUnitTests/PlayBranchHistoryFixtureHandshakeTests.swift').read_text()
        self.assertEqual(len(re.findall(r'    func test', source)), 8)
        for token in ['EnvironmentValues().branchHistoryFixtureHandshake', 'handshake.disarm()',
                      'handshake.cancel()', 'oldCount + 2', 'selection.presentation(snapshot: model.snapshot)',
                      'XCTAssertFalse(model.canWrite)', 'XCTAssertNil(model.reward)']:
            self.assertIn(token, source)
        self.assertIn('Apple simulator/typecheck/runtime remains NOT_RUN', (DOCS / 'contract.md').read_text())


    def test_app_unit_readiness_has_bounded_signal_guard_and_explicit_cleanup(self):
        verify_readiness_cleanup(APP_UNIT.read_text())

    def test_yield_polling_or_missing_readiness_return_is_rejected(self):
        source = APP_UNIT.read_text()
        for old, new in [
            ('let ready = await pause.waitUntilReady(timeout: 2)', 'let ready = true; await Task.yield()'),
            ('            return\n        }', ''),
            ('guard ready, continuation != nil else {', 'if false {')]:
            with self.subTest(old=old), self.assertRaises(AssertionError):
                verify_readiness_cleanup(source.replace(old, new, 1))

    def test_cancel_alone_or_missing_deferred_cancellation_is_rejected(self):
        source = APP_UNIT.read_text()
        for cleanup in ['defer { handshake.cancel() }', 'defer { pause.release() }']:
            with self.subTest(cleanup=cleanup), self.assertRaises(AssertionError):
                verify_readiness_cleanup(source.replace('defer { pause.release(); handshake.cancel() }', cleanup, 1))

    def test_late_registration_or_non_idempotent_release_regressions_are_rejected(self):
        source = APP_UNIT.read_text()
        for token in ['guard !released else { continuation.resume(); return }',
                      'released = true', 'continuation = nil', 'pending?.resume()']:
            with self.subTest(token=token), self.assertRaises(AssertionError):
                verify_readiness_cleanup(source.replace(token, '', 1))

    def test_signal_before_registration_or_unchecked_waiter_result_is_rejected(self):
        source = APP_UNIT.read_text()
        for old, new in [
            ('self.continuation = continuation\n                started.fulfill()',
             'started.fulfill()\n                self.continuation = continuation'),
            ('return result == .completed && continuation != nil', 'return continuation != nil')]:
            with self.subTest(old=old), self.assertRaises(AssertionError):
                verify_readiness_cleanup(source.replace(old, new, 1))

    def test_removing_timeout_or_cancel_regression_execution_is_rejected(self):
        source = APP_UNIT.read_text()
        for token in ['await assertReadinessTimeoutReleasesLateContinuation()',
                      'try await assertCancellationReleasesRegisteredContinuation()',
                      'pause.release(); pause.release()',
                      'defer { pause.release(); task.cancel() }',
                      'XCTAssertNotNil(pause.continuation)']:
            with self.subTest(token=token), self.assertRaises(AssertionError):
                verify_readiness_cleanup(source.replace(token, '', 1))


if __name__ == '__main__': unittest.main()

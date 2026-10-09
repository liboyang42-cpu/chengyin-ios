"""DEBUG ownership source regressions. These are not SwiftUI runtime execution."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / 'App/PlayBranchHistoryFixtureSupport.swift'
APP_UNIT = ROOT / 'Tests/AppUnitTests/PlayBranchHistoryFixtureHandshakeTests.swift'


def verify_lifetime(source):
    assert source.startswith('#if DEBUG\n') and source.rstrip().endswith('#endif')
    assert '@MainActor final class PlayBranchHistoryFixtureState {' in source, 'Missing retained fixture dependency graph'
    host, graph = source.split('@MainActor final class PlayBranchHistoryFixtureState {', 1)
    graph, _ = graph.split('/// Opt-in AppUnit observation', 1)
    assert re.findall(r'@State private var (\w+): (\w+)', host) == [
        ('fixture', 'PlayBranchHistoryFixtureState')], 'Host must retain one entire dependency graph'
    assert '_fixture = State(initialValue: PlayBranchHistoryFixtureState(scenario: selected))' in host
    assert not re.search(r'(?:let|var) (?:owner|recorder|model|handshake)\s*:', host)
    for token in ['let model = fixture.model', 'PlayExperienceView(model: model)',
                  '.environment(\\.branchHistoryFixtureHandshake, fixture.handshake)',
                  'Button("Refresh with empty history") { Task { await fixture.replaceHistory() } }',
                  'fixture.handshake.arm(.refresh)', 'fixture.handshake.arm(.switchOwner)',
                  'fixture.handshake.cancel()\n            fixtureObserver?(fixture, .disappeared)',
                  'PlayBranchHistoryFixtureProbe(fixture: fixture, revision: probeRevision,',
                  'phase: fixture.model.phase, observe: fixtureObserver)',
                  'if let fixtureObserver {']:
        assert token in host, token
    for token in ['private let owner: Owner', 'let recorder: PlayRecoveryRecordingTransport',
                  'let model: PlayExperienceCoordinator', 'let handshake: PlayBranchHistoryFixtureHandshake',
                  'let owner = Owner(), recorder = PlayRecoveryRecordingTransport()',
                  'transport: recorder, enabled: [.reads]', 'currentSession: { owner.session }',
                  'self.owner = owner; self.recorder = recorder; self.model = model',
                  'handshake = PlayBranchHistoryFixtureHandshake { action in',
                  'owner.session = try! .init(accountID: 9002, epoch: 2,', 'model.invalidate()']:
        assert token in graph, token
    refresh = ('Self.configure(recorder, log: "[]", sessionID: 502, version: 0)\n'
               '        await model.load()')
    assert refresh in graph, 'Immediate refresh must configure and load the retained graph'
    assert graph.count('Self.configure(recorder, log: "[]", sessionID: 502, version: 0)') == 2
    assert 'func replaceHistory() async {' in graph
    assert 'PlayBranchHistoryFixtureState(' not in graph, 'Actions must not create a replacement graph'
    assert not re.search(r'Task\.sleep|asyncAfter|Timer\(|URLSession', source)


def verify_mounted_regressions(source):
    assert len(re.findall(r'    func test', source)) == 8
    for token in ['try await assertHostReconstructionRefreshesTheRetainedRecorder()',
                  'try await assertLeavingAndReenteringFixtureResetsItsDependencyGraph()',
                  '@ObservedObject var signal: RebuildSignal',
                  'PlayBranchHistoryFixtureHost(scenario: "recorded", fixtureObserver: observe,',
                  'UIHostingController(rootView: RebuildingHost(signal: signal, observe:',
                  'window.makeKeyAndVisible()', 'defer { mount.close() }',
                  'guard event == .rendered(revision), fixture.model.phase == .ready, result == nil',
                  'await fulfillment(of: [ready], timeout: 2)',
                  'return try XCTUnwrap(result,', 'for revision in [1, 2]',
                  'mount.signal.revision = revision', 'XCTAssertTrue(current === original)',
                  'XCTAssertTrue(current.recorder === original.recorder)',
                  'XCTAssertTrue(current.model === original.model)',
                  'XCTAssertTrue(current.handshake === original.handshake)',
                  'await current.replaceHistory()',
                  'XCTAssertEqual(PlayBranchHistoryPresentation(snapshot: snapshot).state, .empty)',
                  'XCTAssertEqual(snapshot.route?.sessionID, 502)',
                  'XCTAssertEqual(snapshot.route?.version, 0)',
                  'XCTAssertEqual(original.recorder.requests.count, oldCount + 2)',
                  'XCTAssertNil(selection.presentation(snapshot: original.model.snapshot))',
                  'original.handshake.cancel(); await original.handshake.waitForChange()',
                  'mount.signal.mounted = false', 'guard event == .disappeared, !observedExit',
                  'XCTAssertNil(fixture.handshake.armed); XCTAssertFalse(fixture.handshake.applying)',
                  'await fulfillment(of: [disappeared], timeout: 2)',
                  'mount.signal.revision = 1; mount.signal.mounted = true',
                  'XCTAssertFalse(current.recorder === original.recorder)',
                  'XCTAssertFalse(current.model === original.model)',
                  'XCTAssertFalse(current.handshake === original.handshake)',
                  'XCTAssertEqual(current.session.accountID, 9001)',
                  'XCTAssertEqual(current.handshake.consumedCount, 0)',
                  'XCTAssertEqual(PlayBranchHistoryPresentation(snapshot: freshSnapshot).state, .recorded)',
                  'XCTAssertEqual(freshSnapshot.route?.sessionID, 501)',
                  'XCTAssertEqual(freshSnapshot.route?.version, 2)',
                  'XCTAssertEqual(original.recorder.requests.count, retiredCount)',
                  'XCTAssertFalse(current.model.canWrite); XCTAssertNil(current.model.reward); XCTAssertNil(current.model.ending)']:
        assert token in source, token


class BranchHistoryFixtureLifetimeTests(unittest.TestCase):
    def test_entire_fixture_graph_has_one_mounted_state_lifetime(self):
        verify_lifetime(HOST.read_text())

    def test_plain_value_ownership_or_new_action_graph_is_rejected(self):
        source = HOST.read_text()
        for old, new in [
            ('@State private var fixture:', 'private var fixture:'),
            ('await fixture.replaceHistory()', 'await PlayBranchHistoryFixtureState(scenario: "recorded").replaceHistory()'),
            ('transport: recorder, enabled: [.reads]', 'transport: PlayRecoveryRecordingTransport(), enabled: [.reads]'),
            ('currentSession: { owner.session }', 'currentSession: { Owner().session }'),
            ('await model.load()', 'await PlayBranchHistoryFixtureState(scenario: "recorded").model.load()'),
        ]:
            with self.subTest(old=old), self.assertRaises(AssertionError):
                verify_lifetime(source.replace(old, new))

    def test_cancel_and_opt_in_observer_guards_are_retained(self):
        source = HOST.read_text()
        for token in ['fixture.handshake.cancel()', 'if let fixtureObserver {',
                      'phase: fixture.model.phase, observe: fixtureObserver)', '#if DEBUG\n']:
            with self.subTest(token=token), self.assertRaises(AssertionError):
                verify_lifetime(source.replace(token, '', 1))

    def test_hosted_reconstruction_removal_reentry_and_reads_are_authored(self):
        verify_mounted_regressions(APP_UNIT.read_text())

    def test_removing_hosted_regression_or_its_discriminating_assertions_is_rejected(self):
        source = APP_UNIT.read_text()
        for token in ['try await assertHostReconstructionRefreshesTheRetainedRecorder()',
                      'try await assertLeavingAndReenteringFixtureResetsItsDependencyGraph()',
                      'XCTAssertTrue(current.recorder === original.recorder)',
                      'XCTAssertEqual(original.recorder.requests.count, oldCount + 2)',
                      'XCTAssertEqual(PlayBranchHistoryPresentation(snapshot: snapshot).state, .empty)',
                      'mount.signal.mounted = false',
                      'XCTAssertEqual(original.recorder.requests.count, retiredCount)']:
            with self.subTest(token=token), self.assertRaises(AssertionError):
                verify_mounted_regressions(source.replace(token, '', 1))


if __name__ == '__main__':
    unittest.main()

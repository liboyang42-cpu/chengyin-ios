"""Source-only contracts for the normal task result / readback / return journey."""
import json
import pathlib
import re
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

class PlayTaskOutcomeJourneyChecks(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text()
    def test_normal_result_host_survives_missing_node_during_readback(self):
        source = self.read('App/PlayExperienceView.swift').split('@MainActor private struct PlayExperienceNodeView:', 1)[1]
        self.assertIn('List {\n            PlayTaskOutcomeSection(model: model, nodeID: nodeID)\n            if let node {', source)
        self.assertIn('await model.submit(review)', source)
        self.assertIn('PlayExperienceNodeView(nodeID: id, model: model', self.read('App/PlayExperienceView.swift'))

    def test_completion_needs_current_exact_authoritative_node(self):
        source = self.read('Core/PlayTaskOutcomePresentation.swift')
        for token in ['phase == "ready", isCurrentRead, let snapshot', 'snapshot.result.mode == 1',
                      'snapshot.availability == .active || snapshot.availability == .completed',
                      'snapshot.visibleNodes.first(where: { $0.id == nodeID })',
                      'if snapshot.isDone(node)', 'if unresolved || phase == "unknown"']:
            self.assertIn(token, source)
        for forbidden in ['receipt[', 'reward[', 'UserDefaults', 'Date()', 'requestReview', 'URLSession']:
            self.assertNotIn(forbidden, source)

    def test_next_task_is_unique_visible_unlocked_and_never_advances(self):
        source = self.read('Core/PlayTaskOutcomePresentation.swift')
        for token in ['$0.id != nodeID && $0.done == false && !snapshot.isDone($0) && !snapshot.isLocked($0)',
                      'if choices.count == 1, let next = choices.first',
                      'choices.count > 1 ? .chooseTask : .overview',
                      'snapshot.availability == .completed { continuation = .finished }']:
            self.assertIn(token, source)
        app = self.read('App/PlayTaskOutcomeSection.swift')
        self.assertNotIn('NavigationLink', app); self.assertNotIn('selectedNode =', app)
        self.assertIn('dismiss()', app)

    def test_all_states_and_continuations_have_bilingual_copy(self):
        strings = json.loads(self.read('Resources/PlayTaskOutcome.xcstrings'))['strings']
        states = ['awaitingRead', 'loading', 'reviewing', 'submitting', 'needsReadback', 'unknown', 'failed', 'completed', 'pending', 'locked', 'unavailable']
        keys = ['title', 'refresh', 'back'] + [prefix+s for prefix in ['state.', 'detail.'] for s in states] + ['continue.'+s for s in ['nextTask', 'chooseTask', 'finished', 'overview']]
        self.assertEqual(set(strings), set(keys))
        for key in keys:
            for lang in ['en', 'zh-Hans']:
                row = strings[key]['localizations'][lang]['stringUnit']
                self.assertEqual(row['state'], 'translated'); self.assertTrue(row['value'])
        self.assertIn('does not resend', strings['detail.unknown']['localizations']['en']['stringUnit']['value'])
        self.assertIn('does not mean', strings['detail.failed']['localizations']['en']['stringUnit']['value'])

    def test_read_only_action_has_current_owner_visit_and_consumption(self):
        source = self.read('App/PlayTaskOutcomeSection.swift')
        for token in ['visible, active, self.model === model, key == current',
                      'offered == current', 'guard accepts(offered, model: model, nodeID: nodeID), Self.canRead(model)',
                      'visit = UUID()\n        await model.load()', 'model.phase != .loading && model.phase != .submitting && model.phase != .reviewing']:
            self.assertIn(token, source)
        for forbidden in ['model.submit(', 'retryExactBranchAfterReadback', 'requestReview(', 'model.startRun(', 'URLSession']:
            self.assertNotIn(forbidden, source)

    def test_exit_background_and_owner_changes_retire_the_offer(self):
        source = self.read('App/PlayTaskOutcomeSection.swift')
        for token in ['private var model: PlayExperienceCoordinator?',
                      'if self.model !== model || key != next { visit = UUID();',
                      'func setActive(_ value: Bool) { if !value { visit = UUID() }; active = value }',
                      'func disappear() { visit = UUID(); visible = false; active = false }',
                      '.onChange(of: owner)', '.onDisappear { actions.disappear() }']:
            self.assertIn(token, source)
        # One concrete body row owns the actions, not a multi-row Section.
        self.assertLess(source.index('.onDisappear { actions.disappear() }'), source.index('} header:'))

    def test_current_issue_and_explicit_return_are_visible_without_a_new_command(self):
        source = self.read('App/PlayTaskOutcomeSection.swift')
        self.assertIn('if let issue = model.issue { PlayExperienceIssueView(issue: issue) }', source)
        self.assertIn('guard actions.accepts(ticket, model: model, nodeID: nodeID) else { return }\n                    dismiss()', source)
        self.assertIn('table: "PlayTaskOutcome", locale: locale', source)
        self.assertEqual(source.count('.buttonStyle(.borderless)'), 2)

    def test_native_cases_cover_exact_state_and_owner_negatives(self):
        core = self.read('Tests/CoreTests/PlayTaskOutcomePresentationTests.swift')
        app = self.read('Tests/AppUnitTests/PlayTaskOutcomeActionTests.swift')
        self.assertEqual(len(re.findall(r'func test\w+\(', core)), 12)
        self.assertEqual(len(re.findall(r'func test\w+\(', app)), 8)
        for token in ['testBranchHiddenNodeNameIsNeverExposed', 'testUnresolvedResultRemainsUnknownEvenWithDoneReadback', 'testUnavailableRegistrationDoesNotPromoteAnOldDoneFlag']:
            self.assertIn(token, core)
        for token in ['testAccountEpochChangeRejectsCallbackBeforeAnotherRead', 'testReplacementCoordinatorAndNodeNeverBorrowOldTicket', 'testOpenReviewCannotBeReplacedByARefreshAction']:
            self.assertIn(token, app)

if __name__ == '__main__': unittest.main()

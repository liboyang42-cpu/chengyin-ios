"""Focused source controls; they do not execute Swift or a device."""
from pathlib import Path
import json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
class PlayerActionReviewContract(unittest.TestCase):
    def setUp(self):
        self.core=(ROOT/'Core/PlayPlayerActionReview.swift').read_text()
        self.owner=(ROOT/'App/PlayPlayerActionReviewHost.swift').read_text()
        self.host=(ROOT/'App/PlayPlayerAndCircleViews.swift').read_text().split('@MainActor struct PlayCircleView:',1)[0]
    def test_normal_five_actions_all_use_current_ticket(self):
        for x in ['.role, ticket: ticket','.text(nodeID: node.id, answer: actionReview.text(nodeID: node.id)), ticket: ticket',
                  '.choice(nodeID: node.id, choiceID: id), ticket: ticket','.hint(nodeID: node.id), ticket: ticket','.reveal(nodeID: node.id), ticket: ticket']:
            self.assertIn('actionReview.prepare('+x+')',self.host)
        self.assertIn('let ticket = sameModel ? actionReview.capture() : nil',self.host)
        self.assertNotIn('.confirmationDialog(',self.host)
    def test_full_snapshot_session_and_original_allowed_actions(self):
        for x in ['hasCurrentProjection, phase == "ready", pending == nil',
                  'currentSession() == context.owner && projection == context.projection',
                  'guard snapshot.allows(command) else', 'guard !Task.isCancelled, acceptsPlayerActionReview(value) else']:
            self.assertIn(x,self.core)
        self.assertIn('await submit(value.command)',self.core)
    def test_exact_content_and_consequences_are_revalidated(self):
        for x in ['node.task["inputType"].text == "TEXT"','PlayPlayerCommand.textEvidence(answer)',
                  '.utf8.elementsEqual(choiceID.utf8)', 'question = node.task["prompt"].text; detail = answer',
                  'node.hint["nextLevel"].integer', 'node.hint["nextImpactLabel"].text', 'node.hint["revealImpactLabel"].text',
                  'encoder.outputFormatting = [.sortedKeys]', 'a.utf8.elementsEqual(b.utf8)',
                  'before == now && same(current.title, value.title)', 'same(current.consequence, value.consequence)']:
            self.assertIn(x,self.core)
    def test_claim_happens_synchronously_and_cannot_be_reused(self):
        for x in ['guard canConfirm(offered) else { return nil }','claimed = offered.id; working = true; review = nil',
                  'guard claimed == offered.id, working, current, visit == offered.visit, !Task.isCancelled',
                  'claimed = nil\n        defer', 'await model.submitPlayerActionReview(offered.value)']:
            self.assertIn(x,self.owner)
        self.assertLess(self.owner.index('guard let claim = owner.claim(offered)'),self.owner.index('Task { await owner.execute(claim) }'))
    def test_cancel_keeps_input_but_old_editing_ticket_is_rejected(self):
        self.assertIn('guard review?.id == offered.id else { return }; review = nil',self.owner)
        self.assertIn('return visit == ticket.visit && model.acceptsPlayerActionReview(ticket.context)',self.owner)
        self.assertIn('guard accepts(ticket), model.projection?.nodes.contains',self.owner)
        self.assertIn('actionReview.setText($0, nodeID: node.id, ticket: ticket)',self.host)
        self.assertNotIn('@State private var evidence:',self.host)
    def test_real_departure_and_background_clear_sensitive_state(self):
        for x in ['visit = UUID(); claimed = nil; review = nil; drafts = [:]',
                  'func background() { clearVisit(); active = false }',
                  'guard self.root === root, root.isActuallyLeaving else { return }; retire()',
                  'guard self.root === root else { return }', 'guard parent != nil else { return true }',
                  'navigation.topViewController !== current', 'tabs.selectedViewController !== current']:
            self.assertIn(x,self.owner)
        self.assertEqual(self.owner.count('owner?.departed(self)'),2)
        self.assertNotIn('owner?.retire()',self.owner)
        self.assertIn('if phase == .background { focusedNode = nil; actionReview.background() }',self.host)
    def test_stable_normal_owner_real_anchor_and_keyboard_completion(self):
        for x in ['@StateObject private var actionReview', 'actionReview.model === model',
                  'PlayPlayerActionRoot(owner: actionReview)', '.id(offered.id)',
                  '.onAppear { actionReview.appear(active: scenePhase == .active) }',
                  '.focused($focusedNode, equals: node.id)', '.scrollDismissesKeyboard(.interactively)',
                  'Button("action.done") { focusedNode = nil }']:
            self.assertIn(x,self.host)
        self.assertNotIn('.sheet(',self.owner)
        self.assertIn('proxy.scrollTo(id, anchor: .top)',self.host)
        self.assertIn('if let id, actionReview.review?.id == id',self.host)
    def test_original_unknown_recovery_and_readbacks_remain_explicit(self):
        for x in ['Task { await model.recover() }','Task { await model.retryExact() }',
                  'await readback.open()', 'PlayPlayerSubmissionStatusView(', 'PlayPlayerTeamStatusView(', 'PlayPlayerLeaderboardView(']:
            self.assertIn(x,self.host)
        for x in ['URLSession','transport.send','api/','retryExact()','recover()','grant(','award(']:
            self.assertNotIn(x,self.core+self.owner)
    def test_evidence_destination_keeps_its_original_separate_factory(self):
        self.assertIn('PlayerTaskEvidenceView(target: target, player: model, device: deviceModel?(target.nodeID))',self.host)
        self.assertIn('evidenceTarget = try model.evidenceTarget(nodeID: node.id)',self.host)
        self.assertIn('.navigationDestination(item: $evidenceTarget)',self.host)
        self.assertNotIn('uploadPhoto',self.core+self.owner)
    def test_locale_table_complete_and_raw_review_is_not_localized(self):
        c=json.loads((ROOT/'Resources/PlayPlayerActionReview.xcstrings').read_text())
        self.assertEqual(set(c['strings']),{'title','role','text','choice','hint','reveal','level','authority','confirm','cancel','expired'})
        for row in c['strings'].values():
            self.assertEqual(set(row['localizations']),{'en','zh-Hans'})
            for item in row['localizations'].values():self.assertEqual(item['stringUnit']['state'],'translated');self.assertTrue(item['stringUnit']['value'])
        self.assertIn('table: "PlayPlayerActionReview", locale: locale',self.owner)
        for x in ['Text(verbatim: detail)','Text(verbatim: impact)','Text(level, format: .number)']:self.assertIn(x,self.owner)
    def test_authored_tests_cover_each_meaningful_interruption(self):
        source=(ROOT/'Tests/CoreTests/PlayPlayerActionReviewTests.swift').read_text()
        app=(ROOT/'Tests/AppUnitTests/PlayPlayerActionReviewControllerTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test\w+\(',source)),12);self.assertEqual(len(re.findall(r'func test\w+\(',app)),14)
        for x in ['testCanonicallyEqualButByteDifferentDisplayedLabelRejectsOldReview','testUnknownRetainsOriginalRequestAndPreventsNewSubmission','testReadOnlyCapabilityCannotBecomeCommandGrant']:self.assertIn('func '+x+'(',source)
        for x in ['testOldCancelAndConfirmCannotAdoptReplacementReview','testOldNativeRootSynchronousAndQueuedCallbacksCannotRetireReplacement','testNormalPlayerHostInitialAppearanceOwnsFirstReview']:self.assertIn('func '+x+'(',app)
        self.assertIn('UIHostingController(rootView: PlayPlayerSessionView(model:',app)
if __name__=='__main__':unittest.main()

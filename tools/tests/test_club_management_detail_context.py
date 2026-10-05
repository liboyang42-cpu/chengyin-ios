"""Source contracts, not SwiftUI runtime evidence; role/ABA UI tests are authoritative."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ClubManagementDetailContextTests(unittest.TestCase):
    def test_visible_detail_observes_context_and_fences_before_pop(self):
        source = (ROOT / 'App/ClubManagementView.swift').read_text()
        detail = source.split('private func detail(', 1)[1].split('private func leaveScreen()', 1)[0]
        self.assertIn('.onChange(of: readContext) { _, _ in invalidateDetailContext() }', detail)
        reset = detail.split('private func invalidateDetailContext()', 1)[1]
        self.assertIn('guard screenIdentity != identity || screenRevision != viewerRevision else { return }', reset)
        self.assertLess(reset.index('leaveScreen()'), reset.index('selection = nil'))
        for required in ['snapshot = nil', 'stale = false', 'serverReadMessage = nil', 'screenRevision = nil']:
            self.assertIn(required, reset)
        self.assertNotIn('screenRevision = viewerRevision', reset)
        self.assertNotIn('state = .idle', reset)
        leave = source.split('private func leaveScreen()', 1)[1].split('@ViewBuilder private var status', 1)[0]
        for required in ['generation &+= 1', 'loading = false', 'coordinator.leaveScreen', 'cancel()']:
            self.assertIn(required, leave)

    def test_late_completion_fences_and_unknown_journal_are_preserved(self):
        source = (ROOT / 'App/ClubManagementView.swift').read_text()
        self.assertIn('run == generation, identity == captured, access.identity == captured, viewerRevision == revision, screenRevision == revision, !Task.isCancelled', source)
        self.assertIn('screenRevision == revision, !Task.isCancelled else { coordinator.cancel(pending); return }', source)
        coordinator = (ROOT / 'Core/ClubManagementCoordinator.swift').read_text()
        leave = coordinator.split('public func leaveScreen(', 1)[1].split('public func readBack(', 1)[0]
        self.assertIn('case .checking, .awaitingConfirmation: records[key] = nil; return', leave)
        self.assertIn('case .submitting: records[key]?.state = .outcomeUnknown(.cancelled)', leave)
        self.assertNotIn('case .outcomeUnknown: records[key] = nil', leave)

    def test_ui_keeps_fresh_authority_and_role_aba_outcome_assertions(self):
        source = (ROOT / 'Tests/AppUITests/ClubManagementFlowTests.swift').read_text()
        for token in ['String(readsBefore + 1)', 'snapshot.frame.minY >= detail.frame.maxY',
                      'button.descendants(matching: .button).count == 0', 'maximumSwipes: 5',
                      'for scenario in ["refreshRoleABA", "prepareRoleABA"]',
                      'club.management.finishedReads', 'club.management.unknown',
                      'XCTAssertEqual(app.staticTexts["club.management.changes"].label, "1")']:
            self.assertIn(token, source)

if __name__ == '__main__': unittest.main()

from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class OwnerDraftSnapshotDiagnostics(unittest.TestCase):
    def test_entry_diagnostics_use_one_stable_app_snapshot(self):
        source=(ROOT/'Tests/AppUITests/OwnerDraftBrowserFlowTests.swift').read_text()
        block=source.split('private func captureEntryBoundary',1)[1].split('private func record',1)[0]
        self.assertEqual(block.count('app.debugDescription'),1)
        for forbidden in ['target.exists','target.isEnabled','target.isHittable','target.frame','target.elementType','counter.exists','counter.label','app.buttons[','app.staticTexts[','app.descendants(']:
            self.assertNotIn(forbidden,block.split('// Take one app snapshot.',1)[1].split('let snapshot',1)[1])
        self.assertIn('guard app.launchArguments.contains("--owner-draft-fixture")',block)
        self.assertIn('.prefix(65_536)',block)
        self.assertIn('.prefix(1024)',block)
        self.assertIn('attachFixtureScreenshot',block)
    def test_real_route_read_and_no_write_acceptance_assertions_remain(self):
        s=(ROOT/'Tests/AppUITests/OwnerDraftBrowserFlowTests.swift').read_text()
        for text in ['tap("account.ownerDrafts", app, diagnoseEntry: true)','XCTAssertTrue(arrived)',
                     'tap("ownerDraft.row.11", app)','record("list", "1", app); record("restore", "1", app); record("mutations", "0", app)',
                     'XCTAssertEqual(app.textViews.count, 0); XCTAssertEqual(app.textFields.count, 0)']:
            self.assertIn(text,s)

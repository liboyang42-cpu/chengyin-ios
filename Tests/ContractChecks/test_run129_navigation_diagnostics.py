"""Failure-only synthetic diagnostic source checks, not a claim of runtime repair."""
from pathlib import Path
import re,unittest
from tools.run129_repair_planning import historical_source
ROOT=Path(__file__).resolve().parents[2]
from tools.run138_current_source_projection import frozen_context as readiness_prior_context
READINESS_PRIOR_CONTEXT = readiness_prior_context()
ROOT = READINESS_PRIOR_CONTEXT.root
class Run129NavigationDiagnostics(unittest.TestCase):
    def source(self,name):return (ROOT/'Tests/AppUITests'/name).read_text()
    def original(self,name):return historical_source(ROOT/'Tests/AppUITests'/name).read_text()
    def test_image_back_only_caches_original_short_circuit_property_queries(self):
        name='ProjectStoryImageFlowTests.swift';source=self.source(name)
        old='        XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription); button.tap()'
        new='''        let enabled = button.isEnabled
        let hittable: Bool? = enabled ? button.isHittable : nil
        XCTAssertTrue(enabled && hittable == true,
            "STORY_IMAGE_BACK enabled=\\(enabled) hittable=\\(hittable.map { String($0) } ?? "not_queried") " + app.debugDescription)
        button.tap()'''
        self.assertEqual(source.count(new),1);self.assertEqual(source.replace(new,old),self.original(name))
        block=source.split('    private func back(',1)[1].split('    // UNMEASURED',1)[0]
        self.assertEqual(block.count('button.isEnabled'),1);self.assertEqual(block.count('button.isHittable'),1)
        self.assertNotIn('wait',block.lower());self.assertNotIn('Task',block)
    def test_template_back_retains_original_result_and_wait_and_only_late_boolean_diagnostics(self):
        name='ProjectStoryTemplateFlowSupport.swift';source=self.source(name)
        old='        XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))'
        new='''        let arrived = app.textFields["projectEdit.name"].waitForExistence(timeout: 5)
        var diagnostic = ""
        if !arrived {
            let lateNameExists = app.textFields["projectEdit.name"].exists
            let lateChapterVisible = app.navigationBars["Chapter"].exists
            let lateCloseVisible = app.buttons["projectStoryTemplate.close"].exists
            diagnostic = "STORY_TEMPLATE_BACK AFTER_TIMEOUT_ONLY nameExists=\\(lateNameExists) chapterVisible=\\(lateChapterVisible) closeVisible=\\(lateCloseVisible)"
        }
        XCTAssertTrue(arrived, diagnostic)'''
        self.assertEqual(source.count(new),1);self.assertEqual(source.replace(new,old),self.original(name))
        block=source.split('        if !arrived {',1)[1].split('        XCTAssertTrue(arrived, diagnostic)',1)[0]
        self.assertEqual(block.count('.exists'),3);self.assertNotIn('wait',block);self.assertNotIn('try?',block)
    def test_coupon_first_navigation_keeps_result_and_subsequent_assertion_untouched(self):
        name='OwnedCouponCodeJourneyUITests.swift';source=self.source(name)
        before=source.index('        let detailArrived =');after=source.index('        XCTAssertTrue(detailArrived, detailDiagnostic)',before)+len('        XCTAssertTrue(detailArrived, detailDiagnostic)')
        block=source[before:after]
        self.assertIn('let detailArrived = app.navigationBars["Coupon details"].waitForExistence(timeout: 5)',block)
        self.assertIn('if !detailArrived {',block);self.assertIn('AFTER_TIMEOUT_ONLY',block)
        self.assertIn('.prefix(4)',block);self.assertIn('allowedTitles.contains(value) ? value : "other"',block)
        self.assertNotIn('try?',block);self.assertEqual(block.count('waitForExistence'),1)
        old='        XCTAssertTrue(app.navigationBars["Coupon details"].waitForExistence(timeout: 5))'
        self.assertEqual(source[:before]+old+source[after:],self.original(name))
        self.assertEqual(source.count(old),1)
    def test_all_six_template_allowances_bind_the_changed_helper_without_source_escape(self):
        import json,hashlib
        contract=json.loads((ROOT/'tools/run129_repair_planning_contract.json').read_text())
        rows=[r for k,r in contract['required_floors'].items() if k.startswith('ProjectStoryTemplate')]
        self.assertEqual(len(rows),6)
        helper='Tests/AppUITests/ProjectStoryTemplateFlowSupport.swift'
        expected=hashlib.sha256((ROOT/helper).read_bytes()).hexdigest()
        for row in rows:self.assertEqual(row['shared_helper_source_sha256'][helper],expected);self.assertEqual(row['seconds'],900)

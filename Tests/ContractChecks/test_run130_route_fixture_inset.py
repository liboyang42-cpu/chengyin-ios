"""Exact single-hunk run130 candidate; runtime acceptance remains unproven."""
from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
REL='App/PlayRouteMapFixture.swift'
BEFORE='6acec43b0f21ef8c36aeedc748013239d52fe6cf1b8d99a297f4732900d5d0af'
AFTER='fd6a24b2420c7cabc753fb39218a26c3a9b70940f5c2011a9a50834d6f1122b5'
INSERT='                .padding(.bottom, 8)\n'
UI='Tests/AppUITests/PlayRouteMapFlowTests.swift'
UI_SHA='bfdd211e9113d87788f6555d4a4736c6e77e04175d84807981df0fb34d6ed4ca'
HELPER_SHA='705ba7fa14128cfd9e81f181fd2b5f5edd0cb464b2ececd26119510d98ed6e49'
def verify(source,ui,helper):
    assert hashlib.sha256(source.encode()).hexdigest()==AFTER
    assert source.count(INSERT)==1
    assert hashlib.sha256(source.replace(INSERT,'',1).encode()).hexdigest()==BEFORE
    assert hashlib.sha256(ui.encode()).hexdigest()==UI_SHA
    assert hashlib.sha256(helper.encode()).hexdigest()==HELPER_SHA
class Run130SourceBoundary(unittest.TestCase):
    def sources(self):return (ROOT/REL).read_text(),(ROOT/UI).read_text(),(ROOT/'Tests/AppUITests/FailureScreenshot.swift').read_text()
    def test_only_the_approved_layout_or_label_line_is_added(self):verify(*self.sources())
    def test_removed_or_changed_line_is_rejected(self):
        source,ui,helper=self.sources()
        for value in ['',INSERT+'\n',INSERT.replace('8','80') if 'padding' in INSERT else INSERT.replace('model.draft.baseRevision','"fixture-r2"')]:
            with self.subTest(value=value),self.assertRaises(AssertionError):verify(source.replace(INSERT,value,1),ui,helper)
    def test_original_method_wait_and_exact_assertions_cannot_change(self):
        source,ui,helper=self.sources()
        for a,b in [('XCTAssertTrue','XCTAssertFalse'),('timeout: 5','timeout: 20'),('func test','func skipped')]:
            self.assertIn(a,ui)
            with self.assertRaises(AssertionError):verify(source,ui.replace(a,b,1),helper)
    def test_shared_viewport_and_existing_bounded_scroll_are_exact(self):
        source,ui,helper=self.sources();self.assertIn('var bottom = app.frame.maxY - 40',helper)
        with self.assertRaises(AssertionError):verify(source,ui,helper.replace('app.frame.maxY - 40','app.frame.maxY',1))

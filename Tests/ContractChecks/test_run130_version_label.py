"""Exact single-hunk run130 candidate; runtime acceptance remains unproven."""
from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
REL='App/ProjectEditView.swift'
BEFORE='7a54a936c0b46657791a157b7a5613c875ea6c1b5f97fe0886a460370ea4a1cd'
AFTER='3feee5e2ef697bf11dc109ddfe5e997a8acfa2eef14ca780d6b6280c669eac7b'
INSERT='                                .accessibilityLabel(Text(verbatim: model.draft.baseRevision))\n'
UI='Tests/AppUITests/ProjectOwnedEditorFlowTests.swift'
UI_SHA='e06f4f77108ca084088c5a0a412fe754938530611fd4e2ff12199e4d1ae278c6'
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

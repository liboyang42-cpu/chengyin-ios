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
def verify_current(source,ui,helper):
    # A historical checkout without this feature still uses the original guard.
    # Once the topic host exists, current feature contracts and the exact postimage
    # are required; deleting/changing the mount cannot masquerade as old history.
    if (ROOT/'App/ProjectTopicMediaHost.swift').exists():
        try:
            from .test_run130_topic_media_source_adapter import FEATURE_PATHS,verify_current_feature_sources,restore_topic_host_source
        except ImportError:
            from test_run130_topic_media_source_adapter import FEATURE_PATHS,verify_current_feature_sources,restore_topic_host_source
        verify_current_feature_sources(tuple((ROOT/path).read_bytes().decode('utf-8') for path in FEATURE_PATHS))
        source=restore_topic_host_source(source)
    verify(source,ui,helper)
class Run130SourceBoundary(unittest.TestCase):
    def sources(self):return (ROOT/REL).read_bytes().decode('utf-8'),(ROOT/UI).read_bytes().decode('utf-8'),(ROOT/'Tests/AppUITests/FailureScreenshot.swift').read_bytes().decode('utf-8')
    def test_only_the_approved_layout_or_label_line_is_added(self):verify_current(*self.sources())
    def test_removed_or_changed_line_is_rejected(self):
        source,ui,helper=self.sources()
        if (ROOT/"App/ProjectRemoteVersionRow.swift").exists():
            from test_run130_topic_media_source_adapter import restore_topic_host_source
            source=restore_topic_host_source(source)
            validator=verify
        else:
            validator=verify_current
        for value in ['',INSERT+'\n',INSERT.replace('8','80') if 'padding' in INSERT else INSERT.replace('model.draft.baseRevision','"fixture-r2"')]:
            with self.subTest(value=value),self.assertRaises(AssertionError):validator(source.replace(INSERT,value,1),ui,helper)
    def test_original_method_wait_and_exact_assertions_cannot_change(self):
        source,ui,helper=self.sources()
        for a,b in [('XCTAssertTrue','XCTAssertFalse'),('timeout: 5','timeout: 20'),('func test','func skipped')]:
            self.assertIn(a,ui)
            with self.assertRaises(AssertionError):verify_current(source,ui.replace(a,b,1),helper)
    def test_shared_viewport_and_existing_bounded_scroll_are_exact(self):
        source,ui,helper=self.sources();self.assertIn('var bottom = app.frame.maxY - 40',helper)
        with self.assertRaises(AssertionError):verify_current(source,ui,helper.replace('app.frame.maxY - 40','app.frame.maxY',1))

    def test_original_historical_snapshot_still_uses_original_verifier(self):
        source,ui,helper=self.sources()
        if (ROOT/'App/ProjectTopicMediaHost.swift').exists():
            try:
                from .test_run130_topic_media_source_adapter import restore_topic_host_source
            except ImportError:
                from test_run130_topic_media_source_adapter import restore_topic_host_source
            source=restore_topic_host_source(source)
        verify(source,ui,helper)
    def test_checkout_without_topic_host_keeps_legacy_verification(self):
        from tempfile import TemporaryDirectory
        from unittest.mock import patch
        source,ui,helper=self.sources()
        if (ROOT/'App/ProjectTopicMediaHost.swift').exists():
            try:
                from .test_run130_topic_media_source_adapter import restore_topic_host_source
            except ImportError:
                from test_run130_topic_media_source_adapter import restore_topic_host_source
            source=restore_topic_host_source(source)
        with TemporaryDirectory() as folder,patch.dict(verify_current.__globals__,{'ROOT':Path(folder)}):
            verify_current(source,ui,helper)
            with self.assertRaises(AssertionError):verify_current(source.replace(INSERT,'',1),ui,helper)
            with self.assertRaises(AssertionError):verify_current(source,ui+'\n',helper)
            with self.assertRaises(AssertionError):verify_current(source,ui,helper+'\n')

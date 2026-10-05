"""Supplementary native source assertions; not Swift execution evidence."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT/path).read_text()
class TemplateLegacyStory(unittest.TestCase):
    def test_array_precedence_and_noncoercing_legacy_fallback(self):
        s = read('Core/MemberTemplateDetail.swift')
        array = 'if let images = row["imgs"].array { return images.compactMap(\\.text) }'
        legacy = 'guard case .null = row["imgs"], case .string(let legacy) = row["img"], !legacy.isEmpty else { return [] }'
        self.assertIn(array, s); self.assertIn(legacy, s); self.assertLess(s.index(array), s.index(legacy))
        self.assertIn('rows.allSatisfy({ $0.object != nil })', s)
        self.assertIn('text: ParticipationRecord.text(row["text"])', s)
        self.assertIn('tag: ParticipationRecord.text(row["tag"])', s)
    def test_media_boundary_stays_outside_projection(self):
        s = read('Core/MemberTemplateDetail.swift')
        self.assertNotIn('URLSession', s); self.assertNotIn('RetainedImageOrigin.accepts', s)
        view = read('App/MemberTemplateDetailView.swift')
        self.assertIn('NativeMediaGalleryEntry(sources: part.images, scope: reader.scope', view)
        self.assertIn('reader: imageReader', view)
    def test_authored_projection_and_lifecycle_cases(self):
        core = read('Tests/CoreTests/MemberTemplateTests.swift')
        for name in ['testLegacyDTOStoryImageMissingAndNullArrayHydrateWithoutLosingText', 'testCurrentArrayIncludingExplicitEmptyAlwaysWinsOverLegacyImage', 'testMalformedNewImageFieldCannotActivateLegacyFallback', 'testLegacyProjectionDoesNotApproveMediaOriginsOrUnsafeSchemes']:
            self.assertIn(name, core)
        app = read('Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift')
        for value in ['testSearchedPageElevenLegacyStoryRequiresFreshOwnedDetail', 'keyword: "legacy"', 'wire.detailOwner = 8', 'coordinator.rows.isEmpty', 'XCTAssertFalse(coordinator.canSubmit)', '"roleABA"', '"sessionABA"', '"revoke"']:
            self.assertIn(value, app)
        self.assertIn('value.memberID == context.session.accountID', read('Core/TemplateShelfReadApproval.swift'))
